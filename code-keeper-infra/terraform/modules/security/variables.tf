variable "environment" {
  description = "Target deployment environment (staging or production)"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}
