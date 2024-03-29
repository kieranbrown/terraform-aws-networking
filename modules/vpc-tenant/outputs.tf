output "cidr_block" {
  value = var.cidr_block
}

output "subnets" {
  value = {
    public   = { for subnet in aws_subnet.public : subnet.availability_zone => subnet.id... }
    private  = { for subnet in aws_subnet.private : subnet.availability_zone => subnet.id... }
    intra    = { for subnet in aws_subnet.intra : subnet.availability_zone => subnet.id... }
    database = { for subnet in aws_subnet.database : subnet.availability_zone => subnet.id... }
  }
}

output "taggables" {
  value = flatten([
    for account_id in var.ram_share_principals : [
      { // NACL
        account_id  = account_id
        resource_id = aws_network_acl.this.id
        tags        = aws_network_acl.this.tags_all
        type        = "nacl"
      },
      [ // Subnets
        for subnet in concat(aws_subnet.public, aws_subnet.private, aws_subnet.intra, aws_subnet.database) : {
          account_id  = account_id
          resource_id = subnet.id
          tags        = subnet.tags_all
          type        = "subnet"
        }
      ],
    ]
  ])
}
