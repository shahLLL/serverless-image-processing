# Configure AWS Provider
provider "aws" {
    region = "us-west-2"
}

# Data source to fetch the current AWS caller identity
data "aws_caller_identity" "current" {}

# Create Source S3 Bucket
resource "aws_s3_bucket" "source_bucket" {
  bucket = "image-processing-source-bucket-${data.aws_caller_identity.current.account_id}"
  tags = {
    Project = "LambdaTrigger"
  }
}

# Create Lambda Execution Role
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_s3_trigger_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
