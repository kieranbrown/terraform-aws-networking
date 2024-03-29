resource "aws_vpc_ipam_pool" "this" {
  address_family = "ipv4"
  description    = var.description
  locale         = var.locale

  ipam_scope_id       = var.ipam_scope_id
  source_ipam_pool_id = var.source_ipam_pool_id

  tags = {
    Name = var.name
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_ipam_pool_cidr" "this" {
  ipam_pool_id   = aws_vpc_ipam_pool.this.id
  cidr           = var.cidr
  netmask_length = var.netmask_length

  lifecycle {
    prevent_destroy = true
  }
}
