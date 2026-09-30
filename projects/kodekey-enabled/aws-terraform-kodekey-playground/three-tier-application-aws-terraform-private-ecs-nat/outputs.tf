output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecr_app_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecr_search_repository_url" {
  value = aws_ecr_repository.search.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.assets.id
}

output "rds_endpoint" {
  value = aws_db_instance.rds_db.endpoint
}
