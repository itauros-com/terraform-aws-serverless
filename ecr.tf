locals {
  ecr = { for k, v in var.ecr : k => {
    repository_name                    = coalesce(v.repository_name, format("%v/%v", local.prefix, k))
    repository_read_access_arns        = v.repository_read_access_arns
    repository_lambda_read_access_arns = v.repository_lambda_read_access_arns
  } }
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "3.1.0"

  for_each = local.ecr

  repository_name = each.value.repository_name

  repository_read_access_arns        = each.value.repository_read_access_arns
  repository_lambda_read_access_arns = each.value.repository_lambda_read_access_arns

  repository_image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
  repository_image_tag_mutability_exclusion_filter = [
    {
      filter      = "latest*"
      filter_type = "WILDCARD"
    },
    {
      filter      = "dev-*"
      filter_type = "WILDCARD"
    },
    {
      filter      = "qa-*"
      filter_type = "WILDCARD"
    }
  ]

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 untagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = format("%v-%v", local.prefix, each.key)
  })
}
