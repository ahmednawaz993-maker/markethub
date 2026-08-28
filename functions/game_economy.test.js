"use strict";

// Tests for the coin economy.
//   Run:  cd functions && node game_economy.test.js
//
// Two things get the most attention. The STREAK, because a day boundary that is
// an hour out silently robs players who play late at night — the kind of bug
// that generates support mail nobody can reproduce. And the CHEST ODDS, because
// they are invisible: a mistake in the weights cannot be seen by playing, only
// by counting.

const assert = require("assert");
const E = require("./game_economy");

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

// 2026-08-28 12:00 PKT
const NOON_PKT = Date.UTC(2026, 7, 28, 7, 0, 0);
const HOUR = 60 * 60 * 1000;

console.log("game_economy");

// --- Day boundaries --------------------------------------------------------

t("a day rolls over at midnight Pakistan time, not UTC", () => {
  // 23:59 PKT and 00:01 PKT are different days...
  const justBefore = Date.UTC(2026, 7, 28, 18, 59); // 23:59 PKT
  const justAfter = Date.UTC(2026, 7, 28, 19, 1); // 00:01 PKT next day
  assert.strictEqual(
    E.pktDayNumber(justAfter) - E.pktDayNumber(justBefore),
    1,
    "midnight PKT did not roll the day"
  );
  // ...while 04:00 and 06:00 PKT are the SAME day, which UTC days would split.
  const four = Date.UTC(2026, 7, 28, 23, 0); // 04:00 PKT
  const six = Date.UTC(2026, 7, 29, 1, 0); // 06:00 PKT
  assert.strictEqual(
    E.pktDayNumber(four),
    E.pktDayNumber(six),
    "a UTC boundary leaked into the streak"
  );
});

// --- Daily claim -----------------------------------------------------------

t("a first-time player can claim, and starts a streak at one", () => {
  const r = E.resolveDaily({}, NOON_PKT);
  assert.ok(r.canClaim);
  assert.strictEqual(r.streak, 1);
  assert.strictEqual(r.coins, E.DAILY_BY_STREAK[0]);
});

t("claiming twice in one day is refused", () => {
  const r = E.resolveDaily({ lastDailyAt: NOON_PKT, streak: 1 }, NOON_PKT + HOUR);
  assert.ok(!r.canClaim);
  assert.strictEqual(r.coins, 0);
  assert.strictEqual(r.reason, "already_claimed");
});

t("a late-night claim and an early-morning one are the same day", () => {
  // 23:30 PKT then 00:30 PKT is two days and must pay twice; 01:00 then 05:00
  // is one day and must not.
  const lateNight = Date.UTC(2026, 7, 28, 18, 30); // 23:30 PKT
  const afterMidnight = Date.UTC(2026, 7, 28, 19, 30); // 00:30 PKT
  assert.ok(E.resolveDaily({ lastDailyAt: lateNight, streak: 3 }, afterMidnight).canClaim);

  const onePkt = Date.UTC(2026, 7, 28, 20, 0); // 01:00 PKT
  const fivePkt = Date.UTC(2026, 7, 29, 0, 0); // 05:00 PKT
  assert.ok(!E.resolveDaily({ lastDailyAt: onePkt, streak: 3 }, fivePkt).canClaim);
});

t("consecutive days build the streak", () => {
  let profile = {};
  let day = NOON_PKT;
  for (let i = 1; i <= 5; i++) {
    const r = E.resolveDaily(profile, day);
    assert.ok(r.canClaim, `day ${i} could not be claimed`);
    assert.strictEqual(r.streak, i);
    profile = { lastDailyAt: day, streak: r.streak };
    day += E.DAY_MS;
  }
});

t("a missed day resets the streak to one, not zero", () => {
  // Coming back IS day one — a streak of zero would pay nothing for showing up.
  const r = E.resolveDaily(
    { lastDailyAt: NOON_PKT, streak: 6 },
    NOON_PKT + 3 * E.DAY_MS
  );
  assert.ok(r.canClaim);
  assert.strictEqual(r.streak, 1);
  assert.strictEqual(r.coins, E.DAILY_BY_STREAK[0]);
});

t("the reward is capped so a long streak is not unbounded", () => {
  const top = E.DAILY_BY_STREAK[E.DAILY_BY_STREAK.length - 1];
  assert.strictEqual(E.dailyReward(7), top);
  assert.strictEqual(E.dailyReward(40), top);
  assert.strictEqual(E.dailyReward(4000), top);
});

t("the reward table only ever goes up", () => {
  for (let i = 1; i < E.DAILY_BY_STREAK.length; i++) {
    assert.ok(
      E.DAILY_BY_STREAK[i] > E.DAILY_BY_STREAK[i - 1],
      `day ${i + 1} pays less than day ${i}`
    );
  }
});

t("a nonsense streak does not produce a nonsense reward", () => {
  for (const s of [0, -5, NaN, 1.7]) {
    const c = E.dailyReward(s);
    assert.ok(Number.isFinite(c) && c > 0, `streak ${s} gave ${c}`);
  }
});

// --- Chests ----------------------------------------------------------------

t("a chest always pays a real tier", () => {
  for (const r of [0, 0.0001, 0.5, 0.9, 0.999999, 1, 1.5, -1]) {
    const c = E.rollChest(r);
    assert.ok(
      E.CHEST_TIERS.some(([coins]) => coins === c),
      `r=${r} produced ${c}, which is not a tier`
    );
  }
});

t("the chest odds match the declared weights", () => {
  // The whole point of taking the random as an argument: the distribution can
  // be checked exactly rather than sampled and hoped over.
  const N = 200000;
  const counts = {};
  for (let i = 0; i < N; i++) {
    const c = E.rollChest(i / N);
    counts[c] = (counts[c] || 0) + 1;
  }
  const total = E.CHEST_TIERS.reduce((s, [, w]) => s + w, 0);
  for (const [coins, weight] of E.CHEST_TIERS) {
    const expected = weight / total;
    const actual = (counts[coins] || 0) / N;
    assert.ok(
      Math.abs(actual - expected) < 0.005,
      `${coins} coins: expected ${(expected * 100).toFixed(1)}%, got ${(actual * 100).toFixed(1)}%`
    );
  }
});

t("the rarest chest is genuinely rare and the common one common", () => {
  const total = E.CHEST_TIERS.reduce((s, [, w]) => s + w, 0);
  const sorted = [...E.CHEST_TIERS].sort((a, b) => a[0] - b[0]);
  assert.ok(sorted[0][1] / total > 0.3, "the cheapest tier should be common");
  assert.ok(
    sorted[sorted.length - 1][1] / total < 0.02,
    "the richest tier should be rare"
  );
});

// --- Win payouts -----------------------------------------------------------

t("winning pays more than losing, and neither pays nothing", () => {
  const won = E.winReward({ won: true, humanPlayers: 2, mode: "classic" });
  const lost = E.winReward({ won: false, humanPlayers: 2, mode: "classic" });
  assert.ok(won > lost, "a win must beat a loss");
  assert.ok(lost > 0, "finishing a long game must not pay zero");
});

t("beating real people pays more than beating computers", () => {
  const solo = E.winReward({ won: true, humanPlayers: 1, mode: "classic" });
  const full = E.winReward({ won: true, humanPlayers: 4, mode: "classic" });
  assert.ok(full > solo * 3, `a full table paid ${full} vs ${solo} solo`);
});

t("a short game pays less than a long one", () => {
  const quick = E.winReward({ won: true, humanPlayers: 4, mode: "quick" });
  const classic = E.winReward({ won: true, humanPlayers: 4, mode: "classic" });
  const master = E.winReward({ won: true, humanPlayers: 4, mode: "master" });
  assert.ok(quick < classic, "Quick is half the length and should pay less");
  assert.ok(master > classic, "Master is harder and should pay more");
});

t("a payout is always a whole, sane number of coins", () => {
  for (const humans of [0, 1, 2, 3, 4, 99, NaN]) {
    for (const mode of ["classic", "quick", "master", "arrow", undefined]) {
      for (const won of [true, false]) {
        const c = E.winReward({ won, humanPlayers: humans, mode });
        assert.ok(
          Number.isInteger(c) && c > 0 && c < 10000,
          `humans=${humans} mode=${mode} won=${won} gave ${c}`
        );
      }
    }
  }
});

t("no single action can mint an absurd balance", () => {
  // A sanity ceiling. If someone later adds a tier or bumps a multiplier, this
  // is the test that notices the economy has been broken open.
  const maxDaily = Math.max(...E.DAILY_BY_STREAK);
  const maxChest = Math.max(...E.CHEST_TIERS.map(([c]) => c));
  const maxWin = E.winReward({ won: true, humanPlayers: 4, mode: "master" });
  assert.ok(maxDaily <= 2000, `daily reward is too large: ${maxDaily}`);
  assert.ok(maxChest <= 20000, `chest is too large: ${maxChest}`);
  assert.ok(maxWin <= 2000, `win reward is too large: ${maxWin}`);
});

t("chests are earned often enough to matter, rarely enough to mean something", () => {
  assert.ok(E.WINS_PER_CHEST >= 2 && E.WINS_PER_CHEST <= 10);
});

console.log(`\n${pass} passed`);
