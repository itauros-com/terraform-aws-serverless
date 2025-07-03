locals {
  secrets = {
    for k, v in var.secrets : k => {
      ignore_secret_changes = v.ignore_secret_changes
      name                  = coalesce(v.name, format("%v-%v", local.prefix, k))
      secret_string         = v.secret_string
      tags                  = merge(local.tags, v.tags)
    }
  }
}

module "secrets" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.0"

  for_each = local.secrets

  ignore_secret_changes = each.value.ignore_secret_changes
  name                  = each.value.name
  secret_string         = each.value.secret_string
  tags                  = each.value.tags
}
