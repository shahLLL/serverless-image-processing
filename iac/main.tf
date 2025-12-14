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

# Create the Lambda Function
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
      DYNAMODB_TABLE_NAME  = aws_dynamodb_table.image_metadata_table.name
      SNS_TOPIC_ARN        = aws_sns_topic.image_upload_topic.arn
      DESTINATION_BUCKET   = aws_s3_bucket.destination_bucket.bucket
    }
  }
  
  depends_on = [aws_iam_role_policy.lambda_access_policy]
}

# Grant S3 permission to invoke the Lambda function
resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
}

# Configure the S3 Bucket to trigger the Lambda function
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor_lambda.arn
    events              = ["s3:ObjectCreated:*"] 
    filter_suffix       = ".jpg"
  }
  depends_on = [aws_lambda_permission.allow_s3_to_invoke_lambda]
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "image_metadata_table" {
  name           = "ImageMetadataTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ImageKey"

  attribute {
    name = "ImageKey"
    type = "S"
  }

  tags = {
    Project = "LambdaTrigger"
  }
}

# Give Permissions to Lambda
resource "aws_iam_role_policy" "lambda_access_policy" {
 name = "lambda_dynamodb_sns_s3_access"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # DynamoDB Write Access
      {
        Effect   = "Allow",
        Action   = ["dynamodb:PutItem"],
        Resource = aws_dynamodb_table.image_metadata_table.arn
      },
      # SNS Publish Access
      {
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.image_upload_topic.arn
      },
       # S3 Read/Write Access (Crucial for source and destination buckets)
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = [
          "${aws_s3_bucket.source_bucket.arn}/*",
          "${aws_s3_bucket.destination_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create SNS Topic
resource "aws_sns_topic" "image_upload_topic" {
  name = "ImageUploadNotificationTopic"
}
# Subscribe email to SNS Topic
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.image_upload_topic.arn
  protocol  = "email"
  endpoint  = "shahLLL@yahoo.com"
}

# Create Destination S3 Bucket
resource "aws_s3_bucket" "destination_bucket" {
  bucket = "image-processed-destination-bucket-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "destination_buckets_access_block" {
  bucket = aws_s3_bucket.destination_bucket.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}


