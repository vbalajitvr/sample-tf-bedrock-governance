variable "aws_region" {
  description = "AWS region where Bedrock governance resources are deployed."
  type        = string
}

variable "bedrock_region" {
  description = "AWS region where the Bedrock model is available."
  type        = string
}

variable "project_name" {
  description = "Base name used for AWS resources."
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model ID governed by this module."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
}

variable "s3_log_expiration_days" {
  description = "S3 log retention in days."
  type        = number
}

variable "force_destroy_buckets" {
  description = "Allow Terraform to delete non-empty sample buckets during destroy."
  type        = bool
}
