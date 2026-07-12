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
const { getAuth } = require("firebase-admin/auth");
const { defineSecret } = require("firebase-functions/params");
const sgMail = require("@sendgrid/mail");
const {
  cancelReasonText,
  cancellationEligibility,
  returnReasonText,
  returnEligibility,
} = require("./cancellation_logic");
const {
  groupItemsBySeller,
  computeSellerTotals,
  sellerOrderNumber,
} = require("./multiseller_logic");

initializeApp();

// SendGrid API key. Set it once with:
//   firebase functions:secrets:set SENDGRID_API_KEY
const SENDGRID_API_KEY = defineSecret("SENDGRID_API_KEY");

// Support inbox that receives Help/Suggestion emails. SUPPORT_FROM must be a
// verified Single Sender (or a verified domain) in your SendGrid account.
const SUPPORT_TO = "ahmednawaz993@gmail.com";
const SUPPORT_FROM = "ahmednawaz993@gmail.com";

// Free-launch period: no platform commission on any deal until this date, then
// the standard 2% resumes automatically. Keep the date in sync with
// commissionFreeUntil in the app (lib/src/commerce.dart). This is the
// server-authoritative rate used on escrow release + order normalization.
const FREE_UNTIL = Date.parse("2026-10-10T00:00:00Z");
function commissionRate() {
  return Date.now() < FREE_UNTIL ? 0 : 0.02;
}

// Make pushes alert loudly even when the app is closed: deliver at high
// priority and play the device's default notification sound. No channelId is
// set on purpose — that lets FCM use its auto-created default channel (which
// has sound); naming a channel that doesn't exist would suppress the alert on
// Android 8+. iOS plays its default sound via the apns block.
const ANDROID_ALERT = { priority: "high", notification: { sound: "default" } };
const APNS_ALERT = { payload: { aps: { sound: "default" } } };

// Numeric value of a listing's price string. Mirrors parsePrice() in the app
// (lib/src/helpers.dart): strip everything except digits and dots, then parse.
function parsePrice(price) {
  const cleaned = String(price == null ? "" : price).replace(/[^0-9.]/g, "");
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : 0;
}

// Round to 2 decimals (paisa) the same way the escrow release does.
function round2(n) {
  return Math.round(n * 100) / 100;
}

// ---------------------------------------------------------------------------
// Platform-held payment: configurable commission, payout records, audit log.
//
// Money is NEVER moved by client code. The commission rate is configurable at
// config/commission (global + per-category + per-seller override) and falls
// back to the built-in free-launch schedule. sellerPayouts/{orderId} holds one
// payout record per order (doc id == orderId, so a seller order can never be
// paid twice — the idempotency key). financialAuditLog is an append-only trail
// of every money event. See the platform-held-payment spec (sections 1-14).
//
// Wording rule: we say "held by platform / seller settlement / payout /
// payment release" — NEVER "regulated escrow" — because PakBazar does not yet
// hold a payment-provider/regulatory licence. Real provider money movement
// stays behind this trusted backend (currently wallet-settled).
// ---------------------------------------------------------------------------

const ADMIN_EMAIL = "ahmednawaz993@gmail.com";

// Resolve the effective commission for one order. Reads config/commission once
// per call. Precedence: seller override > category rate > global rate; the
// free-launch window (config.freeUntil or FREE_UNTIL) forces 0. Falls back to
// commissionRate() when the config doc is absent. Nothing is hardcoded twice —
// this is the single server-side source of truth for the rate.
async function resolveCommission(db, opts) {
  opts = opts || {};
  let cfg = null;
  try {
    const snap = await db.collection("config").doc("commission").get();
    cfg = snap.exists ? snap.data() : null;
  } catch (_) {
    cfg = null;
  }
  const freeUntil = cfg && cfg.freeUntil ? Date.parse(cfg.freeUntil) : FREE_UNTIL;
  if (Number.isFinite(freeUntil) && Date.now() < freeUntil) {
    return { rate: 0, fixedFee: 0, source: "free_launch" };
  }
  if (!cfg) return { rate: commissionRate(), fixedFee: 0, source: "default" };
  let rate = typeof cfg.globalRate === "number" ? cfg.globalRate : 0.02;
  let source = "global";
  const cats = cfg.categoryRates || {};
  if (opts.category && typeof cats[opts.category] === "number") {
    rate = cats[opts.category];
    source = "category";
  }
  const overrides = cfg.sellerOverrides || {};
  if (opts.sellerId && typeof overrides[opts.sellerId] === "number") {
    rate = overrides[opts.sellerId];
    source = "seller";
  }
  const fixedFee = typeof cfg.fixedFee === "number" ? cfg.fixedFee : 0;
  return { rate, fixedFee, source };
}

// Compute the full server-authoritative payout breakdown for an order.
// itemSubtotal = amount − deliveryFee (commission is on the product only; the
// delivery fee passes through to the seller in full). refund/adjustment reduce
// the seller-payable amount. Never trusts client-submitted totals (section 6).
async function computePayoutBreakdown(db, order, extra) {
  extra = extra || {};
  const amount = Number(order.amount) || 0;
  const deliveryFee = Number(order.deliveryFee) || 0;
  const itemSubtotal = Math.max(0, amount - deliveryFee);
  const { rate, fixedFee, source } = await resolveCommission(db, {
    category: order.category || order.listingCategory || "",
    sellerId: order.sellerId || "",
  });
  const platformCommissionAmount = round2(
    itemSubtotal * rate + (rate > 0 ? fixedFee : 0)
  );
  const buyerDiscount = Number(order.discount) || 0;
  const refundAmount =
    Number(extra.refundAmount != null ? extra.refundAmount : order.refundAmount) || 0;
  const adjustmentAmount =
    Number(extra.adjustmentAmount != null ? extra.adjustmentAmount : order.adjustmentAmount) || 0;
  const sellerPayableAmount = round2(
    amount - platformCommissionAmount - refundAmount - adjustmentAmount
  );
  return {
    itemSubtotal,
    deliveryFee,
    buyerDiscount,
    platformCommissionRate: rate,
    platformCommissionAmount,
    fixedFee: rate > 0 ? fixedFee : 0,
    refundAmount,
    adjustmentAmount,
    sellerPayableAmount: Math.max(0, sellerPayableAmount),
    currency: "PKR",
    calculationVersion: 2,
    commissionSource: source,
  };
}

// Append an immutable financial audit record (section 12). Best-effort: an
// audit-write failure must never break the money operation that triggered it.
async function writeAudit(db, rec) {
  try {
    await db.collection("financialAuditLog").add({
      action: rec.action || "",
      entityType: rec.entityType || "order",
      entityId: String(rec.entityId || ""),
      actorId: rec.actorId || "system",
      actorRole: rec.actorRole || "system",
      previousStatus: rec.previousStatus || "",
      newStatus: rec.newStatus || "",
      amount: Number(rec.amount) || 0,
      reason: rec.reason || "",
      metadata: rec.metadata || {},
      createdAt: Timestamp.now(),
    });
  } catch (e) {
    console.error("writeAudit failed", rec.action, e);
  }
}

// Create/refresh the payout record for one seller order. Doc id == orderId so a
// seller order can never spawn two payout records (idempotency key, section 8).
// Never overwrites a record that has already been released.
async function upsertSellerPayout(db, orderId, order, patch) {
  patch = patch || {};
  const ref = db.collection("sellerPayouts").doc(String(orderId));
  const breakdown = await computePayoutBreakdown(db, order, patch);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists ? snap.data() : null;
    if (existing && existing.releaseStatus === "released") return; // frozen
    const base = existing
      ? {}
      : {
          sellerId: order.sellerId || "",
          orderId: String(orderId),
          parentOrderId: order.parentOrderId || String(orderId),
          payoutAccountId: order.payoutAccountId || "",
          createdAt: Timestamp.now(),
        };
    const keep = (k, d) => (patch[k] != null ? patch[k] : existing ? existing[k] : d);
    tx.set(
      ref,
      Object.assign(base, breakdown, {
        paymentStatus: keep("paymentStatus", "held_by_platform"),
        releaseStatus: keep("releaseStatus", "not_eligible"),
        buyerConfirmedAt: order.buyerConfirmedAt || (existing && existing.buyerConfirmedAt) || null,
        eligibleForReleaseAt: keep("eligibleForReleaseAt", null),
        releasedAmount: keep("releasedAmount", 0),
        transactionReference: keep("transactionReference", ""),
        holdReason: keep("holdReason", ""),
        rejectionReason: keep("rejectionReason", ""),
        failureReason: keep("failureReason", ""),
        releasedAt: keep("releasedAt", null),
        releasedBy: keep("releasedBy", null),
        updatedAt: Timestamp.now(),
      }),
      { merge: true }
    );
  });
  return breakdown;
}

// Best-effort push to the super admin (resolved by email → uid). Used to alert
// the admin that a payout is eligible / a dispute was opened, etc. (section 13).
async function notifyAdmins(db, notification, data) {
  try {
    const u = await getAuth().getUserByEmail(ADMIN_EMAIL);
    if (u && u.uid) await pushToUser(db, u.uid, notification, data);
  } catch (e) {
    console.error("notifyAdmins failed", e);
  }
}

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
      android: ANDROID_ALERT,
      apns: APNS_ALERT,
      webpush: {
        notification: { icon: "/icons/Icon-192.png" },
        fcmOptions: { link: "/" },
      },
    });

    await pruneInvalidTokens(db, recipientId, tokens, response);
  }
);

// notifyOnNewSupportMessage: when a USER posts a message in a support ticket,
// push an FCM alert to every Customer Care agent's registered device (the
// shared `supportTokens` collection, kept in sync by syncSupportPushToken in
// the app). Messages from support ('support' role) are ignored here — the user
// is notified of those by the reply-notification the app already writes.
exports.notifyOnNewSupportMessage = onDocumentCreated(
  "supportTickets/{ticketId}/messages/{messageId}",
  async (event) => {
    const msg = event.data && event.data.data();
    if (!msg) return;
    if (String(msg.senderRole || "") !== "user") return;

    const db = getFirestore();
    const ticketId = event.params.ticketId;

    const ticketSnap = await db
      .collection("supportTickets")
      .doc(ticketId)
      .get();
    const ticket = ticketSnap.data() || {};
    const who = String(ticket.userName || "").trim();
    const title = who ? `New support message from ${who}` : "New support message";
    const body = String(
      msg.text || (msg.type === "voice" ? "🎤 Voice message" : "")
    ).slice(0, 140);

    const tokensSnap = await db.collection("supportTokens").get();
    const tokens = tokensSnap.docs.map((d) => d.id);
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { type: "support", ticketId },
      android: ANDROID_ALERT,
      apns: APNS_ALERT,
      webpush: {
        notification: { icon: "/icons/Icon-192.png" },
        fcmOptions: { link: "/" },
      },
    });

    // Prune any support tokens that are no longer valid.
    const removals = [];
    response.responses.forEach((r, i) => {
      if (!r.success) {
        const code = (r.error && r.error.code) || "";
        if (
          code.includes("registration-token-not-registered") ||
          code.includes("invalid-registration-token") ||
          code.includes("invalid-argument")
        ) {
          removals.push(db.collection("supportTokens").doc(tokens[i]).delete());
        }
      }
    });
    await Promise.all(removals);
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
// ---------------------------------------------------------------------------
// New-listing notifications: opt-in, interest-matched, deduped, rate-limited.
// Users only hear about a listing once it is APPROVED and in stock, and only
// when it matches a saved search, their saved interests, or a seller they
// follow — never a blanket blast.
// ---------------------------------------------------------------------------

// Max immediate new-listing pushes per user per rolling 24h.
const NEW_LISTING_DAILY_CAP = 5;

// First human-readable reason a listing matches a user's interest prefs, or
// null. Price range is a filter (must pass) rather than a match reason itself.
function listingMatchesInterests(listing, prefs) {
  if (!prefs) return null;
  const price = parsePrice(listing.price);
  const min = Number(prefs.priceMin) || 0;
  const max = Number(prefs.priceMax) || 0;
  if ((min > 0 && price < min) || (max > 0 && price > max)) return null;

  const cat = String(listing.category || "");
  const city = String(listing.city || "");
  const title = String(listing.title || "").toLowerCase();
  const cats = Array.isArray(prefs.categories) ? prefs.categories : [];
  const cities = Array.isArray(prefs.cities) ? prefs.cities : [];
  const kws = Array.isArray(prefs.keywords) ? prefs.keywords : [];
  const sellers = Array.isArray(prefs.favoriteSellers)
    ? prefs.favoriteSellers
    : [];

  if (cats.includes(cat)) return `new in ${cat}`;
  if (listing.userId && sellers.includes(listing.userId)) {
    return "a seller you follow";
  }
  for (const kw of kws) {
    if (kw && title.includes(String(kw).toLowerCase())) return `keyword "${kw}"`;
  }
  if (cities.includes(city)) return `new in ${city}`;
  return null;
}

function titleForListing(listing, info) {
  if (info.type === "savedSearch") return `New ad matches ${info.reason}`;
  if (info.type === "follow") return `New ad from ${info.reason}`;
  return `New listing: ${info.reason}`;
}

// Delivers one new-listing alert to a user, honouring their notification prefs,
// idempotency (one alert per user+listing, deterministic id) and a rolling
// daily rate limit. Writes a per-user listingAlerts/{listingId} analytics
// record (section I fields: userId, listingId, notificationType, matchReason,
// sentAt, deliveryStatus).
async function deliverListingAlert(db, uid, listing, listingId, info) {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) return;
  const prefs = (userSnap.data() || {}).notifPrefs || {};

  if (prefs.newListing === false) return; // global opt-out
  if ((prefs.mode || "all") !== "all") return; // daily/weekly/off => no push now

  const alertRef = db
    .collection("users").doc(uid)
    .collection("listingAlerts").doc(String(listingId));
  if ((await alertRef.get()).exists) return; // idempotent

  const since = Timestamp.fromMillis(Date.now() - 24 * 3600 * 1000);
  const recent = await db
    .collection("users").doc(uid)
    .collection("listingAlerts")
    .where("sentAt", ">=", since)
    .get();
  const record = {
    userId: uid,
    listingId: String(listingId),
    notificationType: info.type,
    matchReason: info.reason,
    sentAt: Timestamp.now(),
  };
  if (recent.size >= NEW_LISTING_DAILY_CAP) {
    await alertRef.set({ ...record, deliveryStatus: "rate_limited" });
    return;
  }
  await alertRef.set({ ...record, deliveryStatus: "sent" });

  const title = titleForListing(listing, info);
  const body = `${listing.title} — Rs ${listing.price}`;
  await recordNotification(db, uid, title, body, info.type, String(listingId));

  if (prefs.push === false) return; // in-app inbox only
  const tokensSnap = await db
    .collection("users").doc(uid).collection("fcmTokens").get();
  const tokens = tokensSnap.docs.map((d) => d.id);
  if (tokens.length === 0) return;
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { type: info.type, listingId: String(listingId) },
    android: ANDROID_ALERT,
    apns: APNS_ALERT,
    webpush: {
      notification: { icon: "/icons/Icon-192.png" },
      fcmOptions: { link: "/" },
    },
  });
  await pruneInvalidTokens(db, uid, tokens, response);
}

// Collects recipients (saved-search matches, opted-in interest matches, and the
// poster's followers), dedupes, and delivers — only for approved, in-stock ads.
async function dispatchNewListing(db, listing, listingId) {
  const status = String(listing.approvalStatus || "");
  if (status === "pending" || status === "rejected") return; // not public yet
  if (listing.status && listing.status !== "in_stock") return; // not buyable

  const recipients = new Map(); // uid -> { reason, type }

  const searches = await db.collectionGroup("savedSearches").get();
  searches.forEach((doc) => {
    const userDoc = doc.ref.parent.parent;
    if (!userDoc) return;
    const uid = userDoc.id;
    if (uid === listing.userId || recipients.has(uid)) return;
    if (matchesSavedSearch(listing, doc.data())) {
      recipients.set(uid, {
        reason: `your saved search "${doc.data().label || "search"}"`,
        type: "savedSearch",
      });
    }
  });

  const prefUsers = await db
    .collection("users")
    .where("notifPrefs.newListing", "==", true)
    .get();
  prefUsers.forEach((u) => {
    const uid = u.id;
    if (uid === listing.userId || recipients.has(uid)) return;
    const reason = listingMatchesInterests(listing, (u.data() || {}).notifPrefs);
    if (reason) recipients.set(uid, { reason, type: "newListing" });
  });

  for (const [uid, info] of recipients) {
    await deliverListingAlert(db, uid, listing, listingId, info);
  }

  if (listing.userId) {
    const sellerName = listing.sellerName || "a seller";
    const followersSnap = await db
      .collection("users").doc(listing.userId)
      .collection("followers").get();
    for (const f of followersSnap.docs) {
      const uid = f.id;
      if (uid === listing.userId || recipients.has(uid)) continue;
      await deliverListingAlert(db, uid, listing, listingId, {
        reason: `${sellerName} you follow`,
        type: "follow",
      });
    }
  }
}

// A listing created already-approved (demo/admin auto-approve) is public
// immediately. The normal pending->approved path is handled in the update
// trigger (notifyOnPriceDrop) to avoid a second per-update function.
exports.notifyOnNewListing = onDocumentCreated(
  "listings/{listingId}",
  async (event) => {
    const listing = event.data && event.data.data();
    if (!listing) return;
    await dispatchNewListing(getFirestore(), listing, event.params.listingId);
  }
);

// Notify everyone who saved (favorited) a listing when its price is reduced.
exports.notifyOnPriceDrop = onDocumentUpdated(
  "listings/{listingId}",
  async (event) => {
    const before = event.data && event.data.before.data();
    const after = event.data && event.data.after.data();
    if (!before || !after) return;

    // New-listing alerts fire when a listing becomes public — i.e. its
    // approvalStatus transitions to 'approved' (normal path: user posts pending,
    // an admin approves). Handled here to avoid a second per-update trigger.
    if (
      before.approvalStatus !== "approved" &&
      after.approvalStatus === "approved"
    ) {
      await dispatchNewListing(getFirestore(), after, event.params.listingId);
    }

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
// Merchandise subtotal at/above which delivery is free. Mirror of
// freeDeliveryThreshold in lib/src/commerce.dart — keep the two in sync.
const FREE_DELIVERY_THRESHOLD = 3000;

// Allocates the next human-readable order sequence (PB-{n}) from a counter doc,
// atomically. Starts at 1001.
async function nextOrderNumber(db) {
  const ref = db.collection("counters").doc("orderNumber");
  return db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const cur = s.exists ? Number(s.data().value) || 1000 : 1000;
    const next = cur + 1;
    tx.set(ref, { value: next, updatedAt: Timestamp.now() }, { merge: true });
    return next;
  });
}

// ---------------------------------------------------------------------------
// Multi-seller checkout fan-out (Phase 3)
//
// The buyer writes ONE masterOrders/{id} "checkout intent" (cart items +
// address snapshot + payment method). This trigger validates each listing
// against trusted server data, groups the items by seller, and creates one
// orders/{orderId} sub-order per seller — reusing the existing order collection
// so all fulfillment / cancellation / escrow / payout logic applies unchanged.
// Each sub-order carries masterOrderId + a unique orderNumber (PB-1001-S1) and
// the SAME immutable delivery-address snapshot. Sellers only ever read their
// own sub-order (orders rules scope by sellerId), so one seller can't see
// another's items.
// ---------------------------------------------------------------------------
exports.onMasterOrderCreated = onDocumentCreated(
  "masterOrders/{masterId}",
  async (event) => {
    const master = event.data && event.data.data();
    if (!master) return;
    // Only process a fresh intent once. The top-level check is a cheap early-out;
    // the authoritative guard is the transactional claim below.
    if (master.status !== "pending" || master.sellerOrderIds) return;

    const db = getFirestore();
    const masterRef = event.data.ref;
    const masterId = event.params.masterId;

    // Atomically CLAIM the intent before any sub-order is written. A duplicate
    // event delivery (Firestore triggers are at-least-once) or a retry would
    // otherwise both pass the top-level guard and each create a full set of
    // sub-orders. Flipping status to "processing" in a transaction lets exactly
    // one invocation proceed; the rest bail here.
    try {
      const claimed = await db.runTransaction(async (tx) => {
        const cur = await tx.get(masterRef);
        if (!cur.exists) return false;
        if (cur.get("status") !== "pending" || cur.get("sellerOrderIds")) {
          return false;
        }
        tx.update(masterRef, { status: "processing" });
        return true;
      });
      if (!claimed) return;
    } catch (e) {
      console.error("master claim failed:", (e && e.message) || e);
      return;
    }

    const items = Array.isArray(master.items) ? master.items : [];

    if (items.length === 0) {
      await masterRef.set(
        { status: "failed", failReason: "empty_cart" },
        { merge: true }
      );
      return;
    }

    const orderNo = await nextOrderNumber(db);
    const masterNumber = `PB-${orderNo}`;
    const isCod = master.paymentMethod === "cod";
    const rate = commissionRate();
    const address = master.deliveryAddress || {};
    const buyerName =
      master.buyerName || address.fullName || "A buyer";
    const buyerPhone = master.buyerPhone || address.phone || "";

    const groups = groupItemsBySeller(items);
    const sellerOrderIds = [];
    let sIndex = 0;

    for (const g of groups) {
      // Re-validate each listing against trusted current data (existence,
      // availability, current price). Skip anything no longer buyable.
      const lines = [];
      const lineItems = [];
      for (const it of g.items) {
        const ls = await db.collection("listings").doc(it.listingId).get();
        if (!ls.exists) continue;
        const l = ls.data();
        const status = l.status || (l.isSold ? "sold" : "in_stock");
        if (status !== "in_stock") continue;
        const unitPrice = parsePrice(l.price);
        if (unitPrice <= 0) continue;
        const qty = Math.max(1, Number(it.quantity) || 1);
        lines.push({
          unitPrice,
          quantity: qty,
          deliveryAvailable: l.deliveryAvailable === true,
          deliveryFee: parsePrice(l.deliveryFee),
        });
        lineItems.push({
          listingId: it.listingId,
          title: l.title || "",
          image: (l.images && l.images[0]) || l.imageUrl || "",
          unitPrice,
          quantity: qty,
          lineTotal: round2(unitPrice * qty),
        });
      }
      if (lineItems.length === 0) continue;

      sIndex++;
      const totals = computeSellerTotals(lines, {
        isCod,
        rate,
        freeThreshold: FREE_DELIVERY_THRESHOLD,
      });
      const orderNumber = sellerOrderNumber(masterNumber, sIndex);
      const orderRef = db.collection("orders").doc();
      const unitCount = lineItems.reduce((a, i) => a + i.quantity, 0);
      await orderRef.set({
        masterOrderId: masterId,
        orderNumber,
        sellerId: g.sellerId,
        sellerName: g.sellerName || "",
        buyerId: master.buyerId,
        buyerName,
        buyerPhone,
        items: lineItems,
        itemCount: unitCount,
        listingTitle:
          lineItems.length === 1
            ? lineItems[0].title
            : `${lineItems.length} items`,
        listingImage: lineItems[0].image,
        itemSubtotal: totals.itemSubtotal,
        amount: totals.amount,
        deliveryFee: totals.deliveryFee,
        discount: 0,
        qualifiesForFreeDelivery: totals.qualifiesForFreeDelivery,
        freeDeliveryThreshold: FREE_DELIVERY_THRESHOLD,
        commission: totals.commission,
        sellerPayout: totals.sellerPayout,
        deliveryAddress: address,
        paymentMethod: isCod ? "cod" : "escrow",
        notes: master.notes || "",
        status: isCod ? "cod_pending" : "pending_payment",
        orderStatus: "pending",
        paymentStatus: isCod ? "unpaid" : "payment_pending",
        createdAt: Timestamp.now(),
      });
      sellerOrderIds.push(orderRef.id);

      // Best-effort: a notification failure must not abort the fan-out and
      // orphan the sub-orders already written for other sellers.
      try {
        await pushToUser(
          db,
          g.sellerId,
          {
            title: "New order received",
            body: `New order ${orderNumber} for Rs ${totals.amount}. Review the buyer's delivery details and accept when ready.`,
          },
          { type: "order", orderId: orderRef.id }
        );
      } catch (e) {
        console.error("seller notify failed:", (e && e.message) || e);
      }
      await writeAudit(db, {
        action: "order_placed",
        entityType: "order",
        entityId: orderRef.id,
        actorId: master.buyerId || "",
        actorRole: "buyer",
        newStatus: "pending",
        amount: totals.amount,
        reason: "",
        metadata: { masterOrderId: masterId, orderNumber },
      });
    }

    if (sellerOrderIds.length === 0) {
      await masterRef.set(
        { status: "failed", failReason: "no_items_available", orderNumber: masterNumber },
        { merge: true }
      );
      if (master.buyerId) {
        await pushToUser(
          db,
          master.buyerId,
          {
            title: "Order could not be placed",
            body: "The items in your cart are no longer available.",
          },
          { type: "order", orderId: masterId }
        );
      }
      return;
    }

    await masterRef.set(
      {
        orderNumber: masterNumber,
        sellerOrderIds,
        sellerCount: sellerOrderIds.length,
        status: "placed",
        placedAt: Timestamp.now(),
      },
      { merge: true }
    );
    if (master.buyerId) {
      await pushToUser(
        db,
        master.buyerId,
        {
          title: "Order placed",
          body: `Your order ${masterNumber} was submitted to ${sellerOrderIds.length} seller(s).`,
        },
        { type: "order", orderId: masterId }
      );
    }
  }
);

exports.notifyOnNewOrder = onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const order = snap.data();
    if (!order) return;

    // Multi-seller sub-orders are created by onMasterOrderCreated (admin SDK)
    // with all money fields + status already set authoritatively, and it sends
    // the seller notification itself. Skip them here so the single-listing
    // normalizer never touches them and the seller isn't notified twice.
    if (order.masterOrderId) return;

    const db = getFirestore();

    // Seed the separate order-progress and payment-status fields (section 2) if
    // the client didn't set them. Order progress and money status are tracked in
    // DIFFERENT fields: a COD order is unpaid but processing; a paid escrow order
    // is held_by_platform while it ships. paymentStatus is Cloud-Function-owned
    // (clients can't write it — enforced by the Firestore rules).
    if (order.paymentStatus == null || order.orderStatus == null) {
      const isCodInit = order.status === "cod_pending";
      await snap.ref.set(
        {
          orderStatus: order.orderStatus || "pending",
          paymentStatus:
            order.paymentStatus || (isCodInit ? "unpaid" : "payment_pending"),
        },
        { merge: true }
      );
    }

    // Normalize money fields against the authoritative listing. The buyer
    // creates the order client-side, so without this they could set their own
    // amount/sellerPayout and place a COD (or direct-buy) order for Rs 1 on an
    // expensive item. Recompute amount/commission/sellerPayout/sellerId from
    // the listing the order points at, and notify with the corrected figure.
    // Negotiated orders (fromOffer) keep their agreed price — that amount is
    // protected by the offers rules.
    let amount = order.amount;
    let sellerId = order.sellerId;
    const payable =
      order.status === "cod_pending" || order.status === "pending_payment";
    // A payable, non-negotiated order with no listing can't be price-validated
    // against trusted data, so a client-set amount could stand. Void it rather
    // than trust it (legit single orders always carry a listingId).
    if (order.fromOffer !== true && payable && !order.listingId) {
      await snap.ref.set(
        { status: "cancelled", voidReason: "invalid_order" },
        { merge: true }
      );
      return;
    }
    if (order.fromOffer !== true && payable && order.listingId) {
      const listingSnap = await db
        .collection("listings")
        .doc(order.listingId)
        .get();

      // The ad is gone — void rather than leave a buyer-controlled amount
      // standing, and skip the "new order" notification.
      if (!listingSnap.exists) {
        await snap.ref.set(
          { status: "cancelled", voidReason: "listing_unavailable" },
          { merge: true }
        );
        return;
      }

      const listing = listingSnap.data();
      const itemPrice = parsePrice(listing.price);
      // Delivery fee is added to the buyer total but excluded from commission,
      // so the seller keeps it in full. Only applies when delivery is offered.
      // Free delivery: a merchandise subtotal >= FREE_DELIVERY_THRESHOLD ships
      // free regardless of the seller's per-listing fee. Server-authoritative,
      // so a tampered client cannot avoid (or fake) it.
      const qualifiesFree = itemPrice >= FREE_DELIVERY_THRESHOLD;
      const baseDelivery =
        listing.deliveryAvailable === true
          ? parsePrice(listing.deliveryFee)
          : 0;
      const delivery = qualifiesFree ? 0 : baseDelivery;
      amount = itemPrice + delivery;
      const isCod = order.status === "cod_pending";
      const commission = isCod ? 0 : round2(itemPrice * commissionRate());
      const sellerPayout = round2(amount - commission);
      sellerId = listing.userId || order.sellerId || "";

      if (
        order.amount !== amount ||
        order.deliveryFee !== delivery ||
        order.commission !== commission ||
        order.sellerPayout !== sellerPayout ||
        order.sellerId !== sellerId ||
        order.itemSubtotal !== itemPrice ||
        order.qualifiesForFreeDelivery !== qualifiesFree
      ) {
        await snap.ref.set(
          {
            amount,
            deliveryFee: delivery,
            commission,
            sellerPayout,
            sellerId,
            itemSubtotal: itemPrice,
            qualifiesForFreeDelivery: qualifiesFree,
            freeDeliveryThreshold: FREE_DELIVERY_THRESHOLD,
          },
          { merge: true }
        );
      }
    }

    if (!sellerId) return;

    const body =
      `${order.buyerName || "A buyer"} ordered ` +
      `"${order.listingTitle}" for Rs ${amount}`;
    await recordNotification(
      db,
      sellerId,
      "New order received",
      body,
      "order",
      event.params.orderId
    );

    const tokensSnap = await db
      .collection("users")
      .doc(sellerId)
      .collection("fcmTokens")
      .get();
    const tokens = tokensSnap.docs.map((d) => d.id);
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title: "New order received", body },
      data: { type: "order", orderId: event.params.orderId },
      android: ANDROID_ALERT,
      apns: APNS_ALERT,
      webpush: {
        notification: { icon: "/icons/Icon-192.png" },
        fcmOptions: { link: "/" },
      },
    });

    await pruneInvalidTokens(db, sellerId, tokens, response);
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
    android: ANDROID_ALERT,
    apns: APNS_ALERT,
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
  // Clamp the client-supplied benefit window to a sane range so a tiny payment
  // can never buy an absurdly long feature (defence in depth; the price itself
  // is still debited from the buyer's own wallet).
  const days = Math.min(Math.max(1, Number(p.days) || 7), 365);
  const until = Timestamp.fromMillis(Date.now() + days * 86400000);

  try {
    await db.runTransaction(async (tx) => {
      // Idempotency: a redelivered/duplicate purchase event must not debit the
      // wallet twice. Purchases start unset/pending; anything already resolved
      // has run.
      const purchaseSnap = await tx.get(purchaseRef);
      const pstatus = purchaseSnap.get("status");
      if (pstatus && pstatus !== "pending") return;
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

// Email the support team when a new Customer Care ticket is opened. Recipients
// are the super admin plus every active staff member granted the 'support'
// permission (staff/{lowercased-email} with permissions.support == true).
// Like emailFeedbackToAdmin, this needs a real SENDGRID_API_KEY + verified
// sender to actually deliver.
exports.emailStaffOnNewTicket = onDocumentCreated(
  { document: "supportTickets/{ticketId}", secrets: [SENDGRID_API_KEY] },
  async (event) => {
    const t = event.data && event.data.data();
    if (!t) return;

    const db = getFirestore();
    // De-duped recipient list: super admin + active 'support' staff.
    const recipients = new Set([SUPPORT_TO]);
    try {
      const staffSnap = await db.collection("staff").get();
      staffSnap.forEach((doc) => {
        const s = doc.data() || {};
        const active = s.active !== false;
        const canSupport = !!(s.permissions && s.permissions.support === true);
        const email = (s.email || doc.id || "").trim();
        if (active && canSupport && email) recipients.add(email);
      });
    } catch (err) {
      console.error("staff lookup failed:", (err && err.message) || err);
    }

    const subject =
      `New Customer Care ticket — ${t.subject || "(no subject)"}`;
    const body =
      "A new support ticket was opened on PakBazar.\n\n" +
      `Subject: ${t.subject || "(none)"}\n` +
      `Category: ${t.category || "(none)"}\n` +
      `From: ${t.userEmail || "(not provided)"}\n` +
      `User ID: ${t.userId || "(none)"}\n` +
      `Ticket ID: ${event.params.ticketId}\n\n` +
      `Message:\n${String(t.lastMessage || "")}\n\n` +
      "Target resolution: within 24 hours.\n" +
      "Open Admin Panel → Customer Care to reply.";

    sgMail.setApiKey(SENDGRID_API_KEY.value());
    try {
      await sgMail.send({
        to: Array.from(recipients),
        from: SUPPORT_FROM,
        replyTo: t.userEmail || SUPPORT_TO,
        subject,
        text: body,
      });
    } catch (err) {
      console.error(
        "SendGrid ticket email failed:",
        (err && err.message) || err
      );
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
async function confirmPaymentIntoEscrow(db, orderId, paymentRef, provider, opts) {
  opts = opts || {};
  const orderRef = db.collection("orders").doc(String(orderId));
  let held = null; // set to the order data when the payment is actually held
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
    if (paymentRef) {
      tx.update(paymentRef, {
        status: "paid",
        provider: provider || "test",
        confirmedAt: Timestamp.now(),
      });
    }
    // The money is now received AND held by the platform. Order progress stays
    // "pending" (awaiting the seller to accept & ship); only the payment side
    // advances — the two are deliberately separate fields (section 2).
    tx.update(orderRef, {
      status: "in_escrow",
      paymentStatus: "held_by_platform",
      orderStatus: order.orderStatus || "pending",
      providerTransactionId:
        order.providerTransactionId ||
        (paymentRef ? paymentRef.id : opts.paymentId || ""),
      paymentProvider: provider || "test",
      paymentId: paymentRef ? paymentRef.id : opts.paymentId || null,
      paidToPlatformAt: Timestamp.now(),
      paidAt: Timestamp.now(),
    });
    // Inventory is seller-controlled: paying for an order no longer
    // auto-marks the listing sold (the seller sets status in My Ads).
    tx.set(db.collection("ledger").doc(), {
      type: "escrow_hold",
      orderId: String(orderId),
      amount: Number(order.amount) || 0,
      buyerId: order.buyerId || "",
      sellerId: order.sellerId || "",
      createdAt: Timestamp.now(),
    });
    held = order;
  });

  // Post-transaction side effects (audit + notifications). Only when the hold
  // actually happened — never on an ignored/duplicate confirmation.
  if (!held) return;
  await writeAudit(db, {
    action: "payment_held",
    entityType: "order",
    entityId: String(orderId),
    actorId: held.buyerId || "",
    actorRole: "buyer",
    previousStatus: "pending_payment",
    newStatus: "held_by_platform",
    amount: Number(held.amount) || 0,
    metadata: { provider: provider || "test" },
  });
  if (held.buyerId && !opts.suppressBuyerNotify) {
    await pushToUser(
      db,
      held.buyerId,
      {
        title: "Payment received by PakBazar",
        body: "The seller will be paid after successful delivery confirmation.",
      },
      { type: "order", orderId: String(orderId) }
    );
  }
  if (held.sellerId) {
    await pushToUser(
      db,
      held.sellerId,
      {
        title: "Payment secured by PakBazar",
        body: "Please process and ship the order.",
      },
      { type: "order", orderId: String(orderId) }
    );
  }
}

// Multi-seller: the buyer makes ONE payment for the whole master order; this
// fans the confirmed hold out to every sub-order so each seller's share is
// escrowed independently (each sub-order already carries its own amount /
// commission / payout, so allocation is automatic). Idempotent — each
// confirmPaymentIntoEscrow call guards on its own order status. The buyer gets
// a single summary notification instead of one per seller.
async function confirmMasterPaymentIntoEscrow(db, masterId, paymentRef, provider) {
  const subs = await db
    .collection("orders")
    .where("masterOrderId", "==", String(masterId))
    .get();
  const payId = paymentRef ? paymentRef.id : null;
  let heldCount = 0;
  let buyerId = "";
  let masterNumber = "";
  for (const doc of subs.docs) {
    const st = doc.get("status");
    buyerId = buyerId || doc.get("buyerId") || "";
    const on = doc.get("orderNumber") || "";
    masterNumber =
      masterNumber || (on ? String(on).replace(/-S\d+$/, "") : "");
    if (st === "pending_payment" || st === "payment_review") {
      await confirmPaymentIntoEscrow(db, doc.id, null, provider, {
        paymentId: payId,
        suppressBuyerNotify: true,
      });
      heldCount++;
    }
  }
  if (paymentRef) {
    await paymentRef.update({
      status: heldCount > 0 ? "paid" : "ignored",
      provider: provider || "manual",
      confirmedAt: Timestamp.now(),
    });
  }
  await db
    .collection("masterOrders")
    .doc(String(masterId))
    .set(
      {
        paymentStatus: heldCount > 0 ? "held" : "unknown",
        paidAt: Timestamp.now(),
      },
      { merge: true }
    )
    .catch(() => {});
  if (heldCount > 0 && buyerId) {
    await pushToUser(
      db,
      buyerId,
      {
        title: "Payment received by PakBazar",
        body: `Your payment for ${
          masterNumber || "your order"
        } is held securely. Each seller is paid after you confirm delivery of their package.`,
      },
      { type: "order", orderId: String(masterId) }
    );
  }
}

exports.onPaymentCreated = onDocumentCreated(
  "payments/{paymentId}",
  async (event) => {
    const pay = event.data && event.data.data();
    if (!pay || (!pay.orderId && !pay.masterOrderId)) return;
    // SECURITY: never default to a self-capturing provider. A missing provider
    // is treated as a manual bank transfer that still requires an admin to
    // confirm the money was actually received before the order enters escrow.
    const provider = pay.provider || "manual";
    const db = getFirestore();
    const payRef = event.data.ref;

    // Multi-seller: one payment for a whole master order (no single orderId).
    // Manual proof waits for admin confirmation; PayFast is single-order only.
    if (pay.masterOrderId) {
      const mRef = db.collection("masterOrders").doc(pay.masterOrderId);
      const mSnap = await mRef.get();
      if (!mSnap.exists || mSnap.get("status") !== "placed") {
        await payRef.update({ status: "ignored" });
        return;
      }
      if (provider === "manual") {
        await payRef.update({ status: "awaiting_confirmation" });
        // Reflect "under review" on each sub-order so the buyer sees progress.
        const subs = await db
          .collection("orders")
          .where("masterOrderId", "==", pay.masterOrderId)
          .get();
        const batch = db.batch();
        subs.forEach((d) => {
          if (d.get("status") === "pending_payment") {
            batch.update(d.ref, { status: "payment_review" });
          }
        });
        await batch.commit();
        await mRef.set({ paymentStatus: "review" }, { merge: true });
        return;
      }
      // No other provider is valid for a master payment. The escrow hold is
      // only ever fanned out from an admin-confirmed manual payment
      // (onPaymentAction -> confirmMasterPaymentIntoEscrow); a client can never
      // self-capture with no money received.
      await payRef.update({ status: "invalid_provider" });
      return;
    }

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

    // SECURITY: only manual (admin-confirmed) and payfast (gateway-verified,
    // once its IPN signature check is live) may move an order into escrow. Any
    // other/unknown provider is rejected outright — a client must never be able
    // to self-capture a payment with no money received.
    await payRef.update({ status: "invalid_provider" });
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
      // Both confirm paths are idempotent (guard on each order's status).
      if (pay.masterOrderId) {
        await confirmMasterPaymentIntoEscrow(
          db,
          pay.masterOrderId,
          payRef,
          "manual"
        );
      } else {
        await confirmPaymentIntoEscrow(db, pay.orderId, payRef, "manual");
      }
    } else if (act.type === "reject") {
      await payRef.update({ status: "rejected", rejectedAt: Timestamp.now() });
      // Return the order(s) to payable so the buyer can retry.
      if (pay.masterOrderId) {
        const subs = await db
          .collection("orders")
          .where("masterOrderId", "==", pay.masterOrderId)
          .get();
        const batch = db.batch();
        subs.forEach((d) => {
          if (d.get("status") === "payment_review") {
            batch.update(d.ref, { status: "pending_payment" });
          }
        });
        await batch.commit();
        await db
          .collection("masterOrders")
          .doc(pay.masterOrderId)
          .set({ paymentStatus: "unpaid" }, { merge: true })
          .catch(() => {});
      } else if (pay.orderId) {
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
    const payoutRef = db.collection("sellerPayouts").doc(String(act.orderId));
    const actRef = event.data.ref;
    const adminId = act.by || "admin";

    // Payout queue management (no money movement): an admin can HOLD a payout
    // (park it with a reason) or REJECT it (won't be paid) without touching the
    // held funds. These update only the payout record + audit trail.
    if (act.type === "hold" || act.type === "reject") {
      const oSnap = await orderRef.get();
      const order = oSnap.exists ? oSnap.data() : {};
      await upsertSellerPayout(db, act.orderId, order, {
        releaseStatus: act.type === "hold" ? "on_hold" : "rejected",
        holdReason: act.type === "hold" ? act.reason || "" : "",
        rejectionReason: act.type === "reject" ? act.reason || "" : "",
      });
      await writeAudit(db, {
        action: act.type === "hold" ? "payout_held" : "payout_rejected",
        entityType: "payout",
        entityId: String(act.orderId),
        actorId: adminId,
        actorRole: "admin",
        newStatus: act.type === "hold" ? "on_hold" : "rejected",
        amount: Number(order.sellerPayableAmount || order.sellerPayout) || 0,
        reason: act.reason || "",
      });
      return actRef.update({ status: "done", processedAt: Timestamp.now() });
    }

    // Pre-release safety checks (section 5). Firestore transactions can't run
    // queries, so we verify these here first; the transaction below still
    // guards on order status ("in_escrow") so a double release is impossible.
    let releaseBreakdown = null;
    if (act.type === "release") {
      const s = await orderRef.get();
      if (!s.exists) return actRef.update({ status: "order_missing" });
      const o = s.data();
      if (o.status !== "in_escrow") {
        return actRef.update({ status: "not_in_escrow" });
      }
      if ((Number(o.amount) || 0) <= 0) {
        return actRef.update({ status: "blocked_zero_amount" });
      }
      // Buyer must have confirmed delivery before a payout (section 5). An admin
      // can override in exceptional cases (act.override === true), which is
      // itself recorded in the audit log via metadata below.
      if (o.buyerConfirmed !== true && act.override !== true) {
        return actRef.update({ status: "blocked_not_confirmed" });
      }
      // Do NOT release while an active dispute exists for this order.
      const disp = await db
        .collection("disputes")
        .where("orderId", "==", act.orderId)
        .get();
      if (disp.docs.some((d) => (d.data().status || "open") === "open")) {
        return actRef.update({ status: "blocked_dispute" });
      }
      // A payout can only go to a VERIFIED seller account.
      if (o.sellerId) {
        const verified = await db
          .collection("users")
          .doc(o.sellerId)
          .collection("payoutAccounts")
          .where("verificationStatus", "==", "verified")
          .limit(1)
          .get();
        if (verified.empty) {
          return actRef.update({ status: "blocked_no_verified_account" });
        }
      }
      // Server-authoritative breakdown (reads config/commission). Computed here
      // (outside the transaction) because it does an async config read.
      releaseBreakdown = await computePayoutBreakdown(db, o, {});
      if ((releaseBreakdown.sellerPayableAmount || 0) <= 0) {
        return actRef.update({ status: "blocked_zero_payable" });
      }
    }

    // The value moved this run — captured for post-transaction audit/payout.
    let moved = null;

    await db.runTransaction(async (tx) => {
      // Idempotency: a redelivered or duplicate action doc must never re-apply
      // money. Actions are created with status 'pending'; once processed the
      // status is changed, so anything non-pending here has already run.
      const actSnap = await tx.get(actRef);
      if (
        actSnap.exists &&
        actSnap.get("status") &&
        actSnap.get("status") !== "pending"
      ) {
        return;
      }
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
        const b = releaseBreakdown;
        const payout = b.sellerPayableAmount;
        const txnRef = act.transactionReference || `PB-${act.orderId}`;
        const sellerRef = db.collection("users").doc(order.sellerId);
        const sellerSnap = await tx.get(sellerRef);
        const bal = Number(sellerSnap.get("walletBalance")) || 0;

        tx.update(sellerRef, { walletBalance: bal + payout });
        tx.update(orderRef, {
          status: "released",
          orderStatus: "completed",
          paymentStatus: "released_to_seller",
          commission: b.platformCommissionAmount,
          sellerPayout: payout,
          itemSubtotal: b.itemSubtotal,
          deliveryFee: b.deliveryFee,
          platformCommissionRate: b.platformCommissionRate,
          platformCommissionAmount: b.platformCommissionAmount,
          sellerPayableAmount: payout,
          refundAmount: b.refundAmount,
          adjustmentAmount: b.adjustmentAmount,
          releasedAmount: payout,
          currency: "PKR",
          calculationVersion: b.calculationVersion,
          transactionReference: txnRef,
          releasedBy: adminId,
          releasedAt: Timestamp.now(),
        });
        tx.set(db.collection("ledger").doc(), {
          type: "escrow_release",
          orderId: act.orderId,
          amount: payout,
          commission: b.platformCommissionAmount,
          sellerId: order.sellerId || "",
          createdAt: Timestamp.now(),
        });
        moved = { kind: "release", order, breakdown: b, payout, txnRef };
      } else if (act.type === "refund") {
        // Full refund by default; a partial refund (act.refundAmount < amount)
        // credits the buyer part of the held money and keeps the rest held so a
        // later release nets it out (computePayoutBreakdown subtracts it).
        // Cap every refund at the still-held remainder so repeated and/or
        // partial-then-full refunds can never exceed the order amount. Prior
        // refunds accumulate in refundAmount rather than being overwritten.
        const alreadyRefunded = Number(order.refundAmount) || 0;
        const remaining = round2(amount - alreadyRefunded);
        if (remaining <= 0) {
          tx.update(actRef, { status: "already_refunded" });
          return;
        }
        const requested = Number(act.refundAmount) || 0;
        // requested <= 0 means "refund the rest"; otherwise refund the requested
        // value but never more than what is still held.
        const refundValue =
          requested > 0 ? Math.min(round2(requested), remaining) : remaining;
        const newRefundTotal = round2(alreadyRefunded + refundValue);
        // Once cumulative refunds reach the amount the order is fully refunded;
        // otherwise the balance stays held (partially refunded).
        const fullyRefunded = newRefundTotal >= amount;
        const buyerRef = db.collection("users").doc(order.buyerId);
        const buyerSnap = await tx.get(buyerRef);
        const bal = Number(buyerSnap.get("walletBalance")) || 0;

        tx.update(buyerRef, { walletBalance: round2(bal + refundValue) });
        if (!fullyRefunded) {
          tx.update(orderRef, {
            paymentStatus: "partially_refunded",
            refundAmount: newRefundTotal,
            refundedAt: Timestamp.now(),
          });
        } else {
          tx.update(orderRef, {
            status: "refunded",
            // Cancellations set 'cancelled'; a return refund sets 'returned'.
            orderStatus: act.resultOrderStatus || "cancelled",
            paymentStatus: "refunded",
            refundAmount: newRefundTotal,
            refundedAt: Timestamp.now(),
          });
        }
        tx.set(db.collection("ledger").doc(), {
          type: fullyRefunded ? "escrow_refund" : "escrow_refund_partial",
          orderId: act.orderId,
          amount: refundValue,
          buyerId: order.buyerId || "",
          createdAt: Timestamp.now(),
        });
        moved = { kind: "refund", order, refundValue, partial: !fullyRefunded };
      } else {
        tx.update(actRef, { status: "unknown_type" });
        return;
      }

      tx.update(actRef, { status: "done", processedAt: Timestamp.now() });
    });

    // Post-transaction side effects: payout record, audit trail, notifications.
    if (!moved) return;
    if (moved.kind === "release") {
      await upsertSellerPayout(db, act.orderId, moved.order, {
        paymentStatus: "released_to_seller",
        releaseStatus: "released",
        releasedAmount: moved.payout,
        releasedAt: Timestamp.now(),
        releasedBy: adminId,
        transactionReference: moved.txnRef,
      });
      await writeAudit(db, {
        action: "payout_released",
        entityType: "payout",
        entityId: String(act.orderId),
        actorId: adminId,
        actorRole: "admin",
        previousStatus: "release_pending",
        newStatus: "released_to_seller",
        amount: moved.payout,
        reason: act.override === true ? "admin_override" : "",
        metadata: {
          commission: moved.breakdown.platformCommissionAmount,
          rate: moved.breakdown.platformCommissionRate,
          transactionReference: moved.txnRef,
        },
      });
      if (moved.order.sellerId) {
        await pushToUser(
          db,
          moved.order.sellerId,
          {
            title: "Payout released",
            body: `PKR ${moved.payout} has been released to your wallet.`,
          },
          { type: "payout", orderId: String(act.orderId) }
        );
      }
    } else {
      await upsertSellerPayout(db, act.orderId, moved.order, {
        paymentStatus: moved.partial ? "partially_refunded" : "refunded",
        releaseStatus: moved.partial ? "not_eligible" : "refunded",
        refundAmount: moved.refundValue,
      });
      await writeAudit(db, {
        action: moved.partial ? "refund_partial" : "refund_issued",
        entityType: "order",
        entityId: String(act.orderId),
        actorId: adminId,
        actorRole: "admin",
        newStatus: moved.partial ? "partially_refunded" : "refunded",
        amount: moved.refundValue,
        reason: act.reason || "",
      });
      if (moved.order.buyerId) {
        await pushToUser(
          db,
          moved.order.buyerId,
          {
            title: "Refund issued",
            body: `PKR ${moved.refundValue} has been refunded to your wallet.`,
          },
          { type: "order", orderId: String(act.orderId) }
        );
      }
    }
  }
);

// ---------------------------------------------------------------------------
// Order cancellation (spec sections 7–8, 11–13)
//
// A buyer files a request under orders/{id}/cancellationRequests. The functions
// below decide it server-side. Direct cancels of UNPAID orders are a client
// write (guarded by Firestore rules) and handled by onOrderProgress above.
// Paid cancellations reuse the audited escrow-refund path (onEscrowAction).
// ---------------------------------------------------------------------------

// Pure decision logic (deriveOrderStatus / cancellationEligibility /
// cancelReasonText) lives in ./cancellation_logic so it can be unit-tested
// without Firebase. See cancellation_logic.test.js.

// Approves a cancellation: cancels the order, issues a refund when money is
// held (reusing the audited escrow-refund path), writes audit + notifications.
// Idempotent — a deterministic escrowActions id prevents a double refund, and
// the request's processedAt guards the decision trigger from re-running.
async function processCancellationApproval(
  db, orderId, order, reqRef, req, actorId, actorRole
) {
  const orderRef = db.collection("orders").doc(orderId);
  const reason = req.reasonDetails || cancelReasonText(req.reasonCode);
  const heldInEscrow = order.status === "in_escrow";
  const manualReview = order.status === "payment_review";
  const cancelStamp = {
    cancellationRequested: false,
    cancellationRequestStatus: "approved",
    cancelledAt: Timestamp.now(),
    cancelledBy: actorId || "",
    cancelledByRole: actorRole,
    cancelReason: reason,
    cancelReasonCode: req.reasonCode || "",
  };

  if (heldInEscrow && (Number(order.amount) || 0) > 0) {
    // Reuse the audited escrow-refund flow, which credits the buyer's wallet
    // and sets status:refunded / orderStatus:cancelled. Fixed id → idempotent.
    try {
      await db.collection("escrowActions").doc(`cancel_${orderId}`).create({
        type: "refund",
        orderId,
        by: actorId || "system",
        reason: `cancellation:${req.reasonCode || ""}`,
        source: "cancellation",
        createdAt: Timestamp.now(),
      });
    } catch (e) {
      // Already queued/processed — continue idempotently.
    }
    // Leave status/orderStatus to the refund flow; only stamp the cancel meta.
    await orderRef.set(cancelStamp, { merge: true });
    await reqRef.set(
      {
        requestStatus: "approved",
        refundRequired: true,
        refundStatus: "pending",
        reviewedBy: actorId || "",
        reviewedAt: Timestamp.now(),
        processedAt: Timestamp.now(),
      },
      { merge: true }
    );
  } else {
    // Unpaid / COD (or a not-yet-confirmed manual payment) — cancel directly.
    await orderRef.set(
      Object.assign({ status: "cancelled", orderStatus: "cancelled" }, cancelStamp),
      { merge: true }
    );
    await reqRef.set(
      {
        requestStatus: "approved",
        refundRequired: !!manualReview,
        refundStatus: manualReview ? "manual_review" : "not_required",
        reviewedBy: actorId || "",
        reviewedAt: Timestamp.now(),
        processedAt: Timestamp.now(),
      },
      { merge: true }
    );
    if (manualReview) {
      await notifyAdmins(
        db,
        {
          title: "Refund review needed",
          body: `Cancelled order "${
            order.listingTitle || orderId
          }" had a payment under review — confirm whether a refund is owed.`,
        },
        { type: "order", orderId }
      );
    }
  }

  await writeAudit(db, {
    action: "cancellation_approved",
    entityType: "order",
    entityId: orderId,
    actorId: actorId || "",
    actorRole,
    previousStatus: order.orderStatus || order.status || "",
    newStatus: "cancelled",
    amount: Number(order.amount) || 0,
    reason: req.reasonCode || "",
  });

  if (order.buyerId) {
    await pushToUser(
      db,
      order.buyerId,
      {
        title: "Order cancelled",
        body: heldInEscrow
          ? "Your order was cancelled — your payment is being refunded to your wallet."
          : "Your order has been cancelled.",
      },
      { type: "order", orderId }
    );
  }
  // Tell the seller unless they are the one who approved it.
  if (order.sellerId && actorRole !== "seller") {
    await pushToUser(
      db,
      order.sellerId,
      {
        title: "Order cancelled",
        body: `Order "${order.listingTitle || orderId}" was cancelled.`,
      },
      { type: "order", orderId }
    );
  }
}

// A buyer filed a cancellation request → decide it (auto-approve / auto-reject /
// leave pending for the seller or admin).
exports.onCancellationRequestCreated = onDocumentCreated(
  "orders/{orderId}/cancellationRequests/{requestId}",
  async (event) => {
    const req = event.data && event.data.data();
    if (!req) return;
    const orderId = event.params.orderId;
    const requestId = event.params.requestId;
    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);
    const reqRef = event.data.ref;

    const oSnap = await orderRef.get();
    if (!oSnap.exists) {
      return reqRef.set(
        {
          requestStatus: "rejected",
          adminDecision: "auto",
          sellerResponse: "Order not found.",
          processedAt: Timestamp.now(),
        },
        { merge: true }
      );
    }
    const order = oSnap.data();

    // Flag the order so both apps can show the pending-request state.
    await orderRef.set(
      {
        cancellationRequested: true,
        cancellationRequestId: requestId,
        cancellationRequestStatus: "pending",
      },
      { merge: true }
    );
    await writeAudit(db, {
      action: "cancellation_requested",
      entityType: "order",
      entityId: orderId,
      actorId: req.buyerId || "",
      actorRole: "buyer",
      previousStatus: order.orderStatus || order.status || "",
      newStatus: "cancellation_requested",
      reason: req.reasonCode || "",
    });

    const elig = cancellationEligibility(order);

    if (elig.mode === "auto") {
      await processCancellationApproval(
        db, orderId, order, reqRef, req, req.buyerId || "", "buyer"
      );
      return;
    }

    if (elig.mode === "reject") {
      await orderRef.set(
        { cancellationRequested: false, cancellationRequestStatus: "rejected" },
        { merge: true }
      );
      await reqRef.set(
        {
          requestStatus: "rejected",
          adminDecision: "auto",
          sellerResponse: elig.reason || "",
          refundStatus: "not_required",
          reviewedAt: Timestamp.now(),
          processedAt: Timestamp.now(),
        },
        { merge: true }
      );
      await writeAudit(db, {
        action: "cancellation_rejected",
        entityType: "order",
        entityId: orderId,
        actorRole: "system",
        reason: elig.reason || "",
      });
      if (order.buyerId) {
        await pushToUser(
          db,
          order.buyerId,
          {
            title: "Cancellation not available",
            body: elig.reason || "This order can no longer be cancelled.",
          },
          { type: "order", orderId }
        );
      }
      return;
    }

    // review — needs a seller/admin decision.
    await reqRef.set(
      {
        refundRequired: !!elig.refund,
        refundStatus: elig.refund ? "pending" : "not_required",
      },
      { merge: true }
    );
    if (order.sellerId) {
      await pushToUser(
        db,
        order.sellerId,
        {
          title: "Cancellation requested",
          body: `${order.buyerName || "The buyer"} asked to cancel "${
            order.listingTitle || "an order"
          }". Review and respond.`,
        },
        { type: "order", orderId }
      );
    }
    await notifyAdmins(
      db,
      {
        title: "Cancellation requested",
        body: `Order "${
          order.listingTitle || orderId
        }" has a pending cancellation request.`,
      },
      { type: "order", orderId }
    );
    if (order.buyerId) {
      await pushToUser(
        db,
        order.buyerId,
        {
          title: "Request received",
          body: "Your cancellation request has been sent for review.",
        },
        { type: "order", orderId }
      );
    }
  }
);

// A pending cancellation request was decided by the seller/admin (or withdrawn
// by the buyer). Apply the outcome. Guards against loops via processedAt.
exports.onCancellationRequestDecision = onDocumentUpdated(
  "orders/{orderId}/cancellationRequests/{requestId}",
  async (event) => {
    const before = (event.data.before && event.data.before.data()) || {};
    const after = (event.data.after && event.data.after.data()) || {};
    const orderId = event.params.orderId;
    const db = getFirestore();

    // Only the first pending → decided transition; ignore our own follow-ups.
    if (before.requestStatus !== "pending") return;
    if (before.processedAt || after.processedAt) return;

    const orderRef = db.collection("orders").doc(orderId);
    const reqRef = event.data.after.ref;

    if (after.requestStatus === "approved") {
      const oSnap = await orderRef.get();
      if (!oSnap.exists) return;
      const order = oSnap.data();
      // Re-check eligibility so a stale approval can't cancel a shipped order.
      const elig = cancellationEligibility(order);
      if (elig.mode === "reject") {
        await reqRef.set(
          {
            requestStatus: "rejected",
            sellerResponse: elig.reason || "",
            processedAt: Timestamp.now(),
          },
          { merge: true }
        );
        await orderRef.set(
          {
            cancellationRequested: false,
            cancellationRequestStatus: "rejected",
          },
          { merge: true }
        );
        if (order.buyerId) {
          await pushToUser(
            db,
            order.buyerId,
            { title: "Cancellation not available", body: elig.reason || "" },
            { type: "order", orderId }
          );
        }
        return;
      }
      const actorRole =
        after.decidedByRole || (after.adminDecision ? "admin" : "seller");
      await processCancellationApproval(
        db, orderId, order, reqRef, after, after.reviewedBy || "", actorRole
      );
      return;
    }

    if (after.requestStatus === "rejected") {
      await orderRef.set(
        {
          cancellationRequested: false,
          cancellationRequestStatus: "rejected",
          cancellationDecisionNote: after.sellerResponse || "",
        },
        { merge: true }
      );
      await reqRef.set({ processedAt: Timestamp.now() }, { merge: true });
      await writeAudit(db, {
        action: "cancellation_rejected",
        entityType: "order",
        entityId: orderId,
        actorId: after.reviewedBy || "",
        actorRole: after.decidedByRole || "seller",
        reason: after.sellerResponse || "",
      });
      const oSnap = await orderRef.get();
      const order = oSnap.exists ? oSnap.data() : {};
      if (order.buyerId) {
        await pushToUser(
          db,
          order.buyerId,
          {
            title: "Cancellation declined",
            body: after.sellerResponse
              ? `Your cancellation request was declined: ${after.sellerResponse}`
              : "Your cancellation request was declined.",
          },
          { type: "order", orderId }
        );
      }
      return;
    }

    if (after.requestStatus === "withdrawn") {
      await orderRef.set(
        {
          cancellationRequested: false,
          cancellationRequestStatus: "withdrawn",
        },
        { merge: true }
      );
      await reqRef.set({ processedAt: Timestamp.now() }, { merge: true });
      await writeAudit(db, {
        action: "cancellation_withdrawn",
        entityType: "order",
        entityId: orderId,
        actorId: after.buyerId || "",
        actorRole: "buyer",
      });
    }
  }
);

// ---------------------------------------------------------------------------
// Order returns (Phase 4)
//
// After delivery the buyer files a returnRequest. It always needs seller/admin
// approval; on approval, while the money is still held, the audited escrow
// refund runs with resultOrderStatus 'returned'. Mirrors the cancellation flow.
// ---------------------------------------------------------------------------

// Approves a return: refunds the held payment (reusing the escrow-refund path,
// tagged to land the order on orderStatus 'returned') and records it. Idempotent
// via a deterministic escrowActions id + the request's processedAt.
async function processReturnApproval(
  db, orderId, order, reqRef, req, actorId, actorRole
) {
  const orderRef = db.collection("orders").doc(orderId);
  // Only refundable while the money is still held by the platform.
  if (order.status !== "in_escrow" || (Number(order.amount) || 0) <= 0) {
    await reqRef.set(
      {
        requestStatus: "rejected",
        sellerResponse: "Order is no longer eligible for an in-app refund.",
        processedAt: Timestamp.now(),
      },
      { merge: true }
    );
    await orderRef.set(
      { returnRequested: false, returnRequestStatus: "rejected" },
      { merge: true }
    );
    return;
  }

  try {
    await db.collection("escrowActions").doc(`return_${orderId}`).create({
      type: "refund",
      orderId,
      by: actorId || "system",
      reason: `return:${req.reasonCode || ""}`,
      source: "return",
      resultOrderStatus: "returned",
      createdAt: Timestamp.now(),
    });
  } catch (e) {
    // Already queued/processed — continue idempotently.
  }
  await orderRef.set(
    {
      returnRequested: false,
      returnRequestStatus: "approved",
      returnedAt: Timestamp.now(),
      returnedBy: actorId || "",
      returnReasonCode: req.reasonCode || "",
    },
    { merge: true }
  );
  await reqRef.set(
    {
      requestStatus: "approved",
      refundStatus: "pending",
      reviewedBy: actorId || "",
      reviewedAt: Timestamp.now(),
      processedAt: Timestamp.now(),
    },
    { merge: true }
  );
  await writeAudit(db, {
    action: "return_approved",
    entityType: "order",
    entityId: orderId,
    actorId: actorId || "",
    actorRole,
    previousStatus: order.orderStatus || order.status || "",
    newStatus: "returned",
    amount: Number(order.amount) || 0,
    reason: req.reasonCode || "",
  });
  if (order.buyerId) {
    await pushToUser(
      db,
      order.buyerId,
      {
        title: "Return approved",
        body: "Your return was approved — your payment is being refunded to your wallet.",
      },
      { type: "order", orderId }
    );
  }
  if (order.sellerId && actorRole !== "seller") {
    await pushToUser(
      db,
      order.sellerId,
      {
        title: "Return approved",
        body: `A return on order "${order.listingTitle || orderId}" was approved.`,
      },
      { type: "order", orderId }
    );
  }
}

// A buyer filed a return request → validate + route to the seller/admin.
exports.onReturnRequestCreated = onDocumentCreated(
  "orders/{orderId}/returnRequests/{requestId}",
  async (event) => {
    const req = event.data && event.data.data();
    if (!req) return;
    const orderId = event.params.orderId;
    const requestId = event.params.requestId;
    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);
    const reqRef = event.data.ref;

    const oSnap = await orderRef.get();
    if (!oSnap.exists) {
      return reqRef.set(
        {
          requestStatus: "rejected",
          sellerResponse: "Order not found.",
          processedAt: Timestamp.now(),
        },
        { merge: true }
      );
    }
    const order = oSnap.data();

    await orderRef.set(
      {
        returnRequested: true,
        returnRequestId: requestId,
        returnRequestStatus: "pending",
      },
      { merge: true }
    );
    await writeAudit(db, {
      action: "return_requested",
      entityType: "order",
      entityId: orderId,
      actorId: req.buyerId || "",
      actorRole: "buyer",
      previousStatus: order.orderStatus || order.status || "",
      newStatus: "return_requested",
      reason: req.reasonCode || "",
    });

    const elig = returnEligibility(order);
    if (elig.mode === "reject") {
      await orderRef.set(
        { returnRequested: false, returnRequestStatus: "rejected" },
        { merge: true }
      );
      await reqRef.set(
        {
          requestStatus: "rejected",
          adminDecision: "auto",
          sellerResponse: elig.reason || "",
          processedAt: Timestamp.now(),
          reviewedAt: Timestamp.now(),
        },
        { merge: true }
      );
      if (order.buyerId) {
        await pushToUser(
          db,
          order.buyerId,
          {
            title: "Return not available",
            body: elig.reason || "This order can't be returned in the app.",
          },
          { type: "order", orderId }
        );
      }
      return;
    }

    // review — notify seller + admin, ack the buyer.
    if (order.sellerId) {
      await pushToUser(
        db,
        order.sellerId,
        {
          title: "Return requested",
          body: `${order.buyerName || "The buyer"} requested a return on "${
            order.listingTitle || "an order"
          }". Review and respond.`,
        },
        { type: "order", orderId }
      );
    }
    await notifyAdmins(
      db,
      {
        title: "Return requested",
        body: `Order "${order.listingTitle || orderId}" has a pending return request.`,
      },
      { type: "order", orderId }
    );
    if (order.buyerId) {
      await pushToUser(
        db,
        order.buyerId,
        {
          title: "Return request received",
          body: "Your return request has been sent for review.",
        },
        { type: "order", orderId }
      );
    }
  }
);

// A pending return request was decided (or withdrawn). Apply the outcome.
exports.onReturnRequestDecision = onDocumentUpdated(
  "orders/{orderId}/returnRequests/{requestId}",
  async (event) => {
    const before = (event.data.before && event.data.before.data()) || {};
    const after = (event.data.after && event.data.after.data()) || {};
    const orderId = event.params.orderId;
    const db = getFirestore();

    if (before.requestStatus !== "pending") return;
    if (before.processedAt || after.processedAt) return;

    const orderRef = db.collection("orders").doc(orderId);
    const reqRef = event.data.after.ref;

    if (after.requestStatus === "approved") {
      const oSnap = await orderRef.get();
      if (!oSnap.exists) return;
      const order = oSnap.data();
      const actorRole =
        after.decidedByRole || (after.adminDecision ? "admin" : "seller");
      await processReturnApproval(
        db, orderId, order, reqRef, after, after.reviewedBy || "", actorRole
      );
      return;
    }

    if (after.requestStatus === "rejected") {
      await orderRef.set(
        {
          returnRequested: false,
          returnRequestStatus: "rejected",
          returnDecisionNote: after.sellerResponse || "",
        },
        { merge: true }
      );
      await reqRef.set({ processedAt: Timestamp.now() }, { merge: true });
      await writeAudit(db, {
        action: "return_rejected",
        entityType: "order",
        entityId: orderId,
        actorId: after.reviewedBy || "",
        actorRole: after.decidedByRole || "seller",
        reason: after.sellerResponse || "",
      });
      const oSnap = await orderRef.get();
      const order = oSnap.exists ? oSnap.data() : {};
      if (order.buyerId) {
        await pushToUser(
          db,
          order.buyerId,
          {
            title: "Return declined",
            body: after.sellerResponse
              ? `Your return request was declined: ${after.sellerResponse}`
              : "Your return request was declined.",
          },
          { type: "order", orderId }
        );
      }
      return;
    }

    if (after.requestStatus === "withdrawn") {
      await orderRef.set(
        { returnRequested: false, returnRequestStatus: "withdrawn" },
        { merge: true }
      );
      await reqRef.set({ processedAt: Timestamp.now() }, { merge: true });
      await writeAudit(db, {
        action: "return_withdrawn",
        entityType: "order",
        entityId: orderId,
        actorId: after.buyerId || "",
        actorRole: "buyer",
      });
    }
  }
);

// Alert the seller when a buyer opens a dispute / problem report. The payout is
// already blocked server-side while the dispute is open (see onEscrowAction);
// this only notifies. Admins see disputes in the dashboard.
exports.notifyOnDispute = onDocumentCreated(
  "disputes/{disputeId}",
  async (event) => {
    const d = event.data && event.data.data();
    if (!d || !d.sellerId) return;
    const db = getFirestore();
    const title =
      d.type === "dispute" ? "A dispute was opened" : "A problem was reported";
    const body = `Order: ${d.listingTitle || "your item"}${
      d.reason ? ` — ${d.reason}` : ""
    }`;
    // Mark the order disputed so the seller payout is visibly blocked (the hard
    // block is already enforced in onEscrowAction's pre-release checks). Money
    // status is not changed — the funds simply stay held pending resolution.
    if (d.orderId) {
      try {
        await db
          .collection("orders")
          .doc(String(d.orderId))
          .set({ orderStatus: "disputed", hasOpenDispute: true }, { merge: true });
        await db
          .collection("sellerPayouts")
          .doc(String(d.orderId))
          .set({ releaseStatus: "on_hold", holdReason: "dispute_open", updatedAt: Timestamp.now() }, { merge: true });
      } catch (_) {
        // best-effort — the pre-release query is the authoritative block
      }
    }
    await writeAudit(db, {
      action: "dispute_opened",
      entityType: "order",
      entityId: String(d.orderId || ""),
      actorId: d.buyerId || "",
      actorRole: "buyer",
      newStatus: "disputed",
      reason: d.reason || "",
      metadata: { type: d.type || "problem" },
    });
    await pushToUser(
      db,
      d.sellerId,
      { title, body },
      { type: "dispute", orderId: String(d.orderId || "") }
    );
    await notifyAdmins(
      db,
      { title: "Dispute opened", body },
      { type: "dispute", orderId: String(d.orderId || "") }
    );
  }
);

// ---------------------------------------------------------------------------
// Order fulfillment progress → server-authoritative money effects.
//
// Clients advance the FULFILLMENT side (seller ships; buyer confirms delivery)
// with rules-validated writes, but the MONEY side (payment_status, payout
// records) is owned by this backend. When the buyer confirms delivery on a
// platform-held order, we move payment_status to release_pending and open a
// payout record for admin verification — the buyer app never releases money.
// ---------------------------------------------------------------------------
// Multi-seller (Phase 7): recompute a master order's aggregate delivery
// progress from its sub-orders and, the first time every live package is
// delivered, notify the buyer once. Idempotent — the allDelivered flip is
// guarded inside a transaction so concurrent sub-order updates notify only
// once. Cancelled/returned/refunded packages drop out of the "active" set so
// a partly-cancelled order can still reach "all delivered".
async function refreshMasterProgress(db, masterId) {
  if (!masterId) return;
  const subs = await db
    .collection("orders")
    .where("masterOrderId", "==", String(masterId))
    .get();
  if (subs.empty) return;
  const doneStates = new Set(["delivered", "buyer_confirmed", "completed"]);
  const deadStates = new Set(["cancelled", "returned", "rejected"]);
  let delivered = 0;
  let active = 0;
  subs.forEach((d) => {
    const os = d.get("orderStatus") || "";
    const st = d.get("status") || "";
    if (deadStates.has(os) || st === "cancelled" || st === "refunded") return;
    active++;
    if (doneStates.has(os)) delivered++;
  });
  const allDelivered = active > 0 && delivered === active;
  // Every package ended cancelled/returned/rejected → the whole order is
  // resolved; give it a terminal state instead of a perpetual "placed".
  const allResolved = active === 0 && subs.size > 0;
  const mRef = db.collection("masterOrders").doc(String(masterId));
  let notify = null;
  await db.runTransaction(async (tx) => {
    const m = await tx.get(mRef);
    if (!m.exists) return;
    const wasAll = m.get("allDelivered") === true;
    tx.set(
      mRef,
      {
        deliveredCount: delivered,
        activeCount: active,
        packageCount: subs.size,
        allDelivered,
        progressUpdatedAt: Timestamp.now(),
        ...(allResolved ? { status: "cancelled", allResolved: true } : {}),
      },
      { merge: true }
    );
    if (allDelivered && !wasAll) {
      notify = {
        buyerId: m.get("buyerId") || "",
        number: m.get("orderNumber") || "",
      };
    }
  });
  if (notify && notify.buyerId) {
    await pushToUser(
      db,
      notify.buyerId,
      {
        title: "All packages delivered",
        body: `Every package in order ${
          notify.number || "your order"
        } is delivered. Confirm receipt of each package to release the sellers' payments.`,
      },
      { type: "order", orderId: String(masterId) }
    );
  }
}

exports.onOrderProgress = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = (event.data.before && event.data.before.data()) || {};
    const after = (event.data.after && event.data.after.data()) || {};
    const orderId = event.params.orderId;
    const db = getFirestore();
    const masterId = after.masterOrderId || before.masterOrderId || "";
    // Any fulfillment/status change on a sub-order can shift the master's
    // aggregate delivery progress.
    const progressChanged =
      before.orderStatus !== after.orderStatus ||
      before.status !== after.status;

    // Direct buyer cancellation of an UNPAID order (client write, no request
    // doc). The paid/refund and request-approval paths emit their own
    // notifications, so skip those (they carry a cancellationRequestId or land
    // on status 'refunded').
    if (
      after.status === "cancelled" &&
      before.status !== "cancelled" &&
      !after.cancellationRequestId
    ) {
      await writeAudit(db, {
        action: "buyer_cancelled_pending",
        entityType: "order",
        entityId: orderId,
        actorId: after.cancelledBy || "",
        actorRole: after.cancelledByRole || "buyer",
        previousStatus: before.orderStatus || before.status || "",
        newStatus: "cancelled",
        amount: Number(after.amount) || 0,
        reason: after.cancelReasonCode || after.cancelReason || "",
      });
      if (after.sellerId) {
        await pushToUser(
          db,
          after.sellerId,
          {
            title: "Order cancelled",
            body: `${after.buyerName || "The buyer"} cancelled the order for "${
              after.listingTitle || "an item"
            }".`,
          },
          { type: "order", orderId }
        );
      }
      await notifyAdmins(
        db,
        {
          title: "Order cancelled",
          body: `Order "${
            after.listingTitle || orderId
          }" was cancelled by the buyer.`,
        },
        { type: "order", orderId }
      );
      if (masterId) await refreshMasterProgress(db, masterId);
      return;
    }

    const nowConfirmed =
      (after.orderStatus === "buyer_confirmed" &&
        before.orderStatus !== "buyer_confirmed") ||
      (after.buyerConfirmed === true && before.buyerConfirmed !== true);

    // Buyer confirmed delivery on a held (escrow) order → open the payout for
    // admin verification. Idempotent: skip if we've already moved to
    // release_pending (this function also fires on its own write below).
    if (
      nowConfirmed &&
      after.status === "in_escrow" &&
      before.paymentStatus !== "release_pending" &&
      // This block writes paymentStatus:release_pending, which re-fires this
      // trigger; without this guard it would run twice (duplicate audits/pushes).
      after.paymentStatus !== "release_pending" &&
      after.paymentStatus !== "released_to_seller"
    ) {
      await db.collection("orders").doc(orderId).set(
        {
          orderStatus: "buyer_confirmed",
          paymentStatus: "release_pending",
          buyerConfirmed: true,
          buyerConfirmedBy: after.buyerId || before.buyerId || "",
          buyerConfirmedAt: after.buyerConfirmedAt || Timestamp.now(),
        },
        { merge: true }
      );
      await upsertSellerPayout(db, orderId, after, {
        paymentStatus: "release_pending",
        releaseStatus: "eligible",
        eligibleForReleaseAt: Timestamp.now(),
      });
      await writeAudit(db, {
        action: "buyer_confirmed_delivery",
        entityType: "order",
        entityId: orderId,
        actorId: after.buyerId || "",
        actorRole: "buyer",
        previousStatus: before.orderStatus || before.status || "",
        newStatus: "buyer_confirmed",
        amount: Number(after.amount) || 0,
      });
      await writeAudit(db, {
        action: "commission_calculated",
        entityType: "payout",
        entityId: orderId,
        actorRole: "system",
        amount: Number(after.amount) || 0,
      });
      if (after.sellerId) {
        await pushToUser(
          db,
          after.sellerId,
          {
            title: "Buyer confirmed delivery",
            body: "Your payout is pending platform verification.",
          },
          { type: "payout", orderId }
        );
      }
      await notifyAdmins(
        db,
        {
          title: "Payout eligible",
          body: `Order "${after.listingTitle || orderId}" is ready for payout review.`,
        },
        { type: "payout", orderId }
      );
      if (masterId) await refreshMasterProgress(db, masterId);
      return;
    }

    // Buyer-facing fulfillment notifications (seller advanced the order). For a
    // multi-seller order each sub-order is one package, so name the package so
    // the buyer knows which shipment moved; single Buy Now wording is unchanged.
    if (after.orderStatus !== before.orderStatus && after.buyerId) {
      const isPkg = !!after.masterOrderId;
      const courier = after.courierName ? ` via ${after.courierName}` : "";
      const msg = isPkg
        ? {
            accepted: `Package ${after.orderNumber || ""} was accepted by the seller.`,
            processing: `Package ${after.orderNumber || ""} is being prepared.`,
            shipped: `Package ${after.orderNumber || ""} has shipped${courier}.`,
            delivered: `Package ${
              after.orderNumber || ""
            } is marked delivered — please confirm once you've received and checked it.`,
          }[after.orderStatus]
        : {
            accepted: "The seller accepted your order.",
            processing: "Your order is being prepared.",
            shipped: `Your order has shipped${courier}.`,
            delivered:
              "Your order is marked delivered — please confirm once you've received and checked it.",
          }[after.orderStatus];
      if (msg) {
        await pushToUser(
          db,
          after.buyerId,
          { title: "Order update", body: msg },
          { type: "order", orderId }
        );
      }
    }

    if (masterId && progressChanged) await refreshMasterProgress(db, masterId);
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
      // Idempotency: a redelivered event must not reserve (deduct) twice.
      const wSnap = await tx.get(wRef);
      const wstatus = wSnap.get("status");
      if (wstatus && wstatus !== "pending") return;
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

// Verify a PayFast IPN callback is authentic before trusting it to move money.
// Fails CLOSED: returns false unless the merchant secured key is configured AND
// the callback carries a SIGNATURE that matches the recomputed validation hash.
// Because PayFast is not live yet (the app settles via the manual admin flow),
// this guarantees no unauthenticated caller can settle an order into escrow.
// NOTE: confirm the exact hash field order against your PayFast onboarding pack
// before enabling live payments.
function verifyPayfastIpn(req) {
  const securedKey = process.env.PAYFAST_SECURED_KEY;
  const merchantId = process.env.PAYFAST_MERCHANT_ID;
  if (!securedKey || !merchantId) return false; // not configured → never trust
  const body = req.body || {};
  const provided = String(body.SIGNATURE || body.signature || "");
  if (!provided) return false;
  const basketId = String(body.BASKET_ID || body.basket_id || "");
  const amount = String(body.TXNAMT || body.transaction_amount || "");
  const expected = crypto
    .createHash("md5")
    .update(`${merchantId}:${amount}:${basketId}:${securedKey}`)
    .digest("hex");
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
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

    // SECURITY (C4): never settle money on an unverified callback. Fails closed
    // — acknowledge (200 so PayFast doesn't retry-storm) but move no money —
    // until a verified signature check is configured and passes.
    if (!verifyPayfastIpn(req)) {
      console.warn("payfastIpn: unverified callback ignored", { basketId });
      res.status(200).send("ok");
      return;
    }

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
