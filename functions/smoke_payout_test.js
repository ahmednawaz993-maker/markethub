"use strict";
// End-to-end smoke test of the platform-held payout flow against the LIVE
// backend (project markethub-80276). Drives a synthetic order through the whole
// lifecycle and asserts each deployed Cloud Function effect, then deletes
// everything it created. Uses throwaway UIDs (`smoke_*`) so no real user or
// wallet is ever touched.
//
// Run locally:   cd functions && node smoke_payout_test.js
// Run in CI:     see .github/workflows/smoke-test.yml (post-deploy health check)
//
// Requires android/play-service-account.json (the Firebase Admin SDK service
// account). Exits 0 when every assertion passes, non-zero otherwise.
//
// NOTE: because it runs against production, the admin account receives the
// "Payout eligible" / "Dispute opened" pushes the flow emits; those in-app
// notification docs are cleaned up at the end.

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
  return admin
    .auth()
    .getUserByEmail(ADMIN_EMAIL)
    .then((u) => u.uid)
    .catch(() => null);
}

// Delete every doc a scenario created, incl. any function-produced side docs.
async function cleanup({ orderId, sellerId, actionRefs = [], disputeRef = null }) {
  const dels = [
    db.collection("orders").doc(orderId).delete(),
    db.collection("sellerPayouts").doc(orderId).delete(),
    db.collection("users").doc(sellerId).collection("payoutAccounts").doc("acc1").delete(),
    db.collection("users").doc(sellerId).delete(),
  ];
  for (const r of actionRefs) dels.push(r.delete());
  if (disputeRef) dels.push(disputeRef.delete());
  const aud = await db.collection("financialAuditLog").where("entityId", "==", orderId).get();
  aud.forEach((d) => dels.push(d.ref.delete()));
  const led = await db.collection("ledger").where("orderId", "==", orderId).get();
  led.forEach((d) => dels.push(d.ref.delete()));
  const au = await adminUid();
  if (au) {
    const notes = await db
      .collection("users")
      .doc(au)
      .collection("notifications")
      .where("refId", "==", orderId)
      .get();
    notes.forEach((d) => dels.push(d.ref.delete()));
  }
  await Promise.all(dels.map((p) => p.catch(() => {})));
}

async function seedSeller(sellerId, verified) {
  await db.collection("users").doc(sellerId).set({ walletBalance: 0, smokeTest: true });
  await db
    .collection("users")
    .doc(sellerId)
    .collection("payoutAccounts")
    .doc("acc1")
    .set({
      type: "easypaisa",
      accountTitle: "Smoke Seller",
      verificationStatus: verified ? "verified" : "pending",
    });
}

// -------------------------------------------------------------------------
async function happyPath() {
  const ts = Date.now();
  const sellerId = `smoke_seller_${ts}`;
  const buyerId = `smoke_buyer_${ts}`;
  const orderId = `smoke_order_${ts}`;
  const AMOUNT = 5000;
  const DELIVERY = 200;
  const actionRefs = [];
  console.log(`\n[Happy path]  order=${orderId}`);
  await seedSeller(sellerId, true);
  await db.collection("orders").doc(orderId).set({
    listingTitle: "Smoke Test Item",
    sellerId,
    sellerName: "Smoke Seller",
    buyerId,
    buyerName: "Smoke Buyer",
    amount: AMOUNT,
    deliveryFee: DELIVERY,
    itemSubtotal: AMOUNT - DELIVERY,
    status: "in_escrow",
    orderStatus: "shipped",
    paymentStatus: "held_by_platform",
    paymentMethod: "escrow",
    buyerConfirmed: false,
    smokeTest: true,
    createdAt: Timestamp.now(),
  });

  // A: premature release blocked
  const actA = await db.collection("escrowActions").add({ orderId, type: "release", by: "smoke_admin", status: "pending", createdAt: Timestamp.now() });
  actionRefs.push(actA);
  const aRes = await waitFor(async () => { const st = (await actA.get()).data().status; return st !== "pending" ? st : null; }, "A");
  check("release blocked before buyer confirmation", aRes === "blocked_not_confirmed", { status: aRes });
  check("wallet untouched by blocked release", ((await db.collection("users").doc(sellerId).get()).data().walletBalance || 0) === 0);

  // B: buyer confirms -> payout eligible
  await db.collection("orders").doc(orderId).set({ orderStatus: "buyer_confirmed", buyerConfirmed: true, buyerConfirmedAt: Timestamp.now(), buyerConfirmedBy: buyerId }, { merge: true });
  const payout = await waitFor(async () => { const s = await db.collection("sellerPayouts").doc(orderId).get(); return s.exists && s.data().releaseStatus === "eligible" ? s.data() : null; }, "payout eligible");
  check("sellerPayouts created & eligible", !!payout);
  if (payout) {
    check("payout idempotency key == orderId", payout.orderId === orderId);
    check("sellerPayableAmount correct", payout.sellerPayableAmount === AMOUNT, { got: payout.sellerPayableAmount });
  }
  const orderB = (await db.collection("orders").doc(orderId).get()).data();
  check("paymentStatus -> release_pending", orderB.paymentStatus === "release_pending", { got: orderB.paymentStatus });

  // C: admin release -> settlement
  const actC = await db.collection("escrowActions").add({ orderId, type: "release", by: "smoke_admin", transactionReference: `SMOKE-${ts}`, status: "pending", createdAt: Timestamp.now() });
  actionRefs.push(actC);
  const cRes = await waitFor(async () => { const st = (await actC.get()).data().status; return st !== "pending" ? st : null; }, "C");
  check("release action completed", cRes === "done", { status: cRes });
  const orderC = await waitFor(async () => { const s = await db.collection("orders").doc(orderId).get(); return s.data().status === "released" ? s.data() : null; }, "order released");
  check("order -> released", !!orderC);
  if (orderC) {
    check("paymentStatus -> released_to_seller", orderC.paymentStatus === "released_to_seller", { got: orderC.paymentStatus });
    check("orderStatus -> completed", orderC.orderStatus === "completed", { got: orderC.orderStatus });
  }
  check("seller wallet credited with payable", ((await db.collection("users").doc(sellerId).get()).data().walletBalance || 0) === AMOUNT);
  const payoutC = (await db.collection("sellerPayouts").doc(orderId).get()).data();
  check("payout -> released", payoutC.releaseStatus === "released", { got: payoutC.releaseStatus });
  check("transactionReference stored", payoutC.transactionReference === `SMOKE-${ts}`);
  const actions = (await db.collection("financialAuditLog").where("entityId", "==", orderId).get()).docs.map((d) => d.data().action);
  check("audit trail complete", actions.includes("payout_released") && actions.includes("buyer_confirmed_delivery"), { actions });

  // D: double-release does not double-pay
  const actD = await db.collection("escrowActions").add({ orderId, type: "release", by: "smoke_admin", status: "pending", createdAt: Timestamp.now() });
  actionRefs.push(actD);
  const dRes = await waitFor(async () => { const st = (await actD.get()).data().status; return st !== "pending" ? st : null; }, "D");
  check("second release rejected", dRes === "not_in_escrow", { status: dRes });
  check("wallet NOT double-credited", ((await db.collection("users").doc(sellerId).get()).data().walletBalance || 0) === AMOUNT);

  await cleanup({ orderId, sellerId, actionRefs });
}

async function guard(tag, { verified, disputeOpen, expected }) {
  const ts = Date.now();
  const sellerId = `smoke_seller_${ts}`;
  const buyerId = `smoke_buyer_${ts}`;
  const orderId = `smoke_order_${ts}`;
  const actionRefs = [];
  let disputeRef = null;
  console.log(`\n[Guard: ${tag}]  order=${orderId}`);
  await seedSeller(sellerId, verified);
  await db.collection("orders").doc(orderId).set({
    listingTitle: "Guard Item", sellerId, buyerId, amount: 3000, deliveryFee: 0, itemSubtotal: 3000,
    status: "in_escrow", orderStatus: "buyer_confirmed", paymentStatus: "release_pending",
    buyerConfirmed: true, smokeTest: true, createdAt: Timestamp.now(),
  });
  if (disputeOpen) {
    disputeRef = await db.collection("disputes").add({ orderId, buyerId, sellerId, status: "open", type: "problem", reason: "smoke", createdAt: Timestamp.now() });
    await sleep(5000);
  }
  const act = await db.collection("escrowActions").add({ orderId, type: "release", by: "smoke_admin", status: "pending", createdAt: Timestamp.now() });
  actionRefs.push(act);
  const res = await waitFor(async () => { const st = (await act.get()).data().status; return st !== "pending" ? st : null; }, tag);
  check(`${tag}: release blocked (${expected})`, res === expected, { got: res });
  check(`${tag}: wallet untouched`, ((await db.collection("users").doc(sellerId).get()).data().walletBalance || 0) === 0);
  await cleanup({ orderId, sellerId, actionRefs, disputeRef });
}

async function main() {
  console.log("=== Payout flow smoke test (live markethub-80276) ===");
  await happyPath();
  await guard("no-verified-account", { verified: false, disputeOpen: false, expected: "blocked_no_verified_account" });
  await guard("open-dispute", { verified: true, disputeOpen: true, expected: "blocked_dispute" });
  console.log(`\n=== RESULT: ${pass} passed, ${fail} failed ===`);
  process.exit(fail === 0 ? 0 : 1);
}
main().catch((e) => {
  console.error("smoke test crashed:", e);
  process.exit(2);
});
