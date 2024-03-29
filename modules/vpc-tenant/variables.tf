variable "azs" {
  type = list(string)
}

variable "cidr_block" {
  type = string
}

variable "nacl_rules" {
  type = list(object({
    rule_number = number
    rule_action = string # either 'allow' or 'deny'
    type        = string # either 'ingress' or 'egress'
    protocol    = string
    cidr_block  = string
    from_port   = optional(number)
    to_port     = optional(number)
    icmp_type   = optional(number)
    icmp_code   = optional(number)
  }))

  validation {
    error_message = "[*].type must be either 'ingress' or 'egress'"
    condition     = alltrue([for rule in var.nacl_rules : contains(["ingress", "egress"], rule.type)])
  }
}

variable "name" {
  type = string
}

variable "ram_share_principals" {
  type = set(string)
}

variable "route_table_ids" {
  type = object({
    public  = map(string)
    private = map(string)
    intra   = map(string)
  })
}

variable "subnet_config" {
  type = object({
    public = object({
      count       = optional(number, 3)
      route_table = optional(string, "public")
    })
    private = object({
      count       = optional(number, 3)
      route_table = optional(string, "private")
    })
    intra = object({
      count       = optional(number, 3)
      route_table = optional(string, "intra")
    })
    database = object({
      count       = optional(number, 3)
      route_table = optional(string, "intra")
    })
  })
}

variable "tags" {
  type = map(string)
}

variable "vpc_id" {
  type = string
}
