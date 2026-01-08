# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_s3_trigger_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

# Attach basic execution policy for Lambda logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda access to DynamoDB, SNS, and S3
resource "aws_iam_role_policy" "lambda_access_policy" {
  name = "lambda_dynamodb_sns_s3_access"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.image_metadata_table.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.image_upload_topic.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.source_bucket.arn}/*",
          "${aws_s3_bucket.destination_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Source S3 Bucket
resource "aws_s3_bucket" "source_bucket" {
  bucket = local.source_bucket_name

  tags = local.common_tags
}

# Destination S3 Bucket
resource "aws_s3_bucket" "destination_bucket" {
  bucket = local.dest_bucket_name

  tags = local.common_tags
}

# Block public access for destination bucket
resource "aws_s3_bucket_public_access_block" "destination_bucket_access_block" {
  bucket = aws_s3_bucket.destination_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lambda Function
resource "aws_lambda_function" "image_processor_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "processImageUpload"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("lambda_function.zip")
  runtime          = "python3.9"
  timeout          = 10

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.image_metadata_table.name
      SNS_TOPIC_ARN       = aws_sns_topic.image_upload_topic.arn
      DESTINATION_BUCKET  = aws_s3_bucket.destination_bucket.bucket
    }
  }

  depends_on = [aws_iam_role_policy.lambda_access_policy]

  tags = local.common_tags
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
}

# S3 Bucket Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_lambda]
}

# DynamoDB Table for Image Metadata
resource "aws_dynamodb_table" "image_metadata_table" {
  name         = "ImageMetadataTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ImageKey"

  attribute {
    name = "ImageKey"
    type = "S"
  }

  tags = local.common_tags
}

# SNS Topic for Notifications
resource "aws_sns_topic" "image_upload_topic" {
  name = "ImageUploadNotificationTopic"

  tags = local.common_tags
}

# SNS Topic Subscription (Email)
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.image_upload_topic.arn
  protocol  = "email"
  endpoint  = var.email_endpoint
}
