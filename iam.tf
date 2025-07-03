data "aws_iam_policy_document" "this" {
  for_each = var.policies

  statement {
    effect  = each.value.effect
    actions = each.value.actions
    resources = [
      for v in each.value.resources : (
        each.value.service == "dynamodb" ? module.dynamodb_tables[v].dynamodb_table_arn :
        each.value.service == "secretsmanager" ? module.secrets[v].secret_arn :
        each.value.service == "sqs" ? module.sqs[v].queue_arn :
        each.value.service == "sns" ? module.sns[v].topic_arn :
        each.value.service == "s3" ? (
          strcontains(v, "/") ?
          format("%v/%v", module.buckets[split("/", v)[0]].s3_bucket_arn, join("/", slice(split("/", v), 1, length(split("/", v))))) :
          module.buckets[v].s3_bucket_arn
        ) :
        v
      )
    ]
  }
}

