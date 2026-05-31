output "vpc_id" {
  description = "ID of VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.networking.private_subnet_ids
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "asg_name" {
  value = module.compute.asg_name
}

output "cloudfront_domain_name" {
  value = module.cdn.cloudfront_domain_name
}

output "cloudtrail_bucket" {
  value = module.monitoring.cloudtrail_bucket
}