output "guardrail_identifier" {
  description = "Guardrail ARN for runtime Bedrock calls."
  value       = aws_bedrock_guardrail.recruiter.guardrail_arn
}

output "guardrail_version" {
  description = "Published guardrail version for runtime Bedrock calls."
  value       = aws_bedrock_guardrail_version.recruiter.version
}

output "bedrock_invocation_log_group" {
  description = "CloudWatch Logs group used for Bedrock invocation logs."
  value       = aws_cloudwatch_log_group.bedrock_invocations.name
}

output "bedrock_invocation_log_bucket" {
  description = "S3 bucket used for Bedrock invocation logs."
  value       = aws_s3_bucket.bedrock_logs.bucket
}

output "cloudtrail_name" {
  description = "CloudTrail resource created for audit logging."
  value       = aws_cloudtrail.account_audit.name
}
