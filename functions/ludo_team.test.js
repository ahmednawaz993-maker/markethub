"use strict";

// Server-side team rules.
//   Run:  cd functions && node ludo_team.test.js
//
// The pairing table is duplicated from Dart, so it is asserted value by value.
// Drift here would not throw: the phone would say a move captures nobody while
// the server sent a partner home, and the two boards would diverge mid-game.

const assert = require("assert");
const L = require("./ludo_logic");
const crypto = require("crypto");

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

const YARD = () => ({
  red: [-1, -1, -1, -1],
  green: [-1, -1, -1, -1],
  yellow: [-1, -1, -1, -1],
  blue: [-1, -1, -1, -1],
});

function team(positions, extra = {}) {
  return {
    players: ["red", "green", "yellow", "blue"],
    positions: { ...YARD(), ...positions },
    turn: 0,
    sixes: 0,
    winners: [],
    captured: [],
    dice: null,
    mode: "classic",
    teams: true,
    ...extra,
  };
}

console.log("ludo_logic — teams");

t("the pairing matches kLudoPartners in ludo_engine.dart exactly", () => {
  assert.deepStrictEqual(L.PARTNERS, {
    red: "yellow",
    yellow: "red",
    green: "blue",
    blue: "green",
  });
});

t("the pairing is symmetric and nobody partners themselves", () => {
  for (const [a, b] of Object.entries(L.PARTNERS)) {
    assert.notStrictEqual(a, b);
    assert.strictEqual(L.PARTNERS[b], a);
  }
});

t("a colour is its own ally; partners are allies; opponents are not", () => {
  const s = team({});
  assert.ok(L.areAllies(s, "red", "red"));
  assert.ok(L.areAllies(s, "red", "yellow"));
  assert.ok(!L.areAllies(s, "red", "green"));
  assert.ok(!L.areAllies(s, "red", "blue"));
});

t("in a solo game only a colour itself is an ally", () => {
  const s = team({}, { teams: false });
  assert.ok(L.areAllies(s, "red", "red"));
  assert.ok(!L.areAllies(s, "red", "yellow"));
});

t("a partner on the destination is NOT captured", () => {
  // red 1 + 3 -> 4 (ring 4). yellow enters at 26, so yellow 30 is ring 4.
  const s = team({ red: [1, -1, -1, -1], yellow: [30, -1, -1, -1] }, { dice: 3 });
  const m = L.legalMoves(s, 3).find((x) => x.tokenIndex === 0);
  assert.strictEqual(m.captures.length, 0, "sent its own side home");
});

t("an opponent on the destination IS captured", () => {
  // green enters at 13, so green 43 is ring 4.
  const s = team({ red: [1, -1, -1, -1], green: [43, -1, -1, -1] }, { dice: 3 });
  const m = L.legalMoves(s, 3).find((x) => x.tokenIndex === 0);
  assert.strictEqual(m.captures.length, 1);
  assert.strictEqual(m.captures[0].colour, "green");
});

t("the same partner IS captured when teams are off", () => {
  const s = team(
    { red: [1, -1, -1, -1], yellow: [30, -1, -1, -1] },
    { dice: 3, teams: false }
  );
  const m = L.legalMoves(s, 3).find((x) => x.tokenIndex === 0);
  assert.strictEqual(m.captures[0].colour, "yellow");
});

t("teamHasWon needs BOTH partners home", () => {
  assert.ok(!L.teamHasWon(team({}, { winners: ["red"] })));
  assert.ok(!L.teamHasWon(team({}, { winners: ["red", "green"] })));
  assert.ok(L.teamHasWon(team({}, { winners: ["red", "yellow"] })));
});

t("teamHasWon is false for a solo game however many have finished", () => {
  assert.ok(
    !L.teamHasWon(team({}, { teams: false, winners: ["red", "yellow"] }))
  );
});

t("the flag survives a roll and a move", () => {
  // Same silent failure as in Dart: lose the flag and the next capture sends a
  // partner home.
  let s = team({ red: [1, -1, -1, -1] });
  const r = L.applyRoll(s, 3);
  assert.strictEqual(r.state.teams, true, "dropped on applyRoll");
  const after = L.applyMove(r.state, r.moves.find((m) => m.tokenIndex === 0));
  assert.strictEqual(after.teams, true, "dropped on applyMove");
});

// --- Does a team game actually finish? -------------------------------------
// No friendly fire means fewer captures, which means tokens are sent back less
// often. If that tipped the balance the wrong way, games would run for ever —
// so this plays them out rather than assuming.
let buf = crypto.randomBytes(65536);
let bi = 0;
function die() {
  let b;
  do {
    if (bi >= buf.length) {
      buf = crypto.randomBytes(65536);
      bi = 0;
    }
    b = buf[bi++];
  } while (b >= 252);
  return (b % 6) + 1;
}

t("2v2 games finish, and each side wins about half the time", () => {
  let unfinished = 0;
  let redSide = 0;
  let total = 0;
  const N = 1200;
  for (let g = 0; g < N; g++) {
    let s = team({});
    let rolls = 0;
    while (!L.teamHasWon(s) && rolls < 40000) {
      const r = L.applyRoll(s, die());
      rolls++;
      s = r.state;
      if (r.moves.length) {
        s = L.applyMove(s, L.chooseBotMove(s.players[s.turn], r.moves));
      }
    }
    if (!L.teamHasWon(s)) {
      unfinished++;
      continue;
    }
    total += rolls;
    if (["red", "yellow"].includes(s.winners[0])) redSide++;
  }
  const share = (100 * redSide) / (N - unfinished);
  console.log(
    `        ${N} games, avg ${Math.round(total / (N - unfinished))} rolls, ` +
      `red+yellow won ${share.toFixed(1)}%`
  );
  assert.strictEqual(unfinished, 0, `${unfinished} team games never ended`);
  // Two sides, so anything far from 50% would mean the pairing favours one.
  assert.ok(share > 40 && share < 60, `sides are unbalanced: ${share}%`);
});

t("isDecided stops a solo table at the first winner", () => {
  assert.ok(L.isDecided(team({}, { teams: false, winners: ["red"] })));
  assert.ok(!L.isDecided(team({}, { teams: false, winners: [] })));
});

t("isDecided does NOT stop a 2v2 until a whole side is home", () => {
  // The bug this guards: the bot turn and the stuck-game sweeper both used
  // winners.length > 0, so in a team game they downed tools — and marked the
  // room finished — the moment one partner came home.
  assert.ok(!L.isDecided(team({}, { winners: ["red"] })));
  assert.ok(!L.isDecided(team({}, { winners: ["red", "green"] })));
  assert.ok(L.isDecided(team({}, { winners: ["red", "yellow"] })));
});

console.log(`
${pass} passed`);
