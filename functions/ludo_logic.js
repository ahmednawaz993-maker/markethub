"use strict";

// Pure Ludo logic for the server-side dice roll. No Firebase, no credentials —
// index.js requires these and applies the side effects.
//
// WHY THIS EXISTS. The dice used to be generated on the phone, which meant a
// modified client could simply claim a six. The roll now happens here, inside a
// callable function, and firestore.rules forbids any client from writing a
// non-null dice value. A player can consume a roll; nobody can invent one.
//
// MIRROR WARNING. This is a deliberate second implementation of part of
// lib/src/ludo_engine.dart. Two copies of a rule can drift, so only the part
// the server genuinely needs is duplicated — move GENERATION, which is what
// decides whether a roll is playable at all — and ludo_logic.test.js asserts
// the same cases as test/ludo_engine_test.dart. Anything the server does not
// need to decide stays in Dart only.

const IN_YARD = -1;
const LAST_RING_STEP = 50;
const HOME = 56;
const RING_LENGTH = 52;
const SAFE_CELLS = new Set([0, 8, 13, 21, 26, 34, 39, 47]);
const START_CELL = { red: 0, green: 13, yellow: 26, blue: 39 };
const COLOURS = ["red", "green", "yellow", "blue"];

/** Shared-ring cell for a colour's progress, or null when off the ring. */
function ringCell(colour, progress) {
  if (progress < 0 || progress > LAST_RING_STEP) return null;
  return (START_CELL[colour] + progress) % RING_LENGTH;
}

/**
 * Every move the player to move may legally make with `dice`.
 * Mirrors LudoGame.legalMoves. Returns [{tokenIndex, from, to, captures}].
 */
function legalMoves(state, dice) {
  const colour = state.players[state.turn];
  const mine = state.positions[colour] || [];
  const moves = [];

  for (let i = 0; i < mine.length; i++) {
    const from = mine[i];
    if (from === HOME) continue;

    let to;
    if (from === IN_YARD) {
      if (dice !== 6) continue; // only a six opens the yard
      to = 0; // lands ON the start square, not six past it
    } else {
      to = from + dice;
      if (to > HOME) continue; // home must be exact
    }

    const destRing = ringCell(colour, to);
    if (destRing !== null) {
      // A token may not land on one of its own.
      let blocked = false;
      for (let j = 0; j < mine.length; j++) {
        if (j !== i && ringCell(colour, mine[j]) === destRing) blocked = true;
      }
      if (blocked) continue;
    }

    const captures = [];
    if (destRing !== null && !SAFE_CELLS.has(destRing)) {
      for (const other of state.players) {
        if (other === colour) continue;
        const theirs = state.positions[other] || [];
        for (let k = 0; k < theirs.length; k++) {
          if (ringCell(other, theirs[k]) === destRing) {
            captures.push({ colour: other, tokenIndex: k });
          }
        }
      }
    }
    moves.push({ tokenIndex: i, from, to, captures });
  }
  return moves;
}

/** The next seat that has not already finished. */
function nextSeat(state) {
  const done = state.winners || [];
  let t = state.turn;
  for (let i = 0; i < state.players.length; i++) {
    t = (t + 1) % state.players.length;
    if (!done.includes(state.players[t])) return t;
  }
  return state.turn;
}

/**
 * Applies a roll to `state` and returns the new state plus the moves it allows.
 * Mirrors LudoGame.roll.
 *
 * Three outcomes, and the caller does not get to choose between them:
 *  - a third six running burns the turn and moves nothing,
 *  - a roll with playable moves parks the dice on the document for the player
 *    to consume,
 *  - a roll with nothing playable ends the turn immediately (except a six,
 *    which keeps the dice so the player rolls again).
 */
function applyRoll(state, dice) {
  const sixes = dice === 6 ? (state.sixes || 0) + 1 : 0;

  if (sixes >= 3) {
    return {
      state: { ...state, turn: nextSeat(state), sixes: 0, dice: null },
      moves: [],
      reason: "three_sixes",
    };
  }

  const rolled = { ...state, sixes, dice };
  const moves = legalMoves(rolled, dice);
  if (moves.length > 0) return { state: rolled, moves, reason: "playable" };

  return {
    state: {
      ...state,
      turn: dice === 6 ? state.turn : nextSeat(state),
      sixes: dice === 6 ? sixes : 0,
      dice: null,
    },
    moves: [],
    reason: dice === 6 ? "six_no_move" : "no_move",
  };
}

/**
 * Whether `uid` is the player whose turn it is. The callable checks this before
 * rolling, so one player cannot roll on another's behalf.
 */
function isSeatToMove(state, seats, uid) {
  if (!state || !Array.isArray(state.players)) return false;
  const colour = state.players[state.turn];
  return !!colour && !!uid && (seats || {})[colour] === uid;
}

/**
 * Guard against a second roll before the first is played. Without it a player
 * could roll repeatedly until a six appeared.
 */
function hasPendingRoll(state) {
  return state && state.dice !== null && state.dice !== undefined;
}


/**
 * Applies a move and hands the turn on. Mirrors LudoGame.applyMove.
 *
 * Needed on the server for two things the client cannot be trusted with or is
 * not present for: playing a bot's turn, and advancing a game whose player has
 * walked away.
 */
function applyMove(state, move) {
  const colour = state.players[state.turn];
  const positions = {};
  for (const c of state.players) positions[c] = (state.positions[c] || []).slice();
  positions[colour][move.tokenIndex] = move.to;
  for (const cap of move.captures) positions[cap.colour][cap.tokenIndex] = IN_YARD;

  const winners = (state.winners || []).slice();
  if (positions[colour].every((p) => p === HOME) && !winners.includes(colour)) {
    winners.push(colour);
  }

  // A six, a capture, or getting a token home each earn another roll — but a
  // third six running never does.
  const rolledSix = state.dice === 6;
  const another =
    (rolledSix && (state.sixes || 0) < 3) ||
    move.captures.length > 0 ||
    move.to === HOME;

  const next = { ...state, positions, winners, dice: null };
  next.turn = another ? state.turn : nextSeat({ ...state, winners });
  next.sixes = another && rolledSix ? state.sixes : 0;
  return next;
}

/**
 * Picks a move for a bot, or for a player who has abandoned the game.
 *
 * Deliberately a simple ranking rather than a search: Ludo is mostly dice, a
 * deep search would win too often to be fun, and a bot that plays the obvious
 * move is what a human expects to see. Order: take a capture, bring a token
 * home, leave the yard, reach safety, otherwise push the leading token on.
 */
function chooseBotMove(colour, moves) {
  if (!moves || moves.length === 0) return null;
  let best = null;
  let bestScore = -Infinity;
  for (const m of moves) {
    let score = 0;
    score += m.captures.length * 100;
    if (m.to === HOME) score += 80;
    if (m.from === IN_YARD) score += 50;
    const dest = ringCell(colour, m.to);
    if (dest !== null && SAFE_CELLS.has(dest)) score += 20;
    score += m.to / 2;
    if (score > bestScore) {
      bestScore = score;
      best = m;
    }
  }
  return best;
}

/** True when the player to move has had longer than `seconds` to act. */
function isTurnStale(state, updatedAtMillis, nowMillis, seconds) {
  if (!updatedAtMillis) return false;
  return nowMillis - updatedAtMillis > seconds * 1000;
}

module.exports = {
  IN_YARD,
  LAST_RING_STEP,
  HOME,
  RING_LENGTH,
  SAFE_CELLS,
  START_CELL,
  COLOURS,
  ringCell,
  legalMoves,
  nextSeat,
  applyRoll,
  isSeatToMove,
  hasPendingRoll,
  applyMove,
  chooseBotMove,
  isTurnStale,
};
