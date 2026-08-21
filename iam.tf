data "aws_iam_policy_document" "this" {
  for_each = var.policies

  statement {
    effect  = each.value.effect
    actions = each.value.actions
    # flatten, perche' una risorsa dynamodb ne produce due: la tabella e i suoi
    # indici. Una Query su una GSI richiede il permesso sull'ARN dell'indice, e senza
    # viene negata a runtime — un errore che si scopre in produzione, non al plan.
    # Non e' un allargamento: un indice e' una proiezione della stessa tabella, su cui
    # il permesso e' gia' concesso.
    resources = flatten([
      for v in each.value.resources : (
        each.value.service == "dynamodb" ? [
          module.dynamodb_tables[v].dynamodb_table_arn,
          format("%v/index/*", module.dynamodb_tables[v].dynamodb_table_arn),
        ] :
        each.value.service == "secretsmanager" ? [module.secrets[v].secret_arn] :
        each.value.service == "sqs" ? [module.sqs[v].queue_arn] :
        each.value.service == "sns" ? [module.sns[v].topic_arn] :
        each.value.service == "s3" ? [
          strcontains(v, "/") ?
          format("%v/%v", module.buckets[split("/", v)[0]].s3_bucket_arn, join("/", slice(split("/", v), 1, length(split("/", v))))) :
          module.buckets[v].s3_bucket_arn
        ] :
        [v]
      )
    ])
  }
}

