import json
from pathlib import Path

from conftest import order_event


def queue_size(sqs, queue_url) -> int:
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"],
    )["Attributes"]
    return int(attrs["ApproximateNumberOfMessages"]) + int(
        attrs["ApproximateNumberOfMessagesNotVisible"]
    )


def test_valid_event_is_processed_and_deleted(sqs_setup):
    sqs, queue_url, worker = sqs_setup["sqs"], sqs_setup["queue_url"], sqs_setup["worker"]
    sqs.send_message(QueueUrl=queue_url, MessageBody=order_event())

    assert worker.poll_once() == 1
    assert queue_size(sqs, queue_url) == 0
    assert queue_size(sqs, sqs_setup["dlq_url"]) == 0


def test_batch_processing_counts_each_message(sqs_setup):
    sqs, queue_url, worker = sqs_setup["sqs"], sqs_setup["queue_url"], sqs_setup["worker"]
    for i in range(3):
        sqs.send_message(QueueUrl=queue_url, MessageBody=order_event(order_id=f"o-{i}"))

    total = 0
    for _ in range(3):  # SQS may split a batch across receives
        total += worker.poll_once()
    assert total == 3
    assert queue_size(sqs, queue_url) == 0


def test_malformed_json_is_not_deleted(sqs_setup):
    sqs, queue_url, worker = sqs_setup["sqs"], sqs_setup["queue_url"], sqs_setup["worker"]
    sqs.send_message(QueueUrl=queue_url, MessageBody="this is not json{")

    assert worker.poll_once() == 0
    assert queue_size(sqs, queue_url) == 1  # still there, will be retried


def test_unexpected_event_type_is_poison(sqs_setup):
    sqs, queue_url, worker = sqs_setup["sqs"], sqs_setup["queue_url"], sqs_setup["worker"]
    sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps({"type": "SomethingElse"}))

    assert worker.poll_once() == 0
    assert queue_size(sqs, queue_url) == 1


def test_poison_message_lands_in_dlq_after_three_receives(sqs_setup):
    sqs, queue_url, worker = sqs_setup["sqs"], sqs_setup["queue_url"], sqs_setup["worker"]
    dlq_url = sqs_setup["dlq_url"]
    sqs.send_message(QueueUrl=queue_url, MessageBody="poison{")

    # visibility timeout is 0, so each poll is a fresh receive; after the
    # third failed receive the redrive policy moves the message to the DLQ
    for _ in range(4):
        worker.poll_once()

    assert queue_size(sqs, queue_url) == 0
    assert queue_size(sqs, dlq_url) == 1


def test_good_messages_survive_poison_neighbours(sqs_setup):
    sqs, queue_url, worker = sqs_setup["sqs"], sqs_setup["queue_url"], sqs_setup["worker"]
    sqs.send_message(QueueUrl=queue_url, MessageBody="poison{")
    sqs.send_message(QueueUrl=queue_url, MessageBody=order_event())

    processed = 0
    for _ in range(3):
        processed += worker.poll_once()

    assert processed == 1  # the good one
    assert queue_size(sqs, sqs_setup["dlq_url"]) <= 1


def test_heartbeat_touched_on_poll(sqs_setup):
    worker = sqs_setup["worker"]
    worker.poll_once()
    assert Path(worker.heartbeat_file).exists()


def test_run_respects_max_polls_and_stop(sqs_setup):
    worker = sqs_setup["worker"]
    worker.run(max_polls=2)  # returns; would loop forever if max_polls ignored
    worker.stop()
    worker.run()  # stopped flag set: returns immediately
