"use strict";

// ---------------------------------------------------------------------------
// Budget Calculator & Rate List (AI) — the Firebase half. Pure logic and its
// tests live in ai_helper.js / ai_helper.test.js.
//
// Rate lists: Gemini searches Google for today's prices in a city and the
// result is cached in `aiRateLists/{city}`. The scheduler refreshes the big
// cities every morning; any other city is generated the first time somebody
// opens it that day. Clients never read the collection directly — they go
// through aiRateList — so no rules change was needed and the cache stays
// server-only (default deny). Same for `aiUsage`.
//
// Budget advice: a single structured-output call over the user's own numbers,
// grounded on the cached rate list for their city when there is one.
//
// Runs on the Gemini API FREE tier: gemini-2.5-flash includes Google Search
// grounding (500 requests/day as of 2026-10). No billing account is attached,
// so going over the quota fails the call (429) instead of charging anything.
//
// Set the key once (free, from aistudio.google.com/apikey) with:
//   firebase functions:secrets:set GEMINI_API_KEY
// ---------------------------------------------------------------------------

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const aiHelper = require("./ai_helper");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const AI_MODEL = "gemini-2.5-flash";

// The free tier answers 503 "high demand" (and 429/500) in bursts; a short
// pause usually clears it.
const RETRY_STATUSES = [429, 500, 503];
const RETRY_DELAYS_MS = [5000, 15000];

/**
 * One generateContent call. Returns the first candidate, or throws with the
 * API's own error message (quota, bad key, ...) so it lands in the logs.
 */
async function gemini(body) {
  let res;
  let json;
  for (let attempt = 0; ; attempt++) {
    res = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models/" +
        `${AI_MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": GEMINI_API_KEY.value(),
        },
        body: JSON.stringify(body),
      }
    );
    json = await res.json().catch(() => ({}));
    const delay = RETRY_DELAYS_MS[attempt];
    if (res.ok || !RETRY_STATUSES.includes(res.status) || delay === undefined) {
      break;
    }
    await new Promise((r) => setTimeout(r, delay));
  }
  if (!res.ok) {
    const msg = (json.error && json.error.message) || res.statusText;
    throw new Error(`Gemini ${res.status}: ${msg}`);
  }
  const candidate = json.candidates && json.candidates[0];
  if (!candidate) {
    const reason = json.promptFeedback && json.promptFeedback.blockReason;
    throw new Error(`Gemini returned no candidate (${reason || "unknown"})`);
  }
  return candidate;
}

/** Text of every text part, joined (thought parts skipped). */
function responseText(candidate) {
  return ((candidate.content && candidate.content.parts) || [])
    .filter((p) => typeof p.text === "string" && !p.thought)
    .map((p) => p.text)
    .join("");
}

/**
 * Asks Gemini to research today's prices for [city] with Google Search and
 * returns the validated list, or null when nothing usable came back.
 */
async function generateRateList(city) {
  const candidate = await gemini({
    systemInstruction: { parts: [{ text: aiHelper.RATE_SYSTEM }] },
    contents: [
      {
        role: "user",
        parts: [{ text: aiHelper.buildRatePrompt(city, Date.now()) }],
      },
    ],
    tools: [{ google_search: {} }],
    generationConfig: { maxOutputTokens: 16000 },
  });
  const list = aiHelper.sanitizeRateList(
    aiHelper.extractJson(responseText(candidate))
  );
  if (!list) {
    console.warn("generateRateList unusable", city, candidate.finishReason);
    return null;
  }
  return {
    ...list,
    sources: aiHelper.collectSources(candidate.groundingMetadata),
  };
}

async function refreshRateList(db, city) {
  const list = await generateRateList(city);
  if (!list) return null;
  const doc = { ...list, city, updatedAt: Timestamp.now(), model: AI_MODEL };
  await db.collection("aiRateLists").doc(aiHelper.rateDocId(city)).set(doc);
  return doc;
}

/** Counts one AI call (free-tier quota) against the user's daily allowance. */
async function takeAiAllowance(db, uid, kind) {
  const ref = db.collection("aiUsage").doc(uid);
  const today = aiHelper.pkDayKey(Date.now());
  const ok = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const next = aiHelper.nextUsage(
      snap.exists ? snap.data() : null,
      kind,
      today
    );
    if (!next) return false;
    tx.set(ref, next);
    return true;
  });
  if (!ok) {
    throw new HttpsError(
      "resource-exhausted",
      "You have used today's AI requests. Please try again tomorrow."
    );
  }
}

function rateListReply(doc) {
  return {
    city: doc.city,
    categories: doc.categories || [],
    summary: doc.summary || "",
    sources: doc.sources || [],
    // The app posts raw HTTP rather than using the cloud_functions SDK, so a
    // numeric reply is safe (no dart2js Int64 decoding trap).
    updatedAt: doc.updatedAt ? doc.updatedAt.toMillis() : Date.now(),
  };
}

exports.aiRateList = onCall(
  { secrets: [GEMINI_API_KEY], timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to see rates.");
    const city = request.data && request.data.city;
    if (!aiHelper.isRateCity(city)) {
      throw new HttpsError("invalid-argument", "Pick a city from the list.");
    }
    const db = getFirestore();
    const ref = db.collection("aiRateLists").doc(aiHelper.rateDocId(city));
    const snap = await ref.get();
    const cached = snap.exists ? snap.data() : null;
    if (
      cached &&
      cached.updatedAt &&
      aiHelper.isFresh(cached.updatedAt.toMillis(), Date.now())
    ) {
      return rateListReply(cached);
    }
    await takeAiAllowance(db, uid, "rates");
    let fresh = null;
    try {
      fresh = await refreshRateList(db, city);
    } catch (e) {
      console.error("aiRateList", city, e);
    }
    // Yesterday's list beats no list; the app shows its date.
    if (fresh) return rateListReply(fresh);
    if (cached) return rateListReply(cached);
    throw new HttpsError(
      "unavailable",
      "Could not fetch today's rates. Please try again shortly."
    );
  }
);

// 05:00 in Pakistan, before the markets open.
exports.refreshAiRateLists = onSchedule(
  {
    schedule: "0 5 * * *",
    timeZone: "Asia/Karachi",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 1800,
    memory: "512MiB",
  },
  async () => {
    const db = getFirestore();
    const queue = [...aiHelper.PREWARM_CITIES];
    // A city that fails (busy model, unusable reply) gets one more go at the
    // back of the queue; until then it keeps yesterday's list.
    const retried = new Set();
    let ok = 0;
    const worker = async () => {
      while (queue.length) {
        const city = queue.shift();
        let done = false;
        try {
          done = Boolean(await refreshRateList(db, city));
        } catch (e) {
          console.error("refreshAiRateLists", city, e);
        }
        if (done) {
          ok++;
        } else if (!retried.has(city)) {
          retried.add(city);
          queue.push(city);
        }
      }
    };
    await Promise.all([worker(), worker(), worker()]);
    console.log(
      `refreshAiRateLists: ${ok}/${aiHelper.PREWARM_CITIES.length} refreshed`
    );
  }
);

exports.aiBudgetAdvice = onCall(
  { secrets: [GEMINI_API_KEY], timeoutSeconds: 120 },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    // Guests are anonymous accounts, and a fresh one is a fresh allowance —
    // so the per-user cap only means something for registered users. Rate
    // lists don't need this: the city cache bounds their cost on its own.
    const provider =
      request.auth && request.auth.token.firebase &&
      request.auth.token.firebase.sign_in_provider;
    if (!uid || provider === "anonymous") {
      throw new HttpsError("unauthenticated", "Sign in to get AI advice.");
    }
    let budget;
    try {
      budget = aiHelper.sanitizeBudgetInput(request.data);
    } catch (msg) {
      throw new HttpsError("invalid-argument", String(msg));
    }
    const db = getFirestore();
    await takeAiAllowance(db, uid, "budget");

    let digest = "";
    if (budget.city) {
      const snap = await db
        .collection("aiRateLists")
        .doc(aiHelper.rateDocId(budget.city))
        .get();
      if (snap.exists) digest = aiHelper.rateListDigest(snap.data());
    }

    let candidate;
    try {
      candidate = await gemini({
        systemInstruction: { parts: [{ text: aiHelper.BUDGET_SYSTEM }] },
        contents: [
          {
            role: "user",
            parts: [{ text: aiHelper.buildBudgetPrompt(budget, digest) }],
          },
        ],
        generationConfig: {
          maxOutputTokens: 16000,
          responseMimeType: "application/json",
          responseJsonSchema: aiHelper.BUDGET_SCHEMA,
        },
      });
    } catch (e) {
      console.error("aiBudgetAdvice", e);
      throw new HttpsError(
        "unavailable",
        "The adviser is busy. Please try again shortly."
      );
    }
    if (candidate.finishReason === "SAFETY") {
      throw new HttpsError("failed-precondition", "Could not review this budget.");
    }
    // The schema should give bare JSON; extractJson also copes with fences.
    const parsed = aiHelper.extractJson(responseText(candidate));
    const advice = aiHelper.sanitizeBudgetAdvice(parsed);
    if (!advice) {
      throw new HttpsError(
        "unavailable",
        "Could not review this budget. Please try again."
      );
    }
    return advice;
  }
);
