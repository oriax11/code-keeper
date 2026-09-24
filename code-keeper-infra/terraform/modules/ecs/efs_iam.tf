# =====================================================
# IAM: allow the ECS task role to mount/read/write EFS
# =====================================================

resource "aws_iam_policy" "efs_access" {
  name        = "${var.environment}-efs-access"
  description = "Allow ECS tasks to mount and access EFS access points for the DB volumes in ${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEFSClientMountWrite"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = [
          var.inventory_db_file_system_arn,
          var.billing_db_file_system_arn
        ]
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = [
              var.inventory_db_access_point_arn,
              var.billing_db_access_point_arn
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-efs-access"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_efs_access" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.efs_access.arn
}
