locals {
  dynamodb_tables = {
    for k, v in var.dynamodb_tables : k => {
      attributes     = v.attributes
      billing_mode   = v.billing_mode
      hash_key       = v.hash_key
      name           = coalesce(v.name, format("%v-%v", local.prefix, k))
      read_capacity  = v.read_capacity
      tags           = merge(local.tags, v.tags)
      write_capacity = v.write_capacity

    }
  }
}

module "dynamodb_tables" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 4.0"

  for_each = local.dynamodb_tables

  attributes     = each.value.attributes
  billing_mode   = each.value.billing_mode
  hash_key       = each.value.hash_key
  name           = each.value.name
  read_capacity  = each.value.read_capacity
  tags           = each.value.tags
  write_capacity = each.value.write_capacity
}

