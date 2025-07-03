locals {
  env    = terraform.workspace
  prefix = format("%v-%v", var.project, local.env)

  tags = merge(var.tags, {
    "Environment" = local.env
  })
}

data "aws_caller_identity" "current" {}

