"use strict";

// What a write to a Ludo room causes to happen.
//   Run:  cd functions && node ludo_dispatch.test.js
//
// Three separate Firestore triggers were merged into one, because Firestore has
// no conditional triggers and all three fired on every write — two of them only
// to return immediately. The merge is safe only if the branch that replaced
// them is exactly as exclusive as the three guards were, so that branch is
// pure and tested here.
//
// The failures worth guarding against are both money: paying a table twice, and
// letting a staked table play for a pot that was never collected.

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

console.log("ludo room dispatch");

t("a deleted room asks for nothing", () => {
  assert.deepStrictEqual(L.roomActions({ status: "playing" }, null), []);
  assert.deepStrictEqual(L.roomActions(null, undefined), []);
});

t("a room still waiting asks for nothing", () => {
  assert.deepStrictEqual(L.roomActions(null, { status: "waiting" }), []);
  assert.deepStrictEqual(
    L.roomActions({ status: "waiting" }, { status: "waiting" }),
    []
  );
});

t("a game starting collects the stake BEFORE a bot may move", () => {
  const jobs = L.roomActions({ status: "waiting" }, { status: "playing" });
  assert.deepStrictEqual(jobs, ["stakes", "bot"]);
  // The order is the point. A bot that opened the game first would be playing
  // for a pot that did not exist yet.
  assert.ok(jobs.indexOf("stakes") < jobs.indexOf("bot"));
});

t("a move mid-game still re-checks the stake, and moves the bot", () => {
  // Not just the transition: the collector guards itself on its own marker, so
  // re-checking is free and is what repairs a collection that was missed.
  assert.deepStrictEqual(
    L.roomActions({ status: "playing" }, { status: "playing" }),
    ["stakes", "bot"]
  );
});

t("a game that has just finished pays out exactly once", () => {
  assert.deepStrictEqual(
    L.roomActions({ status: "playing" }, { status: "finished" }),
    ["award"]
  );
});

t("a later write to a finished game does NOT pay again", () => {
  // This is the double-payout guard. The old trigger had it; losing it in the
  // merge would have paid every table twice.
  assert.deepStrictEqual(
    L.roomActions({ status: "finished" }, { status: "finished" }),
    []
  );
});

t("a finished game never runs a bot or takes a stake", () => {
  for (const before of [null, { status: "playing" }, { status: "finished" }]) {
    const jobs = L.roomActions(before, { status: "finished" });
    assert.ok(!jobs.includes("bot"), "a finished game moved a bot");
    assert.ok(!jobs.includes("stakes"), "a finished game took a stake");
  }
});

t("a room created straight into 'playing' still collects", () => {
  // Quick match writes a room that is already playing; there is no earlier
  // version of the document at all.
  assert.deepStrictEqual(L.roomActions(undefined, { status: "playing" }), [
    "stakes",
    "bot",
  ]);
});

t("an unknown status is ignored rather than guessed at", () => {
  assert.deepStrictEqual(L.roomActions(null, { status: "abandoned" }), []);
  assert.deepStrictEqual(L.roomActions(null, {}), []);
});

t("every write asks for at most one job per concern", () => {
  // No status may produce a duplicate — a repeated job means repeated money.
  for (const s of ["waiting", "playing", "finished", "junk"]) {
    for (const b of [null, { status: "waiting" }, { status: "playing" }, { status: "finished" }]) {
      const jobs = L.roomActions(b, { status: s });
      assert.strictEqual(
        new Set(jobs).size,
        jobs.length,
        `duplicate job for ${s} from ${b && b.status}`
      );
    }
  }
});

console.log(`\n${pass} passed`);
