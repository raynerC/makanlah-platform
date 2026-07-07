import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    table_name: str
    aws_region: str
    dynamodb_endpoint_url: str | None
    log_level: str


def load_settings() -> Settings:
    return Settings(
        table_name=os.getenv("MENUS_TABLE", "menus"),
        aws_region=os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-east-1")),
        # set for local dev (DynamoDB Local); unset in AWS
        dynamodb_endpoint_url=os.getenv("DYNAMODB_ENDPOINT_URL") or None,
        log_level=os.getenv("LOG_LEVEL", "INFO"),
    )
