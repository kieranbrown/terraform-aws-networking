locals {
  default_tags = {
    "kb:name"       = "terraform-aws-networking"
    "kb:env"        = "prod"
    "kb:managed-by" = "terraform"
    "kb:part-of"    = null
  }
}

provider "aws" {
  region = var.region

  allowed_account_ids = ["767397739267"]

  assume_role {
    role_arn = "arn:aws:iam::767397739267:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.default_tags
  }
}
