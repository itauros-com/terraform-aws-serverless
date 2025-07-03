locals {
  functions = {
    for k, v in var.functions : k => {
      architectures                     = v.architectures
      cloudwatch_logs_retention_in_days = v.cloudwatch_logs_retention_in_days
      create_package                    = false
      description                       = v.description
      environment_variables             = v.environment_variables
      event_source_mapping              = v.event_source_mapping
      function_name                     = coalesce(v.function_name, format("%v-%v", local.prefix, k))
      function_tags                     = v.function_tags
      handler                           = v.handler
      ignore_source_code_hash           = true
      local_existing_package            = v.local_existing_package
      memory_size                       = v.memory_size
      runtime                           = v.runtime
      tags                              = merge(local.tags, v.tags)
      timeout                           = v.timeout
      policies                          = v.policies
    }
  }

  function_triggers = {
    for v in flatten([
      for lambda_key, lambda in var.functions : concat([
        for api_key, api in var.apigateways : [
          flatten([
            [
              for route_key, route in api.routes : {
                lambda_key  = lambda_key
                trigger_key = api_key
                source      = api_key
                service     = "apigateway"
                action      = "lambda:InvokeFunction"
              } if route_key == lambda_key
            ],
            [
              for auth_key, auth in api.authorizers : {
                lambda_key  = lambda_key
                trigger_key = api_key
                source      = api_key
                service     = "apigateway"
                action      = "lambda:InvokeFunction"
              } if try(auth.lambda, "") == lambda_key
            ]
          ])
        ]
        ],
        [
          for trigger_key, trigger in lambda.triggers : {
            lambda_key       = lambda_key
            trigger_key      = trigger_key
            action           = trigger.action
            principal        = trigger.principal
            principal_org_id = trigger.principal_org_id
            source_arn       = trigger.source_arn
          }
      ])
      ]) : format("%v-%v", v.lambda_key, v.trigger_key) => {
      lambda_key             = v.lambda_key
      trigger_key            = v.trigger_key
      action                 = try(v.action, null)
      principal              = coalesce(try(v.principal, null), format("%s.amazonaws.com", coalesce(v.service, "")))
      principal_org_id       = try(v.principal_org_id, null)
      service                = v.service
      source                 = try(v.source, null)
      source_account         = try(v.source_account, null)
      source_arn             = try(v.source_arn, null)
      event_source_token     = try(v.event_source_token, null)
      function_url_auth_type = try(v.function_url_auth_type, null)
    }
  }
}

module "functions" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  for_each = local.functions

  architectures                     = each.value.architectures
  cloudwatch_logs_retention_in_days = each.value.cloudwatch_logs_retention_in_days
  create_package                    = each.value.create_package
  description                       = each.value.description
  environment_variables = {
    for k, v in each.value.environment_variables : k => (
      startswith(k, "BUCKET_") ? try(module.buckets[v].s3_bucket_id, v) :
      startswith(k, "DYNAMODB_") ? try(module.dynamodb_tables[v].dynamodb_table_id, v) :
      startswith(k, "SECRET_") ? try(module.secrets[v].secret_name, v) :
      startswith(k, "SNS_TOPIC_") ? try(module.sns[v].topic_arn, v) :
      v
    )
  }
  event_source_mapping = {
    for k, v in each.value.event_source_mapping : k => merge(v, try((
      v.service == "sqs" ? { event_source_arn = module.sqs[v.event_source].queue_arn } :
      {}), {}), {
      service = null
    })
  }
  function_name           = each.value.function_name
  function_tags           = each.value.function_tags
  handler                 = each.value.handler
  ignore_source_code_hash = each.value.ignore_source_code_hash
  local_existing_package  = each.value.local_existing_package
  memory_size             = each.value.memory_size
  runtime                 = each.value.runtime
  tags                    = each.value.tags
  timeout                 = each.value.timeout

  attach_policies    = true
  number_of_policies = 1
  policies           = ["arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"]

  attach_policy_jsons    = true
  number_of_policy_jsons = length(each.value.policies)
  policy_jsons           = [for v in each.value.policies : data.aws_iam_policy_document.this[v].json]
}

resource "aws_lambda_permission" "this" {
  for_each = local.function_triggers

  action           = each.value.action
  function_name    = module.functions[each.value.lambda_key].lambda_function_arn
  principal        = coalesce(each.value.principal, format("%s.amazonaws.com", coalesce(each.value.service, "")))
  principal_org_id = each.value.principal_org_id
  source_arn = coalesce(each.value.source_arn, (
    each.value.service == "apigateway" ? format("%v/*/*", module.apigateways_v2[each.value.source].api_execution_arn) :
    each.value.service == "" ? "" :
    ""
  ))
  statement_id = format("%v-%v", local.prefix, each.key)

  lifecycle {
    create_before_destroy = true
  }
}
