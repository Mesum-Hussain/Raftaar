"""HTTP API for the shop: orders and their status."""
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, HTTPException

app = FastAPI(title="shop")


@dataclass
class Order:
    id: int
    sku: str
    quantity: int = 1
    created: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    shipped: Optional[datetime] = None


ORDERS: dict[int, Order] = {}


@app.post("/orders")
def create_order(sku: str, quantity: int = 1) -> Order:
    if quantity <= 0:
        raise HTTPException(status_code=422, detail="quantity must be positive")
    order = Order(id=len(ORDERS) + 1, sku=sku, quantity=quantity)
    ORDERS[order.id] = order
    return order


@app.get("/orders/{order_id}")
def get_order(order_id: int) -> Order:
    # 404 rather than None: clients poll this endpoint
    order = ORDERS.get(order_id)
    if order is None:
        raise HTTPException(status_code=404, detail=f"no order {order_id}")
    return order
