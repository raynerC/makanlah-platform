"""SQS consumer for OrderPlaced events.

Poison-message handling is deliberately hands-off: a message that fails
processing is NOT deleted, so it returns to the queue when its visibility
timeout expires. The queue's redrive policy (maxReceiveCount=3, configured in
Terraform) moves it to the DLQ after the third failed receive — the worker
never talks to the DLQ directly.
"""

import json
import logging
from pathlib import Path

import boto3

logger = logging.getLogger("notify-worker")


class NotifyWorker:
    def __init__(
        self,
        queue_url: str,
        region: str,
        endpoint_url: str | None = None,
        wait_time_seconds: int = 10,
        heartbeat_file: str | None = None,
    ):
        self.sqs = boto3.client("sqs", region_name=region, endpoint_url=endpoint_url)
        self.queue_url = queue_url
        self.wait_time_seconds = wait_time_seconds
        self.heartbeat_file = heartbeat_file
        self._stopped = False

    def stop(self) -> None:
        self._stopped = True

    def run(self, max_polls: int | None = None) -> None:
        polls = 0
        while not self._stopped and (max_polls is None or polls < max_polls):
            self.poll_once()
            polls += 1

    def poll_once(self) -> int:
        """Receive one batch; returns the number of successfully processed messages."""
        resp = self.sqs.receive_message(
            QueueUrl=self.queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=self.wait_time_seconds,
            AttributeNames=["ApproximateReceiveCount"],
        )
        processed = 0
        for message in resp.get("Messages", []):
            receive_count = message.get("Attributes", {}).get("ApproximateReceiveCount", "?")
            try:
                self.handle(message)
            except Exception:
                # no delete: the message becomes visible again and the queue's
                # redrive policy DLQs it after maxReceiveCount receives
                logger.exception(
                    "message processing failed",
                    extra={
                        "extra_fields": {
                            "message_id": message.get("MessageId"),
                            "receive_count": receive_count,
                        }
                    },
                )
                continue
            self.sqs.delete_message(
                QueueUrl=self.queue_url, ReceiptHandle=message["ReceiptHandle"]
            )
            processed += 1
        self._beat()
        return processed

    def handle(self, message: dict) -> None:
        event = json.loads(message["Body"])
        if event.get("type") != "OrderPlaced":
            raise ValueError(f"unexpected event type: {event.get('type')!r}")
        order = event["order"]
        # a real implementation would call SNS/SES/WhatsApp here
        logger.info(
            "notification sent",
            extra={
                "extra_fields": {
                    "channel": "simulated-sms",
                    "order_id": order["order_id"],
                    "stall_id": order["stall_id"],
                    "total_rm": order.get("total_rm"),
                    "customer_name": order.get("customer_name"),
                }
            },
        )

    def _beat(self) -> None:
        if self.heartbeat_file:
            Path(self.heartbeat_file).touch()
