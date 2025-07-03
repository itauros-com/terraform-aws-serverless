locals {
  apigateways = {
    for k, v in var.apigateways : k => {
      authorizers           = v.authorizers
      cors_configuration    = v.cors_configuration
      create_certificate    = v.create_certificate
      create_domain_name    = v.create_domain_name
      create_domain_records = v.create_domain_records
      deploy_stage          = v.deploy_stage
      description           = v.description
      name                  = coalesce(v.name, format("%v-%v", local.prefix, k))
      routes = {
        for r in flatten([
          for lambda_key, routes in v.routes : [
            for route_key, route in routes : {
              lambda_key = lambda_key
              route_key  = route_key
              route      = route
            }
          ]
        ]) : r.route_key => r
      }
      stage_access_log_settings = merge(
        v.stage_access_log_settings,
        {
          format = jsonencode(v.stage_access_log_settings.format)
        }
      )
      stage_description = v.stage_description
      stage_name        = v.stage_name
      stage_variables   = v.stage_variables
      stage_tags        = v.stage_tags
      tags              = merge(local.tags, v.tags)
    }
  }
}

module "apigateways_v2" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 5.0"

  for_each = local.apigateways

  authorizers = {
    for k, v in each.value.authorizers : k => {
      authorizer_credentials_arn        = v.authorizer_credentials_arn
      authorizer_payload_format_version = v.authorizer_payload_format_version
      authorizer_result_ttl_in_seconds  = v.authorizer_result_ttl_in_seconds
      authorizer_type                   = v.authorizer_type
      authorizer_uri                    = coalesce(v.authorizer_uri, module.functions[v.lambda].lambda_function_invoke_arn)
      enable_simple_responses           = v.enable_simple_responses
      identity_sources                  = v.identity_sources
      jwt_configuration                 = v.jwt_configuration
      name                              = v.name
    }
  }
  cors_configuration    = each.value.cors_configuration
  create_certificate    = each.value.create_certificate
  create_domain_name    = each.value.create_domain_name
  create_domain_records = each.value.create_domain_records
  deploy_stage          = each.value.deploy_stage
  description           = each.value.description
  name                  = each.value.name
  routes = {
    for k, v in each.value.routes : k => {
      authorizer_key     = v.route.authorizer_key
      authorization_type = v.route.authorization_type
      integration = {
        uri                    = module.functions[v.lambda_key].lambda_function_invoke_arn
        type                   = v.route.integration.type
        connection_type        = v.route.integration.connection_type
        method                 = v.route.integration.method
        passthrough_behavior   = v.route.integration.passthrough_behavior
        payload_format_version = v.route.integration.payload_format_version
      }
    }
  }
  stage_access_log_settings = each.value.stage_access_log_settings
  stage_description         = each.value.stage_description
  stage_name                = each.value.stage_name
  stage_tags                = each.value.stage_tags
  tags                      = each.value.tags
}
