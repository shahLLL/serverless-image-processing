# Data source to fetch the current AWS caller identity
data "aws_caller_identity" "current" {}

# Locals for common values
locals {
  account_id         = data.aws_caller_identity.current.account_id
  source_bucket_name = "image-processing-source-bucket-${local.account_id}"
  dest_bucket_name   = "image-processed-destination-bucket-${local.account_id}"
  common_tags        = {
    Project = var.project_name
  }
}