locals {
  name        = "video-pipeline-${var.environment}"
  param_path  = "/video-pipeline/${var.environment}"
  secret_name = "video-pipeline/${var.environment}/db"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Infrastructure the app needs. AWS decides some of these values (the queue
# URL), so nobody should copy them into Helm values by hand.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "transcode" {
  name                       = "${local.name}-transcode-jobs"
  visibility_timeout_seconds = 900
  sqs_managed_sse_enabled    = true
}

resource "aws_s3_bucket" "output" {
  bucket_prefix = "${local.name}-output-"
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Infra publishes, apps consume: Terraform writes its outputs to Parameter
# Store, and ESO syncs them into the cluster.
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "queue_url" {
  name  = "${local.param_path}/transcode-queue-url"
  type  = "String"
  value = aws_sqs_queue.transcode.url
}

resource "aws_ssm_parameter" "output_bucket" {
  name  = "${local.param_path}/output-bucket"
  type  = "String"
  value = aws_s3_bucket.output.bucket
}

# ---------------------------------------------------------------------------
# The database password. The ephemeral resource and the write-only argument
# mean the password is generated and sent to AWS without ever being stored
# in the Terraform state file.
# ---------------------------------------------------------------------------

ephemeral "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name                    = local.secret_name
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string_wo = jsonencode({
    username = "transcoder"
    password = ephemeral.random_password.db.result
  })
  secret_string_wo_version = var.db_password_version
}
