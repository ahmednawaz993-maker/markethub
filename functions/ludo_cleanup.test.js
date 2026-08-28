"use strict";

// Which Ludo rooms may be deleted.
//   Run:  cd functions && node ludo_cleanup.test.js
//
// A deletion cannot be undone, and this one is recursive — it takes the room's
// chat, emoji, roll requests and voice signalling with it. So the rule is pure
// and the tests are mostly about what must NOT be deleted. The dangerous
// failure here is not "a stale room survives"; it is "a live game vanishes
// under four people".

const assert = require("assert");
const L = require("./ludo_logic");

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

const NOW = Date.UTC(2026, 7, 28, 12, 0, 0);
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

const room = (status, ageMs, extra = {}) => ({
  status,
  updatedAt: NOW - ageMs,
  ...extra,
});

console.log("ludo room cleanup");

// --- What must never be deleted -------------------------------------------

t("a game in play is never deleted, however long the turn has taken", () => {
  // This is the one that matters. A slow turn is the stuck-game sweeper's
  // problem; deleting the room would end a real game for four people.
  for (const age of [0, HOUR, DAY, 30 * DAY, 365 * DAY]) {
    const r = L.ludoRoomExpiry(room("playing", age), NOW);
    assert.ok(!r.expired, `a playing room aged ${age}ms was marked expired`);
  }
});

t("a room with no timestamp is left alone", () => {
  // We cannot know how old it is. A stray document is cheaper than a wrong
  // deletion.
  for (const bad of [undefined, null, "yesterday", NaN, {}]) {
    const r = L.ludoRoomExpiry({ status: "finished", updatedAt: bad }, NOW);
    assert.ok(!r.expired, `updatedAt=${JSON.stringify(bad)} was deleted`);
    assert.strictEqual(r.reason, "no_timestamp");
  }
});

t("a room stamped in the future is left alone", () => {
  // Clock skew, or a bad write. Either way, not evidence of age.
  const r = L.ludoRoomExpiry(room("finished", -HOUR), NOW);
  assert.ok(!r.expired);
  assert.strictEqual(r.reason, "future");
});

t("an unrecognised status is left alone", () => {
  // A status added later must not be swept by code that predates it.
  const r = L.ludoRoomExpiry(room("paused", 400 * DAY), NOW);
  assert.ok(!r.expired);
});

t("an empty document does not throw", () => {
  assert.ok(!L.ludoRoomExpiry({}, NOW).expired);
  assert.ok(!L.ludoRoomExpiry(null, NOW).expired);
});

// --- What should be deleted ------------------------------------------------

t("a finished game is kept for its retention period, then goes", () => {
  const keep = L.ludoRoomExpiry(room("finished", 2 * DAY), NOW);
  assert.ok(!keep.expired, "a 2-day-old finished game was deleted too early");
  const drop = L.ludoRoomExpiry(room("finished", 4 * DAY), NOW);
  assert.ok(drop.expired);
  assert.strictEqual(drop.reason, "finished");
});

t("the boundary is exclusive, so a room exactly at the limit survives", () => {
  const exact = L.ludoRoomExpiry(
    room("finished", L.LUDO_FINISHED_RETENTION_MS),
    NOW
  );
  assert.ok(!exact.expired, "deleted at exactly the retention age");
  const past = L.ludoRoomExpiry(
    room("finished", L.LUDO_FINISHED_RETENTION_MS + 1000),
    NOW
  );
  assert.ok(past.expired);
});

t("a table nobody ever started is swept after a day", () => {
  // These are real: four rooms sat at one seat for eleven hours because they
  // were created before the auto-start existed.
  assert.ok(!L.ludoRoomExpiry(room("waiting", 6 * HOUR), NOW).expired);
  const drop = L.ludoRoomExpiry(room("waiting", 30 * HOUR), NOW);
  assert.ok(drop.expired);
  assert.strictEqual(drop.reason, "abandoned");
});

t("a waiting room is given far longer than the auto-start countdown", () => {
  // Auto-start fires 12 seconds after the last person sits down. Sweeping
  // anywhere near that would delete tables that were about to begin.
  assert.ok(
    L.LUDO_ABANDONED_MS > 60 * 60 * 1000,
    "abandoned threshold is dangerously short"
  );
  assert.ok(!L.ludoRoomExpiry(room("waiting", 30 * 1000), NOW).expired);
});

// --- The retention values themselves ---------------------------------------

t("retention is long enough to look at a result, short enough to matter", () => {
  const days = L.LUDO_FINISHED_RETENTION_MS / DAY;
  assert.ok(days >= 1 && days <= 30, `retention is ${days} days`);
  const hours = L.LUDO_ABANDONED_MS / HOUR;
  assert.ok(hours >= 2 && hours <= 168, `abandoned threshold is ${hours} hours`);
});

t("an abandoned table is swept sooner than a finished game is forgotten", () => {
  // A finished game has a result someone might want to see; an empty room has
  // nothing in it at all.
  assert.ok(L.LUDO_ABANDONED_MS < L.LUDO_FINISHED_RETENTION_MS);
});

console.log(`\n${pass} passed`);
