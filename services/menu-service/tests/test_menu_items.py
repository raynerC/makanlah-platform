def _add_item(client, stall_id, **overrides):
    payload = {"name": "Chicken Rice", "price_rm": 7.5, "spicy": False, **overrides}
    return client.post(f"/stalls/{stall_id}/menu", json=payload)


def test_add_menu_item(client, stall):
    resp = _add_item(client, stall["stall_id"])
    assert resp.status_code == 201
    body = resp.json()
    assert body["item_id"]
    assert body["stall_id"] == stall["stall_id"]
    assert body["price_rm"] == 7.5
    assert body["available"] is True


def test_add_item_to_missing_stall_is_404(client):
    assert _add_item(client, "nope").status_code == 404


def test_add_item_rejects_negative_price(client, stall):
    resp = _add_item(client, stall["stall_id"], price_rm=-1)
    assert resp.status_code == 422


def test_list_menu_items(client, stall):
    _add_item(client, stall["stall_id"])
    _add_item(client, stall["stall_id"], name="Roasted Chicken Rice", price_rm=8.0)
    resp = client.get(f"/stalls/{stall['stall_id']}/menu")
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_list_items_of_missing_stall_is_404(client):
    assert client.get("/stalls/nope/menu").status_code == 404


def test_update_menu_item(client, stall):
    item = _add_item(client, stall["stall_id"]).json()
    resp = client.put(
        f"/stalls/{stall['stall_id']}/menu/{item['item_id']}",
        json={"price_rm": 8.5, "spicy": True},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["price_rm"] == 8.5
    assert body["spicy"] is True
    assert body["name"] == item["name"]


def test_update_missing_item_is_404(client, stall):
    resp = client.put(f"/stalls/{stall['stall_id']}/menu/nope", json={"price_rm": 1})
    assert resp.status_code == 404


def test_delete_menu_item(client, stall):
    item = _add_item(client, stall["stall_id"]).json()
    assert client.delete(f"/stalls/{stall['stall_id']}/menu/{item['item_id']}").status_code == 204
    assert client.get(f"/stalls/{stall['stall_id']}/menu").json() == []


def test_delete_missing_item_is_404(client, stall):
    assert client.delete(f"/stalls/{stall['stall_id']}/menu/nope").status_code == 404


def test_delete_stall_cascades_to_items(client, stall):
    _add_item(client, stall["stall_id"])
    assert client.delete(f"/stalls/{stall['stall_id']}").status_code == 204
    # stall and its menu are both gone
    assert client.get(f"/stalls/{stall['stall_id']}").status_code == 404
    assert client.get(f"/stalls/{stall['stall_id']}/menu").status_code == 404
