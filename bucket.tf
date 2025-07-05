locals {
  buckets = {
    for k, v in var.buckets : k => {
      block_public_acls       = v.block_public_acls
      block_public_policy     = v.block_public_policy
      bucket                  = coalesce(v.bucket, format("%v-%v", local.prefix, k))
      bucket_prefix           = v.bucket_prefix
      cors_rules              = v.cors_rules
      ignore_public_acls      = v.ignore_public_acls
      lifecycle_rules         = v.lifecycle_rules
      restrict_public_buckets = v.restrict_public_buckets
      tags                    = merge(local.tags, v.tags)
      website                 = v.website
      is_public               = alltrue([!v.block_public_policy, !v.block_public_policy, !v.ignore_public_acls, !v.restrict_public_buckets])
      distribution            = v.distribution
    }
  }
}

module "buckets" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  for_each = local.buckets

  block_public_acls       = each.value.block_public_acls
  block_public_policy     = each.value.block_public_policy
  bucket                  = each.value.bucket
  bucket_prefix           = each.value.bucket_prefix
  cors_rule               = each.value.cors_rules
  ignore_public_acls      = each.value.ignore_public_acls
  lifecycle_rule          = each.value.lifecycle_rules
  restrict_public_buckets = each.value.restrict_public_buckets
  tags                    = each.value.tags
  website                 = each.value.website

  attach_policy = each.value.is_public
  policy = each.value.is_public ? jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = format("arn:aws:s3:::%v/*", each.value.bucket)
      }
    ]
  }) : jsonencode({})
}
