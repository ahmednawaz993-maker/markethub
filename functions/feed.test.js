"use strict";

// What may leave the database on the public feed.
//   Run:  cd functions && node feed.test.js
//
// The feed is served from a CDN, which means its URL is fetchable by anyone —
// that is not a weakness, it is the mechanism, and it is why a response cannot
// be allowed to carry anything private. Every listing document holds the
// seller's mobile number and some hold exact coordinates.
//
// The dangerous failure here is not "a field is missing". It is "a field was
// added to listings six months from now and quietly started being published to
// the open internet". So this test is written as an ALLOWLIST: anything not
// named is a failure, including keys nobody has thought of yet.

const assert = require("assert");
const { cardView } = require("./feed");

let pass = 0;
function t(name, fn) {
  try {
    fn();
    pass++;
    console.log(`  PASS  ${name}`);
  } catch (e) {
    console.log(`  FAIL  ${name}\n        ${e.message}`);
    process.exitCode = 1;
  }
}

/** A listing document with every field the app writes, plus the private ones. */
const full = {
  title: "Toyota Corolla 2022",
  price: "12500000",
  city: "Rawalpindi",
  category: "Vehicles",
  subcategory: "Cars",
  condition: "Used",
  unit: "",
  description: "Single owner",
  sellerName: "Ahmed",
  userId: "uid-123",
  imageUrl: "https://example.com/a.jpg",
  images: ["https://example.com/a.jpg", "not-a-url", "https://example.com/b.jpg"],
  deliveryFee: "500",
  deliveryAvailable: true,
  codAvailable: true,
  sellerVerified: true,
  negotiable: true,
  isFeatured: true,
  status: "in_stock",
  approvalStatus: "approved",
  views: 42,
  previousPrice: "13000000",
  // --- everything below is private and must never appear ---
  phone: "+923001234567",
  latitude: 33.6,
  longitude: 73.04,
  location: "House 12, Street 4, Satellite Town",
};

const ALLOWED = new Set([
  "id", "title", "price", "city", "category", "subcategory", "condition",
  "unit", "description", "sellerName", "userId", "imageUrl", "images",
  "deliveryFee", "deliveryAvailable", "codAvailable", "sellerVerified",
  "negotiable", "isFeatured", "isSold", "status", "approvalStatus", "views",
  "previousPrice", "createdAt", "priceDropAt", "featuredUntil",
]);

console.log("public feed projection");

t("the seller's phone number never leaves the database", () => {
  const v = cardView("l1", full);
  assert.ok(!("phone" in v), "phone was published");
  assert.ok(
    !JSON.stringify(v).includes("923001234567"),
    "the number appeared somewhere in the payload"
  );
});

t("exact coordinates never leave the database", () => {
  const v = cardView("l1", full);
  assert.ok(!("latitude" in v) && !("longitude" in v));
  assert.ok(!JSON.stringify(v).includes("73.04"));
});

t("the free-text address never leaves; the city does", () => {
  // `location` is often a house or shop address written for one buyer.
  const v = cardView("l1", full);
  assert.ok(!("location" in v));
  assert.ok(!JSON.stringify(v).includes("Street 4"));
  assert.strictEqual(v.city, "Rawalpindi");
});

t("NOTHING outside the allowlist is published, ever", () => {
  // The regression this exists for: someone adds `sellerEmail` to listings and
  // it starts being served to the open internet without anybody deciding to.
  const withFutureField = {
    ...full,
    sellerEmail: "seller@example.com",
    buyerNotes: "private",
    idCardNumber: "3520212345678",
  };
  const v = cardView("l1", withFutureField);
  const extra = Object.keys(v).filter((k) => !ALLOWED.has(k));
  assert.deepStrictEqual(extra, [], `unexpected fields published: ${extra}`);
  const body = JSON.stringify(v);
  for (const secret of ["seller@example.com", "private", "3520212345678"]) {
    assert.ok(!body.includes(secret), `${secret} was published`);
  }
});

t("a card still carries what a card needs to draw", () => {
  const v = cardView("l1", full);
  for (const k of ["id", "title", "price", "city", "imageUrl", "userId"]) {
    assert.ok(v[k], `${k} is missing, so the card cannot render`);
  }
  // userId specifically: without it the app cannot hide sellers you blocked.
  assert.strictEqual(v.userId, "uid-123");
});

t("junk in the images array is dropped", () => {
  const v = cardView("l1", full);
  assert.deepStrictEqual(v.images, [
    "https://example.com/a.jpg",
    "https://example.com/b.jpg",
  ]);
});

t("a listing missing every field does not throw", () => {
  // One malformed document must not blank the whole feed for everybody.
  const v = cardView("l1", {});
  assert.strictEqual(v.title, "");
  assert.strictEqual(v.isSold, false);
  assert.strictEqual(v.createdAt, null);
});

t("legacy isSold and modern status agree", () => {
  assert.strictEqual(cardView("l", { isSold: true }).isSold, true);
  assert.strictEqual(cardView("l", { status: "sold" }).isSold, true);
  assert.strictEqual(cardView("l", { status: "in_stock" }).isSold, false);
});

t("timestamps come out as plain numbers", () => {
  // The client parses these; a Firestore Timestamp object would not survive
  // JSON and would arrive as {_seconds: ...}.
  const v = cardView("l", { createdAt: { toMillis: () => 1700000000000 } });
  assert.strictEqual(v.createdAt, 1700000000000);
});

console.log(`\n${pass} passed`);
