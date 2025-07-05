locals {
  cdn = {
    for k, v in local.buckets : k => {
      aliases                      = v.distribution.aliases
      default_root_object          = "index.html"
      create_origin_access_control = true
      origin = {
        (k) = {
          domain_name           = module.buckets[k].s3_bucket_bucket_regional_domain_name
          origin_access_control = "s3_${k}" # Chiave in `origin_access_control`
        }
      }
      default_cache_behavior = merge(
        try(v.default_cache_behavior, {
          viewer_protocol_policy = "redirect-to-https"
          allowed_methods        = ["GET", "HEAD", "OPTIONS"]
          cached_methods         = ["GET", "HEAD"]
        }),
        {
          target_origin_id = k
        }
      )
      custom_error_response = [
        {
          error_code         = 404
          response_code      = 200
          response_page_path = "/index.html"
        },
        {
          error_code         = 403
          response_code      = 200
          response_page_path = "/index.html"
        }
      ]

      certificate_arn = v.distribution.certificate_arn
    }
    if v.distribution != null
  }

  cdn_records = var.zone_id != null ? {
    for v in flatten([
      for cdn_key, cdn in local.cdn : [
        for alias in try(cdn.aliases, []) : {
          name    = module.cdn[cdn_key].cloudfront_distribution_domain_name
          zone_id = module.cdn[cdn_key].cloudfront_distribution_hosted_zone_id
          alias   = alias
          cdn     = cdn_key
        }
      ]]) : format("%v-%v", v.cdn, v.alias) => {
      name    = v.name
      zone_id = v.zone_id
      alias   = v.alias
    }
  } : {}
}

module "cdn" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 3.0"

  for_each = local.cdn

  price_class                  = try(each.value.price_class, "PriceClass_All")
  wait_for_deployment          = try(each.value.wait_for_deployment, false)
  default_root_object          = try(each.value.default_root_object, null)
  create_origin_access_control = try(each.value.create_origin_access_control, false)
  origin_access_control        = try(each.value.origin_access_control, { (each.key) = { description = "", origin_type = "s3", signing_behavior = "always", signing_protocol = "sigv4" } })
  origin                       = try(each.value.origin, null)
  default_cache_behavior       = try(each.value.default_cache_behavior, null)
  custom_error_response        = try(each.value.custom_error_response, null)
  aliases                      = try(each.value.aliases, null)

  viewer_certificate = try(each.value.certificate_arn, null) != null ? {
    acm_certificate_arn = each.value.certificate_arn
    ssl_support_method  = "sni-only"
    } : {
    "cloudfront_default_certificate" : true,
    "minimum_protocol_version" : "TLSv1"
  }

  tags = local.tags
}

resource "aws_route53_record" "cdn" {
  for_each = local.cdn_records

  zone_id = var.zone_id
  name    = each.value.alias
  type    = "A"

  alias {
    name                   = each.value.name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket_policy" "s3_origin_access_control" {
  for_each = local.cdn

  bucket = module.buckets[each.key].s3_bucket_id
  policy = data.aws_iam_policy_document.s3_origin_access_control[each.key].json
}

data "aws_iam_policy_document" "s3_origin_access_control" {
  for_each = local.cdn

  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = [format("%v/*", module.buckets[each.key].s3_bucket_arn)]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values = [
        module.cdn[each.key].cloudfront_distribution_arn
      ]
    }
  }
}
