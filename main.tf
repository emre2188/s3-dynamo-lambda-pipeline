terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------
# Random suffix for unique S3 bucket
# -----------------------------
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

# -----------------------------
# S3 Bucket
# -----------------------------
resource "aws_s3_bucket" "ingestion_bucket" {
  bucket = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.ingestion_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------
# DynamoDB Table: composite key
# -----------------------------
resource "aws_dynamodb_table" "chronic_disease" {
  name         = "chronic-disease-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LocationAbbr"

  attribute {
    name = "LocationAbbr"
    type = "S"
  }
}


# -----------------------------
# IAM Role for Lambda
# -----------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda_s3_to_dynamodb_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# DynamoDB write policy
resource "aws_iam_policy" "dynamodb_write_policy" {
  name = "lambda_dynamodb_write_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.chronic_disease.arn
      }
    ]
  })
}

# S3 read + list policy
resource "aws_iam_policy" "s3_read_policy" {
  name = "lambda_s3_read_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.ingestion_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.ingestion_bucket.arn
      }
    ]
  })
}

# Attach policies to role
resource "aws_iam_role_policy_attachment" "attach_dynamodb_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_write_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------
# Lambda ZIP Archive
# -----------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# -----------------------------
# Lambda Function
# -----------------------------
resource "aws_lambda_function" "s3_ingestion_lambda" {
  function_name = "s3_to_dynamodb_ingestion"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.chronic_disease.name
    }
  }

  timeout     = 300  # seconds, enough for large files
  memory_size = 1024 # MB, more memory for faster processing
}



# -----------------------------
# Allow S3 to invoke Lambda
# -----------------------------
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_ingestion_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.ingestion_bucket.arn
}

# -----------------------------
# S3 → Lambda Trigger
# -----------------------------
resource "aws_s3_bucket_notification" "notify_lambda" {
  bucket = aws_s3_bucket.ingestion_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_ingestion_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.allow_s3
  ]
}
