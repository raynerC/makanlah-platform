from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request

from ..db import MenuRepository
from ..models import MenuItem, MenuItemCreate, MenuItemUpdate, Stall, StallCreate, StallUpdate

router = APIRouter(prefix="/stalls", tags=["stalls"])


def get_repo(request: Request) -> MenuRepository:
    return request.app.state.repo


Repo = Annotated[MenuRepository, Depends(get_repo)]


def _changes_or_422(payload) -> dict:
    changes = payload.model_dump(exclude_unset=True, exclude_none=True)
    if not changes:
        raise HTTPException(status_code=422, detail="no fields to update")
    return changes


@router.post("", response_model=Stall, status_code=201)
def create_stall(payload: StallCreate, repo: Repo):
    return repo.create_stall(payload.model_dump())


@router.get("", response_model=list[Stall])
def list_stalls(repo: Repo):
    return repo.list_stalls()


@router.get("/{stall_id}", response_model=Stall)
def get_stall(stall_id: str, repo: Repo):
    stall = repo.get_stall(stall_id)
    if stall is None:
        raise HTTPException(status_code=404, detail="stall not found")
    return stall


@router.put("/{stall_id}", response_model=Stall)
def update_stall(stall_id: str, payload: StallUpdate, repo: Repo):
    stall = repo.update_stall(stall_id, _changes_or_422(payload))
    if stall is None:
        raise HTTPException(status_code=404, detail="stall not found")
    return stall


@router.delete("/{stall_id}", status_code=204)
def delete_stall(stall_id: str, repo: Repo):
    if not repo.delete_stall(stall_id):
        raise HTTPException(status_code=404, detail="stall not found")


@router.post("/{stall_id}/menu", response_model=MenuItem, status_code=201)
def add_menu_item(stall_id: str, payload: MenuItemCreate, repo: Repo):
    item = repo.add_item(stall_id, payload.model_dump())
    if item is None:
        raise HTTPException(status_code=404, detail="stall not found")
    return item


@router.get("/{stall_id}/menu", response_model=list[MenuItem])
def list_menu_items(stall_id: str, repo: Repo):
    items = repo.list_items(stall_id)
    if items is None:
        raise HTTPException(status_code=404, detail="stall not found")
    return items


@router.put("/{stall_id}/menu/{item_id}", response_model=MenuItem)
def update_menu_item(stall_id: str, item_id: str, payload: MenuItemUpdate, repo: Repo):
    item = repo.update_item(stall_id, item_id, _changes_or_422(payload))
    if item is None:
        raise HTTPException(status_code=404, detail="menu item not found")
    return item


@router.delete("/{stall_id}/menu/{item_id}", status_code=204)
def delete_menu_item(stall_id: str, item_id: str, repo: Repo):
    if not repo.delete_item(stall_id, item_id):
        raise HTTPException(status_code=404, detail="menu item not found")
