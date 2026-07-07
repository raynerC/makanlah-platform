import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

TABLE = "menus-test"


def _create_table(name: str) -> None:
    boto3.resource("dynamodb", region_name="us-east-1").create_table(
        TableName=name,
        KeySchema=[
            {"AttributeName": "pk", "KeyType": "HASH"},
            {"AttributeName": "sk", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "pk", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )


def _make_client(monkeypatch, table_env: str):
    monkeypatch.setenv("MENUS_TABLE", table_env)
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    from app.main import create_app

    return TestClient(create_app())


@pytest.fixture()
def client(monkeypatch):
    """App wired to a moto-mocked DynamoDB table."""
    with mock_aws():
        _create_table(TABLE)
        with _make_client(monkeypatch, TABLE) as test_client:
            yield test_client


@pytest.fixture()
def client_without_table(monkeypatch):
    """App pointing at a table that does not exist (readiness failure path)."""
    with mock_aws():
        with _make_client(monkeypatch, "missing-table") as test_client:
            yield test_client


@pytest.fixture()
def stall(client) -> dict:
    resp = client.post(
        "/stalls",
        json={"name": "Ah Hock Chicken Rice", "cuisine": "chinese", "halal": False},
    )
    assert resp.status_code == 201
    return resp.json()
