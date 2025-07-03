variable "workspace_iam_roles" {
  type        = map(string)
  description = "Workspace IAM roles"
  default     = {}
}

variable "project" {
  type        = string
  description = "Project name"
}

variable "apigateways" {
  type = map(object({
    authorizers = optional(map(object({
      authorizer_credentials_arn        = optional(string)
      authorizer_payload_format_version = optional(string, "2.0")
      authorizer_result_ttl_in_seconds  = optional(number)
      authorizer_type                   = optional(string, "REQUEST")
      authorizer_uri                    = optional(string)
      enable_simple_responses           = optional(bool)
      identity_sources                  = optional(list(string), [])
      jwt_configuration = optional(object({
        audience = optional(list(string))
        issuer   = optional(string)
      }))
      lambda = optional(string)
      name   = optional(string)
    })), {})
    cors_configuration = optional(object({
      allow_credentials = optional(bool)
      allow_headers     = optional(list(string), ["content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token", "x-amz-user-agent"])
      allow_methods     = optional(list(string))
      allow_origins     = optional(list(string))
      expose_headers    = optional(list(string), [])
      max_age           = optional(number)
    }))
    create_certificate    = optional(bool, true)
    create_domain_name    = optional(bool, true)
    create_domain_records = optional(bool, true)
    deploy_stage          = optional(bool, true)
    description           = optional(string)
    name                  = optional(string, "")
    routes = optional(map(map(object({
      authorizer_key     = optional(string)
      authorization_type = optional(string, "NONE")
      integration = optional(object({
        type                   = optional(string, "AWS_PROXY")
        connection_type        = optional(string, "INTERNET")
        method                 = optional(string, "POST")
        passthrough_behavior   = optional(string, "WHEN_NO_MATCH")
        payload_format_version = optional(string, "2.0")
        }), {
        type                   = "AWS_PROXY"
        connection_type        = "INTERNET"
        method                 = "POST"
        passthrough_behavior   = "WHEN_NO_MATCH"
        payload_format_version = "2.0"
      })
    }))), {})
    stage_access_log_settings = optional(object({
      create_log_group = optional(bool, true)
      destination_arn  = optional(string)
      format = optional(any, {
        context = {
          domainName              = "$context.domainName"
          integrationErrorMessage = "$context.integrationErrorMessage"
          protocol                = "$context.protocol"
          requestId               = "$context.requestId"
          requestTime             = "$context.requestTime"
          responseLength          = "$context.responseLength"
          routeKey                = "$context.routeKey"
          stage                   = "$context.stage"
          status                  = "$context.status"
          error = {
            message      = "$context.error.message"
            responseType = "$context.error.responseType"
          }
          identity = {
            sourceIP = "$context.identity.sourceIp"
          }
          integration = {
            error             = "$context.integration.error"
            integrationStatus = "$context.integration.integrationStatus"
          }
        }
      })
      log_group_name              = optional(string)
      log_group_retention_in_days = optional(number, 30)
      log_group_kms_key_id        = optional(string)
      log_group_skip_destroy      = optional(bool)
      log_group_class             = optional(string)
      log_group_tags              = optional(map(string), {})
    }), {})
    stage_description = optional(string, null)
    stage_name        = optional(string, "$default")
    stage_tags        = optional(map(string), {})
    stage_variables   = optional(map(string), {})
    tags              = optional(map(string), {})
  }))
  default = {}
}

variable "buckets" {
  type = map(object({
    block_public_acls   = optional(bool, true)
    block_public_policy = optional(bool, true)
    bucket              = optional(string)
    bucket_prefix       = optional(string)
    cors_rules = optional(list(object({
      allowed_methods = optional(list(string))
      allowed_origins = optional(list(string))
      allowed_headers = optional(list(string))
    })), [])
    ignore_public_acls = optional(bool, true)
    lifecycle_rules = optional(list(object({
      id     = optional(string)
      status = optional(string)
      expiration = optional(object({
        date                         = optional(string)
        days                         = optional(number)
        expired_object_delete_marker = optional(bool)
      }))
      filter = optional(object({
        prefix = optional(string)
      }))
    })), [])
    restrict_public_buckets = optional(bool, true)
    tags                    = optional(map(string), {})
    website                 = optional(any, {})
  }))
  default = {}
}

variable "cloudfront" {
  type = map(object({
    aliases                      = optional(map(string), {})
    create_origin_access_control = optional(bool, false)
    custom_error_response = list(object({
      error_code         = optional(number)
      response_code      = optional(number)
      response_page_path = optional(string)
    }))
    default_cache_behavior = optional(object({
      allowed_methods        = optional(list(string))
      cached_methods         = optional(list(string))
      viewer_protocol_policy = optional(string)
    }))
    default_root_object = optional(string)
    origin = optional(map(object({
      domain_name = optional(string)
      s3_origin   = optional(bool, false)
      s3_bucket   = optional(string)
    })), {})
    origin_access_control = optional(map(object({
      description      = string
      origin_type      = string
      signing_behavior = string
      signing_protocol = string
      })), {
      s3 = {
        description      = "",
        origin_type      = "s3",
        signing_behavior = "always",
        signing_protocol = "sigv4"
      }
    })
    price_class         = optional(string, "PriceClass_All")
    tags                = optional(map(string), {})
    wait_for_deployment = optional(bool, true)
  }))
  default = {}
}

variable "dynamodb_tables" {
  type = map(object({
    attributes     = optional(list(map(string)), [])
    billing_mode   = optional(string, "PAY_PER_REQUEST")
    hash_key       = optional(string)
    name           = optional(string)
    read_capacity  = optional(number)
    tags           = optional(map(string), {})
    write_capacity = optional(number)
  }))
  default = {}
}

variable "functions" {
  type = map(object({
    architectures                     = optional(list(string), ["arm64"])
    cloudwatch_logs_retention_in_days = optional(number, 7)
    description                       = optional(string)
    environment_variables             = optional(map(string), {})
    event_source_mapping              = optional(any, {})
    function_name                     = optional(string)
    function_tags                     = optional(map(string), {})
    handler                           = optional(string, "bootstrap")
    local_existing_package            = optional(string, "functions/dummy/go/dist/bootstrap.zip")
    memory_size                       = optional(number, 128)
    policies                          = optional(list(string), [])
    runtime                           = optional(string, "provided.al2023")
    tags                              = optional(map(string), {})
    timeout                           = optional(number, 3)
    triggers = optional(map(object({
      action                 = optional(string, "lambda:InvokeFunction")
      principal              = optional(string)
      principal_org_id       = optional(string)
      service                = optional(string)
      source                 = optional(string)
      source_arn             = optional(string)
      source_account         = optional(string)
      event_source_token     = optional(string)
      function_url_auth_type = optional(string)
    })), {})
  }))
  default = {}
}

variable "policies" {
  type = map(object({
    service   = optional(string)
    effect    = optional(string)
    actions   = optional(list(string), [])
    resources = optional(list(string), [])
  }))
  default = {}
}

variable "secrets" {
  type = map(object({
    ignore_secret_changes = optional(bool, false)
    name                  = optional(string)
    secret_string         = optional(string, "{}")
    tags                  = optional(map(string), {})
  }))
  default = {}
}

variable "security_groups" {
  type = map(object({
    name        = optional(string)
    description = optional(string)
    egress_with_cidr_blocks = optional(list(object({
      from_port   = optional(number)
      to_port     = optional(number)
      protocol    = optional(string)
      cidr_blocks = optional(string)
    })), [])
    revoke_rules_on_delete = optional(bool, true)
    tags                   = optional(map(string), {})
    vpc_id                 = optional(string)
  }))
  default = {}
}

variable "sns" {
  type = map(object({
    content_based_deduplication = optional(bool, false)
    fifo_topic                  = optional(bool, false)
    name                        = optional(string)
    subscriptions = optional(map(object({
      protocol             = string
      endpoint             = string
      filter_policy        = optional(string)
      filter_policy_scope  = optional(string, "MessageAttributes")
    })), {})
    topic_policy_statements = optional(any, {})
  }))
  default = {}
}

variable "sqs" {
  type = map(object({
    name                        = optional(string)
    create_dlq                  = optional(bool, false)
    fifo_queue                  = optional(bool, false)
    content_based_deduplication = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags"
  default     = {}
}

variable "waf" {
  type = map(object({
    default_action                = optional(string, "block")
    enabled_logging_configuration = optional(bool, false)
    enabled_web_acl_association   = optional(bool, true)
    name                          = optional(string)
    resources = optional(list(object({
      service = optional(string)
      name    = optional(string)
    })), [])
    rules = any
    scope = optional(string, "REGIONAL")
    tags  = optional(map(string), {})
  }))
  default = {}
}
