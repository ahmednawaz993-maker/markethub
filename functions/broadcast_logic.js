"use strict";

// Pure, unit-testable logic for the new-listing broadcast. No Firebase needed.
//   Run:  cd functions && node broadcast_logic.test.js
//
// Every opted-in device is subscribed to ONE FCM topic, so announcing a new
// listing is a single send regardless of how many users PakBazar has. The
// alternative (looping the users collection) would cost a read + a write + a
// send per user per listing.

// The topic every opted-in device is subscribed to.
const NEW_LISTING_TOPIC = "new_listings";

// Longest listing title we put in a notification body; anything longer is
// ellipsised so the alert stays readable on a lock screen.
const MAX_TITLE_CHARS = 60;

// Every device also joins a topic naming its owner. Nothing is ever sent to
// these topics — they exist only so a broadcast can EXCLUDE someone.
//
// FCM has no "send to topic except these devices", but it does support boolean
// conditions over topic membership, so the seller's own topic is negated at
// send time. This has to happen server-side: when the app is backgrounded the
// OS renders a notification-payload message before any app code runs, so
// suppressing it in the client could never hide the tray notification.
function userTopic(uid) {
  const safe = String(uid || "").replace(/[^a-zA-Z0-9-_.~%]/g, "");
  return safe ? `user_${safe}` : "";
}

// Where one listing's broadcast should go: everyone subscribed, minus the
// seller's own devices. Falls back to the plain topic when the seller is
// unknown, since there is then nobody to exclude.
function broadcastTarget(sellerId) {
  const own = userTopic(sellerId);
  if (!own) return { topic: NEW_LISTING_TOPIC };
  return {
    condition: `'${NEW_LISTING_TOPIC}' in topics && !('${own}' in topics)`,
  };
}

function truncate(s, max) {
  const str = String(s == null ? "" : s).trim();
  return str.length <= max ? str : `${str.slice(0, max - 1).trimEnd()}…`;
}

// A listing is worth broadcasting once it is publicly visible AND buyable:
// pending/rejected ads are not public yet, and an out-of-stock ad is not worth
// waking every phone in the country for. Same gate the previous
// interest-matched alerts used.
function shouldBroadcastListing(listing) {
  if (!listing) return false;
  const approval = String(listing.approvalStatus || "");
  if (approval === "pending" || approval === "rejected") return false;
  if (listing.status && listing.status !== "in_stock") return false;
  return true;
}

// True when an update just made a listing public for the first time. This is
// the normal path: the seller posts (pending), an admin approves. A listing
// created already-approved is caught by the create trigger instead.
function becamePublic(before, after) {
  if (!before || !after) return false;
  return (
    before.approvalStatus !== "approved" && after.approvalStatus === "approved"
  );
}

// The listing fields a broadcast is about. Deliberately an ALLOW-list, not a
// deny-list: the app bumps a `views` counter every time anyone opens an ad
// (screen_ad_details.dart), so "announce any field change" would push to the
// entire userbase on every page view — and because a push drives people to
// open the ad, that loop feeds itself. A deny-list would work until the next
// counter field is added and silently reintroduces the same bug.
//
// Add a field here to make edits to it announce; nothing else triggers.
const BROADCAST_FIELDS = [
  "title",
  "price",
  "description",
  "category",
  "subcategory",
  "city",
  "location",
  "condition",
  "unit",
  "images",
  "imageUrl",
  "status",
  "deliveryAvailable",
  "deliveryFee",
  "codAvailable",
  "negotiable",
  "attributes",
];

// Order-independent, Timestamp-safe copy of a value, so two structurally equal
// listings always produce the same signature.
function stableValue(v) {
  if (v == null) return null;
  if (Array.isArray(v)) return v.map(stableValue);
  if (typeof v === "object") {
    if (typeof v.toMillis === "function") return v.toMillis(); // Timestamp
    const out = {};
    for (const k of Object.keys(v).sort()) out[k] = stableValue(v[k]);
    return out;
  }
  return v;
}

// Deterministic string identifying the broadcastable content of a listing.
// Two listings with the same source have nothing new to announce.
function broadcastSignatureSource(listing) {
  const l = listing || {};
  return JSON.stringify(BROADCAST_FIELDS.map((f) => stableValue(l[f])));
}

// Did an edit change anything worth announcing? False for view/favourite
// counter bumps, moderation bookkeeping and other invisible writes.
function hasBroadcastableChange(before, after) {
  return broadcastSignatureSource(before) !== broadcastSignatureSource(after);
}

// Notification copy for a broadcast. The category leads the title so the alert
// is skimmable ("New in Motors"), and the body carries the what/how much/where.
// `kind` is 'new' for a listing's first announcement, 'updated' for every
// announcement after that.
function broadcastMessage(listing, kind) {
  const l = listing || {};
  const category = String(l.category || "").trim();
  const city = String(l.city || "").trim();
  const price = String(l.price == null ? "" : l.price).trim();
  const name = truncate(l.title || "New listing", MAX_TITLE_CHARS) || "New listing";

  const updated = kind === "updated";
  const lead = updated ? "Updated in" : "New in";
  const title = category
    ? `${lead} ${category}`
    : updated
      ? "Updated on PakBazar"
      : "New on PakBazar";
  let body = price ? `${name} — Rs ${price}` : name;
  if (city) body += ` in ${city}`;
  return { title, body };
}

// Whether this user's devices belong on the broadcast topic. `newListing` is
// the master opt-out, `push` keeps alerts in the in-app inbox only, and `mode`
// is the legacy frequency setting — only its explicit 'off' silences the user
// (the 'daily'/'weekly' digests were never actually built, so treating them as
// off would leave those users permanently silent).
function wantsBroadcast(userData) {
  const prefs = (userData || {}).notifPrefs || {};
  if (prefs.newListing === false) return false;
  if (prefs.push === false) return false;
  if (prefs.mode === "off") return false;
  return true;
}

module.exports = {
  NEW_LISTING_TOPIC,
  MAX_TITLE_CHARS,
  BROADCAST_FIELDS,
  userTopic,
  broadcastTarget,
  truncate,
  shouldBroadcastListing,
  becamePublic,
  broadcastSignatureSource,
  hasBroadcastableChange,
  broadcastMessage,
  wantsBroadcast,
};
