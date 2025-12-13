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

