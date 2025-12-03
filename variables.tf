variable "aws_region" {
  description = "AWS region to deploy the resources"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name"
  type        = string
  default     = "s3-ingestion-demo"
}

variable "dynamodb_table_name" {
  description = "Name for the DynamoDB ingestion table"
  type        = string
  default     = "ingestion_table"
}
