import json
import logging
import os
from datetime import datetime
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

# ------------------- Logging Setup -------------------
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# ------------------- Configuration -------------------
class Config:
    def __init__(self):
        self.dynamodb_table = os.environ["DYNAMODB_TABLE_NAME"]
        self.sns_topic_arn = os.environ["SNS_TOPIC_ARN"]
        self.destination_bucket = os.environ["DESTINATION_BUCKET"]
        self.processed_prefix = os.environ.get("PROCESSED_PREFIX", "processed/")

        missing = [
            name for name, value in [
                ("DYNAMODB_TABLE_NAME", self.dynamodb_table),
                ("SNS_TOPIC_ARN", self.sns_topic_arn),
                ("DESTINATION_BUCKET", self.destination_bucket),
            ] if not value
        ]

        if missing:
            raise ValueError(f"Missing required environment variables: {', '.join(missing)}")


# ------------------- Global Clients -------------------
s3_client = boto3.client("s3")
dynamodb_resource = boto3.resource("dynamodb")
sns_client = boto3.client("sns")

# ------------------- Helper Functions -------------------
def copy_image_to_destination(
    source_bucket: str, object_key: str, config: Config
) -> None:
    """Copy the image to destination bucket - critical step"""
    dest_key = f"{config.processed_prefix}{object_key}"

    try:
        s3_client.copy_object(
            Bucket=config.destination_bucket,
            CopySource={"Bucket": source_bucket, "Key": object_key},
            Key=dest_key,
        )
        logger.info(
            "Image copied successfully",
            extra={
                "source": f"{source_bucket}/{object_key}",
                "destination": f"{config.destination_bucket}/{dest_key}",
            },
        )
    except ClientError as e:
        logger.error(
            "Failed to copy image to destination bucket",
            exc_info=True,
            extra={"source_bucket": source_bucket, "key": object_key, "error": str(e)},
        )
        raise  # Critical failure → whole batch should fail


def store_metadata(
    object_key: str, source_bucket: str, config: Config, event_time: str
) -> None:
    """Store metadata in DynamoDB - best effort"""
    try:
        table = dynamodb_resource.Table(config.dynamodb_table)
        table.put_item(
            Item={
                "ImageKey": object_key,
                "SourceBucket": source_bucket,
                "DestinationBucket": config.destination_bucket,
                "UploadTime": event_time,
                "ProcessedAt": datetime.utcnow().isoformat(),
            }
        )
        logger.info("Metadata stored", extra={"key": object_key})
    except ClientError as e:
        logger.warning(
            "Failed to store metadata (continuing)",
            exc_info=True,
            extra={"key": object_key, "error": str(e)},
        )


def send_notification(
    object_key: str, source_bucket: str, config: Config
) -> None:
    """Send SNS notification - best effort"""
    try:
        message = (
            f"Image processing complete\n\n"
            f"Key: {object_key}\n"
            f"Source: {source_bucket}\n"
            f"Destination: {config.destination_bucket}/{config.processed_prefix}{object_key}"
        )

        sns_client.publish(
            TopicArn=config.sns_topic_arn,
            Message=message,
            Subject="New Image Processed",
        )
        logger.info("Notification sent", extra={"key": object_key})
    except ClientError as e:
        logger.warning(
            "Failed to send notification (continuing)",
            exc_info=True,
            extra={"key": object_key, "error": str(e)},
        )


def process_single_record(record: Dict[str, Any], config: Config) -> bool:
    """Process one S3 event record. Returns True if successful."""
    s3_info = record["s3"]
    bucket = s3_info["bucket"]["name"]
    key = s3_info["object"]["key"]
    event_time = record["eventTime"]

    logger.info("Starting processing", extra={"bucket": bucket, "key": key})

    try:
        copy_image_to_destination(bucket, key, config)
        store_metadata(key, bucket, config, event_time)
        send_notification(key, bucket, config)
        return True
    except Exception as e:
        logger.error(
            "Critical failure during record processing",
            exc_info=True,
            extra={"bucket": bucket, "key": key, "event_time": event_time},
        )
        return False

# ------------------- Main Handler -------------------
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda entry point"""
    try:
        config = Config()
    except ValueError as e:
        logger.critical(f"Configuration error: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Missing configuration"})
        }

    records = event.get("Records", [])
    if not records:
        logger.warning("No records in event")
        return {
            "statusCode": 200,
            "body": json.dumps("No records to process")
        }

    successes = 0
    failures = 0

    for record in records:
        if process_single_record(record, config):
            successes += 1
        else:
            failures += 1

    status_code = 200 if failures == 0 else 207  # 207 = Multi-Status / partial success

    return {
        "statusCode": status_code,
        "body": json.dumps({
            "message": "Processing complete",
            "success_count": successes,
            "failure_count": failures,
            "total": len(records)
        })
    }