locals {
  env    = terraform.workspace
  prefix = format("%v-%v", var.project, local.env)

  tags = merge(var.tags, {
    "Environment" = local.env
  })
}

data "aws_caller_identity" "current" {}

terraform {
  backend "s3" {
    bucket               = "itauros-terraform"
    key                  = "serverless-api"
    region               = "eu-west-1"
    use_lockfile         = true
    workspace_key_prefix = "powerflow"
  }
}

provider "aws" {
  assume_role {
    role_arn = var.workspace_iam_roles[terraform.workspace]
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  assume_role {
    role_arn = var.workspace_iam_roles[terraform.workspace]
  }
}
