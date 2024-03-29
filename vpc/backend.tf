terraform {
  backend "s3" {
    region         = "eu-west-2"
    bucket         = "terraform-767397739267-eu-west-2-tfstate"
    key            = "terraform-aws-networking/non-prod/terraform.tfstate"
    dynamodb_table = "terraform-tfstate"
    encrypt        = true

    allowed_account_ids = ["767397739267"]

    assume_role = {
      role_arn = "arn:aws:iam::767397739267:role/OrganizationAccountAccessRole"
    }
  }
}
