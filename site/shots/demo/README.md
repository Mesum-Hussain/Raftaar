# shop

A small shop: a Rust pricing service, a Python API, a Go file server and a React front end.

## Run it

```sh
cargo run --release          # pricing
uvicorn api.app:app --reload # API on :8000
go run ./cmd/server          # static files on :8080
```

- Orders live in PostgreSQL (`db/schema.sql`).
- Prices are frozen when an order is paid.
