"use strict";

// MarketHub Cloud Functions.
//
// notifyOnNewMessage: when a chat message is created, push an FCM notification
// to the OTHER participant's registered devices (users/{uid}/fcmTokens).

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
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
