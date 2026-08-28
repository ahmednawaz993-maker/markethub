"use strict";

// Unit tests for the server-side Ludo roll. No Firebase required.
//   Run:  cd functions && node ludo_logic.test.js
// Exits non-zero if any assertion fails.
//
// This file exists to catch DRIFT. ludo_logic.js is a second implementation of
// part of lib/src/ludo_engine.dart, and two copies of a rule drift silently —
// so these mirror the cases in test/ludo_engine_test.dart deliberately. If a
// rule changes in Dart and not here, the server and the phone will disagree
// about whether a roll was playable, and the game will stall mid-turn.

const assert = require("assert");
const {
  IN_YARD,
  HOME,
  ringCell,
  legalMoves,
  applyRoll,
  applyMove,
  chooseBotMove,
  isTurnStale,
  isSeatToMove,
  hasPendingRoll,
} = require("./ludo_logic");

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

const ALL = ["red", "green", "yellow", "blue"];
function stateWith(positions, extra = {}) {
  return {
    players: Object.keys(positions),
    positions,
    turn: 0,
    sixes: 0,
    winners: [],
    dice: null,
    ...extra,
  };
}
function fresh(players = ALL) {
  const positions = {};
  for (const p of players) positions[p] = [IN_YARD, IN_YARD, IN_YARD, IN_YARD];
  return stateWith(positions);
}

console.log("ludo_logic");

// -- geometry, matching the Dart ringCell tests -----------------------------

t("progress maps onto the shared ring, wrapping at 52", () => {
  assert.strictEqual(ringCell("red", 0), 0);
  assert.strictEqual(ringCell("yellow", 0), 26);
  assert.strictEqual(ringCell("yellow", 30), 4);
  assert.strictEqual(ringCell("blue", 50), 37);
  assert.strictEqual(ringCell("red", IN_YARD), null);
  assert.strictEqual(ringCell("red", 51), null, "home column is off the ring");
  assert.strictEqual(ringCell("red", HOME), null);
});

// -- leaving the yard --------------------------------------------------------

t("only a six opens the yard", () => {
  const s = fresh();
  for (let d = 1; d <= 5; d++) {
    assert.strictEqual(legalMoves(s, d).length, 0, `rolled ${d}`);
  }
  assert.strictEqual(legalMoves(s, 6).length, 4);
});

t("a six places the token on the start square, not six past it", () => {
  assert.strictEqual(legalMoves(fresh(), 6)[0].to, 0);
});

t("a non-six with everything in the yard passes the turn", () => {
  const r = applyRoll(fresh(), 3);
  assert.strictEqual(r.moves.length, 0);
  assert.strictEqual(r.state.players[r.state.turn], "green");
  assert.strictEqual(r.state.dice, null);
});

t("a six with no legal move keeps the turn", () => {
  const s = stateWith({
    red: [HOME, HOME, HOME, 55],
    green: [IN_YARD, IN_YARD, IN_YARD, IN_YARD],
  });
  const r = applyRoll(s, 6); // 55 + 6 overshoots
  assert.strictEqual(r.moves.length, 0);
  assert.strictEqual(r.state.players[r.state.turn], "red");
});

// -- capturing ---------------------------------------------------------------

t("landing on an opponent on an unsafe square captures it", () => {
  const s = stateWith({
    red: [4, IN_YARD, IN_YARD, IN_YARD],
    green: [46, IN_YARD, IN_YARD, IN_YARD], // green 46 == cell 7
  });
  assert.strictEqual(ringCell("green", 46), 7);
  const m = legalMoves(s, 3).find((x) => x.captures.length > 0);
  assert.ok(m, "expected a capturing move");
  assert.strictEqual(m.captures[0].colour, "green");
});

t("nobody is captured on a safe square", () => {
  const s = stateWith({
    red: [4, IN_YARD, IN_YARD, IN_YARD],
    green: [47, IN_YARD, IN_YARD, IN_YARD], // cell 8, a star
  });
  assert.strictEqual(ringCell("green", 47), 8);
  const m = legalMoves(s, 4).find((x) => x.tokenIndex === 0);
  assert.strictEqual(m.captures.length, 0);
});

t("a token in its home column cannot be captured", () => {
  const s = stateWith({
    red: [4, IN_YARD, IN_YARD, IN_YARD],
    green: [53, IN_YARD, IN_YARD, IN_YARD],
  });
  for (let d = 1; d <= 6; d++) {
    for (const m of legalMoves(s, d)) {
      assert.strictEqual(m.captures.length, 0, `rolled ${d}`);
    }
  }
});

// -- the home stretch --------------------------------------------------------

t("home must be reached exactly", () => {
  const s = stateWith({
    red: [53, IN_YARD, IN_YARD, IN_YARD],
    green: [IN_YARD, IN_YARD, IN_YARD, IN_YARD],
  });
  assert.strictEqual(legalMoves(s, 3).filter((m) => m.tokenIndex === 0).length, 1);
  assert.strictEqual(legalMoves(s, 4).filter((m) => m.tokenIndex === 0).length, 0);
  assert.strictEqual(legalMoves(s, 6).filter((m) => m.tokenIndex === 0).length, 0);
});

t("your own tokens may share a square", () => {
  // This used to assert the opposite. The restriction was removed because it
  // made the game misbehave in two reported ways: a six could not open the
  // yard while your own token stood on the start, and with tokens out a roll
  // offered only some of them.
  const s = stateWith({
    red: [4, 6, IN_YARD, IN_YARD],
    green: [IN_YARD, IN_YARD, IN_YARD, IN_YARD],
  });
  assert.strictEqual(legalMoves(s, 2).filter((m) => m.tokenIndex === 0).length, 1);
  assert.strictEqual(legalMoves(s, 2).filter((m) => m.tokenIndex === 1).length, 1);
});

t("every token out is a token that can be moved", () => {
  // The second report, exactly: four tokens on the board, a three rolled, and
  // the player expects a choice of four.
  const s = stateWith({
    red: [3, 4, 5, 6],
    green: [IN_YARD, IN_YARD, IN_YARD, IN_YARD],
  });
  assert.strictEqual(legalMoves(s, 3).length, 4);
});

t("a six opens the yard even when your own token is on the start", () => {
  // The reported bug, on the server side: the start square is safe, so your
  // own pieces may share it. Must match LudoGame.legalMoves exactly — if the
  // server refuses what the phone offers, the move silently fails.
  const s = stateWith({
    red: [0, IN_YARD, IN_YARD, IN_YARD],
    green: [IN_YARD, IN_YARD, IN_YARD, IN_YARD],
  });
  const m = legalMoves(s, 6);
  assert.strictEqual(m.filter((x) => x.from === IN_YARD).length, 3);
  assert.strictEqual(m.filter((x) => x.tokenIndex === 0).length, 1);
});

// -- the six rule ------------------------------------------------------------

t("three sixes running forfeits the turn and moves nothing", () => {
  const s = fresh();
  s.sixes = 2;
  const before = JSON.stringify(s.positions);
  const r = applyRoll(s, 6);
  assert.strictEqual(r.reason, "three_sixes");
  assert.strictEqual(r.moves.length, 0);
  assert.strictEqual(r.state.players[r.state.turn], "green");
  assert.strictEqual(r.state.sixes, 0);
  assert.strictEqual(JSON.stringify(r.state.positions), before);
});

t("a playable roll parks the dice on the document", () => {
  const r = applyRoll(fresh(), 6);
  assert.strictEqual(r.reason, "playable");
  assert.strictEqual(r.state.dice, 6);
  assert.strictEqual(r.state.sixes, 1);
});

t("a non-six resets the six counter", () => {
  const s = fresh();
  s.sixes = 1;
  s.positions.red[0] = 4;
  assert.strictEqual(applyRoll(s, 2).state.sixes, 0);
});

// -- the guards the callable relies on --------------------------------------

t("only the seat to move may roll", () => {
  const s = fresh();
  const seats = { red: "u1", green: "u2" };
  assert.strictEqual(isSeatToMove(s, seats, "u1"), true);
  assert.strictEqual(isSeatToMove(s, seats, "u2"), false, "not green's turn");
  assert.strictEqual(isSeatToMove(s, seats, "stranger"), false);
  assert.strictEqual(isSeatToMove(s, seats, undefined), false);
});

t("a malformed state never authorises a roll", () => {
  assert.strictEqual(isSeatToMove(null, {}, "u1"), false);
  assert.strictEqual(isSeatToMove({}, {}, "u1"), false);
  assert.strictEqual(isSeatToMove({ players: [] }, {}, "u1"), false);
});

// Without this a player could roll over and over until a six turned up.
t("a pending roll blocks a second roll", () => {
  assert.strictEqual(hasPendingRoll({ dice: 4 }), true);
  assert.strictEqual(hasPendingRoll({ dice: null }), false);
  assert.strictEqual(hasPendingRoll({}), false);
});

// -- the property that matters most -----------------------------------------

t("random play always advances; no state rolls forever", () => {
  let seed = 987654321;
  const dice = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return 1 + ((seed >> 16) % 6);
  };
  let s = fresh();
  let rolls = 0;
  let handovers = 0;
  const first = s.turn;
  while (rolls < 5000 && handovers < 50) {
    rolls++;
    const r = applyRoll(s, dice());
    if (r.state.turn !== s.turn) handovers++;
    s = r.state;
    if (r.moves.length > 0) {
      // Consume the roll the way a client would, so the dice never sticks.
      s = { ...s, dice: null };
    }
  }
  assert.ok(handovers > 0, "the turn never moved on");
  assert.notStrictEqual(rolls, 5000, `stuck after ${rolls} rolls from ${first}`);
});

// -- applyMove, needed for bots and for abandoned games ---------------------

t("applying a move advances the token and hands the turn on", () => {
  const s = stateWith(
    {
      red: [4, IN_YARD, IN_YARD, IN_YARD],
      green: [IN_YARD, IN_YARD, IN_YARD, IN_YARD],
    },
    { dice: 2 }
  );
  const m = legalMoves(s, 2).find((x) => x.tokenIndex === 0);
  const next = applyMove(s, m);
  assert.strictEqual(next.positions.red[0], 6);
  assert.strictEqual(next.players[next.turn], "green");
  assert.strictEqual(next.dice, null);
});

t("a capture sends the victim home and keeps the turn", () => {
  const s = stateWith(
    {
      red: [4, IN_YARD, IN_YARD, IN_YARD],
      green: [46, IN_YARD, IN_YARD, IN_YARD],
    },
    { dice: 3 }
  );
  const m = legalMoves(s, 3).find((x) => x.captures.length > 0);
  const next = applyMove(s, m);
  assert.strictEqual(next.positions.green[0], IN_YARD);
  assert.strictEqual(next.players[next.turn], "red", "capture earns a turn");
});

t("bringing the last token home records a winner", () => {
  const s = stateWith(
    {
      red: [HOME, HOME, HOME, 53],
      green: [0, IN_YARD, IN_YARD, IN_YARD],
    },
    { dice: 3 }
  );
  const m = legalMoves(s, 3).find((x) => x.to === HOME);
  assert.deepStrictEqual(applyMove(s, m).winners, ["red"]);
});

// -- the bot -----------------------------------------------------------------

t("the bot prefers a capture over a longer advance", () => {
  const moves = [
    { tokenIndex: 0, from: 4, to: 10, captures: [] },
    {
      tokenIndex: 1,
      from: 2,
      to: 5,
      captures: [{ colour: "green", tokenIndex: 0 }],
    },
  ];
  assert.strictEqual(chooseBotMove("red", moves).tokenIndex, 1);
});

t("the bot prefers going home over leaving the yard", () => {
  const moves = [
    { tokenIndex: 0, from: IN_YARD, to: 0, captures: [] },
    { tokenIndex: 1, from: 53, to: HOME, captures: [] },
  ];
  assert.strictEqual(chooseBotMove("red", moves).tokenIndex, 1);
});

t("the bot always returns one of the offered moves, never null", () => {
  const moves = [{ tokenIndex: 2, from: 1, to: 3, captures: [] }];
  assert.strictEqual(chooseBotMove("red", moves).tokenIndex, 2);
  assert.strictEqual(chooseBotMove("red", []), null);
  assert.strictEqual(chooseBotMove("red", null), null);
});

// -- abandoned games ---------------------------------------------------------

// The failure this fixes: a player closes the app mid-turn and the board is
// frozen forever, because the rules only let the absent player write.
t("a turn goes stale only after the deadline", () => {
  const now = 1000000;
  assert.strictEqual(isTurnStale({}, now - 10000, now, 45), false);
  assert.strictEqual(isTurnStale({}, now - 60000, now, 45), true);
  assert.strictEqual(isTurnStale({}, null, now, 45), false, "unknown is not stale");
  assert.strictEqual(isTurnStale({}, undefined, now, 45), false);
});

t("auto-playing an abandoned turn always advances the game", () => {
  let seed = 24680;
  const roll = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return 1 + ((seed >> 16) % 6);
  };
  let s = fresh();
  let turns = 0;
  while ((s.winners || []).length === 0 && turns < 20000) {
    turns++;
    const r = applyRoll(s, roll());
    s =
      r.moves.length === 0
        ? r.state
        : applyMove(r.state, chooseBotMove(s.players[s.turn], r.moves));
  }
  assert.ok((s.winners || []).length > 0, "no winner after " + turns + " turns");
});

// -- game modes, mirrored from test/ludo_modes_test.dart --------------------
//
// The server rolls and plays the bots, so it decides whether a roll was
// playable at all. If it disagrees with the phone about the Master lock, a
// player is offered a move the server refuses and the turn stalls.

t("Master locks the home column until the colour has captured", () => {
  const base = {
    players: ["red", "green"],
    positions: { red: [48, IN_YARD, IN_YARD, IN_YARD], green: [10, IN_YARD, IN_YARD, IN_YARD] },
    turn: 0,
    sixes: 0,
    winners: [],
    dice: null,
    mode: "master",
    captured: [],
  };
  const shut = legalMoves(base, 5).filter((m) => m.to > 50);
  assert.strictEqual(shut.length, 0, "the column must be shut");

  const open = legalMoves({ ...base, captured: ["red"] }, 5).filter(
    (m) => m.to > 50
  );
  assert.strictEqual(open.length, 1, "a capture opens it");
});

t("a locked token can still travel the ring", () => {
  const s = {
    players: ["red", "green"],
    positions: { red: [30, IN_YARD, IN_YARD, IN_YARD], green: [10, IN_YARD, IN_YARD, IN_YARD] },
    turn: 0, sixes: 0, winners: [], dice: null, mode: "master", captured: [],
  };
  assert.ok(legalMoves(s, 4).length > 0, "it is locked, not frozen");
});

t("Classic never locks the home column", () => {
  const s = {
    players: ["red", "green"],
    positions: { red: [48, IN_YARD, IN_YARD, IN_YARD], green: [10, IN_YARD, IN_YARD, IN_YARD] },
    turn: 0, sixes: 0, winners: [], dice: null, mode: "classic", captured: [],
  };
  assert.strictEqual(legalMoves(s, 5).filter((m) => m.to > 50).length, 1);
});

// A document written before modes existed has no `mode` field at all. It must
// behave as Classic rather than accidentally locking every player out of home.
t("a state with no mode behaves as Classic", () => {
  const s = {
    players: ["red", "green"],
    positions: { red: [48, IN_YARD, IN_YARD, IN_YARD], green: [10, IN_YARD, IN_YARD, IN_YARD] },
    turn: 0, sixes: 0, winners: [], dice: null,
  };
  assert.strictEqual(legalMoves(s, 5).filter((m) => m.to > 50).length, 1);
});

t("applyMove records the Master unlock", () => {
  const s = {
    players: ["red", "green"],
    positions: { red: [4, IN_YARD, IN_YARD, IN_YARD], green: [46, IN_YARD, IN_YARD, IN_YARD] },
    turn: 0, sixes: 0, winners: [], dice: 3, mode: "master", captured: [],
  };
  const cap = legalMoves(s, 3).find((m) => m.captures.length > 0);
  assert.ok(cap, "expected a capture");
  assert.deepStrictEqual(applyMove(s, cap).captured, ["red"]);
});

t("Quick wins on two tokens because that is all a player has", () => {
  const s = {
    players: ["red", "green"],
    positions: { red: [HOME, 53], green: [0, IN_YARD] },
    turn: 0, sixes: 0, winners: [], dice: 3, mode: "quick", captured: [],
  };
  const home = legalMoves(s, 3).find((m) => m.to === HOME);
  assert.deepStrictEqual(applyMove(s, home).winners, ["red"]);
});


// The tests above destructure the exports; the Arrow block below uses a
// namespace so it can assert on the ARROWS table itself.
const L = require("./ludo_logic");

// --- Arrow mode -----------------------------------------------------------
// The arrow table is duplicated from Dart, so it is asserted VALUE BY VALUE
// here. A silent difference would not throw anything; it would just mean the
// phone shows a jump the server does not make, and the game desyncs mid-turn.

t("the arrow table matches kLudoArrows in ludo_engine.dart exactly", () => {
  assert.deepStrictEqual(L.ARROWS, { 2: 9, 15: 22, 28: 35, 41: 48 });
});

t("arrows only apply in arrow mode", () => {
  const base = { mode: "classic" };
  assert.strictEqual(L.arrowJump(base, "red", 2), null);
  assert.strictEqual(L.arrowJump({ mode: "arrow" }, "red", 2), 9);
});

t("an arrow never carries a token past its turn-off", () => {
  const s = { mode: "arrow" };
  for (let p = 0; p <= 50; p++) {
    const j = L.arrowJump(s, "red", p);
    if (j !== null) {
      assert.ok(j <= 50, `arrow from ${p} reached ${j}, past the ring`);
      assert.ok(j > p, `arrow from ${p} went backwards to ${j}`);
      assert.strictEqual(j - p, 7);
    }
  }
});

t("a move onto a tail ends on the head and earns another roll", () => {
  const state = {
    players: ["red", "green"],
    positions: { red: [1, -1, -1, -1], green: [-1, -1, -1, -1] },
    turn: 0,
    sixes: 0,
    winners: [],
    captured: [],
    dice: 1,
    mode: "arrow",
  };
  const moves = L.legalMoves(state, 1);
  const m = moves.find((x) => x.tokenIndex === 0);
  assert.ok(m, "no move for the token on the ring");
  assert.strictEqual(m.to, 9, "did not land on the arrow head");
  assert.strictEqual(m.viaArrow, true);

  const after = L.applyMove(state, m);
  assert.strictEqual(after.positions.red[0], 9);
  // Not a six and no capture, so the extra roll can only come from the arrow.
  assert.strictEqual(after.players[after.turn], "red");
});

t("the same move in classic stops on the tail and passes the turn", () => {
  const state = {
    players: ["red", "green"],
    positions: { red: [1, -1, -1, -1], green: [-1, -1, -1, -1] },
    turn: 0,
    sixes: 0,
    winners: [],
    captured: [],
    dice: 1,
    mode: "classic",
  };
  const m = L.legalMoves(state, 1).find((x) => x.tokenIndex === 0);
  assert.strictEqual(m.to, 2);
  assert.ok(!m.viaArrow);
  assert.strictEqual(L.applyMove(state, m).players[L.applyMove(state, m).turn], "green");
});

t("a capture is resolved at the arrow HEAD, not the tail", () => {
  // Green sitting on ring cell 9 (the head) must be sent home; a green token
  // on cell 2 (the tail) must NOT be, because the token only passes over it.
  const state = {
    players: ["red", "green"],
    positions: { red: [1, -1, -1, -1], green: [-1, -1, -1, -1] },
    turn: 0, sixes: 0, winners: [], captured: [], dice: 1, mode: "arrow",
  };
  // green start is 13, so green progress 48 -> ring (13+48)%52 = 9.
  state.positions.green = [48, -1, -1, -1];
  const m = L.legalMoves(state, 1).find((x) => x.tokenIndex === 0);
  assert.strictEqual(m.to, 9);
  assert.strictEqual(m.captures.length, 1, "should capture on the head");
  assert.strictEqual(m.captures[0].colour, "green");
});
console.log(`\n${pass} passed`);
