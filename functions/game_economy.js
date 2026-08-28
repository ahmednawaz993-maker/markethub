"use strict";

// Ludo coins: daily rewards, chests and win payouts.
//
// THIS IS PLAY MONEY, AND THE SEPARATION FROM REAL MONEY IS THE WHOLE DESIGN.
// PakBazar holds actual funds — walletBalance, escrow on live orders, payout
// accounts, withdrawals. A second currency sitting next to that is a genuine
// hazard: a seller who sees two numbers will eventually try to withdraw the
// wrong one. So:
//
//  * Coins live under users/{uid}/game/profile, nowhere near walletBalance.
//  * They are never denominated in PKR and never appear on a wallet screen.
//  * There is no path from coins to money. They cannot be bought, sold,
//    transferred between players, or cashed out — deliberately, and not merely
//    because that path is unimplemented.
//
// The last point is also why there is no staking or betting here. Coins that
// can be bought with real money AND won from other players is gambling in
// substance whatever it is called, which is illegal in Pakistan and against
// Play's policy. Keeping coins unbuyable and untransferable keeps this a
// progression system.
//
// AUTHORITY. Nothing here is reachable from a client. The balance is written
// only by Cloud Functions with the Admin SDK; firestore.rules makes the profile
// read-only to its owner. A player who could write their own balance would.

/** A day, in ms. Streaks are counted in whole days, not 24-hour windows. */
const DAY_MS = 24 * 60 * 60 * 1000;

/** Coins a brand new player starts with, so the balance is never a bare zero. */
const STARTING_COINS = 500;

/** Daily reward by streak day, capped so day 40 is not worth 40x day one. */
const DAILY_BY_STREAK = [100, 150, 200, 300, 400, 500, 1000];

/** Wins needed to earn a chest. */
const WINS_PER_CHEST = 3;

/** Chest tiers: [coins, weight]. Weights need not sum to anything in
 *  particular; rollChest normalises them. */
const CHEST_TIERS = [
  [250, 50],
  [500, 30],
  [1000, 15],
  [2500, 4],
  [10000, 1],
];

/**
 * The calendar day a timestamp falls on, in Pakistan Standard Time.
 *
 * PKT is UTC+5 with no daylight saving, which is why a fixed offset is correct
 * here and would not be somewhere else. Using UTC days instead would roll the
 * streak over at 5am local time — a player claiming at 2am would silently lose
 * a day, and one claiming at 6am twice would get two rewards.
 */
function pktDayNumber(ms) {
  return Math.floor((ms + 5 * 60 * 60 * 1000) / DAY_MS);
}

/**
 * Resolves a daily claim.
 *
 * Returns { canClaim, streak, coins, reason }. The streak advances only on
 * consecutive days; a gap resets it to 1 rather than to 0, because the day they
 * came back IS day one.
 */
function resolveDaily(profile, nowMs) {
  const today = pktDayNumber(nowMs);
  const last = profile && profile.lastDailyAt
    ? pktDayNumber(Number(profile.lastDailyAt))
    : null;

  if (last !== null && last === today) {
    return { canClaim: false, streak: profile.streak || 1, coins: 0, reason: "already_claimed" };
  }
  const streak = last !== null && today - last === 1
    ? (Number(profile.streak) || 0) + 1
    : 1;
  return { canClaim: true, streak, coins: dailyReward(streak), reason: "ok" };
}

/**
 * Coins for a given streak day, held flat once the table runs out.
 *
 * Defends against a nonsense streak reaching the index. Math.floor(NaN) is NaN,
 * and DAILY_BY_STREAK[NaN] is undefined — so a single corrupt field on one
 * profile would have written `undefined` into that player's balance instead of
 * a number, which is not a failure anyone would trace back to here.
 */
function dailyReward(streak) {
  const n = Number(streak);
  const day = Number.isFinite(n) ? Math.max(1, Math.floor(n)) : 1;
  return DAILY_BY_STREAK[Math.min(day - 1, DAILY_BY_STREAK.length - 1)];
}

/**
 * Picks a chest tier from a uniform random in [0, 1).
 *
 * Taking the random number as an ARGUMENT rather than calling Math.random()
 * inside makes the distribution testable — otherwise the only way to check the
 * odds is to run it a million times and hope.
 */
function rollChest(r) {
  const total = CHEST_TIERS.reduce((s, [, w]) => s + w, 0);
  let x = Math.min(Math.max(r, 0), 0.999999) * total;
  for (const [coins, weight] of CHEST_TIERS) {
    if (x < weight) return coins;
    x -= weight;
  }
  return CHEST_TIERS[0][0];
}

/**
 * Coins for finishing a game.
 *
 * Scaled by how many real people were at the table, because beating three
 * computers is not an achievement and should not pay like one. A player who
 * finishes but does not win still gets something, so a long game is never worth
 * nothing.
 */
function winReward({ won, humanPlayers, mode }) {
  const humans = Math.max(1, Math.min(4, Number(humanPlayers) || 1));
  // A solo game against computers pays a token amount; a full table pays four
  // times as much.
  const base = won ? 100 : 25;
  const modeBonus = mode === "master" ? 1.5 : mode === "quick" ? 0.6 : 1;
  return Math.round(base * humans * modeBonus);
}

module.exports = {
  DAY_MS,
  STARTING_COINS,
  DAILY_BY_STREAK,
  WINS_PER_CHEST,
  CHEST_TIERS,
  pktDayNumber,
  resolveDaily,
  dailyReward,
  rollChest,
  winReward,
};
