data "terraform_remote_state" "ipam" {
  backend = "s3"

  config = {
    region = "eu-west-2"
    bucket = "terraform-767397739267-eu-west-2-tfstate"
    key    = "terraform-aws-networking/ipam/terraform.tfstate"

    assume_role = {
      role_arn = "arn:aws:iam::767397739267:role/OrganizationAccountAccessRole"
    }
  }
}

module "network" {
  source = "../modules/vpc"

  cross_account_tagging_role_name = "terraform-aws-networking-tagger"

  ipam_pool_id = data.terraform_remote_state.ipam.outputs.regional_ipam_pools[var.region].id

  name = var.name

  fck_nat            = var.fck_nat
  single_nat_gateway = var.single_nat_gateway
  enable_nat_gateway = var.enable_nat_gateway

  tenants = [
    for tenant in concat([{ name = "reserved" }], local.tenants) : merge(tenant, try(tenant.networks[var.name], {}), {
      enabled              = tenant.name != null && can(tenant.networks[var.name]) && contains(try(tenant.networks[var.name].regions, [var.region]), var.region)
      ram_share_principals = [for principal in concat(try(tenant.ram_share_principals, []), try(tenant.networks[var.name].ram_share_principals, [])) : local.principals[principal]]
      tags = merge(try(tenant.tags, {}), {
        "kb:pool" = "${var.name}-${coalesce(tenant.name, "deleted")}"
      })
    })
  ]

  tags = {
    "kb:pool" = var.name
  }
}
