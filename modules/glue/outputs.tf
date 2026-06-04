output "job_arn" {
  value = aws_glue_job.this.arn
}

output "job_name" {
  value = aws_glue_job.this.name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
