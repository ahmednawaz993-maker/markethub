"use strict";

// Unit tests for the new-listing broadcast logic (who gets blasted, and when).
//   Run:  cd functions && node broadcast_logic.test.js

const assert = require("assert");
const {
  MAX_TITLE_CHARS,
  NEW_LISTING_TOPIC,
  userTopic,
  broadcastTarget,
  shouldBroadcastListing,
  becamePublic,
  hasBroadcastableChange,
  broadcastMessage,
  wantsBroadcast,
  validateAdminBroadcast,
  canSendBroadcast,
  MAX_BROADCAST_TITLE,
  MAX_BROADCAST_BODY,
} = require("./broadcast_logic");

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

// --- shouldBroadcastListing ------------------------------------------------

t("an approved in-stock listing is broadcast", () => {
  assert.strictEqual(
    shouldBroadcastListing({ approvalStatus: "approved", status: "in_stock" }),
    true
  );
});

t("a pending listing is NOT broadcast (not public yet)", () => {
  assert.strictEqual(shouldBroadcastListing({ approvalStatus: "pending" }), false);
});

t("a rejected listing is NOT broadcast", () => {
  assert.strictEqual(shouldBroadcastListing({ approvalStatus: "rejected" }), false);
});

t("a sold / out-of-stock listing is NOT broadcast", () => {
  assert.strictEqual(
    shouldBroadcastListing({ approvalStatus: "approved", status: "sold" }),
    false
  );
});

t("a listing with no approvalStatus at all is treated as public", () => {
  // Legacy/demo ads written without the field were public under the old rules.
  assert.strictEqual(shouldBroadcastListing({}), true);
});

t("a null listing is never broadcast", () => {
  assert.strictEqual(shouldBroadcastListing(null), false);
});

// --- becamePublic ----------------------------------------------------------

t("pending -> approved is the moment a listing becomes public", () => {
  assert.strictEqual(
    becamePublic({ approvalStatus: "pending" }, { approvalStatus: "approved" }),
    true
  );
});

t("an edit to an already-approved listing does NOT re-broadcast", () => {
  assert.strictEqual(
    becamePublic(
      { approvalStatus: "approved", price: "100" },
      { approvalStatus: "approved", price: "90" }
    ),
    false
  );
});

t("approved -> rejected is not a publication", () => {
  assert.strictEqual(
    becamePublic({ approvalStatus: "approved" }, { approvalStatus: "rejected" }),
    false
  );
});

// --- hasBroadcastableChange ------------------------------------------------

t("a view-counter bump is NOT announced (the self-amplifying loop guard)", () => {
  // The app increments `views` every time anyone opens an ad. If this returned
  // true, every page view would push to the entire userbase -- and each push
  // drives more views.
  const before = { title: "Sofa", price: "5000", views: 41 };
  const after = { title: "Sofa", price: "5000", views: 42 };
  assert.strictEqual(hasBroadcastableChange(before, after), false);
});

t("moderation bookkeeping alone is NOT announced", () => {
  const before = { title: "Sofa", approvalStatus: "pending", updatedAt: 1 };
  const after = { title: "Sofa", approvalStatus: "approved", updatedAt: 2 };
  assert.strictEqual(hasBroadcastableChange(before, after), false);
});

t("a price edit IS announced", () => {
  assert.strictEqual(
    hasBroadcastableChange({ price: "5000" }, { price: "4500" }),
    true
  );
});

t("a title edit IS announced", () => {
  assert.strictEqual(
    hasBroadcastableChange({ title: "Sofa" }, { title: "Leather sofa" }),
    true
  );
});

t("swapping the photos IS announced", () => {
  assert.strictEqual(
    hasBroadcastableChange({ images: ["a.jpg"] }, { images: ["b.jpg"] }),
    true
  );
});

t("an inventory status change IS announced", () => {
  assert.strictEqual(
    hasBroadcastableChange({ status: "sold" }, { status: "in_stock" }),
    true
  );
});

t("re-saving an ad with no real change is NOT announced", () => {
  const l = {
    title: "Sofa",
    price: "5000",
    attributes: { Colour: "Brown", Material: "Leather" },
    images: ["a.jpg"],
  };
  assert.strictEqual(hasBroadcastableChange(l, { ...l }), false);
});

t("attribute key order does not fake a change", () => {
  const before = { attributes: { Colour: "Brown", Material: "Leather" } };
  const after = { attributes: { Material: "Leather", Colour: "Brown" } };
  assert.strictEqual(hasBroadcastableChange(before, after), false);
});

t("an actual attribute edit IS announced", () => {
  const before = { attributes: { Colour: "Brown" } };
  const after = { attributes: { Colour: "Black" } };
  assert.strictEqual(hasBroadcastableChange(before, after), true);
});

// --- broadcastMessage ------------------------------------------------------

t("copy leads with the category and carries price + city", () => {
  const m = broadcastMessage({
    category: "Motors",
    title: "Toyota Xli 2008",
    price: "2,450,000",
    city: "Attock",
  });
  assert.strictEqual(m.title, "New in Motors");
  assert.strictEqual(m.body, "Toyota Xli 2008 — Rs 2,450,000 in Attock");
});

t("an update is labelled as an update, not as new", () => {
  const m = broadcastMessage({ category: "Motors", title: "Xli" }, "updated");
  assert.strictEqual(m.title, "Updated in Motors");
});

t("a listing with no category falls back to a generic title", () => {
  assert.strictEqual(broadcastMessage({ title: "Sofa" }).title, "New on PakBazar");
  assert.strictEqual(
    broadcastMessage({ title: "Sofa" }, "updated").title,
    "Updated on PakBazar"
  );
});

t("a missing price is left out rather than shown as 'Rs '", () => {
  const m = broadcastMessage({ title: "Free kittens", city: "Lahore" });
  assert.strictEqual(m.body, "Free kittens in Lahore");
});

t("an overlong title is ellipsised so the alert stays readable", () => {
  const long = "A".repeat(200);
  const m = broadcastMessage({ title: long, price: "10" });
  const name = m.body.split(" — ")[0];
  assert.ok(name.length <= MAX_TITLE_CHARS, `name was ${name.length} chars`);
  assert.ok(name.endsWith("…"), "expected an ellipsis");
});

t("an empty listing still produces sendable copy", () => {
  const m = broadcastMessage({});
  assert.ok(m.title.length > 0);
  assert.ok(m.body.length > 0);
});

// --- broadcastTarget (the seller-exclusion) --------------------------------

t("a broadcast excludes the seller's own devices", () => {
  const target = broadcastTarget("abc123");
  assert.strictEqual(target.topic, undefined, "must not send to a bare topic");
  assert.strictEqual(
    target.condition,
    `'${NEW_LISTING_TOPIC}' in topics && !('user_abc123' in topics)`
  );
});

t("with no seller there is nobody to exclude, so a plain topic is used", () => {
  assert.deepStrictEqual(broadcastTarget(""), { topic: NEW_LISTING_TOPIC });
  assert.deepStrictEqual(broadcastTarget(null), { topic: NEW_LISTING_TOPIC });
});

t("a uid with illegal topic characters is sanitised, never injected", () => {
  // FCM topic names allow [a-zA-Z0-9-_.~%]. Anything else must be stripped so
  // a crafted uid cannot break out of the quoted condition expression.
  const hostile = "ab'c) in topics && !('x";
  assert.strictEqual(userTopic(hostile), "user_abcintopicsx");

  const condition = broadcastTarget(hostile).condition;
  // Exactly two quoted topic names, and no stray quotes or parens smuggled in.
  assert.strictEqual((condition.match(/'/g) || []).length, 4);
  assert.strictEqual(
    condition,
    `'${NEW_LISTING_TOPIC}' in topics && !('user_abcintopicsx' in topics)`
  );
});

t("the condition stays within FCM's 5-topic limit", () => {
  const occurrences = (broadcastTarget("abc123").condition.match(/in topics/g) || [])
    .length;
  assert.ok(occurrences <= 5, `used ${occurrences} topics`);
});

// --- wantsBroadcast --------------------------------------------------------

t("a user with no prefs at all is subscribed (opt-out, not opt-in)", () => {
  assert.strictEqual(wantsBroadcast({}), true);
  assert.strictEqual(wantsBroadcast(null), true);
});

t("the master new-listing opt-out unsubscribes the user", () => {
  assert.strictEqual(wantsBroadcast({ notifPrefs: { newListing: false } }), false);
});

t("'in-app inbox only' (push off) unsubscribes the user", () => {
  assert.strictEqual(wantsBroadcast({ notifPrefs: { push: false } }), false);
});

t("the legacy mode 'off' still silences the user", () => {
  assert.strictEqual(wantsBroadcast({ notifPrefs: { mode: "off" } }), false);
});

t("legacy daily/weekly users are subscribed, not left silent", () => {
  // Those digests were never implemented, so honouring them literally would
  // mean these users never hear anything at all.
  assert.strictEqual(wantsBroadcast({ notifPrefs: { mode: "daily" } }), true);
  assert.strictEqual(wantsBroadcast({ notifPrefs: { mode: "weekly" } }), true);
});

// --- validateAdminBroadcast ------------------------------------------------

t("a well-formed announcement validates and is trimmed", () => {
  const r = validateAdminBroadcast({
    title: "  Scheduled maintenance  ",
    body: "  PakBazar will be briefly unavailable tonight.  ",
    audience: "all",
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.title, "Scheduled maintenance");
  assert.strictEqual(r.body, "PakBazar will be briefly unavailable tonight.");
});

t("an empty or whitespace-only title is rejected", () => {
  assert.strictEqual(validateAdminBroadcast({ body: "hi" }).ok, false);
  assert.strictEqual(
    validateAdminBroadcast({ title: "   ", body: "hi" }).ok,
    false
  );
});

t("an empty message is rejected", () => {
  assert.strictEqual(validateAdminBroadcast({ title: "Hi" }).ok, false);
});

t("over-long text is rejected rather than silently truncated", () => {
  const longTitle = validateAdminBroadcast({
    title: "A".repeat(MAX_BROADCAST_TITLE + 1),
    body: "ok",
  });
  assert.strictEqual(longTitle.ok, false);
  const longBody = validateAdminBroadcast({
    title: "ok",
    body: "A".repeat(MAX_BROADCAST_BODY + 1),
  });
  assert.strictEqual(longBody.ok, false);
});

t("an unknown audience is rejected", () => {
  const r = validateAdminBroadcast({
    title: "Hi",
    body: "There",
    audience: "everyone-ever",
  });
  assert.strictEqual(r.ok, false);
});

t("a single-user send without a target is rejected", () => {
  const r = validateAdminBroadcast({
    title: "Hi",
    body: "There",
    audience: "user",
  });
  assert.strictEqual(r.ok, false);
});

t("a single-user send with a target validates", () => {
  const r = validateAdminBroadcast({
    title: "Hi",
    body: "There",
    audience: "user",
    targetUid: "abc123",
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.targetUid, "abc123");
});

// --- canSendBroadcast ------------------------------------------------------

const ADMIN = "admin@example.com";

t("the super admin can always send", () => {
  assert.strictEqual(canSendBroadcast(ADMIN, null, ADMIN), true);
  assert.strictEqual(canSendBroadcast("ADMIN@EXAMPLE.COM", null, ADMIN), true);
});

t("staff granted the broadcasts permission can send", () => {
  const staff = { active: true, permissions: { broadcasts: true } };
  assert.strictEqual(canSendBroadcast("s@example.com", staff, ADMIN), true);
});

t("staff WITHOUT the broadcasts permission cannot send", () => {
  const staff = { active: true, permissions: { orders: true } };
  assert.strictEqual(canSendBroadcast("s@example.com", staff, ADMIN), false);
});

t("a deactivated staff member cannot send", () => {
  const staff = { active: false, permissions: { broadcasts: true } };
  assert.strictEqual(canSendBroadcast("s@example.com", staff, ADMIN), false);
});

t("a random signed-in user cannot send", () => {
  assert.strictEqual(canSendBroadcast("nobody@example.com", null, ADMIN), false);
});

t("a missing email cannot send", () => {
  assert.strictEqual(canSendBroadcast("", null, ADMIN), false);
  assert.strictEqual(canSendBroadcast(null, null, ADMIN), false);
});

console.log(`\n${pass} checks passed${process.exitCode ? " (with failures)" : ""}`);
