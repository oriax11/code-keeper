variable "environment" {
  description = "Target deployment environment (staging or production)"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_a_id" {
  description = "Private Subnet A ID"
  type        = string
}

variable "private_subnet_b_id" {
  description = "Private Subnet B ID"
  type        = string
}

variable "inventory_db_sg_id" {
  description = "Security Group ID for Inventory DB"
  type        = string
}

variable "billing_db_sg_id" {
  description = "Security Group ID for Billing DB"
  type        = string
}
