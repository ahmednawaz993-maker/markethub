"use strict";

// MarketHub Cloud Functions.
//
// notifyOnNewMessage: when a chat message is created, push an FCM notification
// to the OTHER participant's registered devices (users/{uid}/fcmTokens).

const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest, onCall, HttpsError } =
  require("firebase-functions/v2/https");
const crypto = require("crypto");
const ludo = require("./ludo_logic");
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
const { refundAllocation } = require("./escrow_logic");
const {
  NEW_LISTING_TOPIC,
  ANNOUNCEMENT_TOPIC,
  validateAdminBroadcast,
  canSendBroadcast,
  userTopic,
  broadcastTarget,
  shouldBroadcastListing,
  becamePublic,
  broadcastMessage,
  wantsBroadcast,
} = require("./broadcast_logic");

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

// Create a document whose id is a deterministic idempotency key.
//
// `.create()` failing with ALREADY_EXISTS means a redelivered event is being
// replayed and the work is already queued — safe to ignore. Every OTHER
// failure (permission, transient, deadline) must propagate: the callers go on
// to stamp the request "approved" and push "your refund is being credited", so
// a blanket catch told buyers their money was on the way when nothing had been
// queued at all, with no alert to anyone.
//
// Returns true if this call created the document, false if it already existed.
async function createOnce(ref, data) {
  try {
    await ref.create(data);
    return true;
  } catch (e) {
    const code = e && e.code;
    if (code === 6 || code === "already-exists") return false;
    throw e;
  }
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

// ---------------------------------------------------------------------------
// New-listing broadcast: every user is told ONCE about each listing that goes
// public (approved + in stock). Something genuinely new on the platform is worth
// everyone's attention — a seller re-editing it is not.
//
// Delivery is a single FCM topic send, not a per-user fan-out: every opted-in
// device is subscribed to NEW_LISTING_TOPIC, so one listing costs one send no
// matter how large the userbase gets. The trade-off is that a topic message
// cannot be personalised and leaves no per-user record — there is no in-app
// inbox copy for a broadcast, unlike pushToUser().
//
// ⚠️ ONCE PER LISTING, deliberately (changed 2026-07-30). This used to re-announce
// after every edit to a listing's content, which was the platform's main source of
// notification spam: editing an ad puts it back in the moderation queue, so each
// re-approval pushed "Updated in <category>" to the entire userbase about an ad
// that was not new. One seller adjusting a price could buzz every phone in the
// country several times. Worse, a push drives people to open the ad, which is a
// loop that feeds itself. If per-edit announcements are ever wanted again they
// need per-listing rate limiting and an opt-out that is actually discoverable —
// do not simply restore the old behaviour.
//
// Unsolicited pushes beyond this are ADMIN-INITIATED ONLY, via the "Notify" tab
// (adminBroadcasts -> onAdminBroadcastCreated -> ANNOUNCEMENT_TOPIC).
//
// Opting out: notifPrefs.newListing=false, notifPrefs.push=false, or
// notifPrefs.mode='off' unsubscribes that user's devices from the topic — see
// wantsBroadcast() and syncNewListingTopicOnPrefs() below.
// ---------------------------------------------------------------------------

// Announces one listing to the whole userbase, the first time it becomes public
// and never again.
//
// listingBroadcasts/{listingId} is the once-only claim. Taking it in a
// transaction gives duplicate suppression (the create trigger and the
// approval-update trigger can both fire for the same listing, only one sends),
// retry safety (a redelivered event finds the claim already held), and
// serialisation of two writes landing together. The claim is released if the
// send itself fails, so a genuine failure can still be retried.
async function broadcastListing(db, listing, listingId) {
  if (!shouldBroadcastListing(listing)) return;

  const claim = db.collection("listingBroadcasts").doc(String(listingId));

  const fresh = await db.runTransaction(async (tx) => {
    const snap = await tx.get(claim);
    const prev = snap.exists ? snap.data() : null;
    // A claim doc exists only because we already announced this listing (or are
    // mid-send). Only an outright send FAILURE is worth retrying. Keying off mere
    // existence rather than a new field matters for migration: docs written by
    // the old per-edit behaviour carry `signature`/`broadcastCount` and no
    // announced flag, and must not each earn one final push on deploy.
    if (prev && prev.deliveryStatus !== "failed") return false;
    tx.set(
      claim,
      {
        listingId: String(listingId),
        sellerId: listing.userId || "",
        announced: true,
        sentAt: Timestamp.now(),
        deliveryStatus: "sending",
      },
      { merge: true }
    );
    return true;
  });
  if (!fresh) return;

  const { title, body } = broadcastMessage(listing, "new");
  try {
    const messageId = await getMessaging().send({
      // Everyone on the topic EXCEPT the seller's own devices.
      ...broadcastTarget(listing.userId),
      notification: { title, body },
      // The app's openNotificationTarget() already routes type 'newListing'
      // + a listing id to the ad screen, so taps deep-link for free.
      data: { type: "newListing", listingId: String(listingId), kind: "new" },
      android: ANDROID_ALERT,
      apns: APNS_ALERT,
      webpush: {
        notification: { icon: "/icons/Icon-192.png" },
        fcmOptions: { link: "/" },
      },
    });
    await claim.set(
      { deliveryStatus: "sent", kind: "new", messageId },
      { merge: true }
    );
  } catch (e) {
    // Mark the claim failed — the only state the transaction above will retry.
    await claim
      .set({ deliveryStatus: "failed", announced: false }, { merge: true })
      .catch(() => {});
    throw e;
  }
}

// ---------------------------------------------------------------------------
// Topic subscription management.
//
// Subscribing happens server-side rather than in the app because the FCM *web*
// SDK has no subscribeToTopic(). Doing it here keeps Android, iOS and web on a
// single code path and makes an opt-out apply to every device a user owns.
// ---------------------------------------------------------------------------

// FCM's topic-management endpoints accept at most 1000 tokens per call.
const TOPIC_BATCH = 1000;

async function setTopicSubscription(
  tokens,
  subscribed,
  topic = NEW_LISTING_TOPIC
) {
  const messaging = getMessaging();
  for (let i = 0; i < tokens.length; i += TOPIC_BATCH) {
    const batch = tokens.slice(i, i + TOPIC_BATCH);
    try {
      if (subscribed) {
        await messaging.subscribeToTopic(batch, topic);
      } else {
        await messaging.unsubscribeFromTopic(batch, topic);
      }
    } catch (e) {
      // One dead token must not stop the rest of the batch; the daily
      // reconciler retries whatever did not stick.
      console.error(`${topic} topic batch failed`, e);
    }
  }
}

async function userTokens(db, uid) {
  const snap = await db
    .collection("users").doc(uid).collection("fcmTokens").get();
  return snap.docs.map((d) => d.id);
}

// Puts a device in (or out of) the admin-announcement topic.
async function setAnnouncementSubscription(token, subscribed) {
  const messaging = getMessaging();
  try {
    if (subscribed) {
      await messaging.subscribeToTopic([token], ANNOUNCEMENT_TOPIC);
    } else {
      await messaging.unsubscribeFromTopic([token], ANNOUNCEMENT_TOPIC);
    }
  } catch (e) {
    console.error("announcement topic subscription failed", e);
  }
}

// Puts a device in (or out of) the topic naming its owner. That membership is
// what lets a broadcast exclude the seller's own devices — see broadcastTarget().
// Accepts one token or many, since the token trigger has a single token while
// the daily reconciler re-asserts all of a user's devices at once. Returns
// whether the call landed, so the reconciler can report how much stuck.
async function setUserTopicSubscription(tokens, uid, subscribed) {
  const topic = userTopic(uid);
  if (!topic) return false;
  const list = Array.isArray(tokens) ? tokens : [tokens];
  if (list.length === 0) return false;
  const messaging = getMessaging();
  try {
    if (subscribed) {
      await messaging.subscribeToTopic(list, topic);
    } else {
      await messaging.unsubscribeFromTopic(list, topic);
    }
    return true;
  } catch (e) {
    console.error(`user topic ${topic} subscription failed`, e);
    return false;
  }
}

// Re-asserts every user's own exclusion topic. Unlike the two shared topics this
// CANNOT be batched — each user has a distinct topic, so it is one FCM call per
// user. Run with bounded concurrency: serial would blow the sweep's timeout once
// the userbase grows, and unbounded would open thousands of sockets at once.
const USER_TOPIC_CONCURRENCY = 20;

async function reconcileUserTopics(entries) {
  let ok = 0;
  for (let i = 0; i < entries.length; i += USER_TOPIC_CONCURRENCY) {
    const slice = entries.slice(i, i + USER_TOPIC_CONCURRENCY);
    const results = await Promise.all(
      slice.map((e) => setUserTopicSubscription(e.tokens, e.uid, true))
    );
    ok += results.filter(Boolean).length;
  }
  return ok;
}

// A device registered (or refreshed) its push token. The app rewrites this doc
// on every launch, so this is also what backfills users who already had a
// token registered before broadcasts existed.
exports.syncNewListingTopicOnToken = onDocumentWritten(
  "users/{uid}/fcmTokens/{token}",
  async (event) => {
    const token = event.params.token;
    const uid = event.params.uid;
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      // Token was removed — drop it from every topic.
      await setTopicSubscription([token], false);
      await setUserTopicSubscription(token, uid, false);
      await setAnnouncementSubscription(token, false);
      return;
    }
    // The owner topic is unconditional: it carries no messages, it only makes
    // this device excludable from its owner's own listings. Opting out of
    // broadcasts is expressed by leaving NEW_LISTING_TOPIC, below.
    await setUserTopicSubscription(token, uid, true);
    // Admin announcements are also unconditional: the new-listing opt-out is
    // about marketplace noise and must not silence service messages.
    await setAnnouncementSubscription(token, true);
    const snap = await getFirestore().collection("users").doc(uid).get();
    await setTopicSubscription([token], wantsBroadcast(snap.data()));
  }
);

// The user changed their notification preferences — apply it to every device
// they own. Fires on any user-doc update, so it early-outs unless the effective
// subscription actually flipped.
exports.syncNewListingTopicOnPrefs = onDocumentUpdated(
  "users/{uid}",
  async (event) => {
    const before = event.data && event.data.before.data();
    const after = event.data && event.data.after.data();
    if (!before || !after) return;
    const wanted = wantsBroadcast(after);
    if (wantsBroadcast(before) === wanted) return;
    const tokens = await userTokens(getFirestore(), event.params.uid);
    if (tokens.length === 0) return;
    await setTopicSubscription(tokens, wanted);
  }
);

// Self-healing sweep: re-asserts every user's subscription once a day, so a
// dropped trigger or a failed batch cannot leave someone permanently silent —
// or, worse, still being blasted after opting out.
//
// Also re-asserts ANNOUNCEMENT_TOPIC for every device that has a token. That
// subscription is otherwise only ever written by syncNewListingTopicOnToken, so
// without this sweep two things go wrong: a device whose subscribe call failed
// (the error is logged and swallowed) can never hear an announcement again, and
// anyone who has not reopened the app since announcements shipped was never
// subscribed in the first place — making "Send to everyone" silently reach only
// a fraction of the userbase.
//
// And the same for each user's own `user_{uid}` topic, which carries no messages
// but is what lets a new-listing broadcast exclude the seller's own devices. It
// had the identical gap: written only by the token trigger, so a failed call
// meant that seller got pushed their own listings forever.
//
// The per-user pass is one FCM call per user, so this needs more than the 60s
// default timeout as the userbase grows.
exports.reconcileNewListingTopic = onSchedule(
  { schedule: "every 24 hours", timeoutSeconds: 540, memory: "512MiB" },
  async () => {
    const db = getFirestore();
    const subscribe = [];
    const unsubscribe = [];
    // Every live token, regardless of preferences: announcements are service
    // messages, and the new-listing opt-out is only about marketplace noise.
    const announce = [];
    // One entry per user with devices — cannot be flattened, each needs its own
    // topic call.
    const owners = [];
    const PAGE = 500;

    let page = await db
      .collection("users")
      .orderBy("__name__")
      .limit(PAGE)
      .get();
    while (!page.empty) {
      for (const u of page.docs) {
        const tokens = await userTokens(db, u.id);
        if (tokens.length === 0) continue;
        announce.push(...tokens);
        owners.push({ uid: u.id, tokens });
        (wantsBroadcast(u.data()) ? subscribe : unsubscribe).push(...tokens);
      }
      if (page.size < PAGE) break;
      page = await db
        .collection("users")
        .orderBy("__name__")
        .startAfter(page.docs[page.size - 1])
        .limit(PAGE)
        .get();
    }

    await setTopicSubscription(subscribe, true);
    await setTopicSubscription(unsubscribe, false);
    await setTopicSubscription(announce, true, ANNOUNCEMENT_TOPIC);
    const ownersOk = await reconcileUserTopics(owners);
    console.log(
      `new-listing topic reconciled: ${subscribe.length} subscribed, ` +
        `${unsubscribe.length} unsubscribed; ` +
        `${announce.length} tokens on ${ANNOUNCEMENT_TOPIC}; ` +
        `${ownersOk}/${owners.length} owner topics re-asserted`
    );
  }
);

// ---------------------------------------------------------------------------
// Admin-composed notifications ("Notify" tab in the admin panel).
//
// The panel writes adminBroadcasts/{id} with status 'pending'; this trigger
// authorises, validates and sends it, then writes the outcome back to the same
// doc so the panel can show delivered/failed. The client never talks to FCM.
//
// Audience 'all' goes to ANNOUNCEMENT_TOPIC (one send, no inbox copy).
// Audience 'user' goes through pushToUser(), which also files an in-app inbox
// copy, so a message aimed at one person survives them missing the push.
// ---------------------------------------------------------------------------
exports.onAdminBroadcastCreated = onDocumentCreated(
  "adminBroadcasts/{broadcastId}",
  async (event) => {
    const doc = event.data;
    const data = doc && doc.data();
    if (!data || data.status !== "pending") return;

    const db = getFirestore();
    const fail = (error) =>
      doc.ref.set(
        { status: "failed", error, processedAt: Timestamp.now() },
        { merge: true }
      );

    // Authorise from the server's own view of the staff roster, not from
    // anything the client put in the document.
    const email = String(data.createdByEmail || "").toLowerCase();
    let staffData = null;
    if (email) {
      const staffSnap = await db.collection("staff").doc(email).get();
      staffData = staffSnap.exists ? staffSnap.data() : null;
    }
    if (!canSendBroadcast(email, staffData, ADMIN_EMAIL)) {
      await fail("Not authorised to send notifications.");
      return;
    }

    const valid = validateAdminBroadcast(data);
    if (!valid.ok) {
      await fail(valid.error);
      return;
    }

    const { title, body, audience, targetUid } = valid;
    // An unrecognised type falls through to the app's "show the text" branch
    // in openNotificationTarget(), so a plain announcement still opens fine.
    const payload = {
      type: String(data.type || "announcement"),
      refId: String(data.refId || ""),
      broadcastId: event.params.broadcastId,
    };

    try {
      if (audience === "user") {
        await pushToUser(db, targetUid, { title, body }, payload);
        await doc.ref.set(
          {
            status: "sent",
            audience: "user",
            sentAt: Timestamp.now(),
            processedAt: Timestamp.now(),
          },
          { merge: true }
        );
        return;
      }

      const messageId = await getMessaging().send({
        topic: ANNOUNCEMENT_TOPIC,
        notification: { title, body },
        data: payload,
        android: ANDROID_ALERT,
        apns: APNS_ALERT,
        webpush: {
          notification: { icon: "/icons/Icon-192.png" },
          fcmOptions: { link: "/" },
        },
      });
      await doc.ref.set(
        {
          status: "sent",
          audience: "all",
          messageId,
          sentAt: Timestamp.now(),
          processedAt: Timestamp.now(),
        },
        { merge: true }
      );
    } catch (e) {
      await fail(String((e && e.message) || e));
    }
  }
);

// A listing created already-approved (demo/admin auto-approve) is public
// immediately. The normal pending->approved path is handled in the update
// trigger (notifyOnPriceDrop) to avoid a second per-update function.
exports.notifyOnNewListing = onDocumentCreated(
  "listings/{listingId}",
  async (event) => {
    const listing = event.data && event.data.data();
    if (!listing) return;
    await broadcastListing(getFirestore(), listing, event.params.listingId);
  }
);

// Notify everyone who saved (favorited) a listing when its price is reduced.
exports.notifyOnPriceDrop = onDocumentUpdated(
  "listings/{listingId}",
  async (event) => {
    const before = event.data && event.data.before.data();
    const after = event.data && event.data.after.data();
    if (!before || !after) return;

    // Announce the listing to everyone the FIRST time it becomes public, and
    // never again. becamePublic fires whenever approvalStatus reaches
    // 'approved', which includes every re-approval after an edit — the
    // once-only claim inside broadcastListing() is what stops those from
    // re-buzzing the userbase. broadcastListing() also re-checks that the ad is
    // approved + in stock, so an edit still pending review is not announced early.
    //
    // The old `|| hasBroadcastableChange(before, after)` arm is gone on purpose:
    // it existed to announce edits, which is exactly the spam we removed.
    if (becamePublic(before, after)) {
      await broadcastListing(getFirestore(), after, event.params.listingId);
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
      .limit(1000)
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
    // Config-aware rate, matching the release path. commissionRate() alone
    // ignores config/commission and drifts from what the seller is actually
    // paid.
    // Note: resolved once for the whole cart, so per-category and per-seller
    // overrides in config/commission do not apply on the multi-seller path.
    // computePayoutBreakdown passes both at release time, so a cart spanning
    // sellers with overrides can still drift. Resolving per seller group is
    // the correct fix; harmless while the launch rate is a flat 0%.
    const { rate } = await resolveCommission(db, {});
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
      // A sub-order is COD only if EVERY item in it offers COD; otherwise the
      // whole seller order falls back to online escrow (server-authoritative,
      // so a tampered client can't force COD on a non-COD item).
      let groupCodOk = true;
      // The seller is whoever actually OWNS the listing, never the sellerId the
      // cart claimed. The single-order path already derives it from the listing
      // (listing.userId); this path used the client's value, so a buyer could
      // mint a sub-order naming an arbitrary uid as seller and misdirect the
      // eventual payout. Items whose owner disagrees with the rest of the group
      // are dropped rather than misattributed.
      let trustedSellerId = "";
      for (const it of g.items) {
        const ls = await db.collection("listings").doc(it.listingId).get();
        if (!ls.exists) continue;
        const l = ls.data();
        const owner = l.userId || "";
        if (!owner) continue;
        if (!trustedSellerId) {
          trustedSellerId = owner;
        } else if (owner !== trustedSellerId) {
          continue;
        }
        const status = l.status || (l.isSold ? "sold" : "in_stock");
        if (status !== "in_stock") continue;
        const unitPrice = parsePrice(l.price);
        if (unitPrice <= 0) continue;
        if (l.codAvailable !== true) groupCodOk = false;
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
      if (lineItems.length === 0 || !trustedSellerId) continue;

      sIndex++;
      const effectiveCod = isCod && groupCodOk;
      const totals = computeSellerTotals(lines, {
        isCod: effectiveCod,
        rate,
        freeThreshold: FREE_DELIVERY_THRESHOLD,
      });
      const orderNumber = sellerOrderNumber(masterNumber, sIndex);
      const orderRef = db.collection("orders").doc();
      const unitCount = lineItems.reduce((a, i) => a + i.quantity, 0);
      await orderRef.set({
        masterOrderId: masterId,
        orderNumber,
        sellerId: trustedSellerId,
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
        paymentMethod: effectiveCod ? "cod" : "escrow",
        notes: master.notes || "",
        status: effectiveCod ? "cod_pending" : "pending_payment",
        orderStatus: "pending",
        paymentStatus: effectiveCod ? "unpaid" : "payment_pending",
        createdAt: Timestamp.now(),
      });
      sellerOrderIds.push(orderRef.id);

      // Best-effort: a notification failure must not abort the fan-out and
      // orphan the sub-orders already written for other sellers.
      try {
        await pushToUser(
          db,
          trustedSellerId,
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

    // Every order gets a human-readable reference (PB-1042) from the same
    // sequence the multi-seller fan-out uses, so a number is unique across BOTH
    // checkout paths and can be quoted in support, notifications and the admin
    // Orders tab. Single-listing and offer-accepted orders had none before.
    //
    // Allocated before the validation branches below on purpose: an order that
    // gets voided still needs to be referenceable ("my order PB-1042 failed").
    // Guarded on the field being absent so a redelivered create event cannot
    // burn a second number.
    if (!order.orderNumber) {
      const seq = await nextOrderNumber(db);
      await snap.ref.set({ orderNumber: `PB-${seq}` }, { merge: true });
    }

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
    // A negotiated order claims its price came from an accepted offer. That
    // claim used to be taken on trust: `fromOffer` is a plain client-written
    // boolean, nothing ever loaded the offer, and the orders create rule does
    // not constrain amount — so writing {fromOffer:true, amount:1} against a
    // PKR 500,000 listing skipped every check below and stood. Verify the offer
    // exists, belongs to this buyer and listing, was actually accepted, and
    // that the order copies its agreed amount exactly.
    if (order.fromOffer === true && payable) {
      const offerId = order.offerId ? String(order.offerId) : "";
      let offer = null;
      if (offerId) {
        const offerSnap = await db.collection("offers").doc(offerId).get();
        offer = offerSnap.exists ? offerSnap.data() : null;
      } else if (order.buyerId && order.listingId) {
        // Older app versions do not write offerId. Those clients are still in
        // the wild, so fall back to locating the buyer's own agreed offer for
        // this listing rather than voiding a legitimate order. Still fully
        // validated below — this only changes how the offer is found.
        // Filter by status IN THE QUERY. Applying limit() first and filtering
        // afterwards meant a buyer who haggled repeatedly on one listing could
        // have their agreed offer fall outside the window, voiding a
        // legitimate order.
        const q = await db
          .collection("offers")
          .where("buyerId", "==", order.buyerId)
          .where("listingId", "==", order.listingId)
          .where("status", "in", ["accepted", "ordered"])
          .limit(25)
          .get();
        const candidates = q.docs.map((d) => d.data());
        // Prefer one whose agreed amount matches what the order charged.
        offer =
          candidates.find(
            (o) => (Number(o.agreedAmount) || 0) === Number(order.itemSubtotal)
          ) ||
          candidates[0] ||
          null;
      }
      const agreed = Number(offer && offer.agreedAmount) || 0;
      const offerOk =
        offer &&
        offer.buyerId === order.buyerId &&
        String(offer.listingId || "") === String(order.listingId || "") &&
        ["accepted", "ordered"].indexOf(String(offer.status || "")) !== -1 &&
        agreed > 0 &&
        // Compare the ITEM subtotal, not the order total: the negotiated price
        // covers the product, and the delivery fee is added on top of it.
        Number(order.itemSubtotal) === agreed;

      if (!offerOk) {
        await snap.ref.set(
          { status: "cancelled", voidReason: "invalid_offer" },
          { merge: true }
        );
        return;
      }

      // An agreed offer is single-use. Its status is already 'ordered' by the
      // time this runs (the client sets it in the same transaction that
      // creates the order), so status alone cannot distinguish the first order
      // from a replay — a scripted client could cite the same offerId again
      // and again to keep buying at the negotiated price.
      if (offerId) {
        const prior = await db
          .collection("orders")
          .where("offerId", "==", offerId)
          .limit(2)
          .get();
        const others = prior.docs.filter((d) => d.id !== snap.ref.id);
        if (others.length > 0) {
          await snap.ref.set(
            { status: "cancelled", voidReason: "offer_already_used" },
            { merge: true }
          );
          return;
        }
      }

      // The agreed price is the buyer's to negotiate; the platform's cut is
      // not. Recompute commission and payout from the same config-aware source
      // the release path uses.
      const offerSellerId = offer.sellerId || order.sellerId || "";
      const { rate: offerRate, fixedFee: offerFee } = await resolveCommission(
        db,
        { category: order.category || "", sellerId: offerSellerId }
      );
      // Commission is charged on the product only; the delivery fee passes
      // through to the seller in full, so the payout is computed from the
      // order TOTAL rather than the negotiated item price. Using `agreed` here
      // silently docked the seller the delivery fee on every offer order.
      const offerCommission =
        order.status === "cod_pending"
          ? 0
          : round2(agreed * offerRate + (offerRate > 0 ? offerFee : 0));
      const offerTotal = Number(order.amount) || agreed;
      const offerPayout = round2(offerTotal - offerCommission);

      if (
        order.commission !== offerCommission ||
        order.sellerPayout !== offerPayout ||
        order.sellerId !== offerSellerId
      ) {
        await snap.ref.set(
          {
            commission: offerCommission,
            sellerPayout: offerPayout,
            sellerId: offerSellerId,
          },
          { merge: true }
        );
      }
    }

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
      // Re-validate COD server-side: if the buyer requested COD on a listing
      // that doesn't offer it (tampered client), downgrade to the online escrow
      // flow rather than committing the seller to a COD they never enabled.
      const codDowngrade =
        order.status === "cod_pending" && listing.codAvailable !== true;
      const isCod = order.status === "cod_pending" && !codDowngrade;
      // Use the same config-aware resolver the payout/release path uses.
      // This used to call commissionRate(), which only knows the built-in
      // free-launch schedule and ignores config/commission (category rates,
      // per-seller overrides, admin-set globalRate). The seller was quoted one
      // commission at order time and paid against a different one at release.
      const { rate: orderRate, fixedFee: orderFee } = await resolveCommission(
        db,
        {
          category: listing.category || order.category || "",
          sellerId: listing.userId || order.sellerId || "",
        }
      );
      const commission = isCod
        ? 0
        : round2(itemPrice * orderRate + (orderRate > 0 ? orderFee : 0));
      const sellerPayout = round2(amount - commission);
      sellerId = listing.userId || order.sellerId || "";

      if (
        codDowngrade ||
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
            ...(codDowngrade
              ? {
                  status: "pending_payment",
                  paymentStatus: "payment_pending",
                  paymentMethod: "escrow",
                }
              : {}),
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

    // Log to the activity trail so admins can monitor buyer→seller orders
    // (the multi-seller fan-out logs its own sub-orders separately).
    await writeAudit(db, {
      action: "order_placed",
      entityType: "order",
      entityId: event.params.orderId,
      actorId: order.buyerId || "",
      actorRole: "buyer",
      newStatus: order.status || "pending_payment",
      amount,
      metadata: { sellerId, listingTitle: order.listingTitle || "" },
    });

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
    refIdFromData(data),
    data
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
    const dbo = getFirestore();
    await pushToUser(
      dbo,
      offer.sellerId,
      {
        title: "New offer received",
        body: `${offer.buyerName || "A buyer"} offered Rs ${offer.offerAmount} for "${offer.listingTitle}"`,
      },
      { type: "offer", offerId: event.params.offerId }
    );
    // Log the inquiry to the activity trail for admin monitoring.
    await writeAudit(dbo, {
      action: "offer_made",
      entityType: "offer",
      entityId: event.params.offerId,
      actorId: offer.buyerId || "",
      actorRole: "buyer",
      newStatus: offer.status || "pending",
      amount: Number(offer.offerAmount) || 0,
      metadata: {
        sellerId: offer.sellerId,
        listingId: offer.listingId || "",
        listingTitle: offer.listingTitle || "",
      },
    });
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
// `refId` is the id of the thing the notification is about (order/offer/chat/
// listing/ticket/…); the in-app inbox uses `type` + `refId` to deep-link the
// user straight to it on tap. `data` (optional) carries the full push payload
// so the client can route without a second lookup where possible.
async function recordNotification(db, uid, title, body, type, refId, data) {
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
        data: data || {},
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
  } catch (e) {
    // Non-critical; the push still goes out.
  }
}

// The push `data` payload uses different id keys per notification type
// (orderId, offerId, chatId, …). Pull whichever one is present so the stored
// notification always has a usable `refId` to deep-link from. Previously only
// `offerId` was read, so every order/chat/dispute/payout notification was saved
// with an empty refId and could not be made tappable.
function refIdFromData(data) {
  const d = data || {};
  return (
    d.refId ||
    d.orderId ||
    d.offerId ||
    d.chatId ||
    d.listingId ||
    d.ticketId ||
    d.withdrawalId ||
    d.masterId ||
    ""
  );
}

// Server-side price list for wallet purchases, keyed "type:days". The client
// used to supply its own `amount` and processPurchase debited it verbatim, so
// a crafted purchase document bought a 365-day home-screen banner for Rs 1 —
// and, for type "banner", published attacker-chosen image/title/subtitle via
// the admin SDK, bypassing the can('featured') rule on the banners collection.
// Keep in sync with the packages offered in lib/src/screen_wallet.dart.
const PURCHASE_PRICES = {
  "banner:7": 2000,
  "banner:30": 6000,
};

// Look up the authoritative price. config/pricing may override or extend the
// built-in table without a deploy; anything not listed is not for sale.
async function resolvePurchasePrice(db, type, days) {
  const key = `${type}:${days}`;
  try {
    const snap = await db.collection("config").doc("pricing").get();
    const table = snap.exists ? snap.data() : null;
    if (table && typeof table[key] === "number" && table[key] > 0) {
      return table[key];
    }
  } catch (_) {
    // Fall through to the built-in table.
  }
  return typeof PURCHASE_PRICES[key] === "number" ? PURCHASE_PRICES[key] : null;
}

// Processes a wallet purchase: atomically checks the balance, deducts it, and
// applies the effect (feature a listing / featured business / home banner).
exports.processPurchase = onDocumentCreated("purchases/{id}", async (event) => {
  const p = event.data && event.data.data();
  if (!p || !p.userId) return;

  const db = getFirestore();
  const purchaseRef = event.data.ref;
  const userRef = db.collection("users").doc(p.userId);
  // Clamp the client-supplied benefit window to a sane range so a tiny payment
  // can never buy an absurdly long feature (defence in depth; the price itself
  // is still debited from the buyer's own wallet).
  const days = Math.min(Math.max(1, Number(p.days) || 7), 365);
  const until = Timestamp.fromMillis(Date.now() + days * 86400000);

  // The price is ours to decide, never the client's.
  const amount = await resolvePurchasePrice(db, String(p.type || ""), days);
  if (amount == null) {
    await purchaseRef.set(
      { status: "invalid_price", amount: Number(p.amount) || 0 },
      { merge: true }
    );
    return;
  }

  // A "feature" purchase must name a listing the buyer actually owns.
  if (p.type === "feature" && p.refId) {
    const target = await db.collection("listings").doc(String(p.refId)).get();
    if (!target.exists || target.get("userId") !== p.userId) {
      await purchaseRef.set({ status: "invalid_target" }, { merge: true });
      return;
    }
  }

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

      const userUpdate = { walletBalance: round2(balance - amount) };
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
        // Record what was actually charged, not what the client asked for.
        amount,
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
  } else if (status === "invalid_price" || status === "invalid_target") {
    // Without this the buyer sits on "activating shortly…" forever, because
    // nothing else ever writes back to a rejected purchase.
    await recordNotification(
      db,
      p.userId,
      "Purchase could not be completed",
      "That promotion is no longer available. You have not been charged — " +
        "please try again from the Wallet screen.",
      "purchase",
      purchaseRef.id
    );
  }
});

// Daily job: turn off Featured listings / businesses / banners whose paid
// window (featuredUntil / featuredBusinessUntil / expiresAt) has passed.
// Deleting users/{uid} does not cascade in Firestore, so the private contact
// document would outlive the account. Once the public copy is stripped that
// subcollection is the ONLY copy of the person's email, phone and address, so
// leaving it behind turns account deletion into PII retention. Runs for every
// delete path (admin panel, deletion requests, support tooling).
exports.cleanupDeletedUserPrivate = onDocumentDeleted(
  "users/{userId}",
  async (event) => {
    const db = getFirestore();
    try {
      // recursiveDelete, not just private/: addresses hold a full street
      // address and phone, payoutAccounts hold IBANs and account numbers, and
      // drafts / savedSearches / notifications / fcmTokens / walletTransactions
      // all survive the parent too. Deleting the account has to remove more
      // PII than it leaves behind.
      await db.recursiveDelete(
        db.collection("users").doc(event.params.userId)
      );
    } catch (e) {
      console.error("cleanupDeletedUserPrivate failed:", (e && e.message) || e);
    }
  }
);

// ---------------------------------------------------------------------------
// One-time (self-terminating) backfill: move contact PII off the public user
// document into users/{uid}/private/contact.
//
// users/{uid} is readable by every signed-in user — seller pages need the name
// and rating, and the Stores / Featured Business rails run real list queries
// over the collection — and Firestore rules cannot filter fields on read. So
// an unfiltered collection('users').get() used to return every user's email,
// phone number and home address.
//
// The client already writes new accounts to the private subcollection and
// reads from it with a fallback to these legacy fields, so this sweep is safe
// to run repeatedly and safe to run while older app versions are still live:
// it copies before it clears. Once no document matches, it costs one empty
// query per day.
// ---------------------------------------------------------------------------
exports.migrateUserContactPii = onSchedule(
  { schedule: "every 24 hours", timeoutSeconds: 540, memory: "512MiB" },
  async () => {
    const db = getFirestore();
    // saveUserLocation() writes lat/lng (not latitude/longitude, which only
    // exist on listings) — captured home coordinates, so they belong here.
    const PII = ["email", "phone", "address", "lat", "lng"];

    // Copying is always safe. CLEARING the public copy is gated, because the
    // admin panel still reads users.email / users.phone in several list views
    // and would render blank rows the moment those fields disappear. Migrate
    // the admin reads to the private subcollection, confirm, then set
    // config/privacy { stripPublicPii: true } to close the exposure.
    let strip = false;
    try {
      const cfg = await db.collection("config").doc("privacy").get();
      strip = cfg.exists && cfg.get("stripPublicPii") === true;
    } catch (_) {
      strip = false;
    }

    let cursor = null;
    let moved = 0;

    // Page through the collection rather than loading it all into memory.
    for (let page = 0; page < 200; page++) {
      let q = db.collection("users").orderBy("__name__").limit(300);
      if (cursor) q = q.startAfter(cursor);
      const snap = await q.get();
      if (snap.empty) break;
      cursor = snap.docs[snap.docs.length - 1];

      const batch = db.batch();
      let pending = 0;

      for (const doc of snap.docs) {
        const d = doc.data() || {};
        const carried = {};
        for (const k of PII) {
          if (d[k] !== undefined && d[k] !== null && d[k] !== "") {
            carried[k] = d[k];
          }
        }
        if (Object.keys(carried).length === 0) continue;

        // Copy into the private doc without clobbering anything already
        // written there by a newer client.
        batch.set(
          doc.ref.collection("private").doc("contact"),
          { ...carried, migratedAt: FieldValue.serverTimestamp() },
          { merge: true }
        );
        pending += 1;
        if (strip) {
          const clear = {};
          for (const k of Object.keys(carried)) clear[k] = FieldValue.delete();
          batch.update(doc.ref, clear);
          pending += 1;
        }
        moved++;
      }

      if (pending > 0) await batch.commit();
      if (snap.size < 300) break;
    }

    if (moved > 0) console.log(`migrateUserContactPii: moved ${moved} users`);
  }
);

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
    // Re-validate stock at capture time: an item can sell out between order
    // placement and payment. Don't hold money for an unavailable item — leave
    // the order payable and skip the capture. (Sub-orders carry items[] rather
    // than a listingId and were validated at fan-out.)
    if (order.listingId) {
      const lSnap = await tx.get(
        db.collection("listings").doc(String(order.listingId))
      );
      const lStatus = lSnap.exists
        ? lSnap.get("status") || (lSnap.get("isSold") ? "sold" : "in_stock")
        : "missing";
      if (lStatus !== "in_stock") {
        if (paymentRef) tx.update(paymentRef, { status: "item_unavailable" });
        return;
      }
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

        // round2 to match the refund path: unrounded float addition lets
        // drift accumulate in real seller balances. set/merge rather than
        // update because tx.update throws NOT_FOUND on a missing user doc
        // (deleted account, unmigrated seller), which would roll back the
        // whole release and strand the funds with only a log line.
        tx.set(
          sellerRef,
          { walletBalance: round2(bal + payout) },
          { merge: true }
        );
        // Record the credit in the seller's wallet history so the balance
        // change has a matching line item (reconciliation / UX).
        tx.set(sellerRef.collection("walletTransactions").doc(), {
          type: "credit",
          amount: payout,
          purpose: "Order payout",
          refId: String(act.orderId),
          createdAt: Timestamp.now(),
        });
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
        // partial-then-full refunds can never exceed the order amount (pure,
        // unit-tested in escrow_logic.test.js). Prior refunds accumulate in
        // refundAmount rather than being overwritten.
        const alloc = refundAllocation(
          amount,
          Number(order.refundAmount) || 0,
          Number(act.refundAmount) || 0
        );
        if (alloc.skip) {
          tx.update(actRef, { status: "already_refunded" });
          return;
        }
        const refundValue = alloc.refundValue;
        const newRefundTotal = alloc.newRefundTotal;
        const fullyRefunded = alloc.fullyRefunded;
        const buyerRef = db.collection("users").doc(order.buyerId);
        const buyerSnap = await tx.get(buyerRef);
        const bal = Number(buyerSnap.get("walletBalance")) || 0;

        tx.set(
          buyerRef,
          { walletBalance: round2(bal + refundValue) },
          { merge: true }
        );
        // Mirror the refund in the buyer's wallet history.
        tx.set(buyerRef.collection("walletTransactions").doc(), {
          type: "credit",
          amount: refundValue,
          purpose: fullyRefunded ? "Order refund" : "Partial refund",
          refId: String(act.orderId),
          createdAt: Timestamp.now(),
        });
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
    // One cancellation per order, so the order-keyed id is the right
    // idempotency key here. createOnce ignores ALREADY_EXISTS but lets a real
    // failure propagate rather than reporting a refund that never queued.
    await createOnce(
      db.collection("escrowActions").doc(`cancel_${orderId}`),
      {
        type: "refund",
        orderId,
        by: actorId || "system",
        reason: `cancellation:${req.reasonCode || ""}`,
        source: "cancellation",
        createdAt: Timestamp.now(),
      }
    );
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
// Buyer-initiated refund requests (admin-controlled)
//
// A buyer whose payment is still HELD in escrow can request a refund at any
// stage. Only ADMIN (orders staff) decides — the seller is notified but does
// not approve/reject. On approval this reuses the audited escrow-refund path
// (a deterministic escrowActions/refund_{requestId} doc → onEscrowAction), which
// credits the buyer's wallet. Admin may issue a full or partial refund
// (act.refundAmount). Mirrors the cancellation flow.
// ---------------------------------------------------------------------------

// Approves a refund: issues the (full or partial) escrow refund when money is
// still held, stamps the order + request, writes audit + notifications.
// Idempotent — the deterministic escrowActions id prevents a double refund, and
// the request's processedAt guards the decision trigger from re-running.
async function processRefundApproval(
  db, orderId, order, reqRef, req, actorId
) {
  const orderRef = db.collection("orders").doc(orderId);
  const amount = Number(order.amount) || 0;

  // The order must still be held in escrow — a stale approval can't refund an
  // order whose money has already been released.
  if (order.status !== "in_escrow" || amount <= 0) {
    await orderRef.set(
      { refundRequested: false, refundRequestStatus: "rejected" },
      { merge: true }
    );
    await reqRef.set(
      {
        requestStatus: "rejected",
        refundStatus: "not_required",
        reviewNote: "No held payment to refund.",
        reviewedBy: actorId || "",
        reviewedAt: Timestamp.now(),
        processedAt: Timestamp.now(),
      },
      { merge: true }
    );
    if (order.buyerId) {
      await pushToUser(
        db,
        order.buyerId,
        {
          title: "Refund unavailable",
          body: "This order has no payment held by PakBazar to refund.",
        },
        { type: "order", orderId }
      );
    }
    return;
  }

  const partial = Number(req.refundAmount) || 0; // 0/blank ⇒ full refund.
  const action = {
    type: "refund",
    orderId,
    by: actorId || "admin",
    reason: `refund:${req.reasonCode || ""}`,
    source: "refund",
    createdAt: Timestamp.now(),
  };
  if (partial > 0) action.refundAmount = partial;
  // Keyed per refund request, not per order: with a fixed `refund_{orderId}`
  // id a second legitimate partial refund on the same order could never be
  // queued, and failed silently. refundAllocation already caps the total so
  // successive partials cannot over-refund.
  await createOnce(
    db.collection("escrowActions").doc(`refund_${reqRef.id}`),
    action
  );
  // Leave status/orderStatus to the refund flow; only stamp the request + flag.
  await orderRef.set(
    {
      refundRequested: false,
      refundRequestStatus: "approved",
      refundApprovedAt: Timestamp.now(),
      refundApprovedBy: actorId || "",
    },
    { merge: true }
  );
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

  await writeAudit(db, {
    action: "refund_approved",
    entityType: "order",
    entityId: orderId,
    actorId: actorId || "",
    actorRole: "admin",
    previousStatus: order.orderStatus || order.status || "",
    newStatus: "refund_approved",
    amount: partial > 0 ? partial : amount,
    reason: req.reasonCode || "",
  });

  if (order.buyerId) {
    await pushToUser(
      db,
      order.buyerId,
      {
        title: "Refund approved",
        body: "Your refund is being credited to your PakBazar wallet.",
      },
      { type: "order", orderId }
    );
  }
  if (order.sellerId) {
    await pushToUser(
      db,
      order.sellerId,
      {
        title: "Order refunded",
        body: `A refund was approved for "${order.listingTitle || orderId}".`,
      },
      { type: "order", orderId }
    );
  }
}

// A buyer filed a refund request → validate + route to admin review. Refunds
// are only meaningful while the payment is held, so non-escrow orders are
// auto-rejected. There is no auto-approval — admin always decides.
exports.onRefundRequestCreated = onDocumentCreated(
  "orders/{orderId}/refundRequests/{requestId}",
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
          reviewNote: "Order not found.",
          processedAt: Timestamp.now(),
        },
        { merge: true }
      );
    }
    const order = oSnap.data();

    if (order.status !== "in_escrow" || (Number(order.amount) || 0) <= 0) {
      await reqRef.set(
        {
          requestStatus: "rejected",
          adminDecision: "auto",
          refundStatus: "not_required",
          reviewNote: "This order has no held payment to refund.",
          reviewedAt: Timestamp.now(),
          processedAt: Timestamp.now(),
        },
        { merge: true }
      );
      if (order.buyerId) {
        await pushToUser(
          db,
          order.buyerId,
          {
            title: "Refund unavailable",
            body: "This order has no payment held by PakBazar to refund.",
          },
          { type: "order", orderId }
        );
      }
      return;
    }

    // Flag the order so both apps can show the pending-request state.
    await orderRef.set(
      {
        refundRequested: true,
        refundRequestId: requestId,
        refundRequestStatus: "pending",
      },
      { merge: true }
    );
    await writeAudit(db, {
      action: "refund_requested",
      entityType: "order",
      entityId: orderId,
      actorId: req.buyerId || "",
      actorRole: "buyer",
      previousStatus: order.orderStatus || order.status || "",
      newStatus: "refund_requested",
      reason: req.reasonCode || "",
    });
    await notifyAdmins(
      db,
      {
        title: "Refund requested",
        body: `Order "${
          order.listingTitle || orderId
        }" has a pending refund request.`,
      },
      { type: "order", orderId }
    );
    if (order.sellerId) {
      await pushToUser(
        db,
        order.sellerId,
        {
          title: "Refund requested",
          body: `${order.buyerName || "The buyer"} requested a refund on "${
            order.listingTitle || "an order"
          }". PakBazar is reviewing it.`,
        },
        { type: "order", orderId }
      );
    }
    if (order.buyerId) {
      await pushToUser(
        db,
        order.buyerId,
        {
          title: "Request received",
          body: "Your refund request has been sent to PakBazar for review.",
        },
        { type: "order", orderId }
      );
    }
  }
);

// An admin decided a pending refund request (or the buyer withdrew it). Apply
// the outcome. Guards against loops via processedAt.
exports.onRefundRequestDecision = onDocumentUpdated(
  "orders/{orderId}/refundRequests/{requestId}",
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
      await processRefundApproval(
        db, orderId, order, reqRef, after, after.reviewedBy || ""
      );
      return;
    }

    if (after.requestStatus === "rejected") {
      await orderRef.set(
        {
          refundRequested: false,
          refundRequestStatus: "rejected",
          refundDecisionNote: after.reviewNote || "",
        },
        { merge: true }
      );
      await reqRef.set({ processedAt: Timestamp.now() }, { merge: true });
      await writeAudit(db, {
        action: "refund_rejected",
        entityType: "order",
        entityId: orderId,
        actorId: after.reviewedBy || "",
        actorRole: "admin",
        reason: after.reviewNote || "",
      });
      const oSnap = await orderRef.get();
      const order = oSnap.exists ? oSnap.data() : {};
      if (order.buyerId) {
        await pushToUser(
          db,
          order.buyerId,
          {
            title: "Refund declined",
            body: after.reviewNote
              ? `Your refund request was declined: ${after.reviewNote}`
              : "Your refund request was declined.",
          },
          { type: "order", orderId }
        );
      }
      return;
    }

    if (after.requestStatus === "withdrawn") {
      await orderRef.set(
        {
          refundRequested: false,
          refundRequestStatus: "withdrawn",
        },
        { merge: true }
      );
      await reqRef.set({ processedAt: Timestamp.now() }, { merge: true });
      await writeAudit(db, {
        action: "refund_withdrawn",
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

  await createOnce(
    db.collection("escrowActions").doc(`return_${orderId}`),
    {
      type: "refund",
      orderId,
      by: actorId || "system",
      reason: `return:${req.reasonCode || ""}`,
      source: "return",
      resultOrderStatus: "returned",
      createdAt: Timestamp.now(),
    }
  );
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

    // A confirmation counts only if the buyer wrote it. The rules now pin
    // buyerConfirmedBy to the authenticated writer, and this is the server-side
    // half of the same check: without it a seller who reached the confirmation
    // fields by any route would satisfy the release-eligibility block below and
    // unlock their own payout. Writes made by this function itself carry the
    // buyerId, so they still pass.
    const confirmedBy = after.buyerConfirmedBy || "";
    const confirmedByBuyer =
      confirmedBy === "" || confirmedBy === (after.buyerId || before.buyerId);

    const nowConfirmed =
      confirmedByBuyer &&
      ((after.orderStatus === "buyer_confirmed" &&
        before.orderStatus !== "buyer_confirmed") ||
        (after.buyerConfirmed === true && before.buyerConfirmed !== true));

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

    // Buyer-facing fulfillment notifications (seller advanced the order). Each
    // step gets its own clear title so the buyer sees exactly where their order
    // is at a glance. For a multi-seller order each sub-order is one package, so
    // name the package so the buyer knows which shipment moved.
    if (after.orderStatus !== before.orderStatus && after.buyerId) {
      const isPkg = !!after.masterOrderId;
      const pkg = after.orderNumber ? ` ${after.orderNumber}` : "";
      const courier = after.courierName ? ` via ${after.courierName}` : "";
      const track = after.trackingNumber
        ? ` (tracking ${after.trackingNumber})`
        : "";
      const steps = {
        accepted: {
          title: "Order accepted",
          body: isPkg
            ? `Package${pkg} was accepted by the seller.`
            : "The seller accepted your order and will prepare it for dispatch.",
        },
        processing: {
          title: "Order being prepared",
          body: isPkg
            ? `Package${pkg} is being prepared for dispatch.`
            : "Your order is being prepared for dispatch.",
        },
        shipped: {
          title: "Order shipped",
          body: isPkg
            ? `Package${pkg} has been dispatched${courier}${track}.`
            : `Your order has been dispatched${courier}${track}.`,
        },
        delivered: {
          title: "Order delivered",
          body: isPkg
            ? `Package${pkg} is marked delivered — please confirm once you've received and checked it.`
            : "Your order is marked delivered — please confirm once you've received and checked it.",
        },
      };
      const step = steps[after.orderStatus];
      if (step) {
        await pushToUser(
          db,
          after.buyerId,
          { title: step.title, body: step.body },
          { type: "order", orderId }
        );
        // Log the fulfillment step to the activity trail so admins can watch
        // the full order lifecycle (accepted → dispatched → delivered).
        await writeAudit(db, {
          action: `order_${after.orderStatus}`,
          entityType: "order",
          entityId: orderId,
          actorId: after.sellerId || "",
          actorRole: "seller",
          previousStatus: before.orderStatus || "",
          newStatus: after.orderStatus || "",
          amount: Number(after.amount) || 0,
          metadata: {
            buyerId: after.buyerId || "",
            courierName: after.courierName || "",
            trackingNumber: after.trackingNumber || "",
          },
        });
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
      tx.set(userRef, { walletBalance: round2(bal - amount) }, { merge: true });
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

    const outcome = await db.runTransaction(async (tx) => {
      const wSnap = await tx.get(wRef);
      if (!wSnap.exists) {
        tx.update(actRef, { status: "missing" });
        return null;
      }
      const w = wSnap.data();
      if (w.status !== "processing") {
        tx.update(actRef, { status: "not_processing" });
        return null;
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
        tx.set(userRef, { walletBalance: round2(bal + amount) }, { merge: true });
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
        return null;
      }

      tx.update(actRef, { status: "done", processedAt: Timestamp.now() });
      return { type: act.type, amount, userId: w.userId || "" };
    });

    // Post-commit: tell the seller their payout was paid or rejected (this was
    // previously silent), and log it to the activity trail for admins.
    if (outcome && outcome.userId) {
      const paid = outcome.type === "paid";
      await pushToUser(
        db,
        outcome.userId,
        {
          title: paid ? "Withdrawal paid" : "Withdrawal rejected",
          body: paid
            ? `Your withdrawal of Rs ${outcome.amount} has been paid out.`
            : `Your withdrawal of Rs ${outcome.amount} was rejected and refunded to your wallet.`,
        },
        { type: "payout", withdrawalId: act.withdrawalId }
      );
      await writeAudit(db, {
        action: paid ? "withdrawal_paid" : "withdrawal_rejected",
        entityType: "withdrawal",
        entityId: act.withdrawalId,
        actorId: act.by || "admin",
        actorRole: "admin",
        newStatus: paid ? "paid" : "rejected",
        amount: outcome.amount,
        metadata: { userId: outcome.userId },
      });
    }
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

// ---------------------------------------------------------------------------
// Ludo — server-side dice.
//
// The dice used to be generated on the phone, so a modified client could simply
// claim a six. It is now generated here with crypto.randomInt (not Math.random,
// which is predictable from prior output) and written by the Admin SDK, and
// firestore.rules forbids any client from writing a non-null dice value. A
// player can consume a roll; nobody can invent one.
//
// The whole thing runs in a transaction: the turn check, the pending-roll check
// and the write have to be one atomic step, or two taps in the same instant
// could both pass the check and roll twice.
// ---------------------------------------------------------------------------
//
// ONE INSTANCE IS KEPT WARM. A cold start on this function measured 7.6
// SECONDS against ~390ms warm, and it lands on whoever rolls first — the worst
// possible person to make wait. The lobby also sends a warming request when it
// opens, which covers anybody who arrives that way, but a player deep-linked
// straight into a game skips the lobby entirely. This is the only function in
// the project that a person waits on with the screen frozen, so it is the only
// one worth paying to keep resident.
exports.ludoRoll = onCall({ minInstances: 1, memory: "256MiB" }, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to play.");
  const roomId = request.data && request.data.roomId;
  if (!roomId || typeof roomId !== "string") {
    throw new HttpsError("invalid-argument", "roomId is required.");
  }

  const db = getFirestore();
  const ref = db.collection("ludoRooms").doc(roomId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "That game is over.");
    const room = snap.data() || {};
    if (room.status !== "playing") {
      throw new HttpsError("failed-precondition", "The game has not started.");
    }
    const state = room.state;
    if (!ludo.isSeatToMove(state, room.seats, uid)) {
      throw new HttpsError("permission-denied", "It is not your turn.");
    }
    // Rolling again before playing the last roll would let a player fish for a
    // six. The client clears `dice` when it applies a move.
    if (ludo.hasPendingRoll(state)) {
      throw new HttpsError("failed-precondition", "Play your roll first.");
    }

    const dice = crypto.randomInt(1, 7); // uniform 1..6, unpredictable
    const outcome = ludo.applyRoll(state, dice);

    tx.update(ref, {
      state: outcome.state,
      updatedAt: Timestamp.now(),
    });
    // Deliberately returns NOTHING. Returning the dice as a number made
    // cloud_functions_web throw "Int64 accessor not supported by dart2js"
    // while decoding the reply — even for a client that discarded it. The
    // result reaches every player through the document instead, which is where
    // it has to go anyway.
    return null;
  });
});

// ---------------------------------------------------------------------------
// Ludo — bot seats and abandoned games.
//
// Two problems that made the game not really playable:
//
//  1. A player who closed the app mid-turn froze the board FOREVER for everyone
//     else. Nothing in the client could fix that: the abandoned device is the
//     only one the rules let write, and it is gone.
//  2. There was no way to play alone.
//
// Both are the same job — something has to take a turn on behalf of a seat that
// is not going to take it itself — so they share one code path.
// ---------------------------------------------------------------------------

const LUDO_TURN_SECONDS = 45; // how long a player has before the turn is taken
const LUDO_BOT_PREFIX = "bot:";

function ludoSeatIsBot(seats, colour) {
  return String((seats || {})[colour] || "").startsWith(LUDO_BOT_PREFIX);
}

/**
 * Plays one turn for `colour`: rolls, and plays the best move if there is one.
 * Returns the new state, or null when there was nothing to do.
 */
function ludoPlayOneTurn(state) {
  const colour = state.players[state.turn];
  const dice = crypto.randomInt(1, 7);
  const rolled = ludo.applyRoll(state, dice);
  if (rolled.moves.length === 0) return rolled.state; // turn already handed on
  const move = ludo.chooseBotMove(colour, rolled.moves);
  return ludo.applyMove(rolled.state, move);
}

/**
 * Takes the turn whenever the seat to move belongs to a bot.
 *
 * Triggered on the room document rather than scheduled, so a bot answers within
 * a second or two of its turn arriving. Guarded against recursion: it only acts
 * when the CURRENT seat is a bot, and each write advances the turn or the dice,
 * so the chain terminates.
 */
exports.ludoBotTurn = onDocumentWritten("ludoRooms/{roomId}", async (event) => {
  const after = event.data && event.data.after && event.data.after.data();
  if (!after || after.status !== "playing") return;
  const state = after.state;
  if (!state || !Array.isArray(state.players)) return;
  if (ludo.isDecided(state)) return;

  const colour = state.players[state.turn];
  if (!ludoSeatIsBot(after.seats, colour)) return;
  // A pending dice means a human is mid-turn; bots never leave one parked.
  if (ludo.hasPendingRoll(state)) return;

  const db = getFirestore();
  const ref = db.collection("ludoRooms").doc(event.params.roomId);
  // A short pause so the board does not jump — a bot that moves instantly reads
  // as a glitch rather than an opponent.
  await new Promise((r) => setTimeout(r, 900));

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const room = snap.data() || {};
    const fresh = room.state;
    // Re-check inside the transaction: a human may have moved meanwhile.
    if (!fresh || room.status !== "playing") return;
    if (ludo.isDecided(fresh)) return;
    const c = fresh.players[fresh.turn];
    if (!ludoSeatIsBot(room.seats, c)) return;
    if (ludo.hasPendingRoll(fresh)) return;

    const next = ludoPlayOneTurn(fresh);
    tx.update(ref, {
      state: next,
      status: ludo.isDecided(next) ? "finished" : "playing",
      updatedAt: Timestamp.now(),
    });
  });
});

/**
 * Sweeps games whose player has walked away.
 *
 * Runs every minute. Any game still "playing" whose last change is older than
 * LUDO_TURN_SECONDS has its turn taken automatically, so the board never
 * freezes because somebody closed the app. This is the only mechanism that can
 * do it — the rules only let the absent player write, and they are gone.
 */
exports.ludoSweepStuckGames = onSchedule("every 1 minutes", async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromMillis(
    Date.now() - LUDO_TURN_SECONDS * 1000
  );
  const stuck = await db
    .collection("ludoRooms")
    .where("status", "==", "playing")
    .where("updatedAt", "<", cutoff)
    .limit(50)
    .get();

  for (const doc of stuck.docs) {
    const room = doc.data() || {};
    const state = room.state;
    if (!state || !Array.isArray(state.players)) continue;
    if (ludo.isDecided(state)) continue;
    try {
      // Play the absent player's turn for them rather than skipping it, so a
      // disconnected player is not simply punished out of the game.
      const next = ludoPlayOneTurn(state);
      await doc.ref.update({
        state: next,
        status: ludo.isDecided(next) ? "finished" : "playing",
        updatedAt: Timestamp.now(),
        autoPlayedAt: Timestamp.now(),
      });
    } catch (err) {
      console.error("ludoSweepStuckGames", doc.id, err);
    }
  }
});

/**
 * Rolls in response to a request document.
 *
 * The callable above works on Android and iOS but its reply cannot be decoded
 * by dart2js — a number in the response throws "Int64 accessor not supported"
 * on web. Rather than tune the payload and hope, the client now asks for a roll
 * by writing a tiny document, and the answer arrives through the game state it
 * is already watching. One transport, every platform, no reply to decode.
 *
 * The callable stays deployed for app versions already in the wild.
 */
exports.ludoRollRequested = onDocumentCreated(
  "ludoRooms/{roomId}/rollRequests/{reqId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const req = snap.data() || {};
    const uid = req.userId;
    const db = getFirestore();
    const ref = db.collection("ludoRooms").doc(event.params.roomId);

    try {
      await db.runTransaction(async (tx) => {
        const roomSnap = await tx.get(ref);
        if (!roomSnap.exists) return;
        const room = roomSnap.data() || {};
        if (room.status !== "playing") return;
        const state = room.state;
        // The same three guards as the callable. Rules already check the turn,
        // but a trigger runs with admin rights so it re-checks for itself.
        if (!ludo.isSeatToMove(state, room.seats, uid)) return;
        if (ludo.hasPendingRoll(state)) return;

        const dice = crypto.randomInt(1, 7);
        const outcome = ludo.applyRoll(state, dice);
        tx.update(ref, {
          state: outcome.state,
          updatedAt: Timestamp.now(),
        });
      });
    } catch (err) {
      console.error("ludoRollRequested", event.params.roomId, err);
    } finally {
      // The request is a doorbell, not a record. Leaving it would let the same
      // request be replayed and would grow the room without bound.
      await snap.ref.delete().catch(() => {});
    }
  }
);

// Server-rendered ad pages + sitemap. Kept in its own module because it is the
// only part of the backend that renders HTML, and it must never share code
// paths with anything that can read a phone number.
const seo = require("./seo");
exports.adPage = seo.adPage;
exports.sitemapXml = seo.sitemapXml;

// ---------------------------------------------------------------------------
// Ludo coins.
//
// PLAY MONEY, kept structurally apart from the real thing. This app holds
// actual funds — walletBalance, escrow on live orders, withdrawals — and a
// second currency beside that is a hazard, so coins live under
// users/{uid}/game/profile and never touch the wallet. There is no path from
// coins to money: they cannot be bought, transferred or cashed out.
//
// The balance is written ONLY here, with the Admin SDK. firestore.rules makes
// the profile read-only to its owner, because a player who could write their
// own balance would.
// ---------------------------------------------------------------------------
const economy = require("./game_economy");

const gameProfileRef = (uid) =>
  getFirestore().collection("users").doc(uid).collection("game").doc("profile");

/**
 * Requests are a doorbell, not a record: the client writes one, this reads it,
 * acts, and deletes it.
 *
 * A callable would be the obvious shape, but cloud_functions_web throws
 * decoding a numeric reply under dart2js ("Int64 accessor not supported"), which
 * is what broke the dice roll — so the whole app talks to the server this way
 * now and carries no cloud_functions dependency.
 */
exports.gameRequestCreated = onDocumentCreated(
  "users/{uid}/gameRequests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const uid = event.params.uid;
    const type = snap.data().type;
    const db = getFirestore();
    const ref = gameProfileRef(uid);

    try {
      await db.runTransaction(async (tx) => {
        const doc = await tx.get(ref);
        const p = doc.exists ? doc.data() : {};
        const coins = Number(p.coins) || economy.STARTING_COINS;

        if (type === "daily") {
          const r = economy.resolveDaily(p, Date.now());
          if (!r.canClaim) return;
          tx.set(
            ref,
            {
              coins: coins + r.coins,
              streak: r.streak,
              lastDailyAt: Date.now(),
              lastAward: { kind: "daily", coins: r.coins, streak: r.streak },
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          return;
        }

        if (type === "chest") {
          const chests = Number(p.chests) || 0;
          if (chests < 1) return;
          // Randomness on the server. A client-supplied roll would simply be
          // replayed until it produced the rarest tier.
          const won = economy.rollChest(Math.random());
          tx.set(
            ref,
            {
              coins: coins + won,
              chests: chests - 1,
              lastAward: { kind: "chest", coins: won },
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          return;
        }
      });
    } catch (err) {
      console.error("gameRequestCreated failed", uid, type, err);
    } finally {
      // Always clear the doorbell. Leaving it would let the trigger re-fire on
      // any later write and pay the same reward twice.
      await snap.ref.delete().catch(() => {});
    }
  }
);

/**
 * Collects the entry stake when a staked table starts.
 *
 * Coins are only ever written here, so the pot has to be built server-side. The
 * client picks a stake and the rules stop anyone joining a table they cannot
 * afford, but the money itself moves at the moment play begins — a table that
 * never starts must never cost anybody anything.
 *
 * `stakeCollectedAt` makes this idempotent. This trigger fires on every write to
 * the room, and charging the table twice would be unrecoverable.
 */
exports.ludoCollectStakes = onDocumentWritten("ludoRooms/{roomId}", async (event) => {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (!after || after.status !== "playing") return;
  if (before && before.status === "playing") return;
  if (after.stakeCollectedAt) return;
  const stake = Number(after.stake) || 0;
  if (stake <= 0) return;

  const db = getFirestore();
  const seats = after.seats || {};
  const contributions = {};
  let pot = 0;

  for (const [colour, uid] of Object.entries(seats)) {
    if (typeof uid !== "string" || uid.startsWith(LUDO_BOT_PREFIX)) continue;
    try {
      const paid = await db.runTransaction(async (tx) => {
        const ref = gameProfileRef(uid);
        const doc = await tx.get(ref);
        const p = doc.exists ? doc.data() : {};
        const balance = Number(p.coins);
        const have = Number.isFinite(balance) ? balance : economy.STARTING_COINS;
        // Clamped: somebody can join a table they can afford and spend the
        // coins elsewhere before it begins. Collecting less beats a negative
        // balance.
        const take = economy.collectStake(stake, have);
        if (take <= 0) return 0;
        tx.set(ref, { coins: have - take }, { merge: true });
        return take;
      });
      if (paid > 0) {
        contributions[colour] = paid;
        pot += paid;
      }
    } catch (err) {
      console.error("ludoCollectStakes", event.params.roomId, uid, err);
    }
  }

  await event.data.after.ref
    .set(
      { pot, stakeContributions: contributions, stakeCollectedAt: Timestamp.now() },
      { merge: true }
    )
    .catch(() => {});
});

/**
 * Pays out when a Ludo room finishes.
 *
 * Runs on the room rather than trusting a client to report its own result, and
 * writes an `awardedAt` marker so a later write to the same document cannot pay
 * the table a second time.
 */
exports.ludoAwardCoins = onDocumentWritten("ludoRooms/{roomId}", async (event) => {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (!after || after.status !== "finished") return;
  if (before && before.status === "finished") return; // already handled
  if (after.coinsAwardedAt) return;

  const state = after.state || {};
  const seats = after.seats || {};
  const winners = state.winners || [];
  if (winners.length === 0) return;

  const humanPlayers = Object.values(seats).filter(
    (v) => typeof v === "string" && !v.startsWith(LUDO_BOT_PREFIX)
  ).length;

  // Anyone who walked out is treated as never having been here: no reward, no
  // share of the pot, no leaderboard row. A game you left is not a game you
  // played, and paying for it would make quitting a losing position free.
  const abandoned = new Set(
    Array.isArray(after.abandonedBy) ? after.abandonedBy : []
  );

  // In a team game the whole winning SIDE is paid, not just whoever came home
  // first — the same rule the win banner shows the players.
  const winningColours = new Set();
  if (state.teams === true) {
    const w = winners[0];
    winningColours.add(w);
    if (ludo.PARTNERS[w]) winningColours.add(ludo.PARTNERS[w]);
  } else {
    winningColours.add(winners[0]);
  }

  const db = getFirestore();
  const writes = [];
  for (const [colour, uid] of Object.entries(seats)) {
    if (typeof uid !== "string" || uid.startsWith(LUDO_BOT_PREFIX)) continue;
    if (abandoned.has(uid)) continue;
    const won = winningColours.has(colour);
    const coins = economy.winReward({
      won,
      humanPlayers,
      mode: state.mode,
    });
    writes.push(
      db.runTransaction(async (tx) => {
        const ref = gameProfileRef(uid);
        const doc = await tx.get(ref);
        const p = doc.exists ? doc.data() : {};
        const wins = (Number(p.gamesWon) || 0) + (won ? 1 : 0);
        // A chest every WINS_PER_CHEST wins, granted at the moment the counter
        // crosses the boundary.
        const earnedChest =
          won && wins % economy.WINS_PER_CHEST === 0 ? 1 : 0;
        tx.set(
          ref,
          {
            coins: (Number(p.coins) || economy.STARTING_COINS) + coins,
            gamesPlayed: (Number(p.gamesPlayed) || 0) + 1,
            gamesWon: wins,
            chests: (Number(p.chests) || 0) + earnedChest,
            lastAward: { kind: won ? "win" : "played", coins },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      })
    );
  }

  // The pot goes to the winning side, split evenly. splitPot gives the
  // remainder to the first winner rather than dropping it, so a pot of 101
  // between two partners pays 51 and 50 and no coin is destroyed.
  const pot = Number(after.pot) || 0;
  const potWinners = [...winningColours]
    .map((c) => seats[c])
    .filter(
      (uid) =>
        typeof uid === "string" &&
        !uid.startsWith(LUDO_BOT_PREFIX) &&
        !abandoned.has(uid)
    );
  const shares = economy.splitPot(pot, potWinners.length || 1);
  const potFor = {};
  potWinners.forEach((uid, i) => {
    potFor[uid] = shares[i] || 0;
  });

  const week = economy.weekIdOf(Date.now());
  for (const [colour, uid] of Object.entries(seats)) {
    if (typeof uid !== "string" || uid.startsWith(LUDO_BOT_PREFIX)) continue;
    if (abandoned.has(uid)) continue;
    const won = winningColours.has(colour);
    const share = potFor[uid] || 0;
    const earned =
      economy.winReward({ won, humanPlayers, mode: state.mode }) + share;
    writes.push(
      (async () => {
        if (share > 0) {
          await db
            .runTransaction(async (tx) => {
              const ref = gameProfileRef(uid);
              const doc = await tx.get(ref);
              const p = doc.exists ? doc.data() : {};
              const have = Number(p.coins);
              tx.set(
                ref,
                {
                  coins:
                    (Number.isFinite(have) ? have : economy.STARTING_COINS) +
                    share,
                },
                { merge: true }
              );
            })
            .catch((err) => console.error("pot payout", uid, err));
        }
        // Weekly standings. Kept per week rather than all-time so a player who
        // starts today is not permanently behind somebody who started in
        // March — an all-time board stops being a competition very quickly.
        await db
          .doc(`leaderboards/${week}/players/${uid}`)
          .set(
            {
              userId: uid,
              name: (after.names || {})[colour] || "Player",
              coinsWon: FieldValue.increment(earned),
              wins: FieldValue.increment(won ? 1 : 0),
              games: FieldValue.increment(1),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          )
          .catch((err) => console.error("leaderboard", uid, err));
      })()
    );
  }

  await Promise.allSettled(writes);
  await event.data.after.ref
    .set({ coinsAwardedAt: Timestamp.now() }, { merge: true })
    .catch(() => {});
});

/**
 * Deletes rooms that have stopped being useful.
 *
 * Nothing has ever deleted a Ludo room, so every game ever played is still in
 * the collection along with its chat, its emoji, its roll requests and its
 * voice signalling. That is fine at 26 rooms and is not fine later — and the
 * lobby query reads this collection.
 *
 * recursiveDelete because Firestore does NOT cascade: deleting the room
 * document alone would orphan every subcollection under it, leaving data that
 * nothing can reach and nothing will ever clean up.
 *
 * Deliberately conservative. It never touches a room that is playing, never
 * touches one with no timestamp, and is capped per run — a sweep that deletes
 * the wrong thing cannot be undone.
 */
const LUDO_SWEEP_LIMIT = 200;

exports.ludoSweepOldRooms = onSchedule("every 24 hours", async () => {
  const db = getFirestore();
  const now = Date.now();
  let deleted = 0;
  const byReason = {};

  for (const status of ["finished", "waiting"]) {
    const snap = await db
      .collection("ludoRooms")
      .where("status", "==", status)
      .limit(LUDO_SWEEP_LIMIT)
      .get();

    for (const doc of snap.docs) {
      if (deleted >= LUDO_SWEEP_LIMIT) break;
      const { expired, reason } = ludo.ludoRoomExpiry(doc.data() || {}, now);
      if (!expired) continue;
      try {
        await db.recursiveDelete(doc.ref);
        deleted++;
        byReason[reason] = (byReason[reason] || 0) + 1;
      } catch (err) {
        // One bad room must not stop the sweep.
        console.error("ludoSweepOldRooms", doc.id, err);
      }
    }
  }

  // Logged even when zero, so the absence of deletions is distinguishable from
  // the job not having run.
  console.log(
    `ludoSweepOldRooms deleted ${deleted} room(s) ${JSON.stringify(byReason)}`
  );
});
