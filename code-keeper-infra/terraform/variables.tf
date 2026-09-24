# ==============================================================================
# ENVIRONMENT AND GENERAL SETTINGS
# ==============================================================================

variable "environment" {
  description = "Target deployment environment (staging or production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "The environment variable must be either 'staging' or 'production'."
  }
}

variable "project" {
  description = "Project name prefix used for resource identification"
  type        = string
  default     = "code-keeper"
}

variable "region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

# ==============================================================================
# NETWORKING
# ==============================================================================

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_a_cidr" {
  description = "CIDR for public subnet A"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_b_cidr" {
  description = "CIDR for public subnet B"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_subnet_a_cidr" {
  description = "CIDR for private subnet A"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_b_cidr" {
  description = "CIDR for private subnet B"
  type        = string
  default     = "10.0.4.0/24"
}

# ==============================================================================
# AWS BUDGET / COST CONTROL
# ==============================================================================

variable "budget_alert_email" {
  description = "Email address for AWS Budget cost alerts (empty disables the budget)"
  type        = string
  default     = ""
}

variable "budget_limit_amount" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "70"
}

# ==============================================================================
# CONTAINER IMAGES
# ==============================================================================

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
  description = "Container image for rabbitmq broker"
  type        = string
  default     = "docker.io/oriax11/rabbit-queue:latest"
}

variable "inventory_db_image" {
  description = "Container image for inventory database"
  type        = string
  default     = "docker.io/oriax11/inventory-db:latest"
}

variable "billing_db_image" {
  description = "Container image for billing database"
  type        = string
  default     = "docker.io/oriax11/billing-db:latest"
}

# ==============================================================================
# APPLICATION SECRETS (sensitive, injected at runtime or via tfvars)
# ==============================================================================

variable "inventory_db_user" {
  description = "Username for inventory database"
  type        = string
  sensitive   = true
}

variable "inventory_db_password" {
  description = "Password for inventory database"
  type        = string
  sensitive   = true
}

variable "inventory_db_name" {
  description = "Database name for inventory database"
  type        = string
  sensitive   = true
}

variable "billing_db_user" {
  description = "Username for billing database"
  type        = string
  sensitive   = true
}

variable "billing_db_password" {
  description = "Password for billing database"
  type        = string
  sensitive   = true
}

variable "billing_db_name" {
  description = "Database name for billing database"
  type        = string
  sensitive   = true
}

variable "rabbitmq_user" {
  description = "Username for RabbitMQ"
  type        = string
  sensitive   = true
}

variable "rabbitmq_password" {
  description = "Password for RabbitMQ"
  type        = string
  sensitive   = true
}

variable "rabbitmq_queue" {
  description = "Queue name for RabbitMQ"
  type        = string
  sensitive   = true
}
