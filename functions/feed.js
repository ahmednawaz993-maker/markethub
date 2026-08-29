"use strict";

// The browse feed, served from the CDN instead of from Firestore.
//
// WHY. Every user on the home screen held a live Firestore listener on the
// newest sixty approved listings. That listener is a connection, and Firestore
// allows one million concurrent connections per database — so at a million
// people browsing, the cap is not a cost problem to optimise, it is a wall.
// Worse, the sixty documents behind it are byte-for-byte IDENTICAL for every
// one of those people: a million connections to deliver one answer.
//
// So the answer is computed once and served from the edge. One origin request
// per minute reads Firestore; everybody else is served by Firebase Hosting's
// CDN and never touches the database at all. Browsing stops consuming
// connections, stops consuming reads, and stops getting slower as the
// marketplace grows — a phone in Karachi is served from a nearby edge rather
// than from us-central1.
//
// WHAT IT MAY CONTAIN. A CDN-cached response is public by construction: the
// URL is fetchable by anyone, and it must be, or it cannot be cached. So this
// decides field by field what leaves the database, exactly as seo.js does for
// /ad pages, and for the same reason — every listing document carries the
// seller's mobile number and some carry exact coordinates. Those never appear
// here. A signed-in user who opens an ad still reads the full document from
// Firestore under the security rules; the phone number is fetched when it is
// needed, by someone entitled to it.
//
// WHAT IT GIVES UP. The feed is no longer live to the second. A new ad appears
// within the cache window rather than instantly. For a classifieds feed that is
// the right trade — nobody is watching the home screen waiting for a stranger's
// sofa to appear — and pull-to-refresh bypasses the cache.

const { onRequest } = require("firebase-functions/v2/https");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

/** How many listings one page of the feed carries. */
const PAGE = 60;

/** Hard ceiling, so a hand-edited `limit` cannot ask for the collection. */
const MAX_PAGE = 100;

/**
 * How long the edge may serve a cached copy, and how long it may keep serving
 * a stale one while it fetches a fresh one behind the scenes.
 *
 * `stale-while-revalidate` is what makes this resilient rather than merely
 * fast: if Firestore is slow, or this function is cold, or the project is
 * having a bad minute, the edge keeps answering from the last good copy
 * instead of showing an empty marketplace. The feed degrades to "slightly out
 * of date" rather than to "broken", which is the whole point of putting
 * something in front of the database.
 */
const CACHE = "public, max-age=60, s-maxage=120, stale-while-revalidate=600";

/**
 * The fields a feed card needs, and nothing else.
 *
 * Deliberately NOT included:
 *  * `phone` — every listing carries the seller's mobile number. Publishing it
 *    here would put every seller's number in front of every scraper on the
 *    internet, permanently, which is the exact failure seo.js was written to
 *    avoid.
 *  * `latitude` / `longitude` — some listings carry the seller's exact
 *    coordinates.
 *  * `location` — free text, and often a house or shop address the seller
 *    wrote for a buyer they had already agreed to meet. `city` is what a card
 *    needs and is safe to publish.
 *
 * `userId` IS included, because the app hides listings from sellers you have
 * blocked and cannot do that without knowing whose listing it is. A Firebase
 * uid is an opaque identifier that grants nothing to whoever knows it — the
 * security rules check who you ARE, never who you can name.
 */
function cardView(id, d) {
  const images = Array.isArray(d.images)
    ? d.images.filter((u) => typeof u === "string" && u.startsWith("http"))
    : [];
  const str = (v) => (v == null ? "" : String(v));
  const millis = (t) => (t && typeof t.toMillis === "function" ? t.toMillis() : null);
  return {
    id,
    title: str(d.title),
    price: str(d.price),
    city: str(d.city),
    category: str(d.category),
    subcategory: str(d.subcategory),
    condition: str(d.condition),
    unit: str(d.unit),
    description: str(d.description),
    sellerName: str(d.sellerName),
    userId: str(d.userId),
    imageUrl: str(d.imageUrl),
    images: images.slice(0, 6),
    deliveryFee: str(d.deliveryFee),
    deliveryAvailable: d.deliveryAvailable === true,
    codAvailable: d.codAvailable === true,
    sellerVerified: d.sellerVerified === true,
    negotiable: d.negotiable === true,
    isFeatured: d.isFeatured === true,
    isSold: d.status === "sold" || d.isSold === true,
    status: str(d.status),
    approvalStatus: str(d.approvalStatus),
    views: Number(d.views) || 0,
    previousPrice: str(d.previousPrice),
    createdAt: millis(d.createdAt),
    priceDropAt: millis(d.priceDropAt),
    featuredUntil: millis(d.featuredUntil),
  };
}

exports.feed = onRequest(
  { region: "us-central1", memory: "256MiB", maxInstances: 20, cors: true },
  async (req, res) => {
    try {
      const limit = Math.min(
        MAX_PAGE,
        Math.max(1, parseInt(req.query.limit, 10) || PAGE)
      );
      // Cursor is the createdAt of the last card the client already has, in
      // milliseconds. Keyset paging rather than an offset: an offset re-reads
      // everything it skips, so page 20 would cost twenty times page 1.
      const before = parseInt(req.query.before, 10);

      let q = getFirestore()
        .collection("listings")
        .where("approvalStatus", "==", "approved")
        .orderBy("createdAt", "desc");
      if (Number.isFinite(before) && before > 0) {
        q = q.startAfter(Timestamp.fromMillis(before));
      }

      const snap = await q.limit(limit).get();
      const items = snap.docs.map((d) => cardView(d.id, d.data() || {}));
      const last = items.length ? items[items.length - 1].createdAt : null;

      res.set("Cache-Control", CACHE);
      res.status(200).json({
        items,
        // Null means the client has reached the end and should stop asking.
        next: items.length < limit ? null : last,
      });
    } catch (err) {
      console.error("feed failed", err);
      // NEVER cache a failure. A cached error would be served to everyone for
      // the length of the window — one bad minute becomes ten minutes of empty
      // marketplace for every visitor.
      res.set("Cache-Control", "no-store");
      res.status(500).json({ items: [], next: null, error: "unavailable" });
    }
  }
);

module.exports.cardView = cardView;
