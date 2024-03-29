locals {
  ipam_config = {
    global_pool = {
      cidr = "10.0.0.0/8"
    }

    regions = {
      eu-west-2 = {}
    }
  }
}

data "aws_region" "this" {
  for_each = local.ipam_config.regions

  name = each.key
}

resource "aws_vpc_ipam" "main" {
  description = "Networking IPAM"

  dynamic "operating_regions" {
    for_each = toset(keys(local.ipam_config.regions))

    content {
      region_name = operating_regions.value
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

module "global_ipam_pool" {
  source = "../modules/ipam-pool"

  ipam_scope_id = aws_vpc_ipam.main.private_default_scope_id

  name        = "global"
  description = "Globally available pool"
  cidr        = local.ipam_config.global_pool.cidr
}

module "regional_ipam_pools" {
  for_each = local.ipam_config.regions
  source   = "../modules/ipam-pool"

  name        = data.aws_region.this[each.key].name
  description = data.aws_region.this[each.key].description

  ipam_scope_id       = aws_vpc_ipam.main.private_default_scope_id
  source_ipam_pool_id = module.global_ipam_pool.id

  locale = each.key

  netmask_length = 11
}
