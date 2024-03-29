variable "cross_account_tagging_role_name" {
  type    = string
  default = null
}

variable "enable_nat_gateway" {
  type = bool
}

variable "fck_nat" {
  type = bool
}

variable "ipam_pool_id" {
  type = string
}

variable "name" {
  type = string
}

variable "single_nat_gateway" {
  type = bool
}

variable "tags" {
  type = map(string)
}

variable "tenants" {
  type = list(object({
    enabled              = bool
    name                 = string
    ram_share_principals = optional(list(string), [])
    nacl_rules = optional(list(object({
      rule_number = number
      rule_action = string # either 'allow' or 'deny'
      type        = string # either 'ingress' or 'egress'
      protocol    = string
      cidr_block  = string
      from_port   = optional(number)
      to_port     = optional(number)
    })), [])
    subnet_config = optional(object({
      public = optional(object({
        count       = optional(number, 3)
        route_table = optional(string, "public")
      }), {})
      private = optional(object({
        count       = optional(number, 3)
        route_table = optional(string, "private")
      }), {})
      intra = optional(object({
        count       = optional(number, 3)
        route_table = optional(string, "intra")
      }), {})
      database = optional(object({
        count       = optional(number, 3)
        route_table = optional(string, "intra")
      }), {})
    }), {})
    tags = map(string)
  }))
}
