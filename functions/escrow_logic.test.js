"use strict";

// Unit tests for the pure escrow refund-allocation logic (the money-loss guard).
//   Run:  cd functions && node escrow_logic.test.js

const assert = require("assert");
const { refundAllocation } = require("./escrow_logic");

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

t("full refund of an un-refunded order refunds the whole amount", () => {
  const r = refundAllocation(1000, 0, 0); // requested<=0 => the rest
  assert.strictEqual(r.refundValue, 1000);
  assert.strictEqual(r.newRefundTotal, 1000);
  assert.strictEqual(r.fullyRefunded, true);
});

t("partial refund keeps the order partially refunded", () => {
  const r = refundAllocation(1000, 0, 300);
  assert.strictEqual(r.refundValue, 300);
  assert.strictEqual(r.newRefundTotal, 300);
  assert.strictEqual(r.fullyRefunded, false);
});

t("partial THEN full only refunds the remainder (no over-credit)", () => {
  // First Rs 300 partial already applied; a follow-up 'full' refund must only
  // pay the remaining 700, never the whole 1000 again.
  const r = refundAllocation(1000, 300, 0);
  assert.strictEqual(r.refundValue, 700);
  assert.strictEqual(r.newRefundTotal, 1000);
  assert.strictEqual(r.fullyRefunded, true);
});

t("two partial refunds accumulate and cap at the amount", () => {
  const a = refundAllocation(1000, 0, 400);
  assert.strictEqual(a.newRefundTotal, 400);
  const b = refundAllocation(1000, 400, 400);
  assert.strictEqual(b.newRefundTotal, 800);
  const c = refundAllocation(1000, 800, 400); // asks 400, only 200 left
  assert.strictEqual(c.refundValue, 200);
  assert.strictEqual(c.newRefundTotal, 1000);
  assert.strictEqual(c.fullyRefunded, true);
});

t("refunding an already fully-refunded order is skipped", () => {
  const r = refundAllocation(1000, 1000, 0);
  assert.strictEqual(r.skip, true);
});

t("a requested amount larger than the order is capped at the amount", () => {
  const r = refundAllocation(1000, 0, 5000);
  assert.strictEqual(r.refundValue, 1000);
  assert.strictEqual(r.fullyRefunded, true);
});

t("rounds to paisa (no floating drift over-credit)", () => {
  const a = refundAllocation(100, 0, 33.335);
  const b = refundAllocation(100, a.newRefundTotal, 33.335);
  const c = refundAllocation(100, b.newRefundTotal, 0);
  assert.ok(c.newRefundTotal <= 100 + 0.001, `total ${c.newRefundTotal} > 100`);
  assert.strictEqual(c.fullyRefunded, true);
});

console.log(`\n${pass} checks passed${process.exitCode ? " (with failures)" : ""}`);
