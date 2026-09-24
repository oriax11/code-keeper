output "alb_sg_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "api_gateway_sg_id" {
  description = "Security group ID for API Gateway"
  value       = aws_security_group.api_gateway.id
}

output "inventory_app_sg_id" {
  description = "Security group ID for Inventory App"
  value       = aws_security_group.inventory_app.id
}

output "inventory_db_sg_id" {
  description = "Security group ID for Inventory DB"
  value       = aws_security_group.inventory_db.id
}

output "rabbitmq_sg_id" {
  description = "Security group ID for RabbitMQ"
  value       = aws_security_group.rabbitmq.id
}

output "billing_app_sg_id" {
  description = "Security group ID for Billing App"
  value       = aws_security_group.billing_app.id
}

output "billing_db_sg_id" {
  description = "Security group ID for Billing DB"
  value       = aws_security_group.billing_db.id
}
