locals {
  name_prefix                = lower(var.project_name)
  guardrail_name             = "${local.name_prefix}-recruiter-guardrail"
  bedrock_logs_prefix        = "bedrock"
  bedrock_logs_bucket_name   = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-bedrock-logs"
  cloudtrail_bucket_name     = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-cloudtrail"
  bedrock_service_source_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "bedrock_logging_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bedrock_service_source_arn]
    }
  }
}

data "aws_iam_policy_document" "bedrock_logging_role_policy" {
  statement {
    sid = "WriteBedrockInvocationLogs"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "${aws_cloudwatch_log_group.bedrock_invocations.arn}:log-stream:aws/bedrock/modelinvocations",
    ]
  }
}

data "aws_iam_policy_document" "bedrock_logs_bucket_policy" {
  statement {
    sid = "AmazonBedrockLogsWrite"

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.bedrock_logs.arn}/${local.bedrock_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/BedrockModelInvocationLogs/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bedrock_service_source_arn]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid = "AWSCloudTrailAclCheck"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  statement {
    sid = "AWSCloudTrailWrite"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket" "bedrock_logs" {
  bucket        = local.bedrock_logs_bucket_name
  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_public_access_block" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  rule {
    id     = "expire-bedrock-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.s3_log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id
  policy = data.aws_iam_policy_document.bedrock_logs_bucket_policy.json
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/aws/bedrock/${local.name_prefix}/model-invocations"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "bedrock_logging" {
  name               = "${local.name_prefix}-bedrock-logging-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_logging_assume_role.json
}

resource "aws_iam_role_policy" "bedrock_logging" {
  name   = "${local.name_prefix}-bedrock-logging"
  role   = aws_iam_role.bedrock_logging.id
  policy = data.aws_iam_policy_document.bedrock_logging_role_policy.json
}

resource "aws_bedrock_guardrail" "recruiter" {
  name                      = local.guardrail_name
  description               = "Guardrail for recruiter resume evaluation workloads."
  blocked_input_messaging   = "Your request was blocked by the Bedrock guardrail."
  blocked_outputs_messaging = "The model response was blocked by the Bedrock guardrail."

  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "SEXUAL"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }

    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      action = "ANONYMIZE"
      type   = "EMAIL"
    }

    pii_entities_config {
      action = "ANONYMIZE"
      type   = "PHONE"
    }
  }
}

resource "aws_bedrock_guardrail_version" "recruiter" {
  guardrail_arn = aws_bedrock_guardrail.recruiter.guardrail_arn
  description   = "Published version for recruiter resume evaluation guardrail."
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  depends_on = [
    aws_iam_role_policy.bedrock_logging,
    aws_s3_bucket_policy.bedrock_logs,
  ]

  logging_config {
    text_data_delivery_enabled      = true
    image_data_delivery_enabled     = false
    embedding_data_delivery_enabled = false
    video_data_delivery_enabled     = false

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations.name
      role_arn       = aws_iam_role.bedrock_logging.arn

      large_data_delivery_s3_config {
        bucket_name = aws_s3_bucket.bedrock_logs.id
        key_prefix  = local.bedrock_logs_prefix
      }
    }

    s3_config {
      bucket_name = aws_s3_bucket.bedrock_logs.id
      key_prefix  = local.bedrock_logs_prefix
    }
  }
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = local.cloudtrail_bucket_name
  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-cloudtrail-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.s3_log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

resource "aws_cloudtrail" "account_audit" {
  depends_on = [aws_s3_bucket_policy.cloudtrail]

  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true
}
