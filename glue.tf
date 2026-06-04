locals {
  glue_connections = {
    for k, v in var.glue.connections : k => {
      name                  = coalesce(v.name, format("%v-conn-%v", local.prefix, k))
      description           = v.description
      subnet_id             = v.subnet_id
      availability_zone     = v.availability_zone
      security_group_ids    = [for sg in v.security_group_ids : try(module.security_groups[sg].security_group_id, sg)]
      connection_properties = v.connection_properties
      tags                  = merge(local.tags, v.tags)
    }
  }
}

resource "aws_glue_connection" "this" {
  for_each = local.glue_connections

  name            = each.value.name
  description     = each.value.description
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = each.value.availability_zone
    subnet_id              = each.value.subnet_id
    security_group_id_list = each.value.security_group_ids
  }

  connection_properties = each.value.connection_properties
  tags                  = each.value.tags
}

module "glue" {
  source   = "./modules/glue"
  for_each = var.glue.jobs

  name        = coalesce(each.value.name, format("%v-%v", local.prefix, each.key))
  description = each.value.description
  tags        = merge(local.tags, each.value.tags)

  job_type            = each.value.job_type
  glue_version        = each.value.glue_version
  worker_type         = each.value.worker_type
  number_of_workers   = each.value.number_of_workers
  max_capacity        = each.value.max_capacity
  timeout             = each.value.timeout
  max_retries         = each.value.max_retries
  max_concurrent_runs = each.value.max_concurrent_runs

  script_location = format("s3://%v/%v",
    try(module.buckets[each.value.script_bucket].s3_bucket_id, each.value.script_bucket),
    each.value.script_key
  )
  python_version = each.value.python_version

  connections  = [for c in each.value.connections : aws_glue_connection.this[c].name]
  policy_jsons = [for p in each.value.policies : data.aws_iam_policy_document.this[p].json]

  default_arguments = merge(
    each.value.default_arguments,
    { for k, v in each.value.environment_arguments : "--${k}" => v }
  )

  schedule    = each.value.schedule
  eventbridge = each.value.eventbridge
}
