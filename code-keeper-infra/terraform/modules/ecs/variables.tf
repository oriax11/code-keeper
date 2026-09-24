variable "environment" {
  description = "Target deployment environment (staging or production)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "api_gateway_sg_id" {
  description = "Security group ID for API Gateway"
  type        = string
}

variable "inventory_app_sg_id" {
  description = "Security group ID for Inventory App"
  type        = string
}

variable "inventory_db_sg_id" {
  description = "Security group ID for Inventory DB"
  type        = string
}

variable "rabbitmq_sg_id" {
  description = "Security group ID for RabbitMQ"
  type        = string
}

variable "billing_app_sg_id" {
  description = "Security group ID for Billing App"
  type        = string
}

variable "billing_db_sg_id" {
  description = "Security group ID for Billing DB"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the ALB target group"
  type        = string
}

variable "lb_dns_name" {
  description = "DNS name of the ALB"
  type        = string
}

variable "lb_arn_suffix" {
  description = "ARN suffix of the ALB"
  type        = string
}

variable "inventory_db_file_system_id" {
  description = "File system ID for Inventory DB"
  type        = string
}

variable "inventory_db_file_system_arn" {
  description = "File system ARN for Inventory DB"
  type        = string
}

variable "inventory_db_access_point_id" {
  description = "Access point ID for Inventory DB"
  type        = string
}

variable "inventory_db_access_point_arn" {
  description = "Access point ARN for Inventory DB"
  type        = string
}

variable "billing_db_file_system_id" {
  description = "File system ID for Billing DB"
  type        = string
}

variable "billing_db_file_system_arn" {
  description = "File system ARN for Billing DB"
  type        = string
}

variable "billing_db_access_point_id" {
  description = "Access point ID for Billing DB"
  type        = string
}

variable "billing_db_access_point_arn" {
  description = "Access point ARN for Billing DB"
  type        = string
}

# --- Container Images ---

variable "api_gateway_image" {
  description = "Container image for api-gateway"
  type        = string
  default     = "docker.io/1ee5lim/api-gateway-app:latest"
}

variable "inventory_app_image" {
  description = "Container image for inventory-app"
  type        = string
  default     = "docker.io/1ee5lim/inventory-app:latest"
}

variable "billing_app_image" {
  description = "Container image for billing-app"
  type        = string
  default     = "docker.io/1ee5lim/billing-app:latest"
}

variable "rabbit_queue_image" {
  description = "Container image for rabbit-queue"
  type        = string
  default     = "docker.io/oriax11/rabbit-queue:latest"
}

variable "inventory_db_image" {
  description = "Container image for inventory-db"
  type        = string
  default     = "docker.io/oriax11/inventory-db:latest"
}

variable "billing_db_image" {
  description = "Container image for billing-db"
  type        = string
  default     = "docker.io/oriax11/billing-db:latest"
}

# --- Application secrets (injected by root module) ---

variable "inventory_db_user" {
  type      = string
  sensitive = true
}

variable "inventory_db_password" {
  type      = string
  sensitive = true
}

variable "inventory_db_name" {
  type      = string
  sensitive = true
}

variable "billing_db_user" {
  type      = string
  sensitive = true
}

variable "billing_db_password" {
  type      = string
  sensitive = true
}

variable "billing_db_name" {
  type      = string
  sensitive = true
}

variable "rabbitmq_user" {
  type      = string
  sensitive = true
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

variable "rabbitmq_queue" {
  type      = string
  sensitive = true
}
