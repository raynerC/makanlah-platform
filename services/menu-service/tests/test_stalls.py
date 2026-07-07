def test_create_stall(client):
    resp = client.post(
        "/stalls",
        json={"name": "Mak Cik Nasi Lemak", "description": "Best sambal in KL", "halal": True},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "Mak Cik Nasi Lemak"
    assert body["halal"] is True
    assert body["stall_id"]
    assert body["created_at"] == body["updated_at"]


def test_create_stall_rejects_empty_name(client):
    resp = client.post("/stalls", json={"name": ""})
    assert resp.status_code == 422


def test_get_stall(client, stall):
    resp = client.get(f"/stalls/{stall['stall_id']}")
    assert resp.status_code == 200
    assert resp.json() == stall


def test_get_missing_stall_is_404(client):
    assert client.get("/stalls/nope").status_code == 404


def test_list_stalls(client, stall):
    resp = client.get("/stalls")
    assert resp.status_code == 200
    ids = [s["stall_id"] for s in resp.json()]
    assert stall["stall_id"] in ids


def test_update_stall(client, stall):
    resp = client.put(f"/stalls/{stall['stall_id']}", json={"name": "Ah Hock Hainanese"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "Ah Hock Hainanese"
    assert body["cuisine"] == stall["cuisine"]  # untouched fields survive


def test_update_missing_stall_is_404(client):
    assert client.put("/stalls/nope", json={"name": "x"}).status_code == 404


def test_update_with_no_fields_is_422(client, stall):
    assert client.put(f"/stalls/{stall['stall_id']}", json={}).status_code == 422


def test_delete_stall(client, stall):
    assert client.delete(f"/stalls/{stall['stall_id']}").status_code == 204
    assert client.get(f"/stalls/{stall['stall_id']}").status_code == 404


def test_delete_missing_stall_is_404(client):
    assert client.delete("/stalls/nope").status_code == 404
