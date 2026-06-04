variable "name" {
  type        = string
  description = "Glue job name (already prefixed by the caller)"
}

variable "description" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "job_type" {
  type        = string
  default     = "glueetl"
  description = "glueetl | pythonshell | glueray"
}

variable "glue_version" {
  type    = string
  default = "4.0"
}

variable "worker_type" {
  type        = string
  default     = null
  description = "G.025X | G.1X | G.2X — only for glueetl"
}

variable "number_of_workers" {
  type    = number
  default = null
}

variable "max_capacity" {
  type        = number
  default     = null
  description = "Only for pythonshell: 0.0625 or 1"
}

variable "timeout" {
  type        = number
  default     = 60
  description = "Job timeout in minutes"
}

variable "max_retries" {
  type    = number
  default = 0
}

variable "max_concurrent_runs" {
  type    = number
  default = 1
}

variable "script_location" {
  type        = string
  description = "Full S3 URI to the job script, e.g. s3://bucket/key/main.py"
}

variable "python_version" {
  type    = string
  default = "3"
}

variable "connections" {
  type        = list(string)
  default     = []
  description = "List of real Glue connection names (already resolved by the caller)"
}

variable "policy_jsons" {
  type        = list(string)
  default     = []
  description = "List of inline IAM policy JSON documents to attach to the job role"
}

variable "default_arguments" {
  type        = map(string)
  default     = {}
  description = "Glue job default arguments, keys already prefixed with --"
}

variable "schedule" {
  type = object({
    type              = optional(string, "SCHEDULED")
    cron              = optional(string)
    start_on_creation = optional(bool, true)
    enabled           = optional(bool, true)
  })
  default = null
}

variable "eventbridge" {
  type = object({
    rule_name      = string
    input_template = optional(string)
  })
  default     = null
  description = "If set, register the job as target of an existing EventBridge rule"
}
