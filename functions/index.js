"use strict";

// MarketHub Cloud Functions.
//
// notifyOnNewMessage: when a chat message is created, push an FCM notification
// to the OTHER participant's registered devices (users/{uid}/fcmTokens).

const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

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
