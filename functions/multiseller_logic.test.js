"use strict";
// Unit tests for the multi-seller fan-out logic. No Firebase.
//   Run:  cd functions && node multiseller_logic.test.js

const assert = require("assert");
const {
  groupItemsBySeller,
  computeSellerTotals,
  sellerOrderNumber,
} = require("./multiseller_logic");

let pass = 0;
function t(name, fn) {
  try {
    fn();
    pass++;
    console.log(`  PASS  ${name}`);
  } catch (e) {
    console.log(`  FAIL  ${name}\n        ${e.message}`);
    process.exitCode = 1;
  }
}

t("groups by seller preserving first-seen order", () => {
  const groups = groupItemsBySeller([
    { sellerId: "s1", sellerName: "A", listingId: "l1" },
    { sellerId: "s2", sellerName: "B", listingId: "l2" },
    { sellerId: "s1", sellerName: "A", listingId: "l3" },
  ]);
  assert.deepStrictEqual(groups.map((g) => g.sellerId), ["s1", "s2"]);
  assert.strictEqual(groups[0].items.length, 2);
  assert.strictEqual(groups[1].items.length, 1);
});

t("seller order numbers follow PB-{n}-S{index}", () => {
  assert.strictEqual(sellerOrderNumber("PB-1001", 1), "PB-1001-S1");
  assert.strictEqual(sellerOrderNumber("PB-1001", 3), "PB-1001-S3");
});

t("computeSellerTotals: escrow, below free-delivery threshold", () => {
  const r = computeSellerTotals(
    [{ unitPrice: 500, quantity: 2, deliveryAvailable: true, deliveryFee: 150 }],
    { isCod: false, rate: 0.02, freeThreshold: 3000 }
  );
  assert.strictEqual(r.itemSubtotal, 1000);
  assert.strictEqual(r.deliveryFee, 150); // below 3000 -> charged
  assert.strictEqual(r.amount, 1150);
  assert.strictEqual(r.commission, 20); // 2% of 1000 product only
  assert.strictEqual(r.sellerPayout, 1130); // amount - commission
});

t("computeSellerTotals: free delivery at/above threshold", () => {
  const r = computeSellerTotals(
    [{ unitPrice: 1500, quantity: 2, deliveryAvailable: true, deliveryFee: 200 }],
    { isCod: false, rate: 0.02, freeThreshold: 3000 }
  );
  assert.strictEqual(r.itemSubtotal, 3000);
  assert.strictEqual(r.deliveryFee, 0);
  assert.strictEqual(r.qualifiesForFreeDelivery, true);
  assert.strictEqual(r.amount, 3000);
});

t("computeSellerTotals: COD takes no commission", () => {
  const r = computeSellerTotals(
    [{ unitPrice: 800, quantity: 1, deliveryAvailable: false, deliveryFee: 0 }],
    { isCod: true, rate: 0.02, freeThreshold: 3000 }
  );
  assert.strictEqual(r.commission, 0);
  assert.strictEqual(r.amount, 800);
  assert.strictEqual(r.sellerPayout, 800);
});

t("computeSellerTotals: charges the highest per-listing fee (one shipment)", () => {
  const r = computeSellerTotals(
    [
      { unitPrice: 300, quantity: 1, deliveryAvailable: true, deliveryFee: 100 },
      { unitPrice: 300, quantity: 1, deliveryAvailable: true, deliveryFee: 250 },
    ],
    { isCod: false, rate: 0, freeThreshold: 3000 }
  );
  assert.strictEqual(r.itemSubtotal, 600);
  assert.strictEqual(r.deliveryFee, 250);
  assert.strictEqual(r.amount, 850);
});

console.log(`\n${pass} checks passed${process.exitCode ? " (with failures)" : ""}`);
