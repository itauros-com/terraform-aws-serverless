locals {
  waf = {
    for k, v in var.waf : k => merge(v, {
      name = coalesce(v.name, format("%v-%v", local.prefix, k))
      tags = merge(v.tags, local.tags)
    })
  }

  waf_ips = {
    for v in flatten([
      for waf_key, waf in local.waf : [
        for rule in waf.rules : {
          waf_key            = waf_key
          rule_name          = rule.name
          scope              = waf.scope
          ip_address_version = rule.ip_address_version
          addresses          = rule.addresses
        } if rule.is_ip_set_rule
      ]
      ]) : format("%v-%v", v.waf_key, v.rule_name) => {
      scope              = v.scope
      ip_address_version = v.ip_address_version
      addresses          = v.addresses
    }
  }
}

resource "aws_wafv2_ip_set" "this" {
  for_each = local.waf_ips

  name               = each.key
  scope              = each.value.scope # "CLOUDFRONT" se usi CloudFront
  ip_address_version = each.value.ip_address_version
  addresses          = each.value.addresses
}

module "wafv2" {
  source  = "aws-ss/wafv2/aws"
  version = "3.10.0"

  for_each = local.waf

  name           = each.value.name
  scope          = each.value.scope
  default_action = each.value.default_action

  rule = [
    for v in each.value.rules : merge(v,
      v.is_ip_set_rule ? {
        ip_set_reference_statement = {
          arn = aws_wafv2_ip_set.this[format("%v-%v", each.key, v.name)].arn
        }
        is_ip_set_rule     = null
        ip_address_version = null
        addresses          = null
      } : {}
    )
  ]

  visibility_config = {
    cloudwatch_metrics_enabled = false
    metric_name                = "api-acl"
    sampled_requests_enabled   = false
  }

  enabled_logging_configuration = each.value.enabled_logging_configuration
  enabled_web_acl_association   = each.value.enabled_web_acl_association
  resource_arn = [
    for v in each.value.resources : (
      v.service == "apigateway" ? module.apigateways_v2[v.name].api_execution_arn :
      ""
    )
  ]

  tags = each.value.tags
}
