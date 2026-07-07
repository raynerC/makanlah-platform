import json
import logging

from worker.config import load_settings
from worker.logging_setup import JsonFormatter, setup_logging


def test_settings_defaults(monkeypatch):
    for var in ("ORDER_EVENTS_QUEUE_URL", "AWS_REGION", "SQS_ENDPOINT_URL", "WAIT_TIME_SECONDS"):
        monkeypatch.delenv(var, raising=False)
    settings = load_settings()
    assert settings.queue_url == ""
    assert settings.wait_time_seconds == 10
    assert settings.sqs_endpoint_url is None


def test_settings_from_env(monkeypatch):
    monkeypatch.setenv("ORDER_EVENTS_QUEUE_URL", "http://sqs/q")
    monkeypatch.setenv("SQS_ENDPOINT_URL", "http://elasticmq:9324")
    monkeypatch.setenv("WAIT_TIME_SECONDS", "2")
    settings = load_settings()
    assert settings.queue_url == "http://sqs/q"
    assert settings.sqs_endpoint_url == "http://elasticmq:9324"
    assert settings.wait_time_seconds == 2


def test_json_formatter_includes_extra_fields():
    record = logging.LogRecord("t", logging.INFO, __file__, 1, "hello %s", ("world",), None)
    record.extra_fields = {"order_id": "o-1"}
    entry = json.loads(JsonFormatter().format(record))
    assert entry["message"] == "hello world"
    assert entry["level"] == "info"
    assert entry["order_id"] == "o-1"
    assert "timestamp" in entry


def test_json_formatter_includes_exception():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        record = logging.LogRecord("t", logging.ERROR, __file__, 1, "failed", (), sys.exc_info())
    entry = json.loads(JsonFormatter().format(record))
    assert "boom" in entry["exception"]


def test_setup_logging_replaces_root_handlers():
    setup_logging("DEBUG")
    root = logging.getLogger()
    assert len(root.handlers) == 1
    assert isinstance(root.handlers[0].formatter, JsonFormatter)
    assert root.level == logging.DEBUG
