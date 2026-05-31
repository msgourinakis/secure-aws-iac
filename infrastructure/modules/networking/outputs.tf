output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}