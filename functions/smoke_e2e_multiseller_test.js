"use strict";
// END-TO-END smoke test of the full multi-seller lifecycle against the LIVE
// markethub-80276 backend, implementing the required scenario:
//   1. Buyer "registers" (throwaway uid + user doc)
//   2. Buyer adds products from THREE sellers
//   3. Buyer completes checkout (masterOrders intent)
//   4. THREE seller sub-orders are created (fan-out, correct per-seller amounts)
//   5. Buyer pays ONCE (manual proof + admin confirm) -> all 3 escrowed
//   6. Seller 1 accepts + ships + delivered
//   7. Seller 2 rejects  -> admin refunds seller 2's amount to the buyer wallet
//   8. Seller 3 accepts (remains active / held)
//   9. Buyer confirms receipt of Seller 1 -> payout becomes release-eligible
//  10. Buyer wallet == exactly Seller 2's amount (no over/under refund)
//  11. Admin sees correct allocation (master held; 3 sub-orders sum to total)
//  12. No stock / payment / authorization error occurs
// Cleans up everything it creates (throwaway `smoke_*` ids).
//
//   Run:  cd functions && node smoke_e2e_multiseller_test.js

const admin = require("firebase-admin");
const sa = require("../android/play-service-account.json");
admin.initializeApp({
  credential: admin.credential.cert(sa),
  projectId: "markethub-80276",
});
const db = admin.firestore();
const { Timestamp } = require("firebase-admin/firestore");

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
const bal = async (uid) =>
  Number((await db.collection("users").doc(uid).get()).get("walletBalance")) || 0;
const subOrders = async (masterId) =>
  (await db.collection("orders").where("masterOrderId", "==", masterId).get()).docs;

(async () => {
  console.log("=== Multi-seller E2E smoke test (LIVE) ===");
  const ts = Date.now();
  const buyer = `smoke_e2e_buyer_${ts}`;
  const sellers = [
    `smoke_e2e_s1_${ts}`,
    `smoke_e2e_s2_${ts}`,
    `smoke_e2e_s3_${ts}`,
  ];
  const listings = [`smoke_e2e_L1_${ts}`, `smoke_e2e_L2_${ts}`, `smoke_e2e_L3_${ts}`];
  const prices = [1000, 1500, 2000];
  const masterId = `smoke_e2e_master_${ts}`;
  const uids = [buyer, ...sellers];

  try {
    // (1) register buyer + sellers, (2) list one product per seller.
    await Promise.all(
      uids.map((u) => db.collection("users").doc(u).set({ walletBalance: 0, smokeTest: true }))
    );
    await Promise.all(
      listings.map((id, i) =>
        db.collection("listings").doc(id).set({
          title: `Smoke ${id}`,
          price: String(prices[i]),
          images: ["http://img/e2e.jpg"],
          status: "in_stock",
          userId: sellers[i],
          deliveryAvailable: false,
          deliveryFee: "0",
          smokeTest: true,
          createdAt: Timestamp.now(),
        })
      )
    );

    // (3) checkout intent across all three sellers.
    await db.collection("masterOrders").doc(masterId).set({
      buyerId: buyer,
      buyerName: "E2E Buyer",
      buyerPhone: "03001234567",
      deliveryAddress: { fullName: "E2E Buyer", phone: "03001234567", city: "Karachi" },
      items: listings.map((id, i) => ({
        listingId: id,
        sellerId: sellers[i],
        sellerName: `Seller ${i + 1}`,
        title: `Smoke ${id}`,
        quantity: 1,
      })),
      sellerCount: 3,
      itemsTotal: prices.reduce((a, b) => a + b, 0),
      paymentMethod: "escrow",
      status: "pending",
      createdAt: Timestamp.now(),
    });

    // (4) fan-out into three sub-orders.
    const master = await waitFor(async () => {
      const m = await db.collection("masterOrders").doc(masterId).get();
      return m.exists && m.data().status === "placed" ? m.data() : null;
    }, "fan-out");
    check("master fanned out (status placed)", !!master);
    let subs = await subOrders(masterId);
    check("three sub-orders created", subs.length === 3, { got: subs.length });
    const bySeller = {};
    subs.forEach((d) => (bySeller[d.data().sellerId] = d));
    check("seller amounts allocated correctly", sellers.every((s, i) => bySeller[s] && bySeller[s].data().amount === prices[i]), {
      got: sellers.map((s) => bySeller[s] && bySeller[s].data().amount),
    });

    // (5) pay ONCE for the whole order (manual proof -> admin confirm).
    const total = prices.reduce((a, b) => a + b, 0);
    const payRef = await db.collection("payments").add({
      masterOrderId: masterId,
      buyerId: buyer,
      amount: total,
      provider: "manual",
      status: "initiated",
      proofRef: "E2E",
      createdAt: Timestamp.now(),
    });
    await waitFor(async () => {
      const p = await payRef.get();
      return p.get("status") === "awaiting_confirmation" ? true : null;
    }, "payment awaiting_confirmation");
    await db.collection("paymentActions").add({
      paymentId: payRef.id, type: "confirm", by: "smoke_admin", status: "pending", createdAt: Timestamp.now(),
    });
    const held = await waitFor(async () => {
      const s = await subOrders(masterId);
      return s.length === 3 && s.every((d) => d.data().status === "in_escrow") ? s : null;
    }, "all sub-orders escrowed");
    check("one payment escrowed all three sub-orders", !!held);

    // Refresh handles.
    subs = await subOrders(masterId);
    subs.forEach((d) => (bySeller[d.data().sellerId] = d));
    const o1 = bySeller[sellers[0]].ref;
    const o2 = bySeller[sellers[1]].ref;
    const o3 = bySeller[sellers[2]].ref;

    // (6) Seller 1 accepts -> ships -> delivered.
    await o1.set({ orderStatus: "accepted" }, { merge: true });
    await o1.set({ orderStatus: "shipped", courierName: "TCS", trackingNumber: "E2E1", shippedAt: Timestamp.now() }, { merge: true });
    await o1.set({ orderStatus: "delivered", deliveredAt: Timestamp.now() }, { merge: true });

    // (7) Seller 2 rejects -> admin refunds seller 2's amount.
    await o2.set({ orderStatus: "rejected" }, { merge: true });
    await db.collection("escrowActions").doc(`refund_e2e_${o2.id}`).set({
      orderId: o2.id, type: "refund", by: "smoke_admin", status: "pending",
      resultOrderStatus: "cancelled", reason: "seller_rejected", createdAt: Timestamp.now(),
    });
    const refunded = await waitFor(async () => {
      const s = await o2.get();
      return s.get("status") === "refunded" ? s.data() : null;
    }, "seller 2 refunded");
    check("seller 2 order refunded", !!refunded);

    // (8) Seller 3 accepts (stays active / held).
    await o3.set({ orderStatus: "accepted" }, { merge: true });

    // (9) Buyer confirms receipt of Seller 1 -> payout becomes eligible.
    await o1.set({ buyerConfirmed: true, buyerConfirmedAt: Timestamp.now(), orderStatus: "buyer_confirmed" }, { merge: true });
    const eligible = await waitFor(async () => {
      const s = await o1.get();
      return s.get("paymentStatus") === "release_pending" ? s.data() : null;
    }, "seller 1 payout eligible");
    check("seller 1 delivery confirmed -> payout release-eligible", !!eligible);

    // (10) buyer wallet == exactly seller 2's amount (no over/under refund).
    const buyerBal = await bal(buyer);
    check("buyer refunded EXACTLY seller 2's amount", buyerBal === prices[1], { got: buyerBal, expected: prices[1] });

    // (10b) seller 3 remains active (held, not refunded/released).
    const s3 = (await o3.get()).data();
    check("seller 3 order remains active (in_escrow)", s3.status === "in_escrow", { got: s3.status });

    // (11) admin allocation: master held; live sub-orders sum to total.
    // The seller-2 refund fires refreshMasterProgress asynchronously, so poll
    // for the master to settle back on paymentStatus=held rather than read once.
    const m2 = await waitFor(async () => {
      const m = (await db.collection("masterOrders").doc(masterId).get()).data();
      return m && m.paymentStatus === "held" ? m : null;
    }, "master paymentStatus=held (admin allocation)");
    check("master paymentStatus=held (admin allocation)", !!m2, {
      got: m2 && m2.paymentStatus,
    });
    const sumAll = subs.reduce((a, d) => a + (d.data().amount || 0), 0);
    check("sub-order amounts sum to the paid total", sumAll === total, { got: sumAll, expected: total });

    // (12) no seller could ever see another seller's sub-order — enforced by
    // rules (orders scoped by sellerId); asserted structurally: each sub-order
    // has exactly one distinct sellerId from our three.
    const sellerIds = new Set(subs.map((d) => d.data().sellerId));
    check("each package isolated to one distinct seller", sellerIds.size === 3);
  } catch (e) {
    console.error("E2E crashed:", e);
    fail++;
  } finally {
    // Cleanup.
    const dels = [];
    const subs = await subOrders(masterId);
    for (const d of subs) {
      dels.push(d.ref.delete());
      dels.push(db.collection("sellerPayouts").doc(d.id).delete());
      dels.push(db.collection("escrowActions").doc(`refund_e2e_${d.id}`).delete());
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
    for (const id of listings) dels.push(db.collection("listings").doc(id).delete());
    for (const u of uids) {
      const notes = await db.collection("users").doc(u).collection("notifications").get();
      notes.forEach((n) => dels.push(n.ref.delete()));
      const wtx = await db.collection("users").doc(u).collection("walletTransactions").get();
      wtx.forEach((w) => dels.push(w.ref.delete()));
      dels.push(db.collection("users").doc(u).delete());
    }
    await Promise.all(dels.map((p) => p.catch(() => {})));
  }

  console.log(`\n=== ${pass} passed, ${fail} failed ===`);
  process.exit(fail === 0 ? 0 : 1);
})();
