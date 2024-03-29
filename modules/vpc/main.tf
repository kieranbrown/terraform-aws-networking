data "aws_default_tags" "current" {}
data "aws_region" "current" {}

resource "aws_vpc_ipam_pool_cidr_allocation" "this" {
  ipam_pool_id   = var.ipam_pool_id
  netmask_length = local.base_netmask_length

  description = "Allocated block for the ${var.name} network"

  lifecycle {
    prevent_destroy = true
  }
}

module "subnet_addrs" {
  source = "github.com/hashicorp/terraform-cidr-subnets?ref=2a772a83e15feb5f224a9d814c36948769d3146b"

  base_cidr_block = local.base_cidr_block

  networks = [
    for tenant in local.tenants : {
      name     = tenant.name
      new_bits = try(tenant.newbits, local.default_tenant_newbits)
    }
  ]
}

locals {
  azs                    = formatlist("${data.aws_region.current.name}%s", ["a", "b", "c"])
  base_cidr_block        = aws_vpc_ipam_pool_cidr_allocation.this.cidr
  base_netmask_length    = 13
  default_tenant_newbits = 20 - local.base_netmask_length

  # This is applied to the reserved NACL. By default, everything is configured to be blocked.
  # Ports must be opened here to allow egress access.
  firewall_rules = [
    # { # ICMP
    #   rule_number = 900
    #   protocol    = "icmp"
    #   icmp_type   = -1
    #   icmp_code   = -1
    # },
    { # SSH
      rule_number = 1000
      protocol    = "tcp"
      port        = 22
    },
    { # DNS (TCP)
      rule_number = 1100
      protocol    = "tcp"
      port        = 53
    },
    { # DNS (UDP)
      rule_number = 1200
      protocol    = "udp"
      port        = 53
    },
    { # HTTP
      rule_number = 1300
      protocol    = "tcp"
      port        = 80
    },
    { # HTTPS (TCP)
      rule_number = 1400
      protocol    = "tcp"
      port        = 443
    },
    { # HTTPS (UDP HTTP/3)
      rule_number = 1500
      protocol    = "udp"
      port        = 443
    },
    { # SMTPS
      rule_number = 1600
      protocol    = "tcp"
      port        = 465
    },
    { # SMTP/TLS
      rule_number = 1700
      protocol    = "tcp"
      port        = 587
    },
    { # Ephemeral Ports (TCP)
      rule_number = 5000
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
    },
    { # Ephemeral Ports (UDP)
      rule_number = 5100
      protocol    = "udp"
      from_port   = 1024
      to_port     = 65535
    },
  ]

  reserved_tenant_config_override = var.tenants[index(var.tenants[*].name, "reserved")]

  reserved_tenant = merge(local.reserved_tenant_config_override, {
    name    = "reserved"
    enabled = true

    nacl_rules = concat(try(local.reserved_tenant_config_override.nacl_rules, []), flatten([
      for type in ["ingress", "egress"] : [
        [
          {
            rule_number = 100
            rule_action = "allow"
            type        = type
            protocol    = -1
            cidr_block  = local.base_cidr_block
          }
        ],
        [
          for rule in local.firewall_rules : {
            rule_number = rule.rule_number
            rule_action = "allow"
            type        = type
            protocol    = rule.protocol
            cidr_block  = try(rule.cidr_block, "0.0.0.0/0")
            from_port   = try(rule.from_port, rule.port, null)
            to_port     = try(rule.to_port, rule.port, null)
            icmp_type   = try(rule.icmp_type, null)
            icmp_code   = try(rule.icmp_code, null)
          }
        ]
      ]
    ]))

    subnet_config = merge(try(local.reserved_tenant_config_override.subnet_config, {}), {
      database = { count = 0 }
      intra    = { count = 0 }
    })
  })

  tenants = concat([local.reserved_tenant], [for tenant in var.tenants : tenant if tenant.name != "reserved"])

  # vpc partitions as the maximum you can allocate is /16
  vpc_cidr_block_newbits   = 16 - local.base_netmask_length
  vpc_max_cidr_allocations = 5 # a maximum of 8 could be allocated with a quota increase
  vpc_main_cidr_block      = cidrsubnet(local.base_cidr_block, local.vpc_cidr_block_newbits, 0)
  vpc_additional_cidr_blocks = [
    for i in range(1, local.vpc_max_cidr_allocations) :
    cidrsubnet(local.base_cidr_block, local.vpc_cidr_block_newbits, i)
  ]
}

# trivy:ignore:avd-aws-0178 Flow logs are not yet required - potentially a future enhancement
resource "aws_vpc" "this" {
  cidr_block = local.vpc_main_cidr_block

  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count = length(local.vpc_additional_cidr_blocks)

  vpc_id     = aws_vpc.this.id
  cidr_block = local.vpc_additional_cidr_blocks[count.index]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  tags = merge(var.tags, {
    Name = "${var.name}-default-DO_NOT_USE"
  })
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-default-DO_NOT_USE"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

################################################
#                 NAT Gateway                  #
################################################

resource "aws_eip" "nat_gateway" {
  for_each = toset(slice(local.azs, 0, var.enable_nat_gateway == false ? 0 : var.single_nat_gateway ? 1 : length(local.azs)))

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = var.fck_nat == false ? aws_eip.nat_gateway : {}

  allocation_id = each.value.id

  subnet_id = module.tenants["reserved"].subnets.public[each.key][0]

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })
}

module "fck_nat" {
  # todo: switch this back to upstream once my changes are merged
  source = "github.com/kieranbrown/terraform-aws-fck-nat?ref=e5ecafc3bee32c8bc517e25a1ba3563276814f72"

  for_each = var.fck_nat == true ? aws_eip.nat_gateway : {}

  name      = "${var.name}-fck-nat-${each.key}"
  vpc_id    = aws_vpc.this.id
  subnet_id = module.tenants["reserved"].subnets.public[each.key][0]

  eip_allocation_ids = [each.value.id]
  use_spot_instances = true

  # provider level default_tags won't be propogated onto the ASG without this
  tags = merge(data.aws_default_tags.current.tags, var.tags)

  depends_on = [aws_vpc_ipv4_cidr_block_association.this]
}

################################################
#                 Route tables                 #
################################################

resource "aws_default_route_table" "this" {
  default_route_table_id = aws_vpc.this.default_route_table_id

  tags = merge(var.tags, {
    Name = "${var.name}-default-DO_NOT_USE"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-public"
  })
}

resource "aws_route" "public_igw" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table" "private" {
  for_each = toset(local.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = format("${var.name}-private-${each.key}")
  })
}

resource "aws_route" "private_nat" {
  for_each = var.enable_nat_gateway ? aws_route_table.private : {}

  destination_cidr_block = "0.0.0.0/0"

  route_table_id       = each.value.id
  nat_gateway_id       = try(aws_nat_gateway.this[each.key].id, aws_nat_gateway.this[one(keys(aws_nat_gateway.this))].id, null)
  network_interface_id = try(module.fck_nat[each.key].eni_id, module.fck_nat[one(keys(module.fck_nat))].eni_id, null)
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-intra"
  })
}

################################################
#                 VPC Endpoints                #
################################################

module "endpoints" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc//modules/vpc-endpoints?ref=a837be12882c8f74984620752937b4806da2d6d4"

  vpc_id = aws_vpc.this.id

  endpoints = {
    dynamodb = {
      service      = "dynamodb"
      service_type = "Gateway"
      route_table_ids = concat(
        [aws_route_table.public.id],
        values(aws_route_table.private)[*].id,
      )
      tags = { Name = "${var.name}-dynamodb-vpc-endpoint" }
    },
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      route_table_ids = concat(
        [aws_route_table.public.id],
        values(aws_route_table.private)[*].id,
      )
      tags = { Name = "${var.name}-s3-vpc-endpoint" }
    },
  }

  tags = var.tags
}

################################################
#             Tenant Configuration             #
################################################

module "tenants" {
  for_each = { for tenant in local.tenants : tenant.name => tenant if tenant.enabled }
  source   = "../vpc-tenant"

  name = "${var.name}-${each.key}"
  azs  = local.azs

  cidr_block = module.subnet_addrs.network_cidr_blocks[each.key]

  nacl_rules = concat(
    lookup(each.value, "nacl_rules", []),
    # These rules are only applied to tenants and not the reserved subnets
    each.key == "reserved" ? [] : flatten([
      [
        for index, tenant in distinct(concat(["reserved", each.key], try(each.value.trusted_tenants, []))) : {
          rule_number = (index + 1) * 100
          rule_action = "allow"
          type        = "ingress"
          protocol    = -1
          cidr_block  = module.subnet_addrs.network_cidr_blocks[tenant]
        }
      ],
      [
        {
          # Deny all VPC access
          rule_number = 32765
          rule_action = "deny"
          type        = "ingress"
          protocol    = -1
          cidr_block  = local.base_cidr_block
        },
        {
          # Allow all inbound access
          rule_number = 32766
          rule_action = "allow"
          type        = "ingress"
          protocol    = -1
          cidr_block  = "0.0.0.0/0"
        },
        {
          # Allow all outbound access
          rule_number = 32766
          rule_action = "allow"
          type        = "egress"
          protocol    = -1
          cidr_block  = "0.0.0.0/0"
        },
      ]
    ]),
  )

  ram_share_principals = try(each.value.ram_share_principals, [])

  route_table_ids = {
    public  = { for az in local.azs : az => aws_route_table.public.id }
    private = { for az, rt in aws_route_table.private : az => rt.id }
    intra   = { for az in local.azs : az => aws_route_table.intra.id }
  }

  subnet_config = {
    public   = try(each.value.subnet_config.public, {})
    private  = try(each.value.subnet_config.private, {})
    intra    = try(each.value.subnet_config.intra, {})
    database = try(each.value.subnet_config.database, {})
  }

  tags = merge(var.tags, try(each.value.tags, {}))

  vpc_id = aws_vpc.this.id
}

################################################
#            Cross Account Tagging             #
################################################

locals {
  taggables = concat(
    flatten(values(module.tenants)[*].taggables),
    flatten([
      for account_id in distinct(flatten([for tenant in local.tenants : try(tenant.ram_share_principals, []) if tenant.enabled])) : [
        { // VPC
          account_id  = account_id
          resource_id = aws_vpc.this.id
          tags        = aws_vpc.this.tags_all
          type        = "vpc"
        },
        { // IGW
          account_id  = account_id
          resource_id = aws_internet_gateway.this.id
          tags        = aws_internet_gateway.this.tags_all
          type        = "igw"
        },
        [ // Route Tables
          for rt in concat([aws_route_table.public], values(aws_route_table.private), [aws_route_table.intra]) : {
            account_id  = account_id
            resource_id = rt.id
            tags        = rt.tags_all
            type        = "rt"
          }
        ],
        [ // Nat Gateways
          for ng in aws_nat_gateway.this : {
            account_id  = account_id
            resource_id = ng.id
            tags        = ng.tags_all
            type        = "nacl"
          }
        ],
      ]
    ])
  )
}

module "cross_account_tagging" {
  source = "../cross-account-tagging"

  for_each = {
    for taggable in local.taggables : join("/", [taggable.account_id, taggable.type, taggable.tags.Name]) => taggable
    if var.cross_account_tagging_role_name != null
  }

  account_id  = each.value.account_id
  resource_id = each.value.resource_id
  role_name   = var.cross_account_tagging_role_name
  tags        = each.value.tags

  depends_on = [module.tenants]
}
