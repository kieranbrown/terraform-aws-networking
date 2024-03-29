locals {
  create_ram_share    = length(var.ram_share_principals) > 0
  partitioned_subnets = cidrsubnets(var.cidr_block, 2, 2, 2, 2)
  public_subnets      = [for i in range(var.subnet_config.public.count) : cidrsubnet(local.partitioned_subnets[0], 2, i)]
  private_subnets     = [for i in range(var.subnet_config.private.count) : cidrsubnet(local.partitioned_subnets[1], 2, i)]
  intra_subnets       = [for i in range(var.subnet_config.intra.count) : cidrsubnet(local.partitioned_subnets[2], 2, i)]
  database_subnets    = [for i in range(var.subnet_config.database.count) : cidrsubnet(local.partitioned_subnets[3], 2, i)]
}

# trivy:ignore:avd-aws-0164 These subnets are designed to be public and have a Public IP by default
resource "aws_subnet" "public" {
  count = length(local.public_subnets)

  vpc_id            = var.vpc_id
  cidr_block        = local.public_subnets[count.index]
  availability_zone = var.azs[count.index % length(var.azs)]

  #checkov:skip=CKV_AWS_130:These subnets are designed to be public and have a Public IP by default
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.azs[count.index % length(var.azs)]}"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = var.route_table_ids[var.subnet_config.public.route_table][aws_subnet.public[count.index].availability_zone]
}

resource "aws_subnet" "private" {
  count = length(local.private_subnets)

  vpc_id            = var.vpc_id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = var.azs[count.index % length(var.azs)]

  tags = merge(var.tags, {
    Name = "${var.name}-private-${var.azs[count.index % length(var.azs)]}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.route_table_ids[var.subnet_config.private.route_table][aws_subnet.private[count.index].availability_zone]
}

resource "aws_subnet" "intra" {
  count = length(local.intra_subnets)

  vpc_id            = var.vpc_id
  cidr_block        = local.intra_subnets[count.index]
  availability_zone = var.azs[count.index % length(var.azs)]

  tags = merge(var.tags, {
    Name = "${var.name}-intra-${var.azs[count.index % length(var.azs)]}"
  })
}

resource "aws_route_table_association" "intra" {
  count = length(aws_subnet.intra)

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = var.route_table_ids[var.subnet_config.intra.route_table][aws_subnet.intra[count.index].availability_zone]
}

resource "aws_subnet" "database" {
  count = length(local.database_subnets)

  vpc_id            = var.vpc_id
  cidr_block        = local.database_subnets[count.index]
  availability_zone = var.azs[count.index % length(var.azs)]

  tags = merge(var.tags, {
    Name = "${var.name}-database-${var.azs[count.index % length(var.azs)]}"
  })
}

resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = var.route_table_ids[var.subnet_config.database.route_table][aws_subnet.database[count.index].availability_zone]
}

resource "aws_network_acl" "this" {
  vpc_id = var.vpc_id

  subnet_ids = [
    for subnet in concat(aws_subnet.public, aws_subnet.private, aws_subnet.intra, aws_subnet.database) : subnet.id
  ]

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_network_acl_rule" "this" {
  for_each = { for rule in var.nacl_rules : "${rule.type}|${rule.rule_number}" => rule }

  network_acl_id = aws_network_acl.this.id

  rule_number = each.value.rule_number
  egress      = each.value.type == "egress"
  protocol    = each.value.protocol
  rule_action = each.value.rule_action
  cidr_block  = each.value.cidr_block
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  icmp_type   = each.value.icmp_type
  icmp_code   = each.value.icmp_code
}

resource "aws_ram_resource_share" "this" {
  count = local.create_ram_share ? 1 : 0
  name  = "networking-${var.name}"
  tags  = var.tags
}

resource "aws_ram_resource_association" "public_subnets" {
  count              = local.create_ram_share ? length(local.public_subnets) : 0
  resource_share_arn = aws_ram_resource_share.this[0].arn
  resource_arn       = aws_subnet.public[count.index].arn
}

resource "aws_ram_resource_association" "private_subnets" {
  count              = local.create_ram_share ? length(local.private_subnets) : 0
  resource_share_arn = aws_ram_resource_share.this[0].arn
  resource_arn       = aws_subnet.private[count.index].arn
}

resource "aws_ram_resource_association" "intra_subnets" {
  count              = local.create_ram_share ? length(local.intra_subnets) : 0
  resource_share_arn = aws_ram_resource_share.this[0].arn
  resource_arn       = aws_subnet.intra[count.index].arn
}

resource "aws_ram_resource_association" "database_subnets" {
  count              = local.create_ram_share ? length(local.database_subnets) : 0
  resource_share_arn = aws_ram_resource_share.this[0].arn
  resource_arn       = aws_subnet.database[count.index].arn
}

resource "aws_ram_principal_association" "this" {
  for_each           = local.create_ram_share ? var.ram_share_principals : []
  resource_share_arn = aws_ram_resource_share.this[0].arn
  principal          = each.value
}
