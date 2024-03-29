data "aws_organizations_organization" "current" {}

locals {
  principals = { for account in data.aws_organizations_organization.current.accounts : account.name => account.id }

  # PLEASE READ THIS NOTICE BEFORE MODIFYING ANY OF THE TENANTS BELOW
  # ------------------------------------------------------------------------------
  # due to the way CIDR blocks are allocated the ORDER OF TENANTS CANNOT BE CHANGED
  # due to the way CIDR blocks are allocated the TENANTS CAN NEVER BE DELETED
  # if you wish to "delete" a tenant, simply set the name to null (name = null)
  # this will safely remove the tenants infrastructure while preserving order
  # this approach allows the tenants cidr block to be reallocated to a new tenant in the future

  tenants = [
    {
      name = "sandbox"
      networks = {
        non-prod = {
          ram_share_principals = ["Sandbox"]
        }
      }
    }
  ]
}
