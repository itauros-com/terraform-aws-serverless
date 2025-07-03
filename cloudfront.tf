locals {
  cloudfront = {
    for k, v in var.cloudfront : k => {
      aliases                      = v.aliases
      create_origin_access_control = v.create_origin_access_control
      custom_error_response        = v.custom_error_response
      default_cache_behavior       = v.default_cache_behavior
      default_root_object          = v.default_root_object
      dns_records                  = v.dns_records
      origin                       = v.origin
      origin_access_control        = v.origin_access_control
      price_class                  = v.price_class
      tags                         = merge(local.tags, v.tags)
      wait_for_deployment          = v.wait_for_deployment
    }
  }

  cloudfront_buckets = {
    for v in flatten([
      for cdn_key, cdn in local.cloudfront : [
        for origin_key, origin in cdn.origin : {
          cdn_key   = cdn_key
          s3_bucket = origin.s3_bucket
        } if origin.s3_origin == true
      ]
    ]) : format("%v-%v", v.cdn_key, v.s3_bucket) => v
  }

  cloudfront_records = {
    for v in flatten([
      for cdn_key, cdn in local.cloudfront : [
        for alias, zone_id in cdn.aliases : {
          cdn_key = cdn_key
          alias   = alias
          zone_id = zone_id
        }
      ]
    ]) : format("%v-%v", v.cdn_key, v.alias) => v
  }
}

module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 3.0"

  for_each = local.cloudfront

  aliases                      = [for k, v in each.value.aliases : k]
  create_origin_access_control = each.value.create_origin_access_control
  custom_error_response        = each.value.custom_error_response
  default_cache_behavior       = each.value.default_cache_behavior
  default_root_object          = each.value.default_root_object
  origin = {
    for k, v in each.value.origin : k => {
      domain_name           = module.buckets[v.s3_bucket].s3_bucket_bucket_regional_domain_name
      origin_access_control = "s3_${k}"
    } if v.s3_origin == true
  }
  origin_access_control = each.value.origin_access_control
  price_class           = each.value.price_class
  tags                  = each.value.tags
  wait_for_deployment   = each.value.wait_for_deployment
}

resource "aws_route53_record" "cloudfront" {
  for_each = local.cloudfront_records

  name    = each.value.alias
  type    = "A"
  zone_id = each.value.zone_id

  alias {
    name                   = module.cloudfront[each.value.cdn_key].cloudfront_distribution_domain_name
    zone_id                = module.cloudfront[each.value.cdn_key].cloudfront_distribution_hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket_policy" "cloudfront" {
  for_each = local.cloudfront_buckets

  bucket = module.buckets[each.value.s3_bucket].s3_bucket_id
  policy = data.aws_iam_policy_document.cloudfront[each.key].json
}

data "aws_iam_policy_document" "cloudfront" {
  for_each = local.cloudfront_buckets

  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = [format("%v/*", module.buckets[each.value.s3_bucket].s3_bucket_arn)]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values = [
        module.cloudfront[each.value.cdn_key].cloudfront_distribution_arn
      ]
    }
  }
}
