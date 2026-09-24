# =====================================================
# ALB SECURITY GROUP
# Internet -> ALB
# =====================================================

resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "Allow HTTP/HTTPS traffic to ALB in ${var.environment}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-alb-sg"
    Environment = var.environment
  }
}

# =====================================================
# API GATEWAY SECURITY GROUP
# ALB -> API Gateway
# =====================================================

resource "aws_security_group" "api_gateway" {
  name        = "${var.environment}-api-gateway-sg"
  description = "Security group for API Gateway in ${var.environment}"
  vpc_id      = var.vpc_id

  # Only ALB can access API Gateway
  ingress {
    description     = "Traffic from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-api-gateway-sg"
    Environment = var.environment
  }
}

# =====================================================
# INVENTORY APP SECURITY GROUP
# API Gateway -> Inventory App
# =====================================================

resource "aws_security_group" "inventory_app" {
  name        = "${var.environment}-inventory-app-sg"
  description = "Security group for Inventory App in ${var.environment}"
  vpc_id      = var.vpc_id

  # Only API Gateway can access Inventory App
  ingress {
    description     = "Traffic from API Gateway"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-inventory-app-sg"
    Environment = var.environment
  }
}

# =====================================================
# INVENTORY DATABASE SECURITY GROUP
# Inventory App -> Inventory DB
# =====================================================

resource "aws_security_group" "inventory_db" {
  name        = "${var.environment}-inventory-db-sg"
  description = "Security group for Inventory PostgreSQL in ${var.environment}"
  vpc_id      = var.vpc_id

  # ONLY Inventory App can access PostgreSQL
  ingress {
    description     = "PostgreSQL from Inventory App"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.inventory_app.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-inventory-db-sg"
    Environment = var.environment
  }
}

# =====================================================
# RABBITMQ SECURITY GROUP
# API Gateway, Billing App -> RabbitMQ
# =====================================================

resource "aws_security_group" "rabbitmq" {
  name        = "${var.environment}-rabbitmq-sg"
  description = "Security group for RabbitMQ in ${var.environment}"
  vpc_id      = var.vpc_id

  # API Gateway and Billing App can access RabbitMQ
  ingress {
    description     = "RabbitMQ from API Gateway and Billing App"
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id, aws_security_group.billing_app.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-rabbitmq-sg"
    Environment = var.environment
  }
}

# =====================================================
# BILLING APP SECURITY GROUP
# RabbitMQ -> Billing App
# =====================================================

resource "aws_security_group" "billing_app" {
  name        = "${var.environment}-billing-app-sg"
  description = "Security group for Billing App in ${var.environment}"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-billing-app-sg"
    Environment = var.environment
  }
}

# =====================================================
# BILLING DATABASE SECURITY GROUP
# Billing App -> Billing DB
# =====================================================

resource "aws_security_group" "billing_db" {
  name        = "${var.environment}-billing-db-sg"
  description = "Security group for Billing PostgreSQL in ${var.environment}"
  vpc_id      = var.vpc_id

  # ONLY Billing App can access PostgreSQL
  ingress {
    description     = "PostgreSQL from Billing App"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.billing_app.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-billing-db-sg"
    Environment = var.environment
  }
}
