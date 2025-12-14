import logging
import json
import boto3
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
s3 = boto3.client('s3')

TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
DESTINATION_BUCKET = os.environ.get('DESTINATION_BUCKET')

def lambda_handler(event, context):
    for record in event['Records']:
        source_bucket = record['s3']['bucket']['name']
        object_key = record['s3']['object']['key']
        event_time = record['eventTime']
        
        logger.info(f"Processing object: '{object_key}' in source bucket '{source_bucket}'")

        # --- 1. S3 Processing: Copy object to destination bucket ---
        if DESTINATION_BUCKET:
            try:
                s3.copy_object(
                    Bucket=DESTINATION_BUCKET,
                    CopySource={'Bucket': source_bucket, 'Key': object_key},
                    Key=f"processed/{object_key}" # Stored in a 'processed' subfolder
                )
                logger.info(f"Successfully copied '{object_key}' to '{DESTINATION_BUCKET}/processed/'")
            except Exception as e:
                logger.error(f"Error copying object to destination S3 bucket: {e}")

        # --- 2. DynamoDB: Store metadata ---
        if TABLE_NAME:
            try:
                table = dynamodb.Table(TABLE_NAME)
                table.put_item(
                    Item={
                        'ImageKey': object_key,
                        'SourceBucket': source_bucket,
                        'DestinationBucket': DESTINATION_BUCKET,
                        'UploadTime': event_time,
                        'Timestamp': str(datetime.now())
                    }
                )
                logger.info(f"Logged metadata for '{object_key}' to DynamoDB table '{TABLE_NAME}'")
            except Exception as e:
                logger.error(f"Error writing to DynamoDB: {e}")

        # --- 3. SNS: Send Notification ---
        if SNS_TOPIC_ARN:
            try:
                message = f"New image uploaded: {object_key} to bucket {source_bucket}. Processing complete."
                sns.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Message=message,
                    Subject="New Image Upload Notification"
                )
                logger.info("Sent SNS notification.")
            except Exception as e:
                logger.error(f"Error publishing to SNS: {e}")

    return {
        'statusCode': 200,
        'body': json.dumps('Workflow executed successfully!')
    }

