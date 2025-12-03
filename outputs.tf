output "s3_bucket_name" {
  description = "The name of the S3 bucket created"
  value       = aws_s3_bucket.ingestion_bucket.bucket
}

output "dynamodb_table_name" {
  description = "The name of DynamoDB table created"
  value       = aws_dynamodb_table.ingestion_table.name
}

output "lambda_role_arn" {
  description = "IAM role for Lambda"
  value       = aws_iam_role.lambda_role.arn
}