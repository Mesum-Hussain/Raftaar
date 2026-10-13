//! Order service: reads orders from the queue and prices them.
use std::collections::HashMap;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq)]
pub struct Order {
    pub id: u64,
    pub sku: String,
    pub quantity: u32,
}

pub struct Pricer {
    prices: HashMap<String, f64>,
    discount: f64,
}

impl Pricer {
    pub fn new(discount: f64) -> Self {
        Self { prices: HashMap::new(), discount }
    }

    /// The total for one order, or None when the SKU is unknown.
    pub fn total(&self, order: &Order) -> Option<f64> {
        let unit = self.prices.get(&order.sku)?;
        let gross = unit * f64::from(order.quantity);
        Some(gross * (1.0 - self.discount))
    }
}

fn main() {
    let started = Instant::now();
    let mut pricer = Pricer::new(0.15);
    pricer.prices.insert("kbd-60".into(), 89.0);
    let order = Order { id: 42, sku: "kbd-60".into(), quantity: 3 };
    match pricer.total(&order) {
        Some(total) => println!("order {} costs {:.2}", order.id, total),
        None => eprintln!("unknown sku {}", order.sku),
    }
    assert!(started.elapsed() < Duration::from_millis(5));
}
