module "eventbridge" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "~> 4.0"

  for_each = var.eventbridge

  create_bus = each.value.create_bus
  bus_name   = each.value.bus_name
  # null = module default (bus_name): kept for the pre-existing instances
  # whose role is already named after the bus.
  role_name = each.value.iam_role_name

  attach_lambda_policy = true
  lambda_target_arns = [
    for schedule_key, schedule in each.value.schedules :
    try(module.functions[schedule.arn].lambda_function_arn, schedule.arn)
  ]

  schedules = {
    for schedule_key, schedule in each.value.schedules :
    schedule_key => {
      description         = schedule.description
      schedule_expression = schedule.schedule_expression
      timezone            = schedule.timezone
      arn                 = try(module.functions[schedule.arn].lambda_function_arn, schedule.arn)
      input               = schedule.input
    }
  }

  tags = merge(var.tags, each.value.tags)
}
