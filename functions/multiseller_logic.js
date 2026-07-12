"use strict";

// Pure logic for multi-seller checkout fan-out (Phase 3). No Firebase — unit
// tested with plain `node` (see multiseller_logic.test.js). index.js calls
// these while creating the per-seller orders from a masterOrders intent.

function parsePrice(p) {
  const cleaned = String(p == null ? "" : p).replace(/[^0-9.]/g, "");
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : 0;
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

/// Groups cart line items by sellerId, preserving first-seen seller order.
/// items: [{ sellerId, sellerName, listingId, quantity }]
function groupItemsBySeller(items) {
  const order = [];
  const bySeller = {};
  const names = {};
  for (const it of items || []) {
    const sid = it.sellerId || "";
    if (!(sid in bySeller)) {
      bySeller[sid] = [];
      order.push(sid);
    }
    bySeller[sid].push(it);
    names[sid] = it.sellerName || names[sid] || "Seller";
  }
  return order.map((sid) => ({
    sellerId: sid,
    sellerName: names[sid],
    items: bySeller[sid],
  }));
}

/// Computes one seller sub-order's money from its trusted line items. Mirrors
/// the single-order rules in commerce.dart / notifyOnNewOrder:
///   • commission is taken on the product subtotal only (0 for COD),
///   • delivery is free when the seller subtotal >= freeThreshold, else the
///     highest per-listing delivery fee among the seller's items (one shipment),
///   • the seller keeps the full delivery fee.
/// lines: [{ unitPrice, quantity, deliveryAvailable, deliveryFee }]
function computeSellerTotals(lines, { isCod, rate, freeThreshold }) {
  let subtotal = 0;
  let deliveryAvailable = false;
  let maxFee = 0;
  for (const l of lines) {
    const q = Math.max(1, Number(l.quantity) || 1);
    subtotal += (Number(l.unitPrice) || 0) * q;
    if (l.deliveryAvailable) {
      deliveryAvailable = true;
      maxFee = Math.max(maxFee, Number(l.deliveryFee) || 0);
    }
  }
  subtotal = round2(subtotal);
  const qualifiesForFreeDelivery = subtotal >= freeThreshold;
  const deliveryFee = qualifiesForFreeDelivery
    ? 0
    : deliveryAvailable
      ? maxFee
      : 0;
  const amount = round2(subtotal + deliveryFee);
  const commission = isCod ? 0 : round2(subtotal * rate);
  const sellerPayout = round2(amount - commission);
  return {
    itemSubtotal: subtotal,
    deliveryFee,
    amount,
    commission,
    sellerPayout,
    qualifiesForFreeDelivery,
  };
}

/// Seller sub-order number, e.g. ("PB-1001", 2) -> "PB-1001-S2".
function sellerOrderNumber(masterNumber, index) {
  return `${masterNumber}-S${index}`;
}

module.exports = {
  parsePrice,
  round2,
  groupItemsBySeller,
  computeSellerTotals,
  sellerOrderNumber,
};
