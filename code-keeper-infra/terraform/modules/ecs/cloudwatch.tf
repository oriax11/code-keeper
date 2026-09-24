resource "aws_cloudwatch_log_group" "inventory" {
  name              = "/ecs/${var.environment}-inventory"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-inventory-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "billing" {
  name              = "/ecs/${var.environment}-billing"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-billing-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/ecs/${var.environment}-api-gateway"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-api-gateway-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "inventory_db" {
  name              = "/ecs/${var.environment}-inventory-db"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-inventory-db-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "billing_db" {
  name              = "/ecs/${var.environment}-billing-db"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-billing-db-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "rabbitmq" {
  name              = "/ecs/${var.environment}-rabbitmq"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-rabbitmq-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-microservices"

  dashboard_body = jsonencode({
    widgets = [
      # =====================================================
      # API GATEWAY CPU
      # =====================================================
      {
        type   = "metric"
        width  = 6
        height = 4

        properties = {
          title = "${var.environment} API Gateway CPU"

          metrics = [
            [
              "AWS/ECS",
              "CPUUtilization",
              "ClusterName",
              aws_ecs_cluster.main.name,
              "ServiceName",
              aws_ecs_service.api-gateway.name
            ]
          ]

          period = 300
          stat   = "Average"
          region = var.region

          view = "singleValue"

          singleValueFullPrecision = false
        }
      },

      # =====================================================
      # API GATEWAY MEMORY
      # =====================================================
      {
        type   = "metric"
        width  = 6
        height = 4

        properties = {
          title = "${var.environment} API Gateway Memory"

          metrics = [
            [
              "AWS/ECS",
              "MemoryUtilization",
              "ClusterName",
              aws_ecs_cluster.main.name,
              "ServiceName",
              aws_ecs_service.api-gateway.name
            ]
          ]

          period = 300
          stat   = "Average"
          region = var.region

          view = "singleValue"

          singleValueFullPrecision = false
        }
      },

      # =====================================================
      # INVENTORY CPU
      # =====================================================
      {
        type   = "metric"
        width  = 6
        height = 4

        properties = {
          title = "${var.environment} Inventory CPU"

          metrics = [
            [
              "AWS/ECS",
              "CPUUtilization",
              "ClusterName",
              aws_ecs_cluster.main.name,
              "ServiceName",
              aws_ecs_service.inventory_app.name
            ]
          ]

          period = 300
          stat   = "Average"
          region = var.region

          view = "singleValue"

          singleValueFullPrecision = false
        }
      },

      # =====================================================
      # INVENTORY MEMORY
      # =====================================================
      {
        type   = "metric"
        width  = 6
        height = 4

        properties = {
          title = "${var.environment} Inventory Memory"

          metrics = [
            [
              "AWS/ECS",
              "MemoryUtilization",
              "ClusterName",
              aws_ecs_cluster.main.name,
              "ServiceName",
              aws_ecs_service.inventory_app.name
            ]
          ]

          period = 300
          stat   = "Average"
          region = var.region

          view = "singleValue"

          singleValueFullPrecision = false
        }
      },

      # =====================================================
      # BILLING CPU
      # =====================================================
      {
        type   = "metric"
        width  = 6
        height = 4

        properties = {
          title = "${var.environment} Billing CPU"

          metrics = [
            [
              "AWS/ECS",
              "CPUUtilization",
              "ClusterName",
              aws_ecs_cluster.main.name,
              "ServiceName",
              aws_ecs_service.billing_app.name
            ]
          ]

          period = 300
          stat   = "Average"
          region = var.region

          view = "singleValue"

          singleValueFullPrecision = false
        }
      },

      # =====================================================
      # BILLING MEMORY
      # =====================================================
      {
        type   = "metric"
        width  = 6
        height = 4

        properties = {
          title = "${var.environment} Billing Memory"

          metrics = [
            [
              "AWS/ECS",
              "MemoryUtilization",
              "ClusterName",
              aws_ecs_cluster.main.name,
              "ServiceName",
              aws_ecs_service.billing_app.name
            ]
          ]

          period = 300
          stat   = "Average"
          region = var.region

          view = "singleValue"

          singleValueFullPrecision = false
        }
      }
    ]
  })
}
