"use strict";

// The six-player board, server side.
//   Run:  cd functions && node ludo_six.test.js
//
// The server rolls the dice and plays the bots, so it has to know the hexagon
// as well as the phone does. These values are asserted against the Dart spec in
// lib/src/ludo_engine.dart — not recomputed here with the same formula, which
// would agree with itself however wrong both sides were.

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

console.log("ludo_logic — six players");

t("the four-seat spec still produces the old hard-coded constants", () => {
  // The whole refactor is only safe if this holds. These are the literals this
  // file carried before the board became a spec.
  const f = L.specFor(4);
  assert.strictEqual(f.ringLength, 52);
  assert.strictEqual(f.lastRingStep, 50);
  assert.strictEqual(f.home, 56);
  assert.deepStrictEqual(f.colours, ["red", "green", "yellow", "blue"]);
  assert.deepStrictEqual(f.colours.map(f.startCell), [0, 13, 26, 39]);
  assert.deepStrictEqual(
    [...f.safeCells].sort((a, b) => a - b),
    [0, 8, 13, 21, 26, 34, 39, 47]
  );
  assert.deepStrictEqual(f.arrows, { 2: 9, 15: 22, 28: 35, 41: 48 });
});

t("the six-seat spec matches LudoBoardSpec.six in Dart", () => {
  const x = L.specFor(6);
  assert.strictEqual(x.ringLength, 72);
  assert.strictEqual(x.spacing, 12);
  assert.strictEqual(x.lastRingStep, 70);
  assert.strictEqual(x.home, 76);
  assert.deepStrictEqual(x.colours.map(x.startCell), [0, 12, 24, 36, 48, 60]);
});

t("the board is chosen by how many are seated", () => {
  for (const n of [2, 3, 4]) assert.strictEqual(L.specFor(n).seats, 4);
  for (const n of [5, 6]) assert.strictEqual(L.specFor(n).seats, 6);
  assert.strictEqual(L.specOf({ players: ["red", "green"] }).seats, 4);
  assert.strictEqual(
    L.specOf({ players: ["red", "green", "yellow", "blue", "purple", "orange"] })
      .seats,
    6
  );
});

t("a six-player state uses hexagon geometry, not the cross", () => {
  // Green enters at 12 on the hexagon and at 13 on the cross. Reading the wrong
  // board would put every green token one square out for the whole game.
  const six = { players: L.specFor(6).colours };
  const four = { players: L.specFor(4).colours };
  assert.strictEqual(L.specOf(six).startCell("green"), 12);
  assert.strictEqual(L.specOf(four).startCell("green"), 13);
});

function sixState(positions, extra = {}) {
  const spec = L.specFor(6);
  const base = {};
  for (const c of spec.colours) base[c] = [-1, -1, -1, -1];
  return {
    players: spec.colours,
    positions: { ...base, ...positions },
    turn: 0,
    sixes: 0,
    winners: [],
    captured: [],
    dice: null,
    mode: "classic",
    ...extra,
  };
}

t("only a six opens the yard on the hexagon too", () => {
  const s = sixState({});
  for (let d = 1; d <= 5; d++) {
    assert.strictEqual(L.legalMoves(s, d).length, 0, `a ${d} opened the yard`);
  }
  assert.ok(L.legalMoves(s, 6).length > 0);
});

t("a capture is computed on the 72-ring", () => {
  // red 1 + 4 -> 5. green enters at 12, so green 65 is ring (12+65)%72 = 5.
  const s = sixState({ red: [1, -1, -1, -1], green: [65, -1, -1, -1] }, { dice: 4 });
  const m = L.legalMoves(s, 4).find((x) => x.tokenIndex === 0);
  assert.strictEqual(m.to, 5);
  assert.strictEqual(m.captures.length, 1);
  assert.strictEqual(m.captures[0].colour, "green");
});

t("home must still be reached exactly", () => {
  const spec = L.specFor(6);
  const s = sixState({ red: [spec.home - 3, -1, -1, -1] }, { dice: 3 });
  assert.ok(L.legalMoves(s, 3).some((m) => m.to === spec.home));
  assert.ok(!L.legalMoves(s, 4).some((m) => m.tokenIndex === 0));
});

// --- Whole games ------------------------------------------------------------
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

t("six-player games played by the SERVER all finish", () => {
  // The bots are the server's, so this exercises the path a real online table
  // takes when players time out or seats are filled by computers.
  const spec = L.specFor(6);
  let unfinished = 0;
  let total = 0;
  const N = 600;
  for (let g = 0; g < N; g++) {
    let s = sixState({});
    let rolls = 0;
    while (s.winners.length < spec.seats - 1 && rolls < 40000) {
      const r = L.applyRoll(s, die());
      rolls++;
      s = r.state;
      if (r.moves.length) {
        s = L.applyMove(s, L.chooseBotMove(s.players[s.turn], r.moves, spec));
      }
    }
    if (s.winners.length < spec.seats - 1) {
      unfinished++;
      continue;
    }
    total += rolls;
  }
  console.log(`        ${N} games, avg ${Math.round(total / (N - unfinished))} rolls`);
  assert.strictEqual(unfinished, 0, `${unfinished} six-player games never ended`);
});

console.log(`\n${pass} passed`);
