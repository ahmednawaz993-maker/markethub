"use strict";
// End-to-end smoke test of the MULTI-SELLER CART / CHECKOUT flow against the LIVE
// backend (project markethub-80276). Drives a synthetic masterOrders checkout
// intent through the deployed Cloud Functions and asserts:
//   • onMasterOrderCreated fans it out into one orders/{id} sub-order per seller
//     (correct amounts, PB-n-S{i} numbers, master stamped placed + counts)
//   • confirmMasterPaymentIntoEscrow escrows EVERY sub-order from ONE payment
//   • onOrderProgress sends a named-package delivery push per sub-order
//   • refreshMasterProgress aggregates deliveredCount + fires one "all delivered"
//     push once every package is delivered
//   • COD checkout fans out into cod_pending sub-orders (no payment needed)
// Then deletes everything it created. Uses throwaway UIDs (`smoke_*`).
//
// Run locally:   cd functions && node smoke_multiseller_test.js
// Requires android/play-service-account.json (Firebase Admin SDK) and the
// multi-seller functions DEPLOYED. Exits 0 when every assertion passes.

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
async function waitFor(fn, label, tries = 25, gap = 3000) {
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

async function seedUser(uid) {
  await db.collection("users").doc(uid).set({ walletBalance: 0, smokeTest: true });
}
async function seedListing(id, sellerId, price) {
  await db.collection("listings").doc(id).set({
    title: `Smoke ${id}`,
    price: String(price),
    images: ["http://img/smoke.jpg"],
    status: "in_stock",
    userId: sellerId,
    deliveryAvailable: false,
    deliveryFee: "0",
    smokeTest: true,
    createdAt: Timestamp.now(),
  });
}
async function subOrders(masterId) {
  const s = await db.collection("orders").where("masterOrderId", "==", masterId).get();
  return s.docs;
}

async function cleanup({ masterId, listingIds, uids }) {
  const dels = [];
  const subs = await subOrders(masterId);
  for (const d of subs) {
    dels.push(d.ref.delete());
    dels.push(db.collection("sellerPayouts").doc(d.id).delete());
    const led = await db.collection("ledger").where("orderId", "==", d.id).get();
    led.forEach((l) => dels.push(l.ref.delete()));
    const aud = await db.collection("financialAuditLog").where("entityId", "==", d.id).get();
    aud.forEach((a) => dels.push(a.ref.delete()));
  }
  dels.push(db.collection("masterOrders").doc(masterId).delete());
  const pays = await db.collection("payments").where("masterOrderId", "==", masterId).get();
  for (const p of pays.docs) {
    dels.push(p.ref.delete());
    const acts = await db.collection("paymentActions").where("paymentId", "==", p.id).get();
    acts.forEach((a) => dels.push(a.ref.delete()));
  }
  for (const lid of listingIds) dels.push(db.collection("listings").doc(lid).delete());
  // Throwaway UIDs only — order notifications carry no orderId in refId, so we
  // clear the whole (test-only) notifications subcollection for each. The admin
  // account is deliberately NOT touched (this flow sends it no notifications).
  for (const uid of uids) {
    const notes = await db.collection("users").doc(uid).collection("notifications").get();
    notes.forEach((n) => dels.push(n.ref.delete()));
    dels.push(db.collection("users").doc(uid).delete());
  }
  await Promise.all(dels.map((p) => p.catch(() => {})));
}

// Scenario 1 — ONLINE (escrow) two-seller checkout: fan-out → pay-once → deliver.
async function escrowMultiSeller() {
  const ts = Date.now();
  const s1 = `smoke_seller_a_${ts}`;
  const s2 = `smoke_seller_b_${ts}`;
  const buyer = `smoke_buyer_${ts}`;
  const L1 = `smoke_L1_${ts}`;
  const L2 = `smoke_L2_${ts}`;
  const L3 = `smoke_L3_${ts}`;
  const masterId = `smoke_master_esc_${ts}`;
  const listingIds = [L1, L2, L3];
  const uids = [s1, s2, buyer];
  console.log(`\n[1: escrow multi-seller]  master=${masterId}`);
  await Promise.all([seedUser(s1), seedUser(s2), seedUser(buyer)]);
  // Seller A sells L1(1000)+L2(500); Seller B sells L3(2000).
  await Promise.all([
    seedListing(L1, s1, 1000),
    seedListing(L2, s1, 500),
    seedListing(L3, s2, 2000),
  ]);

  // Buyer writes the checkout intent (what placeCartOrder does).
  await db.collection("masterOrders").doc(masterId).set({
    buyerId: buyer,
    buyerName: "Smoke Buyer",
    buyerPhone: "03001234567",
    deliveryAddress: { fullName: "Smoke Buyer", phone: "03001234567", city: "Karachi" },
    items: [
      { listingId: L1, sellerId: s1, sellerName: "Seller A", title: "Smoke L1", quantity: 1 },
      { listingId: L2, sellerId: s1, sellerName: "Seller A", title: "Smoke L2", quantity: 1 },
      { listingId: L3, sellerId: s2, sellerName: "Seller B", title: "Smoke L3", quantity: 1 },
    ],
    sellerCount: 2,
    itemsTotal: 3500,
    paymentMethod: "escrow",
    status: "pending",
    createdAt: Timestamp.now(),
  });

  // (A) Fan-out.
  const master = await waitFor(async () => {
    const m = await db.collection("masterOrders").doc(masterId).get();
    return m.exists && m.data().status === "placed" ? m.data() : null;
  }, "master fan-out");
  check("master fanned out → status placed", !!master);
  check("master stamped sellerCount=2", master && master.sellerCount === 2, { got: master && master.sellerCount });
  check("master has 2 sellerOrderIds", master && (master.sellerOrderIds || []).length === 2, {
    got: master && (master.sellerOrderIds || []).length,
  });
  const subs = await subOrders(masterId);
  check("two sub-orders created", subs.length === 2, { got: subs.length });
  const byAmt = {};
  subs.forEach((d) => (byAmt[d.data().sellerId] = d.data().amount));
  check("seller A sub-order amount = 1500 (L1+L2)", byAmt[s1] === 1500, { got: byAmt[s1] });
  check("seller B sub-order amount = 2000 (L3)", byAmt[s2] === 2000, { got: byAmt[s2] });
  const nums = subs.map((d) => d.data().orderNumber).sort();
  check("sub-orders numbered PB-n-S1 / PB-n-S2", nums.every((n) => /^PB-\d+-S\d+$/.test(n)), { got: nums });
  check("sub-orders start pending_payment", subs.every((d) => d.data().status === "pending_payment"), {
    got: subs.map((d) => d.data().status),
  });

  // (B) Pay ONCE for the whole master via the real manual flow: submit proof
  // (-> awaiting_confirmation) then an admin confirm action fans the hold out.
  const total = byAmt[s1] + byAmt[s2];
  const payRef = await db.collection("payments").add({
    masterOrderId: masterId,
    buyerId: buyer,
    amount: total,
    provider: "manual",
    status: "initiated",
    proofRef: "SMOKE",
    createdAt: Timestamp.now(),
  });
  const awaiting = await waitFor(async () => {
    const p = await payRef.get();
    return p.get("status") === "awaiting_confirmation" ? true : null;
  }, "payment awaiting_confirmation");
  check("manual master payment → awaiting_confirmation (no self-capture)", !!awaiting);
  await db.collection("paymentActions").add({
    paymentId: payRef.id,
    type: "confirm",
    by: "smoke_admin",
    status: "pending",
    createdAt: Timestamp.now(),
  });
  const held = await waitFor(async () => {
    const s = await subOrders(masterId);
    return s.length === 2 && s.every((d) => d.data().status === "in_escrow") ? s : null;
  }, "all sub-orders in escrow");
  check("one payment escrowed BOTH sub-orders", !!held);
  check(
    "each sub-order paymentStatus=held_by_platform",
    held && held.every((d) => d.data().paymentStatus === "held_by_platform"),
    { got: held && held.map((d) => d.data().paymentStatus) }
  );
  const mPaid = (await db.collection("masterOrders").doc(masterId).get()).data();
  check("master paymentStatus=held", mPaid.paymentStatus === "held", { got: mPaid.paymentStatus });

  // (C) Deliver both packages → per-package push + aggregate "all delivered".
  for (const d of held || []) {
    await d.ref.set({ orderStatus: "delivered", deliveredAt: Timestamp.now() }, { merge: true });
  }
  const done = await waitFor(async () => {
    const m = await db.collection("masterOrders").doc(masterId).get();
    return m.data().allDelivered === true ? m.data() : null;
  }, "master allDelivered");
  check("master aggregates allDelivered=true", !!done);
  check("master deliveredCount=2", done && done.deliveredCount === 2, { got: done && done.deliveredCount });
  // Notifications carry no orderId in refId; the buyer UID is throwaway so its
  // whole notifications collection belongs to this test — match on text.
  const allNote = await waitFor(async () => {
    const s = await db.collection("users").doc(buyer).collection("notifications").get();
    return s.docs.some((n) => /all packages delivered/i.test(n.data().title || "")) ? true : null;
  }, "all-delivered push");
  check("buyer got one 'All packages delivered' push", !!allNote);
  const pkgNote = await waitFor(async () => {
    const s = await db.collection("users").doc(buyer).collection("notifications").get();
    return s.docs.some((n) => /package .*marked delivered/i.test(n.data().body || "")) ? true : null;
  }, "per-package delivered push");
  check("buyer got a named-package delivery push", !!pkgNote);

  await cleanup({ masterId, listingIds, uids });
}

// Scenario 2 — COD single-seller checkout: fan-out → cod_pending (no payment).
async function codMultiSeller() {
  const ts = Date.now();
  const s1 = `smoke_seller_c_${ts}`;
  const buyer = `smoke_buyer_c_${ts}`;
  const L1 = `smoke_Lc_${ts}`;
  const masterId = `smoke_master_cod_${ts}`;
  console.log(`\n[2: COD checkout]  master=${masterId}`);
  await Promise.all([seedUser(s1), seedUser(buyer), seedListing(L1, s1, 1200)]);
  await db.collection("masterOrders").doc(masterId).set({
    buyerId: buyer,
    buyerName: "Smoke COD Buyer",
    buyerPhone: "03007654321",
    deliveryAddress: { fullName: "Smoke COD Buyer", phone: "03007654321", city: "Lahore" },
    items: [{ listingId: L1, sellerId: s1, sellerName: "Seller C", title: "Smoke Lc", quantity: 2 }],
    sellerCount: 1,
    itemsTotal: 2400,
    paymentMethod: "cod",
    status: "pending",
    createdAt: Timestamp.now(),
  });
  const subs = await waitFor(async () => {
    const s = await subOrders(masterId);
    return s.length === 1 ? s : null;
  }, "COD fan-out");
  check("COD checkout fanned out into 1 sub-order", !!subs);
  if (subs) {
    const d = subs[0].data();
    check("COD sub-order status=cod_pending", d.status === "cod_pending", { got: d.status });
    check("COD sub-order amount=2400 (1200 x2)", d.amount === 2400, { got: d.amount });
    check("COD sub-order paymentMethod=cod", d.paymentMethod === "cod", { got: d.paymentMethod });
  }
  await cleanup({ masterId, listingIds: [L1], uids: [s1, buyer] });
}

(async () => {
  console.log("=== Multi-seller cart/checkout smoke test (LIVE) ===");
  try {
    await escrowMultiSeller();
    await codMultiSeller();
  } catch (e) {
    console.error("Smoke test crashed:", e);
    fail++;
  }
  console.log(`\n=== ${pass} passed, ${fail} failed ===`);
  process.exit(fail === 0 ? 0 : 1);
})();
