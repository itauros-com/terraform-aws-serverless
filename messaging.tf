locals {
  sns = {
    for k, v in var.sns : k => {
      content_based_deduplication = v.content_based_deduplication
      fifo_topic                  = v.fifo_topic
      name                        = coalesce(v.name, format("%v-%v", local.prefix, k))
      subscriptions               = v.subscriptions
      topic_policy_statements     = v.topic_policy_statements
    }
  }
  sqs = {
    for k, v in var.sqs : k => {
      name                        = coalesce(v.name, format("%v-%v", local.prefix, k))
      fifo_queue                  = v.fifo_queue
      create_dlq                  = v.create_dlq
      content_based_deduplication = v.content_based_deduplication
      visibility_timeout_seconds  = v.visibility_timeout_seconds
    }
  }

  sns_sqs_subscriptions = {
    for v in flatten([
      for sns_key, sns in local.sns : [
        for sub_key, sub in sns.subscriptions : {
          sns_key              = sns_key
          sub_key              = sub_key
          endpoint             = sub.endpoint
          filter_policy        = sub.filter_policy
          filter_policy_scope  = sub.filter_policy != null ? sub.filter_policy_scope : null
          raw_message_delivery = sub.raw_message_delivery
        } if sub.protocol == "sqs"
      ]
    ]) : format("%v-%v", v.sns_key, v.sub_key) => v
  }

  sns_topics_with_sqs = {
    for sns_key, sns in local.sns : sns_key => {
      topic_arn = module.sns[sns_key].topic_arn
      sqs_endpoints = [
        for sub_key, sub in sns.subscriptions : try(module.sqs[sub.endpoint].queue_arn, sub.endpoint)
        if sub.protocol == "sqs"
      ]
    } if length([for sub in sns.subscriptions : sub if sub.protocol == "sqs"]) > 0
  }

  # SQS allows ONE Policy attribute per queue. When multiple SNS topics
  # publish to the same queue (fan-in), we must emit a single
  # aws_sqs_queue_policy with one statement per source topic — not one
  # policy per subscription, which would race-overwrite and only the
  # last writer's policy survives. Group subscriptions by endpoint queue.
  sns_sqs_subscriptions_by_endpoint = {
    for endpoint in distinct([for s in local.sns_sqs_subscriptions : s.endpoint]) :
    endpoint => [for s in local.sns_sqs_subscriptions : s if s.endpoint == endpoint]
  }
}

module "sns" {
  source  = "terraform-aws-modules/sns/aws"
  version = "~> 6.0"

  for_each = local.sns

  name                        = each.value.name
  fifo_topic                  = each.value.fifo_topic
  content_based_deduplication = each.value.content_based_deduplication
  create_topic_policy         = false
  enable_default_topic_policy = false
}

module "sqs" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.0"

  for_each = local.sqs

  name                        = each.value.name
  fifo_queue                  = each.value.fifo_queue
  create_dlq                  = each.value.create_dlq
  content_based_deduplication = each.value.content_based_deduplication
  visibility_timeout_seconds  = each.value.visibility_timeout_seconds
}

data "aws_iam_policy_document" "sns" {
  for_each = local.sns_topics_with_sqs

  statement {
    effect = "Allow"
    actions = [
      "sns:Subscribe",
      "sns:Receive",
    ]
    resources = [each.value.topic_arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringLike"
      variable = "sns:Endpoint"
      values   = each.value.sqs_endpoints
    }
  }
}

resource "aws_sns_topic_policy" "sns" {
  for_each = local.sns_topics_with_sqs

  arn    = each.value.topic_arn
  policy = data.aws_iam_policy_document.sns[each.key].json
}

data "aws_iam_policy_document" "sqs" {
  for_each = local.sns_sqs_subscriptions_by_endpoint

  dynamic "statement" {
    for_each = each.value
    content {
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [module.sqs[each.key].queue_arn]

      principals {
        type        = "Service"
        identifiers = ["sns.amazonaws.com"]
      }

      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [module.sns[statement.value.sns_key].topic_arn]
      }
    }
  }
}

resource "aws_sqs_queue_policy" "sqs" {
  for_each = local.sns_sqs_subscriptions_by_endpoint

  queue_url = try(module.sqs[each.key].queue_url, each.key)
  policy    = data.aws_iam_policy_document.sqs[each.key].json
}

resource "aws_sns_topic_subscription" "sqs" {
  for_each = local.sns_sqs_subscriptions

  topic_arn            = module.sns[each.value.sns_key].topic_arn
  protocol             = "sqs"
  endpoint             = try(module.sqs[each.value.endpoint].queue_arn, each.value.endpoint)
  filter_policy        = each.value.filter_policy
  filter_policy_scope  = each.value.filter_policy_scope
  raw_message_delivery = each.value.raw_message_delivery
}

# Preserve aws_sqs_queue_policy state across the refactor from
# per-subscription keys (sns_key-sub_key) to per-queue keys (endpoint).
# Each block is a no-op if the source key isn't in state for the
# current workspace, so all envs can share the same set of moves.
moved {
  from = aws_sqs_queue_policy.sqs["operations-sqs"]
  to   = aws_sqs_queue_policy.sqs["operations"]
}
moved {
  from = aws_sqs_queue_policy.sqs["operation_actions-history"]
  to   = aws_sqs_queue_policy.sqs["history"]
}
moved {
  from = aws_sqs_queue_policy.sqs["operation_actions-emails"]
  to   = aws_sqs_queue_policy.sqs["emails"]
}
moved {
  from = aws_sqs_queue_policy.sqs["operation_actions-embeddings"]
  to   = aws_sqs_queue_policy.sqs["embeddings"]
}
moved {
  from = aws_sqs_queue_policy.sqs["operation_actions-docmetadata"]
  to   = aws_sqs_queue_policy.sqs["docmetadata"]
}
moved {
  from = aws_sqs_queue_policy.sqs["operation_actions-docgen"]
  to   = aws_sqs_queue_policy.sqs["docgen"]
}
moved {
  from = aws_sqs_queue_policy.sqs["operation_actions-notifications"]
  to   = aws_sqs_queue_policy.sqs["notifications"]
}
