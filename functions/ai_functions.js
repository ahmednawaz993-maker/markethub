"use strict";

// ---------------------------------------------------------------------------
// Budget Calculator & Rate List (AI) — the Firebase half. Pure logic and its
// tests live in ai_helper.js / ai_helper.test.js.
//
// Rate lists: Claude searches the web for today's prices in a city and the
// result is cached in `aiRateLists/{city}`. The scheduler refreshes the big
// cities every morning; any other city is generated the first time somebody
// opens it that day. Clients never read the collection directly — they go
// through aiRateList — so no rules change was needed and the cache stays
// server-only (default deny). Same for `aiUsage`.
//
// Budget advice: a single structured-output call over the user's own numbers,
// grounded on the cached rate list for their city when there is one.
//
// Set the key once with:
//   firebase functions:secrets:set ANTHROPIC_API_KEY
// ---------------------------------------------------------------------------

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const aiHelper = require("./ai_helper");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const AI_MODEL = "claude-sonnet-5-5";

function anthropicClient() {
  const Anthropic = require("@anthropic-ai/sdk").default;
  return new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });
}

/** Text of every text block, joined (thinking and tool blocks skipped). */
function responseText(content) {
  return (content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
}

/**
 * Asks Claude to research today's prices for [city] and returns the validated
 * list, or null when nothing usable came back.
 */
async function generateRateList(city) {
  const client = anthropicClient();
  const messages = [
    { role: "user", content: aiHelper.buildRatePrompt(city, Date.now()) },
  ];
  const allContent = [];
  let response;
  // Server-side web search can pause a long turn; resume it a couple of times.
  for (let i = 0; i < 3; i++) {
    response = await client.beta.messages.create({
      model: AI_MODEL,
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "medium" },
      system: aiHelper.RATE_SYSTEM,
      tools: [{ type: "web_search_20260209", name: "web_search", max_uses: 8 }],
      messages,
    });
    allContent.push(...response.content);
    if (response.stop_reason !== "pause_turn") break;
    messages.push({ role: "assistant", content: response.content });
  }
  if (response.stop_reason === "refusal") {
    console.warn("generateRateList refused", city, response.stop_details);
    return null;
  }
  const list = aiHelper.sanitizeRateList(
    aiHelper.extractJson(responseText(response.content))
  );
  if (!list) {
    console.warn("generateRateList unusable", city, response.stop_reason);
    return null;
  }
  return { ...list, sources: aiHelper.collectSources(allContent) };
}

async function refreshRateList(db, city) {
  const list = await generateRateList(city);
  if (!list) return null;
  const doc = { ...list, city, updatedAt: Timestamp.now(), model: AI_MODEL };
  await db.collection("aiRateLists").doc(aiHelper.rateDocId(city)).set(doc);
  return doc;
}

/** Counts one paid AI call against the user's daily allowance. */
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
  { secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 300, memory: "512MiB" },
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
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 1800,
    memory: "512MiB",
  },
  async () => {
    const db = getFirestore();
    const queue = [...aiHelper.PREWARM_CITIES];
    let ok = 0;
    const worker = async () => {
      while (queue.length) {
        const city = queue.shift();
        try {
          if (await refreshRateList(db, city)) ok++;
        } catch (e) {
          console.error("refreshAiRateLists", city, e);
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
  { secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 120 },
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

    let response;
    try {
      response = await anthropicClient().beta.messages.create({
        model: AI_MODEL,
        max_tokens: 16000,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: {
          effort: "low",
          format: { type: "json_schema", schema: aiHelper.BUDGET_SCHEMA },
        },
        system: aiHelper.BUDGET_SYSTEM,
        messages: [
          { role: "user", content: aiHelper.buildBudgetPrompt(budget, digest) },
        ],
      });
    } catch (e) {
      console.error("aiBudgetAdvice", e);
      throw new HttpsError(
        "unavailable",
        "The adviser is busy. Please try again shortly."
      );
    }
    if (response.stop_reason === "refusal") {
      throw new HttpsError("failed-precondition", "Could not review this budget.");
    }
    let parsed = null;
    try {
      parsed = JSON.parse(responseText(response.content));
    } catch (_) {
      parsed = null;
    }
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
