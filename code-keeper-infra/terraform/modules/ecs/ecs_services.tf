# =====================================================
# SERVICE DISCOVERY NAMESPACE
# =====================================================

resource "aws_service_discovery_private_dns_namespace" "main" {
  name = var.environment
  vpc  = var.vpc_id

  tags = {
    Name        = "${var.environment}-sd-namespace"
    Environment = var.environment
  }
}

# =====================================================
# TASK DEFINITION: API GATEWAY
# =====================================================

resource "aws_ecs_task_definition" "api-gateway" {
  family       = "${var.environment}-api-gateway"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "api-gateway"
      image     = var.api_gateway_image
      essential = true

      portMappings = [
        {
          name          = "api-gateway"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "INVENTORY_APP_HOST"
          value = "inventory-app"
        },
        {
          name  = "INVENTORY_APP_PORT"
          value = "8080"
        },
        {
          name  = "RABBITMQ_HOST"
          value = "rabbit-queue"
        },
        {
          name  = "RABBITMQ_PORT"
          value = "5672"
        },
        {
          name  = "APIGATEWAY_PORT"
          value = "3000"
        },
        {
          name  = "PYTHONUNBUFFERED"
          value = "1"
        },
        {
          name  = "COGNITO_REGION"
          value = var.region
        },
        {
          name  = "COGNITO_USER_POOL_ID"
          value = aws_cognito_user_pool.main.id
        },
        {
          name  = "COGNITO_APP_CLIENT_ID"
          value = aws_cognito_user_pool_client.app.id
        }
      ]

      secrets = [
        {
          name      = "RABBITMQ_USER"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_USER::"
        },
        {
          name      = "RABBITMQ_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_PASSWORD::"
        },
        {
          name      = "RABBITMQ_QUEUE"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_QUEUE::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api_gateway.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "api-gateway"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

# =====================================================
# TASK DEFINITION: INVENTORY
# =====================================================

resource "aws_ecs_task_definition" "inventory" {
  family       = "${var.environment}-inventory"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "inventory-app"
      image     = var.inventory_app_image
      essential = true

      portMappings = [
        {
          name          = "inventory-app"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "INVENTORY_APP_PORT"
          value = "8080"
        },
        {
          name  = "PYTHONUNBUFFERED"
          value = "1"
        }
      ]

      secrets = [
        {
          name      = "INVENTORY_DB_USER"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:INVENTORY_DB_USER::"
        },
        {
          name      = "INVENTORY_DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:INVENTORY_DB_PASSWORD::"
        },
        {
          name      = "INVENTORY_DB_NAME"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:INVENTORY_DB_NAME::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.inventory.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "inventory"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

# =====================================================
# TASK DEFINITION: BILLING
# =====================================================

resource "aws_ecs_task_definition" "billing" {
  family       = "${var.environment}-billing"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "billing-app"
      image     = var.billing_app_image
      essential = true

      portMappings = [
        {
          name          = "billing-app"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "RABBITMQ_HOST"
          value = "rabbit-queue"
        },
        {
          name  = "RABBITMQ_PORT"
          value = "5672"
        },
        {
          name  = "BILLING_APP_PORT"
          value = "8080"
        },
        {
          name  = "PYTHONUNBUFFERED"
          value = "1"
        }
      ]

      secrets = [
        {
          name      = "BILLING_DB_USER"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:BILLING_DB_USER::"
        },
        {
          name      = "BILLING_DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:BILLING_DB_PASSWORD::"
        },
        {
          name      = "BILLING_DB_NAME"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:BILLING_DB_NAME::"
        },
        {
          name      = "RABBITMQ_USER"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_USER::"
        },
        {
          name      = "RABBITMQ_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_PASSWORD::"
        },
        {
          name      = "RABBITMQ_QUEUE"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_QUEUE::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.billing.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "billing"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

# =====================================================
# TASK DEFINITION: RABBITMQ
# =====================================================

resource "aws_ecs_task_definition" "rabbit_queue" {
  family       = "${var.environment}-rabbit-queue"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "rabbit-queue"
      image     = var.rabbit_queue_image
      essential = true

      portMappings = [
        {
          name          = "rabbitmq"
          containerPort = 5672
          hostPort      = 5672
          protocol      = "tcp"
        },
        {
          name          = "rabbitmq-management"
          containerPort = 15672
          hostPort      = 15672
          protocol      = "tcp"
        }
      ]

      secrets = [
        {
          name      = "RABBITMQ_USER"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_USER::"
        },
        {
          name      = "RABBITMQ_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_PASSWORD::"
        },
        {
          name      = "RABBITMQ_QUEUE"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:RABBITMQ_QUEUE::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.rabbitmq.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "rabbitmq"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

# =====================================================
# TASK DEFINITION: INVENTORY DB
# =====================================================

resource "aws_ecs_task_definition" "inventory_db" {
  family       = "${var.environment}-inventory-db"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  volume {
    name = "inventory-db-data"

    efs_volume_configuration {
      file_system_id     = var.inventory_db_file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.inventory_db_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "inventory-db"
      image     = var.inventory_db_image
      essential = true

      portMappings = [
        {
          name          = "postgres"
          containerPort = 5432
          hostPort      = 5432
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "inventory-db-data"
          containerPath = "/var/lib/postgresql/"
          readOnly      = false
        }
      ]

      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:INVENTORY_DB_USER::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:INVENTORY_DB_PASSWORD::"
        },
        {
          name      = "DB_NAME"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:INVENTORY_DB_NAME::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.inventory_db.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "inventory-db"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

# =====================================================
# TASK DEFINITION: BILLING DB
# =====================================================

resource "aws_ecs_task_definition" "billing_db" {
  family       = "${var.environment}-billing-db"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  volume {
    name = "billing-db-data"

    efs_volume_configuration {
      file_system_id     = var.billing_db_file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.billing_db_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "billing-db"
      image     = var.billing_db_image
      essential = true

      portMappings = [
        {
          name          = "postgres"
          containerPort = 5432
          hostPort      = 5432
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "billing-db-data"
          containerPath = "/var/lib/postgresql/"
          readOnly      = false
        }
      ]

      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:BILLING_DB_USER::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:BILLING_DB_PASSWORD::"
        },
        {
          name      = "DB_NAME"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:BILLING_DB_NAME::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.billing_db.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "billing-db"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

# =====================================================
# SERVICE: API GATEWAY (behind ALB)
# =====================================================

resource "aws_ecs_service" "api-gateway" {
  name                   = "${var.environment}-api-gateway-service"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.api-gateway.arn
  desired_count          = 2
  enable_execute_command = true
  launch_type            = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.api_gateway_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "api-gateway"
    container_port   = 3000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name      = "api-gateway"
      discovery_name = "api-gateway"

      client_alias {
        dns_name = "api-gateway"
        port     = 3000
      }
    }
  }

  depends_on = [
    aws_ecs_service.rabbit_queue,
    aws_ecs_service.inventory_app,
    aws_ecs_service.billing_app
  ]

  tags = {
    Name        = "${var.environment}-api-gateway-service"
    Environment = var.environment
  }
}

# =====================================================
# SERVICE: INVENTORY
# =====================================================

resource "aws_ecs_service" "inventory_app" {
  name                   = "${var.environment}-inventory-service"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.inventory.arn
  desired_count          = 2
  force_new_deployment   = true
  enable_execute_command = true
  launch_type            = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.inventory_app_sg_id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name      = "inventory-app"
      discovery_name = "inventory-app"

      client_alias {
        dns_name = "inventory-app"
        port     = 8080
      }
    }
  }

  depends_on = [
    aws_service_discovery_private_dns_namespace.main,
    aws_ecs_service.inventory_db
  ]

  tags = {
    Name        = "${var.environment}-inventory-service"
    Environment = var.environment
  }
}

# =====================================================
# SERVICE: BILLING
# =====================================================

resource "aws_ecs_service" "billing_app" {
  name                   = "${var.environment}-billing-service"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.billing.arn
  desired_count          = 2
  force_new_deployment   = true
  enable_execute_command = true
  launch_type            = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.billing_app_sg_id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name      = "billing-app"
      discovery_name = "billing-app"

      client_alias {
        dns_name = "billing-app"
        port     = 8080
      }
    }
  }

  depends_on = [
    aws_service_discovery_private_dns_namespace.main,
    aws_ecs_service.billing_db,
    aws_ecs_service.rabbit_queue
  ]

  tags = {
    Name        = "${var.environment}-billing-service"
    Environment = var.environment
  }
}

# =====================================================
# SERVICE: RABBITMQ
# =====================================================

resource "aws_ecs_service" "rabbit_queue" {
  name                   = "${var.environment}-rabbit-queue"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.rabbit_queue.arn
  desired_count          = 1
  force_new_deployment   = true
  enable_execute_command = true
  launch_type            = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.rabbitmq_sg_id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name      = "rabbitmq"
      discovery_name = "rabbit-queue"

      client_alias {
        dns_name = "rabbit-queue"
        port     = 5672
      }
    }
  }

  depends_on = [
    aws_service_discovery_private_dns_namespace.main
  ]

  tags = {
    Name        = "${var.environment}-rabbit-queue"
    Environment = var.environment
  }
}

# =====================================================
# SERVICE: INVENTORY DB
# =====================================================

resource "aws_ecs_service" "inventory_db" {
  name                   = "${var.environment}-inventory-db"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.inventory_db.arn
  desired_count          = 1
  force_new_deployment   = true
  enable_execute_command = true
  launch_type            = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.inventory_db_sg_id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name      = "postgres"
      discovery_name = "inventory-db"

      client_alias {
        dns_name = "inventory-db"
        port     = 5432
      }
    }
  }

  depends_on = [
    aws_service_discovery_private_dns_namespace.main,
  ]

  tags = {
    Name        = "${var.environment}-inventory-db"
    Environment = var.environment
  }
}

# =====================================================
# SERVICE: BILLING DB
# =====================================================

resource "aws_ecs_service" "billing_db" {
  name                   = "${var.environment}-billing-db"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.billing_db.arn
  desired_count          = 1
  force_new_deployment   = true
  enable_execute_command = true
  launch_type            = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.billing_db_sg_id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name      = "postgres"
      discovery_name = "billing-db"

      client_alias {
        dns_name = "billing-db"
        port     = 5432
      }
    }
  }

  depends_on = [
    aws_service_discovery_private_dns_namespace.main,
  ]

  tags = {
    Name        = "${var.environment}-billing-db"
    Environment = var.environment
  }
}
