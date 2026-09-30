output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.isolated_db[*].id
}

output "alb_security_group_id" {
  value = aws_security_group.alb_sg.id
}

output "app_security_group_id" {
  value = aws_security_group.app_sg.id
}

output "db_security_group_id" {
  value = aws_security_group.db_sg.id
}

output "alb_dns_name" {
  description = "The publicly accessible DNS name of the Load Balancer"
  value       = aws_lb.app_alb.dns_name
}
