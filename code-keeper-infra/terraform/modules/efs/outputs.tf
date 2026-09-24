output "inventory_db_file_system_id" {
  description = "File system ID for Inventory DB (shared EFS)"
  value       = aws_efs_file_system.main.id
}

output "inventory_db_file_system_arn" {
  description = "File system ARN for Inventory DB"
  value       = aws_efs_file_system.main.arn
}

output "inventory_db_access_point_id" {
  description = "Access point ID for Inventory DB"
  value       = aws_efs_access_point.inventory_db.id
}

output "inventory_db_access_point_arn" {
  description = "Access point ARN for Inventory DB"
  value       = aws_efs_access_point.inventory_db.arn
}

output "billing_db_file_system_id" {
  description = "File system ID for Billing DB (shared EFS)"
  value       = aws_efs_file_system.main.id
}

output "billing_db_file_system_arn" {
  description = "File system ARN for Billing DB"
  value       = aws_efs_file_system.main.arn
}

output "billing_db_access_point_id" {
  description = "Access point ID for Billing DB"
  value       = aws_efs_access_point.billing_db.id
}

output "billing_db_access_point_arn" {
  description = "Access point ARN for Billing DB"
  value       = aws_efs_access_point.billing_db.arn
}

output "efs_security_group_id" {
  description = "Security group ID for EFS NFS"
  value       = aws_security_group.db_efs.id
}
