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
  region = var.aws_region. # Region to Create AWS Resources from Variables file
}

# Random suffix for globally-unique S3 bucket name
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
  bucket = "${var.bucket_prefix}-${random_string.suffix.result}"   # Construct bucket name with random suffix
  force_destroy = false                                             # Prevent deletion if objects exist
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.ingestion_bucket.id        # Enable versioning on the bucket

  versioning_configuration {
    status = "Enabled"                                # Keep all object versions
  }
}

# -----------------------------
# DynamoDB Table
# -----------------------------
resource "aws_dynamodb_table" "ingestion_table" {
  name         = var.dynamodb_table_name    # Table name from variables
  billing_mode = "PAY_PER_REQUEST"          # On-demand billing (no capacity settings)

  hash_key = "id"                           # Partition key named "id"

  attribute {
    name = "id"                             # Define attribute named "id"
    type = "S"                              # Attribute type = string
  }
}

# -----------------------------
# IAM Role for Lambda
# -----------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda_s3_to_dynamodb_role"                # Name of the IAM role for Lambda

  assume_role_policy = jsonencode({                  # Trust policy so Lambda can assume this role
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"                     # Lambda requests STS to assume role
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"            # Only Lambda can use this role
        }
      }
    ]
  })
}

# Policy for DynamoDB write access
resource "aws_iam_policy" "dynamodb_write_policy" {
  name = "lambda_dynamodb_write_policy"                 # Policy name for DynamoDB access

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"                                # Allow Lambda to write to DynamoDB
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.ingestion_table.arn  # Only this table
      }
    ]
  })
}

# Policy for S3 read access
resource "aws_iam_policy" "s3_read_policy" {
  name = "lambda_s3_read_policy"                       # Policy name for S3 read access 

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"                               # Allow Lambda to read objects in S3
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.ingestion_bucket.arn}/*". # Only objects inside this bucket
      }
    ]
  })
}

# Attach both policies to lambda role
resource "aws_iam_role_policy_attachment" "attach_dynamodb_policy" {
  role       = aws_iam_role.lambda_role.name                        # Attach DynamoDB policy to role
  policy_arn = aws_iam_policy.dynamodb_write_policy.arn             # Policy ARN reference
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.lambda_role.name                        # Attach S3 read policy to role
  policy_arn = aws_iam_policy.s3_read_policy.arn                    # Policy ARN reference
}

resource "aws_iam_role_policy_attachment" "attach_basic_execution" {
  role       = aws_iam_role.lambda_role.name                        # Attach AWS-managed Lambda logging policy
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"  # Allows CloudWatch logs
}

