output "environment" {
  description = "The deployed environment name"
  value       = var.environment
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = module.alb.lb_dns_name
}

output "app_url" {
  description = "HTTP URL of the application"
  value       = "http://${module.alb.lb_dns_name}"
}

output "app_url_https" {
  description = "HTTPS URL of the application"
  value       = "https://${module.alb.lb_dns_name}"
}

output "acm_certificate_arn" {
  description = "ARN of the self-signed certificate in ACM"
  value       = module.alb.acm_certificate_arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs.cluster_arn
}

output "api_gateway_service_name" {
  description = "Name of the API Gateway ECS service"
  value       = module.ecs.api_gateway_service_name
}

output "inventory_service_name" {
  description = "Name of the Inventory ECS service"
  value       = module.ecs.inventory_service_name
}

output "billing_service_name" {
  description = "Name of the Billing ECS service"
  value       = module.ecs.billing_service_name
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = module.ecs.cognito_user_pool_id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito App Client"
  value       = module.ecs.cognito_app_client_id
}
