locals {
  security_groups = {
    for k, v in var.security_groups : k => {
      description             = v.description
      egress_with_cidr_blocks = v.egress_with_cidr_blocks
      name                    = coalesce(v.name, format("%v-%v", local.prefix, k))
      revoke_rules_on_delete  = v.revoke_rules_on_delete
      tags                    = merge(local.tags, v.tags)
      vpc_id                  = v.vpc_id
    }
  }
}

module "security_groups" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  for_each = local.security_groups

  description             = each.value.description
  egress_with_cidr_blocks = each.value.egress_with_cidr_blocks
  name                    = each.value.name
  revoke_rules_on_delete  = each.value.revoke_rules_on_delete
  tags                    = each.value.tags
  vpc_id                  = each.value.vpc_id
}
