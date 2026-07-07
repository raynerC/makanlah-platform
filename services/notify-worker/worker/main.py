import logging
import signal

from .config import load_settings
from .consumer import NotifyWorker
from .logging_setup import setup_logging

logger = logging.getLogger("notify-worker")


def main() -> None:
    settings = load_settings()
    setup_logging(settings.log_level)

    worker = NotifyWorker(
        queue_url=settings.queue_url,
        region=settings.aws_region,
        endpoint_url=settings.sqs_endpoint_url,
        wait_time_seconds=settings.wait_time_seconds,
        heartbeat_file=settings.heartbeat_file,
    )

    def shutdown(signum, frame):
        logger.info("shutdown signal received", extra={"extra_fields": {"signal": signum}})
        worker.stop()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    logger.info(
        "notify-worker started",
        extra={"extra_fields": {"queue_url": settings.queue_url}},
    )
    worker.run()
    logger.info("notify-worker stopped")


if __name__ == "__main__":
    main()
