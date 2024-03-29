output "cidr_block" {
  value = local.base_cidr_block
}

output "tenants" {
  value = {
    for name, outputs in module.tenants : name => {
      for k, v in outputs : k => v if !contains(["taggables"], k)
    }
  }
}

output "vpc_id" {
  value = aws_vpc.this.id
}
