"use strict";

// Pure decision logic for order cancellation (spec sections 7–8). Extracted
// from index.js so it can be unit-tested with plain `node` (no Firebase, no
// credentials). index.js requires these; the triggers apply the side effects.

// Mirror of orderStatusOf() in lib/src/commerce.dart — derives the fulfillment
// status, tolerating legacy docs that only carry the escrow `status`.
function deriveOrderStatus(o) {
  const known = [
    "pending", "accepted", "processing", "shipped", "delivered",
    "buyer_confirmed", "completed", "rejected", "cancelled", "disputed",
  ];
  if (o.orderStatus && known.includes(o.orderStatus)) return o.orderStatus;
  switch (o.status || "") {
    case "pending_payment":
    case "payment_review":
      return "pending";
    case "cod_pending":
      return "processing";
    case "in_escrow":
      return o.buyerConfirmed === true ? "buyer_confirmed" : "accepted";
    case "released":
    case "completed":
      return "completed";
    case "refunded":
    case "cancelled":
      return "cancelled";
    default:
      return "pending";
  }
}

// Human text for a stored reason code (audit + fallback cancelReason).
function cancelReasonText(code) {
  return (
    {
      ordered_by_mistake: "Ordered by mistake",
      incorrect_address: "Incorrect address",
      change_products: "Need to change products",
      payment_problem: "Payment problem",
      seller_delay: "Seller delay",
      other: "Other",
    }[code] || ""
  );
}

// Authoritative decision on what may happen to a cancellation request, keyed on
// the live money + fulfillment state. Mirrors cancelUiFor() on the client.
//   auto   → cancel immediately (with refund when money is held)
//   review → seller/admin must approve
//   reject → not cancellable (already shipped/finalized)
function cancellationEligibility(o) {
  const status = o.status || "";
  if (["released", "completed", "refunded", "cancelled"].includes(status)) {
    return { mode: "reject", reason: "This order is already finalized." };
  }
  if (status === "pending_payment" || status === "cod_pending") {
    return { mode: "auto", refund: false };
  }
  if (status === "payment_review") {
    return { mode: "review", refund: true };
  }
  if (status === "in_escrow") {
    const os = deriveOrderStatus(o);
    if (os === "pending") return { mode: "auto", refund: true };
    if (os === "accepted" || os === "processing") {
      return { mode: "review", refund: true };
    }
    if (os === "shipped") {
      return {
        mode: "reject",
        reason: "This order has already shipped — please contact support.",
      };
    }
    return { mode: "reject", reason: "This order can no longer be cancelled." };
  }
  return { mode: "review", refund: false };
}

// Human text for a stored return reason code.
function returnReasonText(code) {
  return (
    {
      damaged: "Damaged or defective",
      not_as_described: "Not as described",
      wrong_item: "Wrong item received",
      missing_parts: "Missing parts or accessories",
      no_longer_needed: "No longer needed",
      other: "Other",
    }[code] || ""
  );
}

// Whether a delivered order can be returned through the app. Returns are only
// self-service while the money is still HELD by the platform (a clean refund,
// no seller-wallet clawback): status in_escrow + delivered/buyer_confirmed.
// Once released to the seller (or COD), returns go through support instead.
function returnEligibility(o) {
  const status = o.status || "";
  const os = deriveOrderStatus(o);
  if (status === "in_escrow" && (os === "delivered" || os === "buyer_confirmed")) {
    return { mode: "review" };
  }
  return {
    mode: "reject",
    reason:
      "This order is not eligible for an in-app return. Please contact support.",
  };
}

module.exports = {
  deriveOrderStatus,
  cancelReasonText,
  cancellationEligibility,
  returnReasonText,
  returnEligibility,
};
