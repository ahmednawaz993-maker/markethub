"use strict";
// End-to-end smoke test of the ORDER CANCELLATION flow against the LIVE backend
// (project markethub-80276). Drives synthetic orders through each cancellation
// path and asserts the deployed Cloud Function effects, then deletes everything
// it created. Uses throwaway UIDs (`smoke_*`) so no real user/wallet is touched.
//
// Run locally:   cd functions && node smoke_cancellation_test.js
// Run in CI:     add alongside smoke_payout_test.js in smoke-test.yml.
//
// Requires android/play-service-account.json (Firebase Admin SDK). Requires the
// new functions (onCancellationRequestCreated / onCancellationRequestDecision)
// to be DEPLOYED. Exits 0 when every assertion passes, non-zero otherwise.

const admin = require("firebase-admin");
const sa = require("../android/play-service-account.json");
admin.initializeApp({
  credential: admin.credential.cert(sa),
  projectId: "markethub-80276",
});
const db = admin.firestore();
const { Timestamp } = require("firebase-admin/firestore");
const ADMIN_EMAIL = "ahmednawaz993@gmail.com";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let pass = 0;
let fail = 0;
function check(name, cond, extra) {
  if (cond) {
    pass++;
    console.log(`  PASS  ${name}`);
  } else {
    fail++;
    console.log(`  FAIL  ${name}${extra ? "  -> " + JSON.stringify(extra) : ""}`);
  }
}
async function waitFor(fn, label, tries = 20, gap = 3000) {
  for (let i = 0; i < tries; i++) {
    const v = await fn();
    if (v) return v;
    await sleep(gap);
  }
  console.log(`  (timed out waiting for ${label})`);
  return null;
}
async function adminUid() {
  return admin.auth().getUserByEmail(ADMIN_EMAIL).then((u) => u.uid).catch(() => null);
}

async function seedParties(sellerId, buyerId) {
  await db.collection("users").doc(sellerId).set({ walletBalance: 0, smokeTest: true });
  await db.collection("users").doc(buyerId).set({ walletBalance: 0, smokeTest: true });
}

async function cleanup({ orderId, sellerId, buyerId }) {
  const dels = [];
  const reqs = await db.collection("orders").doc(orderId).collection("cancellationRequests").get();
  reqs.forEach((d) => dels.push(d.ref.delete()));
  dels.push(db.collection("orders").doc(orderId).delete());
  dels.push(db.collection("sellerPayouts").doc(orderId).delete());
  dels.push(db.collection("escrowActions").doc(`cancel_${orderId}`).delete());
  dels.push(db.collection("users").doc(sellerId).delete());
  dels.push(db.collection("users").doc(buyerId).delete());
  const aud = await db.collection("financialAuditLog").where("entityId", "==", orderId).get();
  aud.forEach((d) => dels.push(d.ref.delete()));
  const led = await db.collection("ledger").where("orderId", "==", orderId).get();
  led.forEach((d) => dels.push(d.ref.delete()));
  for (const uid of [sellerId, buyerId, await adminUid()]) {
    if (!uid) continue;
    const notes = await db.collection("users").doc(uid).collection("notifications").where("refId", "==", orderId).get();
    notes.forEach((d) => dels.push(d.ref.delete()));
  }
  await Promise.all(dels.map((p) => p.catch(() => {})));
}

// A) Direct cancel of an UNPAID (COD) order → order cancelled + audit written.
async function directCancelUnpaid() {
  const ts = Date.now();
  const sellerId = `smoke_seller_${ts}`;
  const buyerId = `smoke_buyer_${ts}`;
  const orderId = `smoke_cancel_cod_${ts}`;
  const listingId = `smoke_cancelL_${ts}`;
  console.log(`\n[A: direct cancel of unpaid COD]  order=${orderId}`);
  await seedParties(sellerId, buyerId);
  // A real COD order always references an in-stock, COD-enabled listing;
  // notifyOnNewOrder now voids payable orders that have no listingId.
  await db.collection("listings").doc(listingId).set({
    title: "Smoke COD Item", price: "1500", images: ["x"], status: "in_stock",
    userId: sellerId, deliveryAvailable: false, deliveryFee: "0",
    codAvailable: true, smokeTest: true, createdAt: Timestamp.now(),
  });
  await db.collection("orders").doc(orderId).set({
    listingTitle: "Smoke COD Item", listingId, sellerId, buyerId,
    buyerName: "Smoke Buyer", amount: 1500, status: "cod_pending",
    orderStatus: "processing", paymentMethod: "cod", smokeTest: true,
    createdAt: Timestamp.now(),
  });
  // Client-equivalent direct cancel write (admin SDK bypasses rules).
  await db.collection("orders").doc(orderId).set({
    status: "cancelled", orderStatus: "cancelled", cancelledBy: buyerId,
    cancelledByRole: "buyer", cancelReason: "changed mind",
    cancelReasonCode: "ordered_by_mistake", cancelledAt: Timestamp.now(),
  }, { merge: true });
  const aud = await waitFor(async () => {
    const s = await db.collection("financialAuditLog")
      .where("entityId", "==", orderId).where("action", "==", "buyer_cancelled_pending").get();
    return s.empty ? null : s.docs[0].data();
  }, "cancel audit");
  check("direct cancel writes buyer_cancelled_pending audit", !!aud);
  const note = await waitFor(async () => {
    const s = await db.collection("users").doc(sellerId).collection("notifications").where("refId", "==", orderId).get();
    return s.empty ? null : true;
  }, "seller cancel notification");
  check("seller notified of buyer cancel", !!note);
  await db.collection("listings").doc(listingId).delete().catch(() => {});
  await cleanup({ orderId, sellerId, buyerId });
}

// B) Cancellation REQUEST on a paid-but-unaccepted order → auto-approved with a
//    wallet refund (reuses the escrow-refund path).
async function requestAutoApproveWithRefund() {
  const ts = Date.now();
  const sellerId = `smoke_seller_${ts}`;
  const buyerId = `smoke_buyer_${ts}`;
  const orderId = `smoke_cancel_paid_${ts}`;
  const AMOUNT = 4000;
  console.log(`\n[B: paid & unaccepted → auto-approve + refund]  order=${orderId}`);
  await seedParties(sellerId, buyerId);
  await db.collection("orders").doc(orderId).set({
    listingTitle: "Smoke Paid Item", sellerId, buyerId, buyerName: "Smoke Buyer",
    amount: AMOUNT, status: "in_escrow", orderStatus: "pending",
    paymentStatus: "held_by_platform", paymentMethod: "escrow",
    smokeTest: true, createdAt: Timestamp.now(),
  });
  await db.collection("orders").doc(orderId).collection("cancellationRequests").add({
    orderId, buyerId, sellerId, reasonCode: "incorrect_address", reasonDetails: "wrong city",
    requestStatus: "pending", requestedBy: buyerId, requestedAt: Timestamp.now(),
  });
  const order = await waitFor(async () => {
    const s = await db.collection("orders").doc(orderId).get();
    return s.data().status === "refunded" ? s.data() : null;
  }, "order refunded");
  check("paid-pending cancel → order refunded", !!order);
  if (order) check("orderStatus → cancelled", order.orderStatus === "cancelled", { got: order.orderStatus });
  const bal = (await db.collection("users").doc(buyerId).get()).data().walletBalance || 0;
  check("buyer wallet refunded full amount", bal === AMOUNT, { got: bal });
  const aud = await waitFor(async () => {
    const s = await db.collection("financialAuditLog")
      .where("entityId", "==", orderId).where("action", "==", "cancellation_approved").get();
    return s.empty ? null : true;
  }, "approval audit");
  check("cancellation_approved audit written", !!aud);
  await cleanup({ orderId, sellerId, buyerId });
}

// C) Cancellation REQUEST on an ACCEPTED order → stays pending until the seller
//    approves; approval then cancels + refunds.
async function requestNeedsApproval() {
  const ts = Date.now();
  const sellerId = `smoke_seller_${ts}`;
  const buyerId = `smoke_buyer_${ts}`;
  const orderId = `smoke_cancel_acc_${ts}`;
  const AMOUNT = 2500;
  console.log(`\n[C: accepted → request, seller approves]  order=${orderId}`);
  await seedParties(sellerId, buyerId);
  await db.collection("orders").doc(orderId).set({
    listingTitle: "Smoke Accepted Item", sellerId, buyerId, buyerName: "Smoke Buyer",
    amount: AMOUNT, status: "in_escrow", orderStatus: "accepted",
    paymentStatus: "held_by_platform", paymentMethod: "escrow",
    smokeTest: true, createdAt: Timestamp.now(),
  });
  const reqRef = await db.collection("orders").doc(orderId).collection("cancellationRequests").add({
    orderId, buyerId, sellerId, reasonCode: "seller_delay", reasonDetails: "too slow",
    requestStatus: "pending", requestedBy: buyerId, requestedAt: Timestamp.now(),
  });
  // The order must NOT auto-cancel; it should be flagged pending for review.
  const flagged = await waitFor(async () => {
    const s = await db.collection("orders").doc(orderId).get();
    return s.data().cancellationRequestStatus === "pending" ? s.data() : null;
  }, "request flagged pending");
  check("accepted order flagged cancellationRequestStatus=pending", !!flagged);
  check("accepted order NOT auto-cancelled", flagged && flagged.status === "in_escrow", { got: flagged && flagged.status });
  // Seller approves.
  await reqRef.set({ requestStatus: "approved", reviewedBy: sellerId, decidedByRole: "seller", reviewedAt: Timestamp.now() }, { merge: true });
  const order = await waitFor(async () => {
    const s = await db.collection("orders").doc(orderId).get();
    return s.data().status === "refunded" ? s.data() : null;
  }, "order refunded after approval");
  check("seller approval → order refunded", !!order);
  const bal = (await db.collection("users").doc(buyerId).get()).data().walletBalance || 0;
  check("buyer wallet refunded after approval", bal === AMOUNT, { got: bal });
  await cleanup({ orderId, sellerId, buyerId });
}

// D) Cancellation REQUEST on a SHIPPED order → auto-rejected (support only).
async function requestRejectedAfterShip() {
  const ts = Date.now();
  const sellerId = `smoke_seller_${ts}`;
  const buyerId = `smoke_buyer_${ts}`;
  const orderId = `smoke_cancel_ship_${ts}`;
  console.log(`\n[D: shipped → request auto-rejected]  order=${orderId}`);
  await seedParties(sellerId, buyerId);
  await db.collection("orders").doc(orderId).set({
    listingTitle: "Smoke Shipped Item", sellerId, buyerId, buyerName: "Smoke Buyer",
    amount: 3000, status: "in_escrow", orderStatus: "shipped",
    paymentStatus: "held_by_platform", paymentMethod: "escrow",
    courierName: "TCS", trackingNumber: "X1", smokeTest: true, createdAt: Timestamp.now(),
  });
  const reqRef = await db.collection("orders").doc(orderId).collection("cancellationRequests").add({
    orderId, buyerId, sellerId, reasonCode: "other", reasonDetails: "",
    requestStatus: "pending", requestedBy: buyerId, requestedAt: Timestamp.now(),
  });
  const decided = await waitFor(async () => {
    const s = await reqRef.get();
    return s.data().requestStatus !== "pending" ? s.data() : null;
  }, "request auto-decided");
  check("shipped request auto-rejected", decided && decided.requestStatus === "rejected", { got: decided && decided.requestStatus });
  const order = (await db.collection("orders").doc(orderId).get()).data();
  check("shipped order stays in_escrow (not cancelled)", order.status === "in_escrow", { got: order.status });
  await cleanup({ orderId, sellerId, buyerId });
}

(async () => {
  console.log("=== Cancellation smoke test (LIVE) ===");
  try {
    await directCancelUnpaid();
    await requestAutoApproveWithRefund();
    await requestNeedsApproval();
    await requestRejectedAfterShip();
  } catch (e) {
    console.error("Smoke test crashed:", e);
    fail++;
  }
  console.log(`\n=== ${pass} passed, ${fail} failed ===`);
  process.exit(fail === 0 ? 0 : 1);
})();
