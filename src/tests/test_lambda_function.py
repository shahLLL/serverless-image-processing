import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import lambda_function  # noqa: E402


@pytest.fixture(autouse=True)
def set_required_env(monkeypatch):
    monkeypatch.setenv("DYNAMODB_TABLE_NAME", "test-table")
    monkeypatch.setenv("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123456789012:test")
    monkeypatch.setenv("DESTINATION_BUCKET", "dest-bucket")
    monkeypatch.delenv("PROCESSED_PREFIX", raising=False)

# Configuration validation
def test_config_requires_expected_environment_variables(monkeypatch):
    # Confirms the app raises a clear error when required environment variables are missing.
    monkeypatch.delenv("DYNAMODB_TABLE_NAME", raising=False)

    with pytest.raises(ValueError, match="DYNAMODB_TABLE_NAME"):
        lambda_function.Config()

# S3 copy path
def test_copy_image_to_destination_calls_s3_copy(monkeypatch):
    # Verifies the function builds the destination key correctly and calls the S3 copy operation with the expected bucket and key.
    config = lambda_function.Config()
    calls = {}

    def fake_copy_object(**kwargs):
        calls.update(kwargs)

    monkeypatch.setattr(
        lambda_function,
        "s3_client",
        SimpleNamespace(copy_object=fake_copy_object),
    )

    lambda_function.copy_image_to_destination("source-bucket", "image.jpg", config)

    assert calls["Bucket"] == "dest-bucket"
    assert calls["Key"] == "processed/image.jpg"
    assert calls["CopySource"] == {"Bucket": "source-bucket", "Key": "image.jpg"}

# DynamoDB metadata write
def test_store_metadata_uses_dynamodb_table(monkeypatch):
    # Confirms metadata is written to the expected table with the expected fields.
    config = lambda_function.Config()
    stored_items = []

    class FakeTable:
        def put_item(self, Item):
            stored_items.append(Item)

    class FakeDynamoResource:
        def Table(self, name):
            assert name == "test-table"
            return FakeTable()

    monkeypatch.setattr(lambda_function, "dynamodb_resource", FakeDynamoResource())

    lambda_function.store_metadata(
        "image.jpg",
        "source-bucket",
        config,
        "2024-01-01T00:00:00Z",
    )

    assert stored_items[0]["ImageKey"] == "image.jpg"
    assert stored_items[0]["SourceBucket"] == "source-bucket"

# SNS notification
def test_send_notification_publishes_to_sns(monkeypatch):
    # Verifies the notification message is published to the configured SNS topic.
    config = lambda_function.Config()
    published = []

    def fake_publish(**kwargs):
        published.append(kwargs)

    monkeypatch.setattr(
        lambda_function,
        "sns_client",
        SimpleNamespace(publish=fake_publish),
    )

    lambda_function.send_notification("image.jpg", "source-bucket", config)

    assert published[0]["TopicArn"] == "arn:aws:sns:us-east-1:123456789012:test"
    assert "image.jpg" in published[0]["Message"]

# Record processing flow
def test_process_single_record_returns_false_on_failure(monkeypatch):
    # Confirms a single record returns failure when one of the processing steps raises an exception.
    config = lambda_function.Config()

    def fake_copy_image(*args, **kwargs):
        raise lambda_function.ClientError(
            {"Error": {"Code": "Test", "Message": "boom"}},
            "CopyObject",
        )

    monkeypatch.setattr(lambda_function, "copy_image_to_destination", fake_copy_image)
    monkeypatch.setattr(lambda_function, "store_metadata", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        lambda_function,
        "send_notification",
        lambda *args, **kwargs: None,
    )

    record = {
        "s3": {"bucket": {"name": "source-bucket"}, "object": {"key": "image.jpg"}},
        "eventTime": "2024-01-01T00:00:00Z",
    }

    assert lambda_function.process_single_record(record, config) is False

# Lambda handler response
def test_lambda_handler_returns_207_when_any_record_fails(monkeypatch):
    # Verifies the handler returns a partial-success response when some records fail and others succeed.
    monkeypatch.setattr(lambda_function, "Config", lambda: SimpleNamespace(
        dynamodb_table="test-table",
        sns_topic_arn="arn:aws:sns:us-east-1:123456789012:test",
        destination_bucket="dest-bucket",
        processed_prefix="processed/",
    ))

    def fake_process_single_record(record, config):
        return record["s3"]["object"]["key"] == "ok.jpg"

    monkeypatch.setattr(lambda_function, "process_single_record", fake_process_single_record)

    event = {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "source"},
                    "object": {"key": "bad.jpg"},
                }
            },
            {
                "s3": {
                    "bucket": {"name": "source"},
                    "object": {"key": "ok.jpg"},
                }
            },
        ]
    }

    response = lambda_function.lambda_handler(event, None)

    assert response["statusCode"] == 207
    assert "failure_count" in response["body"]
