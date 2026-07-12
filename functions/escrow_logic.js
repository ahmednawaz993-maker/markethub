"use strict";

// Pure, unit-testable escrow money helpers. No Firebase required.
//   Run:  cd functions && node escrow_logic.test.js

function round2(n) {
  return Math.round((Number(n) || 0) * 100) / 100;
}

// Decide how much of an escrow refund to actually apply, given the order amount
// and how much has already been refunded. Guarantees total refunds can never
// exceed `amount` no matter how many times a refund action is (re)issued.
//
//   amount          — the held order amount
//   alreadyRefunded — cumulative refundAmount already credited (0 if none)
//   requested       — the amount asked for; <= 0 means "refund the rest"
//
// Returns { skip } when nothing remains to refund, otherwise
//   { refundValue, newRefundTotal, fullyRefunded }.
function refundAllocation(amount, alreadyRefunded, requested) {
  const amt = round2(amount);
  const prior = round2(alreadyRefunded);
  const remaining = round2(amt - prior);
  if (remaining <= 0) return { skip: true, remaining: 0 };
  const req = round2(requested);
  const refundValue = req > 0 ? Math.min(req, remaining) : remaining;
  const newRefundTotal = round2(prior + refundValue);
  return {
    skip: false,
    refundValue,
    newRefundTotal,
    fullyRefunded: newRefundTotal >= amt,
    remaining,
  };
}

module.exports = { round2, refundAllocation };
