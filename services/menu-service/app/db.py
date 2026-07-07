"""DynamoDB repository for stalls and menu items.

Single-table layout:

    pk = STALL#<stall_id>   sk = META           -> stall record
    pk = STALL#<stall_id>   sk = ITEM#<item_id> -> one menu item

A stall and its whole menu live in one partition, so fetching a menu is a
single Query. Listing all stalls scans on sk = META — fine at this project's
scale; a GSI on sk would replace it if stall count grew.
"""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr, Key
from botocore.exceptions import ClientError

STALL_FIELDS = ("stall_id", "name", "description", "cuisine", "halal", "created_at", "updated_at")
ITEM_FIELDS = (
    "item_id",
    "stall_id",
    "name",
    "description",
    "price_rm",
    "spicy",
    "available",
    "created_at",
    "updated_at",
)


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def _new_id() -> str:
    return uuid.uuid4().hex[:12]


class MenuRepository:
    def __init__(self, table_name: str, region: str, endpoint_url: str | None = None):
        resource = boto3.resource("dynamodb", region_name=region, endpoint_url=endpoint_url)
        self.table = resource.Table(table_name)

    def ping(self) -> bool:
        try:
            self.table.load()
            return True
        except Exception:
            return False

    # ---- stalls ----

    def create_stall(self, data: dict) -> dict:
        stall_id = _new_id()
        now = _now()
        record = {
            "pk": f"STALL#{stall_id}",
            "sk": "META",
            "stall_id": stall_id,
            "created_at": now,
            "updated_at": now,
            **data,
        }
        self.table.put_item(Item=record)
        return _project(record, STALL_FIELDS)

    def get_stall(self, stall_id: str) -> dict | None:
        resp = self.table.get_item(Key={"pk": f"STALL#{stall_id}", "sk": "META"})
        record = resp.get("Item")
        return _project(record, STALL_FIELDS) if record else None

    def list_stalls(self) -> list[dict]:
        records: list[dict] = []
        kwargs: dict = {"FilterExpression": Attr("sk").eq("META")}
        while True:
            resp = self.table.scan(**kwargs)
            records.extend(resp.get("Items", []))
            last_key = resp.get("LastEvaluatedKey")
            if not last_key:
                break
            kwargs["ExclusiveStartKey"] = last_key
        return [_project(r, STALL_FIELDS) for r in records]

    def update_stall(self, stall_id: str, changes: dict) -> dict | None:
        updated = self._update(f"STALL#{stall_id}", "META", changes)
        return _project(updated, STALL_FIELDS) if updated else None

    def delete_stall(self, stall_id: str) -> bool:
        """Delete the stall and every menu item in its partition."""
        if self.get_stall(stall_id) is None:
            return False
        resp = self.table.query(KeyConditionExpression=Key("pk").eq(f"STALL#{stall_id}"))
        with self.table.batch_writer() as batch:
            for record in resp.get("Items", []):
                batch.delete_item(Key={"pk": record["pk"], "sk": record["sk"]})
        return True

    # ---- menu items ----

    def add_item(self, stall_id: str, data: dict) -> dict | None:
        if self.get_stall(stall_id) is None:
            return None
        item_id = _new_id()
        now = _now()
        record = {
            "pk": f"STALL#{stall_id}",
            "sk": f"ITEM#{item_id}",
            "item_id": item_id,
            "stall_id": stall_id,
            "created_at": now,
            "updated_at": now,
            **data,
            "price_rm": Decimal(str(data["price_rm"])),
        }
        self.table.put_item(Item=record)
        return _project(record, ITEM_FIELDS)

    def list_items(self, stall_id: str) -> list[dict] | None:
        if self.get_stall(stall_id) is None:
            return None
        condition = Key("pk").eq(f"STALL#{stall_id}") & Key("sk").begins_with("ITEM#")
        resp = self.table.query(KeyConditionExpression=condition)
        return [_project(r, ITEM_FIELDS) for r in resp.get("Items", [])]

    def get_item(self, stall_id: str, item_id: str) -> dict | None:
        resp = self.table.get_item(Key={"pk": f"STALL#{stall_id}", "sk": f"ITEM#{item_id}"})
        record = resp.get("Item")
        return _project(record, ITEM_FIELDS) if record else None

    def update_item(self, stall_id: str, item_id: str, changes: dict) -> dict | None:
        if "price_rm" in changes:
            changes = {**changes, "price_rm": Decimal(str(changes["price_rm"]))}
        updated = self._update(f"STALL#{stall_id}", f"ITEM#{item_id}", changes)
        return _project(updated, ITEM_FIELDS) if updated else None

    def delete_item(self, stall_id: str, item_id: str) -> bool:
        try:
            self.table.delete_item(
                Key={"pk": f"STALL#{stall_id}", "sk": f"ITEM#{item_id}"},
                ConditionExpression="attribute_exists(pk)",
            )
            return True
        except ClientError as err:
            if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return False
            raise

    # ---- internals ----

    def _update(self, pk: str, sk: str, changes: dict) -> dict | None:
        """SET the given fields; None if the record does not exist."""
        changes = {**changes, "updated_at": _now()}
        fields = list(changes)
        names = {f"#f{i}": field for i, field in enumerate(fields)}
        values = {f":v{i}": changes[field] for i, field in enumerate(fields)}
        expression = "SET " + ", ".join(f"#f{i} = :v{i}" for i in range(len(fields)))
        try:
            resp = self.table.update_item(
                Key={"pk": pk, "sk": sk},
                UpdateExpression=expression,
                ExpressionAttributeNames=names,
                ExpressionAttributeValues=values,
                ConditionExpression="attribute_exists(pk)",
                ReturnValues="ALL_NEW",
            )
        except ClientError as err:
            if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return None
            raise
        return resp["Attributes"]


def _project(record: dict, fields: tuple[str, ...]) -> dict:
    out = {k: record[k] for k in fields if k in record}
    if isinstance(out.get("price_rm"), Decimal):
        out["price_rm"] = float(out["price_rm"])
    return out
