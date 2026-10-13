import { useEffect, useState } from "react";

type Order = { id: number; sku: string; quantity: number; shipped?: string };

const API = import.meta.env.VITE_API ?? "http://localhost:8000";

export function OrderList({ customer }: { customer: string }) {
  const [orders, setOrders] = useState<Order[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    fetch(`${API}/orders?customer=${customer}`, { signal: controller.signal })
      .then((res) => (res.ok ? res.json() : Promise.reject(res.status)))
      .then(setOrders)
      .catch((e) => setError(String(e)));
    return () => controller.abort();
  }, [customer]);

  if (error) return <p className="error">Could not load orders: {error}</p>;
  return (
    <ul className="orders">
      {orders.map((o) => (
        <li key={o.id} data-shipped={Boolean(o.shipped)}>
          #{o.id} {o.sku} × {o.quantity}
        </li>
      ))}
    </ul>
  );
}
