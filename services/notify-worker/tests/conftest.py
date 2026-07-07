import json

import boto3
import pytest
from moto import mock_aws

from worker.consumer import NotifyWorker

REGION = "us-east-1"


@pytest.fixture()
def sqs_setup(monkeypatch, tmp_path):
    """Main queue with a DLQ redrive policy of maxReceiveCount=3, like production."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", REGION)
    with mock_aws():
        sqs = boto3.client("sqs", region_name=REGION)
        dlq_url = sqs.create_queue(QueueName="order-events-dlq")["QueueUrl"]
        dlq_arn = sqs.get_queue_attributes(QueueUrl=dlq_url, AttributeNames=["QueueArn"])[
            "Attributes"
        ]["QueueArn"]
        queue_url = sqs.create_queue(
            QueueName="order-events",
            Attributes={
                "VisibilityTimeout": "0",  # instant retries in tests
                "RedrivePolicy": json.dumps(
                    {"deadLetterTargetArn": dlq_arn, "maxReceiveCount": "3"}
                ),
            },
        )["QueueUrl"]
        worker = NotifyWorker(
            queue_url=queue_url,
            region=REGION,
            wait_time_seconds=0,
            heartbeat_file=str(tmp_path / "heartbeat"),
        )
        yield {"sqs": sqs, "queue_url": queue_url, "dlq_url": dlq_url, "worker": worker}


def order_event(**overrides) -> str:
    order = {
        "order_id": "o-123",
        "stall_id": "stall-1",
        "total_rm": 15.0,
        "customer_name": "Rayner",
        **overrides,
    }
    return json.dumps({"type": "OrderPlaced", "order": order})
