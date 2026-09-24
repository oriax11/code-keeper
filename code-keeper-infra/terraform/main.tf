# ==============================================================================
# ROOT MODULE — Code-Keeper Infrastructure
# Environment-aware provisioning for Staging and Production stacks.
# ==============================================================================

module "vpc" {
  source = "./modules/vpc"

  environment           = var.environment
  region                = var.region
  vpc_cidr              = var.vpc_cidr
  public_subnet_a_cidr  = var.public_subnet_a_cidr
  public_subnet_b_cidr  = var.public_subnet_b_cidr
  private_subnet_a_cidr = var.private_subnet_a_cidr
  private_subnet_b_cidr = var.private_subnet_b_cidr
}

module "security" {
  source = "./modules/security"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

module "efs" {
  source = "./modules/efs"

  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_a_id = module.vpc.private_subnet_a_id
  private_subnet_b_id = module.vpc.private_subnet_b_id
  inventory_db_sg_id  = module.security.inventory_db_sg_id
  billing_db_sg_id    = module.security.billing_db_sg_id
}

module "alb" {
  source = "./modules/alb"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
}

module "ecs" {
  source = "./modules/ecs"

  environment        = var.environment
  region             = var.region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  api_gateway_sg_id   = module.security.api_gateway_sg_id
  inventory_app_sg_id = module.security.inventory_app_sg_id
  inventory_db_sg_id  = module.security.inventory_db_sg_id
  rabbitmq_sg_id      = module.security.rabbitmq_sg_id
  billing_app_sg_id   = module.security.billing_app_sg_id
  billing_db_sg_id    = module.security.billing_db_sg_id

  target_group_arn = module.alb.target_group_arn
  lb_dns_name      = module.alb.lb_dns_name
  lb_arn_suffix    = module.alb.lb_arn_suffix

  inventory_db_file_system_id   = module.efs.inventory_db_file_system_id
  inventory_db_file_system_arn  = module.efs.inventory_db_file_system_arn
  inventory_db_access_point_id  = module.efs.inventory_db_access_point_id
  inventory_db_access_point_arn = module.efs.inventory_db_access_point_arn
  billing_db_file_system_id     = module.efs.billing_db_file_system_id
  billing_db_file_system_arn    = module.efs.billing_db_file_system_arn
  billing_db_access_point_id    = module.efs.billing_db_access_point_id
  billing_db_access_point_arn   = module.efs.billing_db_access_point_arn

  api_gateway_image   = var.api_gateway_image
  inventory_app_image = var.inventory_app_image
  billing_app_image   = var.billing_app_image
  rabbit_queue_image  = var.rabbit_queue_image
  inventory_db_image  = var.inventory_db_image
  billing_db_image    = var.billing_db_image

  inventory_db_user     = var.inventory_db_user
  inventory_db_password = var.inventory_db_password
  inventory_db_name     = var.inventory_db_name
  billing_db_user       = var.billing_db_user
  billing_db_password   = var.billing_db_password
  billing_db_name       = var.billing_db_name
  rabbitmq_user         = var.rabbitmq_user
  rabbitmq_password     = var.rabbitmq_password
  rabbitmq_queue        = var.rabbitmq_queue
}
