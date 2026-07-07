from pydantic import BaseModel, Field


class StallCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    cuisine: str | None = Field(default=None, max_length=50)
    halal: bool = False


class StallUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    cuisine: str | None = Field(default=None, max_length=50)
    halal: bool | None = None


class Stall(BaseModel):
    stall_id: str
    name: str
    description: str | None = None
    cuisine: str | None = None
    halal: bool = False
    created_at: str
    updated_at: str


class MenuItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    price_rm: float = Field(gt=0, le=1000)
    spicy: bool = False
    available: bool = True


class MenuItemUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    price_rm: float | None = Field(default=None, gt=0, le=1000)
    spicy: bool | None = None
    available: bool | None = None


class MenuItem(BaseModel):
    item_id: str
    stall_id: str
    name: str
    description: str | None = None
    price_rm: float
    spicy: bool = False
    available: bool = True
    created_at: str
    updated_at: str
