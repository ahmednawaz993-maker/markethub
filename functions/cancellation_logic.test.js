"use strict";

// Unit tests for the pure cancellation decision logic. No Firebase required.
//   Run:  cd functions && node cancellation_logic.test.js
// Exits non-zero if any assertion fails.

const assert = require("assert");
const {
  deriveOrderStatus,
  cancelReasonText,
  cancellationEligibility,
  returnReasonText,
  returnEligibility,
} = require("./cancellation_logic");

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

// deriveOrderStatus mirrors orderStatusOf() in the Flutter app.
t("deriveOrderStatus: explicit orderStatus wins", () => {
  assert.strictEqual(
    deriveOrderStatus({ orderStatus: "shipped", status: "in_escrow" }),
    "shipped"
  );
});
t("deriveOrderStatus: legacy mapping", () => {
  assert.strictEqual(deriveOrderStatus({ status: "pending_payment" }), "pending");
  assert.strictEqual(deriveOrderStatus({ status: "cod_pending" }), "processing");
  assert.strictEqual(deriveOrderStatus({ status: "in_escrow" }), "accepted");
  assert.strictEqual(
    deriveOrderStatus({ status: "in_escrow", buyerConfirmed: true }),
    "buyer_confirmed"
  );
  assert.strictEqual(deriveOrderStatus({ status: "refunded" }), "cancelled");
});

// cancellationEligibility — the authoritative server decision.
t("eligibility: unpaid → auto, no refund", () => {
  assert.deepStrictEqual(cancellationEligibility({ status: "pending_payment" }), {
    mode: "auto",
    refund: false,
  });
  assert.deepStrictEqual(cancellationEligibility({ status: "cod_pending" }), {
    mode: "auto",
    refund: false,
  });
});
t("eligibility: paid & not accepted → auto with refund", () => {
  assert.deepStrictEqual(
    cancellationEligibility({ status: "in_escrow", orderStatus: "pending" }),
    { mode: "auto", refund: true }
  );
});
t("eligibility: accepted/processing → review with refund", () => {
  assert.strictEqual(
    cancellationEligibility({ status: "in_escrow", orderStatus: "accepted" }).mode,
    "review"
  );
  assert.strictEqual(
    cancellationEligibility({ status: "in_escrow", orderStatus: "processing" })
      .mode,
    "review"
  );
});
t("eligibility: legacy held order (no orderStatus) → review, not auto", () => {
  // Must NOT be auto-cancellable — a mid-flight legacy order needs approval.
  assert.strictEqual(
    cancellationEligibility({ status: "in_escrow" }).mode,
    "review"
  );
});
t("eligibility: payment_review → review with refund", () => {
  assert.deepStrictEqual(cancellationEligibility({ status: "payment_review" }), {
    mode: "review",
    refund: true,
  });
});
t("eligibility: shipped → reject", () => {
  assert.strictEqual(
    cancellationEligibility({ status: "in_escrow", orderStatus: "shipped" }).mode,
    "reject"
  );
});
t("eligibility: delivered/terminal → reject", () => {
  assert.strictEqual(
    cancellationEligibility({ status: "in_escrow", orderStatus: "delivered" })
      .mode,
    "reject"
  );
  assert.strictEqual(cancellationEligibility({ status: "released" }).mode, "reject");
  assert.strictEqual(cancellationEligibility({ status: "completed" }).mode, "reject");
  assert.strictEqual(cancellationEligibility({ status: "cancelled" }).mode, "reject");
});

t("cancelReasonText resolves known codes and blanks unknown", () => {
  assert.strictEqual(cancelReasonText("ordered_by_mistake"), "Ordered by mistake");
  assert.strictEqual(cancelReasonText("seller_delay"), "Seller delay");
  assert.strictEqual(cancelReasonText("nope"), "");
});

// Returns: only self-service while money is held + delivered/buyer_confirmed.
t("returnEligibility: delivered & held → review", () => {
  assert.strictEqual(
    returnEligibility({ status: "in_escrow", orderStatus: "delivered" }).mode,
    "review"
  );
  assert.strictEqual(
    returnEligibility({ status: "in_escrow", orderStatus: "buyer_confirmed" })
      .mode,
    "review"
  );
});
t("returnEligibility: not-yet-delivered → reject", () => {
  assert.strictEqual(
    returnEligibility({ status: "in_escrow", orderStatus: "shipped" }).mode,
    "reject"
  );
  assert.strictEqual(
    returnEligibility({ status: "in_escrow", orderStatus: "pending" }).mode,
    "reject"
  );
});
t("returnEligibility: released/COD → reject (support only)", () => {
  assert.strictEqual(returnEligibility({ status: "released" }).mode, "reject");
  assert.strictEqual(returnEligibility({ status: "completed" }).mode, "reject");
  assert.strictEqual(
    returnEligibility({ status: "cod_pending", orderStatus: "delivered" }).mode,
    "reject"
  );
});
t("returnReasonText resolves known codes and blanks unknown", () => {
  assert.strictEqual(returnReasonText("damaged"), "Damaged or defective");
  assert.strictEqual(returnReasonText("wrong_item"), "Wrong item received");
  assert.strictEqual(returnReasonText("nope"), "");
});

console.log(`\n${pass} checks passed${process.exitCode ? " (with failures)" : ""}`);
