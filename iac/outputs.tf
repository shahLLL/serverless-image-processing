# Output the names of key resources
output "source_bucket_name" {
  value = aws_s3_bucket.source_bucket.bucket
}

output "destination_bucket_name" {
  value = aws_s3_bucket.destination_bucket.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.image_upload_topic.arn
}
