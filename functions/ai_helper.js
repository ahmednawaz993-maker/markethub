"use strict";

// Budget Calculator & Rate List — the pure half.
//
// Everything here is free of Firebase and the network so it can be tested with
// plain `node ai_helper.test.js`: which cities and categories exist, the
// prompts, and — most importantly — the validation of what the model sends
// back. A rate list is shown to people deciding what to pay for flour, so a
// malformed or absurd answer must be dropped here rather than rendered.

// Same list, same order, as kPakistanPrayerCities in lib/src/prayer_times.dart.
// The city is part of the cache key, so it has to come from a closed set —
// otherwise any string a client sends becomes a fresh (paid) generation.
const RATE_CITIES = [
  "Karachi", "Lahore", "Faisalabad", "Rawalpindi", "Islamabad", "Gujranwala",
  "Peshawar", "Multan", "Hyderabad", "Quetta", "Bahawalpur", "Sargodha",
  "Sialkot", "Sukkur", "Larkana", "Sheikhupura", "Mardan", "Gujrat", "Kasur",
  "Rahim Yar Khan", "Sahiwal", "Okara", "Wah Cantonment", "Dera Ghazi Khan",
  "Mingora", "Nawabshah", "Chiniot", "Kotri", "Khanpur", "Hafizabad", "Kohat",
  "Jhang", "Muzaffargarh", "Khanewal", "Abbottabad", "Mirpur Khas",
  "Jacobabad", "Attock", "Gilgit", "Muzaffarabad",
];

// Refreshed every morning by the scheduler so most people never wait. The
// rest are generated the first time somebody asks that day.
const PREWARM_CITIES = RATE_CITIES.slice(0, 10);

// A cached list is served until it is this old.
const RATE_TTL_MS = 20 * 60 * 60 * 1000;

const RATE_CATEGORIES = [
  {
    id: "groceries",
    label: "Groceries",
    hint: "atta (20 kg bag), rice (basmati, per kg), sugar, cooking oil / ghee " +
      "(per litre or kg), daal (moong, masoor, chana), tea (per kg)",
  },
  {
    id: "vegetables_fruits",
    label: "Vegetables & Fruit",
    hint: "potatoes, onions, tomatoes, garlic, ginger, seasonal vegetables, " +
      "bananas (per dozen), apples, seasonal fruit — per kg unless noted",
  },
  {
    id: "meat_dairy",
    label: "Meat, Milk & Eggs",
    hint: "beef, mutton, chicken (live and meat), fresh milk (per litre), " +
      "yogurt, eggs (per dozen)",
  },
  {
    id: "fuel_transport",
    label: "Fuel & Transport",
    hint: "petrol and high-speed diesel (official OGRA/government price per " +
      "litre), LPG (per kg and 11.8 kg cylinder), CNG if sold",
  },
  {
    id: "utilities",
    label: "Bills & Utilities",
    hint: "typical domestic electricity per unit, gas bill bands, basic home " +
      "internet package, mobile data bundle",
  },
  {
    id: "construction",
    label: "Construction",
    hint: "cement (50 kg bag), steel/sarya (per kg or ton), bricks (per 1000), " +
      "sand and crush (per truck or cubic foot)",
  },
];
const CATEGORY_IDS = RATE_CATEGORIES.map((c) => c.id);

function isRateCity(city) {
  return typeof city === "string" && RATE_CITIES.includes(city);
}

/** Firestore doc id for a city's list. */
function rateDocId(city) {
  return city.toLowerCase().replace(/[^a-z0-9]+/g, "_");
}

function isFresh(updatedAtMs, nowMs) {
  return typeof updatedAtMs === "number" && nowMs - updatedAtMs < RATE_TTL_MS;
}

/** Calendar date in Pakistan, e.g. "26 October 2026". */
function pkDate(nowMs) {
  return new Date(nowMs).toLocaleDateString("en-GB", {
    timeZone: "Asia/Karachi",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

const RATE_SYSTEM =
  "You compile a daily market rate list for ordinary households in Pakistan. " +
  "Use web search to find CURRENT prices — official notifications (district " +
  "price control committees, OGRA, NEPRA, PBS SPI), recent Pakistani news and " +
  "price-tracking sites. Prefer sources from the last few days; if a city " +
  "has nothing local, use the nearest big city or the national figure and " +
  "say so in that item's note. Give realistic retail ranges in Pakistani " +
  "rupees. Never invent precision you do not have: a wider range is better " +
  "than a wrong exact number. Reply with ONLY the JSON object requested, no " +
  "prose before or after it.";

function buildRatePrompt(city, nowMs) {
  const cats = RATE_CATEGORIES.map(
    (c) => `- "${c.id}" (${c.label}): ${c.hint}`
  ).join("\n");
  return (
    `Today is ${pkDate(nowMs)}. Build today's rate list for ${city}, Pakistan.\n\n` +
    `Categories (6–10 items each):\n${cats}\n\n` +
    "Return exactly this JSON shape:\n" +
    "{\n" +
    '  "categories": [\n' +
    '    {"id": "<category id>", "items": [\n' +
    '      {"name": "Atta (flour)", "unit": "20 kg bag", "low": 2600, ' +
    '"high": 2900, "note": "optional, short"}\n' +
    "    ]}\n" +
    "  ],\n" +
    '  "summary": "one or two sentences on what is notable this week"\n' +
    "}\n" +
    "low and high are whole rupees (numbers, not strings). Leave out any item " +
    "you could not find a credible current price for."
  );
}

/** Pulls the first top-level JSON object out of the model's text. */
function extractJson(text) {
  if (typeof text !== "string") return null;
  const start = text.indexOf("{");
  if (start < 0) return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) {
        try {
          return JSON.parse(text.slice(start, i + 1));
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}

function cleanText(v, max) {
  if (typeof v !== "string") return "";
  return v.replace(/\s+/g, " ").trim().slice(0, max);
}

function toRupees(v) {
  const n = typeof v === "string" ? Number(v.replace(/[^0-9.]/g, "")) : v;
  return typeof n === "number" && Number.isFinite(n) ? Math.round(n) : NaN;
}

// Nothing a household buys here costs under Rs 1 or over Rs 5 crore; outside
// that is a parsing accident (a phone number, a year) rather than a price.
const MIN_PRICE = 1;
const MAX_PRICE = 50000000;

/**
 * Validates a parsed rate list. Returns null when nothing usable survives —
 * the caller then keeps yesterday's list rather than publishing an empty one.
 */
function sanitizeRateList(raw) {
  if (!raw || !Array.isArray(raw.categories)) return null;
  const byId = new Map();
  for (const cat of raw.categories) {
    if (!cat || !CATEGORY_IDS.includes(cat.id) || byId.has(cat.id)) continue;
    const items = [];
    for (const it of Array.isArray(cat.items) ? cat.items : []) {
      if (!it) continue;
      const name = cleanText(it.name, 60);
      const unit = cleanText(it.unit, 30);
      let low = toRupees(it.low);
      let high = toRupees(it.high);
      if (Number.isNaN(high)) high = low;
      if (Number.isNaN(low)) low = high;
      if (!name || Number.isNaN(low)) continue;
      if (low > high) [low, high] = [high, low];
      if (low < MIN_PRICE || high > MAX_PRICE) continue;
      // A range wider than 4x says the model was unsure, not that the market is.
      if (high > low * 4) continue;
      items.push({ name, unit, low, high, note: cleanText(it.note, 120) });
      if (items.length >= 12) break;
    }
    if (items.length) byId.set(cat.id, items);
  }
  if (byId.size === 0) return null;
  return {
    // Fixed category order, whatever order the model used.
    categories: RATE_CATEGORIES.filter((c) => byId.has(c.id)).map((c) => ({
      id: c.id,
      label: c.label,
      items: byId.get(c.id),
    })),
    summary: cleanText(raw.summary, 400),
  };
}

/** Distinct source URLs from the web_search results in a response. */
function collectSources(content, max = 8) {
  const out = [];
  for (const block of Array.isArray(content) ? content : []) {
    if (!block || block.type !== "web_search_tool_result") continue;
    // A failed search returns an error OBJECT here instead of a list.
    if (!Array.isArray(block.content)) continue;
    for (const r of block.content) {
      if (!r || typeof r.url !== "string" || !/^https?:\/\//.test(r.url)) {
        continue;
      }
      if (out.some((s) => s.url === r.url)) continue;
      out.push({ url: r.url, title: cleanText(r.title, 100) });
      if (out.length >= max) return out;
    }
  }
  return out;
}

// --------------------------------------------------------------------------
// Budget advice
// --------------------------------------------------------------------------

const EXPENSE_KEYS = [
  "rent", "groceries", "utilities", "transport", "education", "health",
  "loans", "committee", "other",
];

const MAX_MONTHLY = 100000000; // Rs 10 crore — above this is a typo

function money(v) {
  const n = toRupees(v);
  return Number.isNaN(n) || n < 0 ? 0 : Math.min(n, MAX_MONTHLY);
}

/** Validates the client's budget form; throws a message string on bad input. */
function sanitizeBudgetInput(data) {
  const d = data || {};
  const city = isRateCity(d.city) ? d.city : "";
  const familySize = Math.max(1, Math.min(30, Math.round(Number(d.familySize) || 1)));
  const income = money(d.income);
  const expenses = {};
  for (const k of EXPENSE_KEYS) expenses[k] = money((d.expenses || {})[k]);
  const lang = d.lang === "ur" ? "ur" : "en";
  if (income === 0 && EXPENSE_KEYS.every((k) => expenses[k] === 0)) {
    throw "Enter your income or at least one expense first.";
  }
  return { city, familySize, income, expenses, lang };
}

function budgetTotals(b) {
  const spent = EXPENSE_KEYS.reduce((s, k) => s + b.expenses[k], 0);
  return { spent, left: b.income - spent };
}

const BUDGET_SYSTEM =
  "You are a practical, kind household-budget adviser for families in " +
  "Pakistan. Give concrete, local advice: committees (BC), utility-store and " +
  "Sasta Bazaar savings, buying atta and ghee in bulk, slab-aware " +
  "electricity use, school-fee and transport options, avoiding high-interest " +
  "informal loans. Be realistic about low incomes — never shame, never " +
  "suggest anything risky or haram (no interest-based schemes, no " +
  "gambling). Amounts are monthly, in Pakistani rupees.";

function buildBudgetPrompt(b, rateSummary) {
  const t = budgetTotals(b);
  const lines = EXPENSE_KEYS.filter((k) => b.expenses[k] > 0)
    .map((k) => `- ${k}: Rs ${b.expenses[k].toLocaleString("en-US")}`)
    .join("\n");
  return (
    `City: ${b.city || "not given"}. Family size: ${b.familySize}.\n` +
    `Monthly income: Rs ${b.income.toLocaleString("en-US")}.\n` +
    `Monthly expenses:\n${lines || "- none entered"}\n` +
    `Total spent: Rs ${t.spent.toLocaleString("en-US")}; ` +
    `left over: Rs ${t.left.toLocaleString("en-US")}.\n` +
    (rateSummary ? `\nToday's local prices (for reference):\n${rateSummary}\n` : "") +
    "\nReview this budget. Point out anything that looks high for this " +
    "family size and city, suggest where they could save and roughly how " +
    "much, and a sensible monthly savings target. Keep each tip one or two " +
    "sentences. " +
    (b.lang === "ur"
      ? "Write every string in simple Urdu (Urdu script)."
      : "Write in simple English.")
  );
}

const BUDGET_SCHEMA = {
  type: "object",
  properties: {
    summary: { type: "string" },
    savingsTarget: { type: "integer" },
    tips: { type: "array", items: { type: "string" } },
    warnings: { type: "array", items: { type: "string" } },
  },
  required: ["summary", "savingsTarget", "tips", "warnings"],
  additionalProperties: false,
};

function sanitizeBudgetAdvice(raw) {
  if (!raw || typeof raw.summary !== "string") return null;
  const list = (v, n) =>
    (Array.isArray(v) ? v : []).map((s) => cleanText(s, 300)).filter(Boolean).slice(0, n);
  return {
    summary: cleanText(raw.summary, 600),
    savingsTarget: money(raw.savingsTarget),
    tips: list(raw.tips, 8),
    warnings: list(raw.warnings, 4),
  };
}

/** A compact text form of a cached rate list, fed to the budget adviser. */
function rateListDigest(list, perCategory = 4) {
  if (!list || !Array.isArray(list.categories)) return "";
  return list.categories
    .map((c) =>
      `${c.label}: ` +
      c.items
        .slice(0, perCategory)
        .map((i) => `${i.name} ${i.unit} Rs ${i.low}–${i.high}`)
        .join("; ")
    )
    .join("\n");
}

// Per-user daily allowance of AI calls that cost money. Cached rate lists are
// free and do not count.
const DAILY_LIMITS = { budget: 10, rates: 5 };

/** Next usage counters, or null when today's allowance is spent. */
function nextUsage(prev, kind, todayKey) {
  const fresh = !prev || prev.day !== todayKey;
  const used = fresh ? 0 : Number(prev[kind]) || 0;
  if (used >= DAILY_LIMITS[kind]) return null;
  const base = fresh ? { day: todayKey } : { ...prev };
  base[kind] = used + 1;
  return base;
}

function pkDayKey(nowMs) {
  return new Date(nowMs + 5 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

module.exports = {
  RATE_CITIES,
  PREWARM_CITIES,
  RATE_CATEGORIES,
  RATE_TTL_MS,
  RATE_SYSTEM,
  BUDGET_SYSTEM,
  BUDGET_SCHEMA,
  EXPENSE_KEYS,
  DAILY_LIMITS,
  isRateCity,
  rateDocId,
  isFresh,
  buildRatePrompt,
  extractJson,
  sanitizeRateList,
  collectSources,
  sanitizeBudgetInput,
  budgetTotals,
  buildBudgetPrompt,
  sanitizeBudgetAdvice,
  rateListDigest,
  nextUsage,
  pkDayKey,
};
