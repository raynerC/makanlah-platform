import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    queue_url: str
    aws_region: str
    sqs_endpoint_url: str | None
    wait_time_seconds: int
    heartbeat_file: str
    log_level: str


def load_settings() -> Settings:
    return Settings(
        queue_url=os.getenv("ORDER_EVENTS_QUEUE_URL", ""),
        aws_region=os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-east-1")),
        # set for local dev (ElasticMQ); unset in AWS
        sqs_endpoint_url=os.getenv("SQS_ENDPOINT_URL") or None,
        wait_time_seconds=int(os.getenv("WAIT_TIME_SECONDS", "10")),
        # touched after every poll; the container HEALTHCHECK watches its age
        heartbeat_file=os.getenv("HEARTBEAT_FILE", "/tmp/notify-worker-heartbeat"),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
    )
