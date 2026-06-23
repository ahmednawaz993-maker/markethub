"use strict";

// MarketHub Cloud Functions.
//
// notifyOnNewMessage: when a chat message is created, push an FCM notification
// to the OTHER participant's registered devices (users/{uid}/fcmTokens).

const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const crypto = require("crypto");
const { initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { defineSecret } = require("firebase-functions/params");
const sgMail = require("@sendgrid/mail");

initializeApp();

// SendGrid API key. Set it once with:
//   firebase functions:secrets:set SENDGRID_API_KEY
const SENDGRID_API_KEY = defineSecret("SENDGRID_API_KEY");

// Support inbox that receives Help/Suggestion emails. SUPPORT_FROM must be a
// verified Single Sender (or a verified domain) in your SendGrid account.
const SUPPORT_TO = "ahmednawaz993@gmail.com";
const SUPPORT_FROM = "ahmednawaz993@gmail.com";

// Platform commission taken on each released escrow deal. Keep in sync with
// commissionRate in the app (lib/src/commerce.dart).
const COMMISSION_RATE = 0.02;

// PayFast (gopayfast, Pakistan) credentials — read from process.env so the
// (default) manual payment flow deploys without them. When you activate the
// gateway, set them: firebase functions:secrets:set PAYFAST_MERCHANT_ID /
// PAYFAST_SECURED_KEY, then bind the secrets to onPaymentCreated + payfastIpn.

exports.notifyOnNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const msg = event.data && event.data.data();
    if (!msg) return;

    const chatId = event.params.chatId;
    const db = getFirestore();

    const chatSnap = await db.collection("chats").doc(chatId).get();
    const chat = chatSnap.data();
    if (!chat) return;

    const participants = chat.participants || [];
    const recipientId = participants.find((p) => p !== msg.senderId);
    if (!recipientId) return;

    // Friendly sender name based on which side of the chat sent it.
    const senderName =
      msg.senderId === chat.buyerId ? chat.buyerName : chat.sellerName;

    await recordNotification(
      db,
      recipientId,
      senderName ? `New message from ${senderName}` : "New message",
      String(msg.text || "").slice(0, 140),
      "chat",
      chatId
    );

    // Collect the recipient's device tokens.
    const tokensSnap = await db
      .collection("users")
      .doc(recipientId)
      .collection("fcmTokens")
      .get();
    const tokens = tokensSnap.docs.map((d) => d.id);
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: senderName ? `New message from ${senderName}` : "New message",
        body: String(msg.text || "").slice(0, 140),
      },
      data: {
        type: "chat",
        chatId,
        listingTitle: String(chat.listingTitle || ""),
      },
      webpush: {
        notification: { icon: "/icons/Icon-192.png" },
        fcmOptions: { link: "/" },
      },
    });

    await pruneInvalidTokens(db, recipientId, tokens, response);
  }
);

// Recompute a seller's aggregate rating whenever one of their reviews is
// created, edited or deleted. This is the AUTHORITATIVE source of
// ratingSum/ratingCount on the user doc — clients can no longer write those
// fields (Firestore rules block it), so a rating cannot be forged. We re-sum
// the reviews subcollection (one doc per reviewer, each a validated 1-5 stars).
// Writes the parent user doc only, so it never re-triggers itself.
exports.onReviewWrite = onDocumentWritten(
  "users/{sellerId}/reviews/{reviewerId}",
  async (event) => {
    const sellerId = event.params.sellerId;
    const db = getFirestore();
    const snap = await db
      .collection("users")
      .doc(sellerId)
      .collection("reviews")
      .get();

    let sum = 0;
    let count = 0;
    snap.forEach((d) => {
      const r = d.data().rating;
      if (typeof r === "number" && r >= 1 && r <= 5) {
        sum += r;
        count += 1;
      }
    });

    await db
      .collection("users")
      .doc(sellerId)
      .set({ ratingSum: sum, ratingCount: count }, { merge: true });
  }
);

// Notify users whose saved search matches a newly posted ad.
exports.notifyOnNewListing = onDocumentCreated(
  "listings/{listingId}",
  async (event) => {
    const listing = event.data && event.data.data();
    if (!listing) return;

    const db = getFirestore();
    const searches = await db.collectionGroup("savedSearches").get();

    // One notification per user (dedupe), carrying the matched search label.
    const toNotify = new Map();
    searches.forEach((doc) => {
      const userDoc = doc.ref.parent.parent;
      if (!userDoc) return;
      const uid = userDoc.id;
      if (uid === listing.userId) return; // don't notify the poster
      if (toNotify.has(uid)) return; // already queued for this user
      if (matchesSavedSearch(listing, doc.data())) {
        toNotify.set(uid, doc.data().label || "your saved search");
      }
    });

    for (const [uid, label] of toNotify) {
      await recordNotification(
        db,
        uid,
        `New ad matches "${label}"`,
        `${listing.title} — Rs ${listing.price}`,
        "savedSearch",
        event.params.listingId
      );

      const tokensSnap = await db
        .collection("users")
        .doc(uid)
        .collection("fcmTokens")
        .get();
      const tokens = tokensSnap.docs.map((d) => d.id);
      if (tokens.length === 0) continue;

      const response = await getMessaging().sendEachForMulticast({
        tokens,
        notification: {
          title: `New ad matches "${label}"`,
          body: `${listing.title} — Rs ${listing.price}`,
        },
        data: {
          type: "savedSearch",
          listingId: event.params.listingId,
        },
        webpush: {
          notification: { icon: "/icons/Icon-192.png" },
          fcmOptions: { link: "/" },
        },
      });

      await pruneInvalidTokens(db, uid, tokens, response);
    }

    // Also notify everyone who follows the poster (skipping anyone already
    // alerted via a saved-search match above, to avoid a double ping).
    if (listing.userId) {
      const sellerName = listing.sellerName || "A seller you follow";
      const followersSnap = await db
        .collection("users")
        .doc(listing.userId)
        .collection("followers")
        .get();

      for (const f of followersSnap.docs) {
        const uid = f.id;
        if (uid === listing.userId) continue; // shouldn't happen, be safe
        if (toNotify.has(uid)) continue; // already pinged for this ad
        await pushToUser(
          db,
          uid,
          {
            title: `New ad from ${sellerName}`,
            body: `${listing.title} — Rs ${listing.price}`,
          },
          { type: "follow", listingId: event.params.listingId }
        );
      }
    }
  }
);

// Notify everyone who saved (favorited) a listing when its price is reduced.
exports.notifyOnPriceDrop = onDocumentUpdated(
  "listings/{listingId}",
  async (event) => {
    const before = event.data && event.data.before.data();
    const after = event.data && event.data.after.data();
    if (!before || !after) return;

    // Only act when a fresh price drop was just recorded by the app.
    const beforeDrop = before.priceDropAt;
    const afterDrop = after.priceDropAt;
    if (!afterDrop) return;
    const beforeMs = beforeDrop && beforeDrop.toMillis ? beforeDrop.toMillis() : 0;
    const afterMs = afterDrop.toMillis ? afterDrop.toMillis() : 0;
    if (afterMs <= beforeMs) return; // no new drop

    const db = getFirestore();
    const saves = await db
      .collectionGroup("favorites")
      .where("savedListingId", "==", event.params.listingId)
      .get();

    const title = "Price drop on a saved ad";
    const body = `${after.title} is now Rs ${after.price} (was Rs ${before.price})`;

    for (const doc of saves.docs) {
      const userDoc = doc.ref.parent.parent;
      if (!userDoc) continue;
      const uid = userDoc.id;
      if (uid === after.userId) continue; // don't notify the seller
      await pushToUser(db, uid, { title, body }, {
        type: "priceDrop",
        listingId: event.params.listingId,
      });
    }
  }
);

function matchesSavedSearch(listing, s) {
  const cat = s.category;
  if (cat && cat !== "All" && listing.category !== cat) return false;

  const sub = s.subcategory;
  if (sub && sub !== "All" && listing.subcategory !== sub) return false;

  const city = s.city;
  if (city && city !== "All" && listing.city !== city) return false;

  const price = parseFloat(String(listing.price || "").replace(/[^0-9.]/g, "")) || 0;
  if (s.minPrice != null && price < s.minPrice) return false;
  if (s.maxPrice != null && price > s.maxPrice) return false;

  const q = String(s.query || "").toLowerCase().trim();
  if (q) {
    const hay = [
      listing.title,
      listing.description,
      listing.category,
      listing.subcategory,
      listing.location,
      listing.city,
    ]
      .map((x) => String(x || "").toLowerCase())
      .join(" ");
    if (!hay.includes(q)) return false;
  }
  return true;
}

// Removes FCM tokens that the messaging API reported as permanently invalid.
async function pruneInvalidTokens(db, uid, tokens, response) {
  const removals = [];
  response.responses.forEach((r, i) => {
    if (!r.success) {
      const code = (r.error && r.error.code) || "";
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-registration-token") ||
        code.includes("invalid-argument")
      ) {
        removals.push(
          db
            .collection("users")
            .doc(uid)
            .collection("fcmTokens")
            .doc(tokens[i])
            .delete()
        );
      }
    }
  });
  await Promise.all(removals);
}

// Notify a seller when a buyer places an order on their listing.
exports.notifyOnNewOrder = onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const order = event.data && event.data.data();
    if (!order || !order.sellerId) return;

    const db = getFirestore();
    await recordNotification(
      db,
      order.sellerId,
      "New order received",
      `${order.buyerName || "A buyer"} ordered "${order.listingTitle}" for Rs ${order.amount}`,
      "order",
      event.params.orderId
    );

    const tokensSnap = await db
      .collection("users")
      .doc(order.sellerId)
      .collection("fcmTokens")
      .get();
    const tokens = tokensSnap.docs.map((d) => d.id);
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "New order received",
        body: `${order.buyerName || "A buyer"} ordered "${order.listingTitle}" for Rs ${order.amount}`,
      },
      data: { type: "order", orderId: event.params.orderId },
      webpush: {
        notification: { icon: "/icons/Icon-192.png" },
        fcmOptions: { link: "/" },
      },
    });

    await pruneInvalidTokens(db, order.sellerId, tokens, response);
  }
);

// Shared helper: push a notification to all of a user's registered devices.
async function pushToUser(db, uid, notification, data) {
  await recordNotification(
    db,
    uid,
    notification.title,
    notification.body,
    (data && data.type) || "",
    (data && data.offerId) || ""
  );
  const tokensSnap = await db
    .collection("users")
    .doc(uid)
    .collection("fcmTokens")
    .get();
  const tokens = tokensSnap.docs.map((d) => d.id);
  if (tokens.length === 0) return;
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification,
    data: data || {},
    webpush: {
      notification: { icon: "/icons/Icon-192.png" },
      fcmOptions: { link: "/" },
    },
  });
  await pruneInvalidTokens(db, uid, tokens, response);
}

// Notify a seller when a buyer makes an offer on their listing.
exports.notifyOnNewOffer = onDocumentCreated(
  "offers/{offerId}",
  async (event) => {
    const offer = event.data && event.data.data();
    if (!offer || !offer.sellerId) return;
    await pushToUser(
      getFirestore(),
      offer.sellerId,
      {
        title: "New offer received",
        body: `${offer.buyerName || "A buyer"} offered Rs ${offer.offerAmount} for "${offer.listingTitle}"`,
      },
      { type: "offer", offerId: event.params.offerId }
    );
  }
);

// Notify the relevant party when an offer's status changes.
exports.notifyOnOfferUpdate = onDocumentUpdated(
  "offers/{offerId}",
  async (event) => {
    const before = event.data && event.data.before.data();
    const after = event.data && event.data.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;

    let recipientId;
    let title;
    let body;
    const title2 = `"${after.listingTitle}"`;
    switch (after.status) {
      case "accepted":
        recipientId = after.buyerId;
        title = "Offer accepted";
        body = `Your offer on ${title2} was accepted — tap to buy.`;
        break;
      case "countered":
        recipientId = after.buyerId;
        title = "Seller countered";
        body = `Seller countered Rs ${after.counterAmount} on ${title2}.`;
        break;
      case "declined":
        recipientId = after.buyerId;
        title = "Offer declined";
        body = `Your offer on ${title2} was declined.`;
        break;
      case "ordered":
        recipientId = after.sellerId;
        title = "Deal agreed";
        body = `${after.buyerName || "The buyer"} agreed to buy ${title2} for Rs ${after.agreedAmount}.`;
        break;
      default:
        return;
    }
    if (!recipientId) return;
    await pushToUser(getFirestore(), recipientId, { title, body }, {
      type: "offer",
      offerId: event.params.offerId,
    });
  }
);

// Persists a notification into the user's history (for the in-app bell).
async function recordNotification(db, uid, title, body, type, refId) {
  try {
    await db
      .collection("users")
      .doc(uid)
      .collection("notifications")
      .add({
        title: title || "",
        body: body || "",
        type: type || "",
        refId: refId || "",
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
  } catch (e) {
    // Non-critical; the push still goes out.
  }
}

// Processes a wallet purchase: atomically checks the balance, deducts it, and
// applies the effect (feature a listing / featured business / home banner).
exports.processPurchase = onDocumentCreated("purchases/{id}", async (event) => {
  const p = event.data && event.data.data();
  if (!p || !p.userId) return;

  const db = getFirestore();
  const purchaseRef = event.data.ref;
  const userRef = db.collection("users").doc(p.userId);
  const amount = Number(p.amount) || 0;
  const days = Number(p.days) || 7;
  const until = Timestamp.fromMillis(Date.now() + days * 86400000);

  try {
    await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const balance = Number(userSnap.get("walletBalance")) || 0;
      if (amount <= 0 || balance < amount) {
        tx.update(purchaseRef, { status: "insufficient" });
        return;
      }

      const userUpdate = { walletBalance: balance - amount };
      if (p.type === "feature" && p.refId) {
        tx.update(db.collection("listings").doc(p.refId), {
          isFeatured: true,
          featuredUntil: until,
        });
      } else if (p.type === "featuredBusiness") {
        userUpdate.featuredBusiness = true;
        userUpdate.featuredBusinessUntil = until;
      } else if (p.type === "banner") {
        tx.set(db.collection("banners").doc(), {
          imageUrl: p.imageUrl || "",
          title: p.bannerTitle || "",
          subtitle: p.bannerSubtitle || "",
          sellerId: p.userId,
          category: "",
          order: 99,
          active: true,
          createdAt: FieldValue.serverTimestamp(),
          expiresAt: until,
        });
      }

      tx.update(userRef, userUpdate);
      tx.set(userRef.collection("walletTransactions").doc(), {
        type: "debit",
        amount,
        purpose: p.type || "purchase",
        refId: p.refId || "",
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.update(purchaseRef, {
        status: "completed",
        completedAt: FieldValue.serverTimestamp(),
      });
    });
  } catch (e) {
    await purchaseRef.update({ status: "error" });
  }

  const fresh = await purchaseRef.get();
  const status = fresh.get("status");
  if (status === "completed") {
    await recordNotification(
      db,
      p.userId,
      "Purchase successful",
      `Your ${p.type} is now active.`,
      "purchase",
      purchaseRef.id
    );
  } else if (status === "insufficient") {
    await recordNotification(
      db,
      p.userId,
      "Insufficient wallet balance",
      "Top up your PakBazar Wallet to complete this purchase.",
      "purchase",
      purchaseRef.id
    );
  }
});

// Daily job: turn off Featured listings / businesses / banners whose paid
// window (featuredUntil / featuredBusinessUntil / expiresAt) has passed.
exports.expireFeatured = onSchedule("every 24 hours", async () => {
  const db = getFirestore();
  const now = Timestamp.now();

  let batch = db.batch();
  let pending = 0;
  const flush = async (force) => {
    if (pending >= 400 || (force && pending > 0)) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  };

  const listings = await db
    .collection("listings")
    .where("featuredUntil", "<", now)
    .get();
  for (const doc of listings.docs) {
    if (doc.get("isFeatured")) {
      batch.update(doc.ref, { isFeatured: false });
      pending++;
      await flush(false);
    }
  }

  const businesses = await db
    .collection("users")
    .where("featuredBusinessUntil", "<", now)
    .get();
  for (const doc of businesses.docs) {
    if (doc.get("featuredBusiness")) {
      batch.update(doc.ref, { featuredBusiness: false });
      pending++;
      await flush(false);
    }
  }

  const banners = await db
    .collection("banners")
    .where("expiresAt", "<", now)
    .get();
  for (const doc of banners.docs) {
    if (doc.get("active")) {
      batch.update(doc.ref, { active: false });
      pending++;
      await flush(false);
    }
  }

  await flush(true);
});

// When a user submits a Help request or Suggestion (a `feedback` doc), email
// it to the admin via SendGrid so it lands in the inbox automatically — no
// user mail-app step. Reply-To is set to the user so the admin can reply
// straight from their inbox.
exports.emailFeedbackToAdmin = onDocumentCreated(
  { document: "feedback/{feedbackId}", secrets: [SENDGRID_API_KEY] },
  async (event) => {
    const fb = event.data && event.data.data();
    if (!fb) return;

    const type = fb.type || "Help";
    const userEmail = fb.email || "(not provided)";
    const message = String(fb.message || "");

    sgMail.setApiKey(SENDGRID_API_KEY.value());

    try {
      await sgMail.send({
        to: SUPPORT_TO,
        from: SUPPORT_FROM,
        replyTo: fb.email || SUPPORT_TO,
        subject: `PakBazar ${type} — from ${userEmail}`,
        text:
          `New ${type} submitted on PakBazar.\n\n` +
          `From: ${userEmail}\n` +
          `User ID: ${fb.userId || "(none)"}\n\n` +
          `Message:\n${message}\n`,
      });
    } catch (err) {
      console.error("SendGrid send failed:", (err && err.message) || err);
    }
  }
);

// ---------------------------------------------------------------------------
// Escrow payments
//
// Money only ever moves inside these Cloud Functions (admin SDK), never from a
// client. Flow:
//   1. Buyer creates a `payments` doc (status 'initiated').
//   2. onPaymentCreated confirms it and moves the order to `in_escrow`. The
//      TEST provider auto-confirms here; once PayFast is configured, confirm
//      from the verified gateway webhook instead of auto-confirming.
//   3. An admin creates an `escrowActions` doc (release | refund).
//   4. onEscrowAction releases the seller payout into their wallet (and books
//      the commission) or refunds the buyer.
// Every movement is appended to the immutable `ledger` collection for audit.
// All transitions are guarded on the order status, so they are idempotent and
// safe against double-taps / retries.
// ---------------------------------------------------------------------------

// Shared: confirm a captured payment -> move the order into escrow, mark the
// listing sold, record the hold in the ledger. Idempotent (guards on order
// status). Used by the TEST provider and by the verified PayFast IPN webhook.
async function confirmPaymentIntoEscrow(db, orderId, paymentRef, provider) {
  const orderRef = db.collection("orders").doc(String(orderId));
  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      if (paymentRef) tx.update(paymentRef, { status: "order_missing" });
      return;
    }
    const order = orderSnap.data();
    if (
      order.status !== "pending_payment" &&
      order.status !== "payment_review"
    ) {
      if (paymentRef) tx.update(paymentRef, { status: "ignored" });
      return;
    }
    const listingRef = order.listingId
      ? db.collection("listings").doc(String(order.listingId))
      : null;
    const listingSnap = listingRef ? await tx.get(listingRef) : null;

    if (paymentRef) {
      tx.update(paymentRef, {
        status: "paid",
        provider: provider || "test",
        confirmedAt: Timestamp.now(),
      });
    }
    tx.update(orderRef, {
      status: "in_escrow",
      paymentId: paymentRef ? paymentRef.id : null,
      paidAt: Timestamp.now(),
    });
    if (listingSnap && listingSnap.exists) {
      tx.update(listingRef, { isSold: true });
    }
    tx.set(db.collection("ledger").doc(), {
      type: "escrow_hold",
      orderId: String(orderId),
      amount: Number(order.amount) || 0,
      buyerId: order.buyerId || "",
      sellerId: order.sellerId || "",
      createdAt: Timestamp.now(),
    });
  });
}

exports.onPaymentCreated = onDocumentCreated(
  "payments/{paymentId}",
  async (event) => {
    const pay = event.data && event.data.data();
    if (!pay || !pay.orderId) return;
    const provider = pay.provider || "test";
    const db = getFirestore();
    const payRef = event.data.ref;

    if (provider === "payfast") {
      // Initiate the hosted checkout and store the redirect URL on the payment
      // doc; the order only enters escrow once the verified PayFast IPN fires.
      try {
        const orderSnap = await db
          .collection("orders")
          .doc(pay.orderId)
          .get();
        if (
          !orderSnap.exists ||
          orderSnap.get("status") !== "pending_payment"
        ) {
          await payRef.update({ status: "ignored" });
          return;
        }
        const checkout = await initiatePayfastCheckout(
          db,
          payRef.id,
          orderSnap.data()
        );
        await payRef.update({
          status: "awaiting_gateway",
          redirectUrl: checkout.redirectUrl,
          gatewayMode: checkout.mode,
        });
      } catch (err) {
        console.error("PayFast initiate failed:", (err && err.message) || err);
        await payRef.update({
          status: "gateway_error",
          error: String((err && err.message) || err),
        });
      }
      return;
    }

    if (provider === "manual") {
      // Buyer transferred to the platform's receiving account off-app and
      // submitted proof; an admin verifies and confirms. No external gateway.
      const oRef = db.collection("orders").doc(pay.orderId);
      const oSnap = await oRef.get();
      if (!oSnap.exists || oSnap.get("status") !== "pending_payment") {
        await payRef.update({ status: "ignored" });
        return;
      }
      await payRef.update({ status: "awaiting_confirmation" });
      await oRef.update({ status: "payment_review" });
      return;
    }

    // TEST provider: capture immediately.
    await confirmPaymentIntoEscrow(db, pay.orderId, payRef, "test");
  }
);

// Admin confirms or rejects a manual payment (buyer paid the platform account
// and submitted proof). Confirm -> the order enters escrow; reject -> the
// payment is marked rejected. The admin creates a paymentActions doc.
exports.onPaymentAction = onDocumentCreated(
  "paymentActions/{actionId}",
  async (event) => {
    const act = event.data && event.data.data();
    if (!act || !act.paymentId || !act.type) return;

    const db = getFirestore();
    const actRef = event.data.ref;
    const payRef = db.collection("payments").doc(act.paymentId);
    const paySnap = await payRef.get();
    if (!paySnap.exists) {
      await actRef.update({ status: "missing" });
      return;
    }
    const pay = paySnap.data();
    if (pay.status !== "awaiting_confirmation") {
      await actRef.update({ status: "not_pending" });
      return;
    }

    if (act.type === "confirm") {
      // confirmPaymentIntoEscrow is idempotent (guards on order status).
      await confirmPaymentIntoEscrow(db, pay.orderId, payRef, "manual");
    } else if (act.type === "reject") {
      await payRef.update({ status: "rejected", rejectedAt: Timestamp.now() });
      // Return the order to payable so the buyer can retry.
      if (pay.orderId) {
        await db
          .collection("orders")
          .doc(pay.orderId)
          .update({ status: "pending_payment" })
          .catch(() => {});
      }
    } else {
      await actRef.update({ status: "unknown_type" });
      return;
    }
    await actRef.update({ status: "done", processedAt: Timestamp.now() });
  }
);

exports.onEscrowAction = onDocumentCreated(
  "escrowActions/{actionId}",
  async (event) => {
    const act = event.data && event.data.data();
    if (!act || !act.orderId || !act.type) return;

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(act.orderId);
    const actRef = event.data.ref;

    await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        tx.update(actRef, { status: "order_missing" });
        return;
      }
      const order = orderSnap.data();
      if (order.status !== "in_escrow") {
        tx.update(actRef, { status: "not_in_escrow" });
        return;
      }

      const amount = Number(order.amount) || 0;

      if (act.type === "release") {
        // Commission/payout are recomputed here (server-authoritative) rather
        // than trusting whatever the client stored on the order.
        const commission = Math.round(amount * COMMISSION_RATE * 100) / 100;
        const payout = amount - commission;
        const sellerRef = db.collection("users").doc(order.sellerId);
        const sellerSnap = await tx.get(sellerRef);
        const bal = Number(sellerSnap.get("walletBalance")) || 0;

        tx.update(sellerRef, { walletBalance: bal + payout });
        tx.update(orderRef, {
          status: "released",
          commission,
          sellerPayout: payout,
          releasedAt: Timestamp.now(),
        });
        tx.set(db.collection("ledger").doc(), {
          type: "escrow_release",
          orderId: act.orderId,
          amount: payout,
          commission,
          sellerId: order.sellerId || "",
          createdAt: Timestamp.now(),
        });
      } else if (act.type === "refund") {
        const buyerRef = db.collection("users").doc(order.buyerId);
        const buyerSnap = await tx.get(buyerRef);
        const bal = Number(buyerSnap.get("walletBalance")) || 0;

        tx.update(buyerRef, { walletBalance: bal + amount });
        tx.update(orderRef, { status: "refunded", refundedAt: Timestamp.now() });
        tx.set(db.collection("ledger").doc(), {
          type: "escrow_refund",
          orderId: act.orderId,
          amount,
          buyerId: order.buyerId || "",
          createdAt: Timestamp.now(),
        });
      } else {
        tx.update(actRef, { status: "unknown_type" });
        return;
      }

      tx.update(actRef, { status: "done", processedAt: Timestamp.now() });
    });
  }
);

// ---------------------------------------------------------------------------
// Seller payout / withdrawal
//
// A seller requests a withdrawal (withdrawals doc). onWithdrawalCreated
// reserves the funds by deducting their wallet immediately (so the same money
// can't be spent or withdrawn twice). An admin then creates a withdrawalActions
// doc: "paid" finalizes it (money sent off-platform), "rejected" refunds the
// reserved amount back to the wallet. All movement is server-side and logged.
// ---------------------------------------------------------------------------

exports.onWithdrawalCreated = onDocumentCreated(
  "withdrawals/{withdrawalId}",
  async (event) => {
    const w = event.data && event.data.data();
    if (!w || !w.userId) return;

    const db = getFirestore();
    const wRef = event.data.ref;
    const userRef = db.collection("users").doc(w.userId);
    const amount = Number(w.amount) || 0;

    await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const bal = Number(userSnap.get("walletBalance")) || 0;
      if (amount <= 0 || bal < amount) {
        tx.update(wRef, { status: "insufficient" });
        return;
      }
      // Reserve: deduct now so the balance can't be double-spent/withdrawn.
      tx.update(userRef, { walletBalance: bal - amount });
      tx.update(wRef, { status: "processing", reservedAt: Timestamp.now() });
      tx.set(userRef.collection("walletTransactions").doc(), {
        type: "debit",
        amount,
        purpose: "Withdrawal",
        createdAt: Timestamp.now(),
      });
      tx.set(db.collection("ledger").doc(), {
        type: "withdrawal_reserve",
        withdrawalId: wRef.id,
        userId: w.userId,
        amount,
        createdAt: Timestamp.now(),
      });
    });
  }
);

exports.onWithdrawalAction = onDocumentCreated(
  "withdrawalActions/{actionId}",
  async (event) => {
    const act = event.data && event.data.data();
    if (!act || !act.withdrawalId || !act.type) return;

    const db = getFirestore();
    const actRef = event.data.ref;
    const wRef = db.collection("withdrawals").doc(act.withdrawalId);

    await db.runTransaction(async (tx) => {
      const wSnap = await tx.get(wRef);
      if (!wSnap.exists) {
        tx.update(actRef, { status: "missing" });
        return;
      }
      const w = wSnap.data();
      if (w.status !== "processing") {
        tx.update(actRef, { status: "not_processing" });
        return;
      }
      const amount = Number(w.amount) || 0;

      if (act.type === "paid") {
        tx.update(wRef, { status: "paid", paidAt: Timestamp.now() });
        tx.set(db.collection("ledger").doc(), {
          type: "withdrawal_paid",
          withdrawalId: act.withdrawalId,
          userId: w.userId || "",
          amount,
          createdAt: Timestamp.now(),
        });
      } else if (act.type === "rejected") {
        // Refund the reserved amount back to the seller's wallet.
        const userRef = db.collection("users").doc(w.userId);
        const userSnap = await tx.get(userRef);
        const bal = Number(userSnap.get("walletBalance")) || 0;
        tx.update(userRef, { walletBalance: bal + amount });
        tx.update(wRef, { status: "rejected", rejectedAt: Timestamp.now() });
        tx.set(userRef.collection("walletTransactions").doc(), {
          type: "credit",
          amount,
          purpose: "Withdrawal refund",
          createdAt: Timestamp.now(),
        });
        tx.set(db.collection("ledger").doc(), {
          type: "withdrawal_refund",
          withdrawalId: act.withdrawalId,
          userId: w.userId || "",
          amount,
          createdAt: Timestamp.now(),
        });
      } else {
        tx.update(actRef, { status: "unknown_type" });
        return;
      }

      tx.update(actRef, { status: "done", processedAt: Timestamp.now() });
    });
  }
);

// ---------------------------------------------------------------------------
// PayFast (gopayfast, Pakistan) gateway — Phase 2 scaffold
//
// SCAFFOLD: the flow and signing follow PayFast Pakistan's documented hosted-
// checkout API, but the exact endpoint URLs, the IPN field names, and the IPN
// verification MUST be confirmed against YOUR merchant onboarding pack and
// tested in the sandbox before going live. Adjust the marked spots below.
//
// Activation:
//   1. Get a gopayfast merchant account (sandbox + production credentials).
//   2. firebase functions:secrets:set PAYFAST_MERCHANT_ID
//      firebase functions:secrets:set PAYFAST_SECURED_KEY
//   3. Admin Panel -> Payment a/c: set provider=payfast, mode, merchant name,
//      token/transaction URLs, and the return/IPN URL (the deployed payfastIpn
//      URL). Configure that same IPN URL in the PayFast dashboard.
//   4. Deploy:  firebase deploy --only functions
// ---------------------------------------------------------------------------

async function payfastConfig(db) {
  const snap = await db.collection("config").doc("payment").get();
  const c = snap.data() || {};
  const sandbox = (c.payfastMode || "sandbox") !== "live";
  return {
    mode: sandbox ? "sandbox" : "live",
    merchantName: c.merchantName || "PakBazar",
    // Defaults are the commonly-published gopayfast endpoints — VERIFY against
    // your onboarding pack; override via these config fields if they differ.
    tokenUrl:
      c.payfastTokenUrl ||
      (sandbox
        ? "https://ipguat.apps.net.pk/Ecommerce/api/Transaction/GetAccessToken"
        : "https://ipg1.apps.net.pk/Ecommerce/api/Transaction/GetAccessToken"),
    txnUrl:
      c.payfastTxnUrl ||
      (sandbox
        ? "https://ipguat.apps.net.pk/Ecommerce/api/Transaction/PostTransaction"
        : "https://ipg1.apps.net.pk/Ecommerce/api/Transaction/PostTransaction"),
    returnUrl: c.payfastReturnUrl || "",
  };
}

// Gets a one-time access token, then builds the signed hosted-checkout URL.
// basketId is the payment doc id so the IPN can map the callback back to it.
async function initiatePayfastCheckout(db, basketId, order) {
  const cfg = await payfastConfig(db);
  const merchantId = process.env.PAYFAST_MERCHANT_ID || "";
  const securedKey = process.env.PAYFAST_SECURED_KEY || "";
  const amount = Number(order.amount) || 0;

  const tokenRes = await fetch(cfg.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      MERCHANT_ID: merchantId,
      SECURED_KEY: securedKey,
      BASKET_ID: String(basketId),
      TXNAMT: String(amount),
    }),
  });
  const tokenJson = await tokenRes.json().catch(() => ({}));
  const token = tokenJson.ACCESS_TOKEN || tokenJson.token;
  if (!token) {
    throw new Error("No PayFast access token: " + JSON.stringify(tokenJson));
  }

  const signature = crypto
    .createHash("md5")
    .update(`${merchantId}:${cfg.merchantName}:${amount}:${basketId}`)
    .digest("hex");

  const params = new URLSearchParams({
    MERCHANT_ID: merchantId,
    MERCHANT_NAME: cfg.merchantName,
    TOKEN: token,
    PROCCODE: "00",
    TXNAMT: String(amount),
    CUSTOMER_MOBILE_NO: order.buyerPhone || "",
    CUSTOMER_EMAIL_ADDRESS: order.buyerEmail || "",
    SIGNATURE: signature,
    TXNDESC: `PakBazar order ${order.listingTitle || basketId}`,
    BASKET_ID: String(basketId),
    ORDER_DATE: new Date().toISOString().slice(0, 19).replace("T", " "),
    SUCCESS_URL: cfg.returnUrl,
    FAILURE_URL: cfg.returnUrl,
    CHECKOUT_URL: cfg.returnUrl,
  });

  // NOTE: some PayFast setups require a form POST to txnUrl rather than a GET
  // redirect. If your sandbox needs a POST, host a tiny auto-submitting form
  // page and point redirectUrl at it. Verify during sandbox testing.
  return { redirectUrl: `${cfg.txnUrl}?${params.toString()}`, mode: cfg.mode };
}

// PayFast posts the transaction result here (the IPN/ITN). Configure this
// function's URL as the IPN / CHECKOUT_URL in the PayFast dashboard.
exports.payfastIpn = onRequest(async (req, res) => {
    const body = req.body || {};
    const q = req.query || {};
    // VERIFY these field names against your onboarding pack.
    const basketId =
      body.BASKET_ID || body.basket_id || q.basket_id || q.BASKET_ID;
    const code = String(
      body.err_code || body.ERR_CODE || body.RESPONSE_CODE || ""
    );
    const success =
      code === "000" ||
      String(body.transaction_status || "").toLowerCase() === "completed";

    if (!basketId) {
      res.status(400).send("missing basket id");
      return;
    }

    // TODO: verify the IPN signature/authenticity per your PayFast pack before
    // trusting it (recompute the validation hash and compare) — do not settle
    // money on an unverified callback in production.

    const db = getFirestore();
    const payRef = db.collection("payments").doc(String(basketId));
    try {
      const paySnap = await payRef.get();
      if (!paySnap.exists) {
        res.status(404).send("unknown payment");
        return;
      }
      const orderId = paySnap.get("orderId");
      if (success) {
        await confirmPaymentIntoEscrow(db, orderId, payRef, "payfast");
      } else {
        await payRef.update({ status: "failed", gatewayCode: code });
      }
      res.status(200).send("OK");
    } catch (err) {
      console.error("PayFast IPN error:", (err && err.message) || err);
      res.status(500).send("error");
    }
  }
);
