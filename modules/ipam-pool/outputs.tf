output "id" {
  value = aws_vpc_ipam_pool.this.id

  depends_on = [aws_vpc_ipam_pool_cidr.this]
}
