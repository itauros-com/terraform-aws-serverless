data "aws_vpc" "this" {
  for_each = toset([
    for k, v in var.security_groups : v.vpc_id
    if v.vpc_id != null && !startswith(v.vpc_id, "vpc-")
  ])

  filter {
    name   = "tag:Name"
    values = [each.value]
  }
}

locals {
  security_groups = {
    for k, v in var.security_groups : k => {
      description = v.description
      egress_with_cidr_blocks = [
        for e in v.egress_with_cidr_blocks : merge(e, {
          cidr_blocks = try(data.aws_vpc.this[e.cidr_blocks].cidr_block, e.cidr_blocks)
        })
      ]
      egress_with_source_security_group_id = v.egress_with_source_security_group_id
      ingress_with_self                    = v.ingress_with_self
      egress_with_self                     = v.egress_with_self
      name                                 = coalesce(v.name, format("%v-%v", local.prefix, k))
      revoke_rules_on_delete               = v.revoke_rules_on_delete
      tags                                 = merge(local.tags, v.tags)
      vpc_id                               = try(data.aws_vpc.this[v.vpc_id].id, v.vpc_id)
    }
  }
}

module "security_groups" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  for_each = local.security_groups

  description                          = each.value.description
  egress_with_cidr_blocks              = each.value.egress_with_cidr_blocks
  egress_with_source_security_group_id = each.value.egress_with_source_security_group_id
  ingress_with_self                    = each.value.ingress_with_self
  egress_with_self                     = each.value.egress_with_self
  name                                 = each.value.name
  revoke_rules_on_delete               = each.value.revoke_rules_on_delete
  tags                                 = each.value.tags
  vpc_id                               = each.value.vpc_id
}
