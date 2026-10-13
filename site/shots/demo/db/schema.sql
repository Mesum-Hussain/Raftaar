-- Orders and their items; totals are computed, never stored.
CREATE TABLE customers (
    id          BIGSERIAL PRIMARY KEY,
    email       TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE orders (
    id          BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES customers (id),
    status      TEXT NOT NULL DEFAULT 'new'
                CHECK (status IN ('new', 'paid', 'shipped', 'cancelled')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE order_items (
    order_id    BIGINT NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    sku         TEXT NOT NULL,
    quantity    INTEGER NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (order_id, sku)
);

CREATE INDEX orders_by_customer ON orders (customer_id, created_at DESC);

-- The revenue of the last 30 days, per day
SELECT date_trunc('day', o.created_at) AS day,
       SUM(i.quantity * i.unit_price)  AS revenue
FROM orders o
JOIN order_items i ON i.order_id = o.id
WHERE o.status IN ('paid', 'shipped')
  AND o.created_at > now() - INTERVAL '30 days'
GROUP BY 1
ORDER BY 1;
