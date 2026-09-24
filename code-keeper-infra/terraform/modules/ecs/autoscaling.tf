# =====================================================
# ECS SERVICE AUTO SCALING (stateless tier)
#
# Target-tracking on average CPU. Min 2 keeps one task per AZ; max 4 caps
# cost. Stateful services (rabbit-queue, both DBs) stay fixed at 1.
# =====================================================

locals {
  autoscaled_services = {
    api-gateway   = aws_ecs_service.api-gateway.name
    inventory-app = aws_ecs_service.inventory_app.name
    billing-app   = aws_ecs_service.billing_app.name
  }
}

resource "aws_appautoscaling_target" "app" {
  for_each = local.autoscaled_services

  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${each.value}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "app_cpu" {
  for_each = local.autoscaled_services

  name               = "${var.environment}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.app[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.app[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 70.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
