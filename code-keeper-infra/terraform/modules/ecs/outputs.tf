output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "task_role_name" {
  description = "Name of the ECS task IAM role"
  value       = aws_iam_role.ecs_task.name
}

output "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  value       = aws_iam_role.ecs_task.arn
}

output "execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  value       = aws_iam_role.ecs_execution.arn
}

output "api_gateway_service_name" {
  description = "Name of the API Gateway ECS service"
  value       = aws_ecs_service.api-gateway.name
}

output "inventory_service_name" {
  description = "Name of the Inventory ECS service"
  value       = aws_ecs_service.inventory_app.name
}

output "billing_service_name" {
  description = "Name of the Billing ECS service"
  value       = aws_ecs_service.billing_app.name
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito App Client"
  value       = aws_cognito_user_pool_client.app.id
}
