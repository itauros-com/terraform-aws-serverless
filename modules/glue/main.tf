data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "inline" {
  count  = length(var.policy_jsons)
  name   = "${var.name}-inline-${count.index}"
  role   = aws_iam_role.this.id
  policy = var.policy_jsons[count.index]
}

resource "aws_glue_job" "this" {
  name              = var.name
  description       = var.description
  role_arn          = aws_iam_role.this.arn
  glue_version      = var.glue_version
  worker_type       = var.job_type == "glueetl" ? var.worker_type : null
  number_of_workers = var.job_type == "glueetl" ? var.number_of_workers : null
  max_capacity      = var.job_type == "pythonshell" ? var.max_capacity : null
  timeout           = var.timeout
  max_retries       = var.max_retries
  connections       = var.connections
  default_arguments = var.default_arguments
  tags              = var.tags

  execution_property {
    max_concurrent_runs = var.max_concurrent_runs
  }

  command {
    name            = var.job_type
    script_location = var.script_location
    python_version  = var.job_type == "glueetl" || var.job_type == "pythonshell" ? var.python_version : null
  }
}

resource "aws_glue_trigger" "this" {
  count = var.schedule != null && try(var.schedule.type, null) == "SCHEDULED" ? 1 : 0

  name              = "${var.name}-trigger"
  type              = "SCHEDULED"
  schedule          = var.schedule.cron
  start_on_creation = var.schedule.start_on_creation
  enabled           = var.schedule.enabled
  tags              = var.tags

  actions {
    job_name = aws_glue_job.this.name
  }
}

data "aws_iam_policy_document" "eventbridge_assume" {
  count = var.eventbridge != null ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eventbridge_start" {
  count = var.eventbridge != null ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["glue:StartJobRun"]
    resources = [aws_glue_job.this.arn]
  }
}

resource "aws_iam_role" "eventbridge" {
  count              = var.eventbridge != null ? 1 : 0
  name               = "${var.name}-eb-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "eventbridge_start" {
  count  = var.eventbridge != null ? 1 : 0
  name   = "${var.name}-eb-start"
  role   = aws_iam_role.eventbridge[0].id
  policy = data.aws_iam_policy_document.eventbridge_start[0].json
}

resource "aws_cloudwatch_event_target" "this" {
  count = var.eventbridge != null ? 1 : 0

  rule      = var.eventbridge.rule_name
  target_id = var.name
  arn       = aws_glue_job.this.arn
  role_arn  = aws_iam_role.eventbridge[0].arn
  input     = var.eventbridge.input_template
}
