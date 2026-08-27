"use strict";

// Server-rendered listing pages, so search engines and link previews can
// actually read an ad.
//
// WHY THIS EXISTS RATHER THAN A RULES CHANGE. The obvious move — make the
// listings collection publicly readable — does not work, for two independent
// reasons:
//
//  1. Nothing to read. The app is Flutter/CanvasKit: it paints into a <canvas>,
//     so the DOM holds no text at all. Every /ad/{id} URL returned the identical
//     2,616-byte shell with the same generic <title> and no og: tags. A crawler
//     would index 165 copies of one blank page no matter what the rules said.
//  2. It would publish phone numbers. Every listing document carries the
//     seller's mobile number, and Firestore rules cannot filter fields on read —
//     a public read is a read of the WHOLE document. Public rules would put 165
//     Pakistani mobile numbers (and 22 sets of exact coordinates) in front of
//     every scraper on the internet, permanently.
//
// Rendering here solves both. This runs with the Admin SDK, so the rules are
// untouched and this code decides field by field what leaves the database:
// title, price, city, description, images. Never the phone, never lat/lng.
//
// It is also not cloaking. Every visitor gets the same HTML — there is no
// user-agent sniffing. A human sees the listing text immediately (instead of a
// blank splash) and Flutter then boots over it, showing the same content.

const { onRequest } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");

const SITE = "https://pakbazar24.com";
const SHELL_URL = `${SITE}/index.html`;
const SHELL_TTL_MS = 10 * 60 * 1000;

let shellCache = { html: null, at: 0 };

/** The deployed app shell, cached per instance so a hit is not a round trip. */
async function appShell() {
  const now = Date.now();
  if (shellCache.html && now - shellCache.at < SHELL_TTL_MS) {
    return shellCache.html;
  }
  const res = await fetch(SHELL_URL, { redirect: "follow" });
  if (!res.ok) throw new Error(`shell fetch ${res.status}`);
  const html = await res.text();
  shellCache = { html, at: now };
  return html;
}

/**
 * Escapes text for HTML. Listing titles and descriptions are written by
 * sellers, so this is the difference between a marketplace and a stored-XSS
 * hole that we would be serving to every visitor and every crawler.
 */
function esc(v) {
  return String(v == null ? "" : v)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** JSON for a <script> block: `</script>` inside a string would end it early. */
function jsonLd(obj) {
  return JSON.stringify(obj).replace(/</g, "\\u003c");
}

function clamp(s, n) {
  const t = String(s == null ? "" : s).replace(/\s+/g, " ").trim();
  return t.length <= n ? t : `${t.slice(0, n - 1).trimEnd()}…`;
}

/**
 * The subset of a listing that is safe to publish.
 *
 * An allowlist, deliberately, not a denylist: a field added to listings later
 * must not become public because nobody remembered to exclude it here.
 */
function publicView(id, d) {
  const images = Array.isArray(d.images)
    ? d.images.filter((u) => typeof u === "string" && u.startsWith("http"))
    : [];
  const image =
    typeof d.imageUrl === "string" && d.imageUrl.startsWith("http")
      ? d.imageUrl
      : images[0] || `${SITE}/icons/Icon-192.png`;
  return {
    id,
    title: String(d.title || "Listing"),
    price: String(d.price || ""),
    // City only. The free-text `location` is often a house or shop address the
    // seller wrote for a buyer they had already agreed to meet — not something
    // to publish to the open web, and not needed for search relevance.
    city: String(d.city || ""),
    description: String(d.description || ""),
    category: String(d.category || ""),
    subcategory: String(d.subcategory || ""),
    condition: String(d.condition || ""),
    sellerName: String(d.sellerName || ""),
    isSold: d.status === "sold" || d.isSold === true,
    image,
    images: images.slice(0, 6),
  };
}

/** The head tags a crawler and a link preview actually read. */
function headTags(v, url) {
  const title = `${clamp(v.title, 70)}${v.city ? ` in ${esc(v.city)}` : ""} | PakBazar`;
  const desc = clamp(
    v.description || `${v.title} for sale on PakBazar.`,
    155
  );
  const priceText = v.price ? `PKR ${v.price}` : "";
  const ld = {
    "@context": "https://schema.org",
    "@type": "Product",
    name: v.title,
    description: desc,
    image: v.images.length ? v.images : [v.image],
    category: [v.category, v.subcategory].filter(Boolean).join(" > "),
    itemCondition:
      v.condition && /new/i.test(v.condition)
        ? "https://schema.org/NewCondition"
        : "https://schema.org/UsedCondition",
    offers: {
      "@type": "Offer",
      url,
      priceCurrency: "PKR",
      price: String(v.price || "").replace(/[^\d.]/g, "") || undefined,
      availability: v.isSold
        ? "https://schema.org/SoldOut"
        : "https://schema.org/InStock",
      areaServed: v.city || "Pakistan",
      seller: v.sellerName
        ? { "@type": "Organization", name: v.sellerName }
        : undefined,
    },
  };
  return `
  <title>${esc(title)}</title>
  <meta name="description" content="${esc(desc)}">
  <link rel="canonical" href="${esc(url)}">
  <meta property="og:type" content="product">
  <meta property="og:site_name" content="PakBazar">
  <meta property="og:title" content="${esc(clamp(v.title, 90))}">
  <meta property="og:description" content="${esc(desc)}">
  <meta property="og:url" content="${esc(url)}">
  <meta property="og:image" content="${esc(v.image)}">
  <meta property="og:locale" content="en_PK">
  ${priceText ? `<meta property="product:price:amount" content="${esc(String(v.price).replace(/[^\d.]/g, ""))}">
  <meta property="product:price:currency" content="PKR">` : ""}
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${esc(clamp(v.title, 90))}">
  <meta name="twitter:description" content="${esc(desc)}">
  <meta name="twitter:image" content="${esc(v.image)}">
  <script type="application/ld+json">${jsonLd(ld)}</script>`;
}

/**
 * The visible block, which replaces the loading splash on an ad URL.
 *
 * It is real content in normal flow, not hidden text: before Flutter boots the
 * visitor reads the listing, and once the app paints its first frame the block
 * is removed and the app shows the same thing. Faster for people, and legible
 * to a crawler that runs no JavaScript.
 */
function seoBody(v, url) {
  const price = v.price ? `PKR ${esc(v.price)}` : "";
  const bits = [v.category, v.subcategory, v.condition, v.city]
    .filter(Boolean)
    .map(esc)
    .join(" · ");
  return `
  <div id="pb-seo">
    <a class="pb-seo-brand" href="/"><img src="/splash_logo.png" alt="PakBazar" height="44"></a>
    <h1>${esc(v.title)}</h1>
    ${price ? `<p class="pb-seo-price">${price}${v.isSold ? ' <span class="pb-seo-sold">Sold</span>' : ""}</p>` : ""}
    ${bits ? `<p class="pb-seo-meta">${bits}</p>` : ""}
    <img class="pb-seo-img" src="${esc(v.image)}" alt="${esc(v.title)}">
    ${v.description ? `<p class="pb-seo-desc">${esc(v.description)}</p>` : ""}
    ${v.sellerName ? `<p class="pb-seo-meta">Sold by ${esc(v.sellerName)}</p>` : ""}
    <p class="pb-seo-cta"><a href="${esc(url)}">Open in PakBazar to contact the seller</a></p>
    <noscript><p class="pb-seo-meta">Enable JavaScript to use PakBazar.</p></noscript>
  </div>`;
}

const SEO_CSS = `
  <style>
    #pb-seo {
      max-width: 640px; margin: 0 auto; padding: 20px 18px 48px;
      font-family: -apple-system, Roboto, Arial, sans-serif; color: #101828;
    }
    html[data-theme="dark"] #pb-seo { color: #E7ECF3; }
    #pb-seo .pb-seo-brand { display: inline-block; margin-bottom: 12px; }
    #pb-seo h1 { font-size: 21px; line-height: 1.3; margin: 0 0 8px; }
    #pb-seo .pb-seo-price { font-size: 19px; font-weight: 800; margin: 0 0 6px; color: #173A6B; }
    html[data-theme="dark"] #pb-seo .pb-seo-price { color: #83ABE8; }
    #pb-seo .pb-seo-sold {
      font-size: 12px; font-weight: 700; color: #B42318;
      background: rgba(180,35,24,.10); border-radius: 999px; padding: 2px 8px; vertical-align: middle;
    }
    #pb-seo .pb-seo-meta { font-size: 13px; color: #667085; margin: 0 0 10px; }
    #pb-seo .pb-seo-img { width: 100%; height: auto; border-radius: 12px; margin: 10px 0 14px; }
    #pb-seo .pb-seo-desc { font-size: 15px; line-height: 1.55; white-space: pre-wrap; }
    #pb-seo .pb-seo-cta a { color: #173A6B; font-weight: 700; }
  </style>`;

/** Swaps the splash for the listing block and hard-codes the strings we need. */
function renderShell(shell, v, url) {
  let html = shell;
  // Drop the generic title/description so ours is the only one.
  html = html.replace(/<title>[\s\S]*?<\/title>/i, "");
  html = html.replace(/<meta\s+name="description"[^>]*>/i, "");
  html = html.replace("</head>", `${headTags(v, url)}\n${SEO_CSS}\n</head>`);
  // Replace the loading splash: on an ad URL there is something better to show.
  html = html.replace(
    /<div id="pb-splash">[\s\S]*?<\/div>\s*(?=<script>)/i,
    `${seoBody(v, url)}\n  `
  );
  html = html.replace(
    /var s = document\.getElementById\('pb-splash'\);/,
    "var s = document.getElementById('pb-splash') || document.getElementById('pb-seo');"
  );
  return html;
}

function notFoundPage(url) {
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ad not available | PakBazar</title>
<meta name="robots" content="noindex">
<link rel="canonical" href="${esc(SITE)}">
</head><body style="font-family:-apple-system,Roboto,Arial,sans-serif;max-width:560px;margin:0 auto;padding:48px 20px;color:#101828">
<h1 style="font-size:20px">This ad is no longer available</h1>
<p style="color:#667085">It may have been sold or removed by the seller.</p>
<p><a href="${esc(SITE)}" style="color:#173A6B;font-weight:700">Browse PakBazar</a></p>
</body></html>`;
}

/**
 * GET /ad/{listingId}
 *
 * Falls back to the untouched app shell on any failure. A rendering problem
 * must degrade to "the app loads normally", never to an error page — this
 * function sits in front of a URL people share.
 */
exports.adPage = onRequest(
  { region: "us-central1", memory: "256MiB", invoker: "public" },
  async (req, res) => {
    const id = (req.path || "").split("/").filter(Boolean).pop() || "";
    const url = `${SITE}/ad/${encodeURIComponent(id)}`;
    try {
      const snap = await getFirestore().collection("listings").doc(id).get();
      const d = snap.exists ? snap.data() : null;
      // Only approved ads are published. An unapproved or deleted one is
      // noindex, so a rejected listing never enters the search index.
      if (!d || d.approvalStatus !== "approved") {
        res.set("Cache-Control", "public, max-age=300");
        res.status(404).type("html").send(notFoundPage(url));
        return;
      }
      const shell = await appShell();
      res.set("Cache-Control", "public, max-age=300, s-maxage=900");
      res.status(200).type("html").send(renderShell(shell, publicView(id, d), url));
    } catch (err) {
      console.error("adPage failed", id, err);
      try {
        res.set("Cache-Control", "no-store");
        res.status(200).type("html").send(await appShell());
      } catch (_) {
        res.status(302).set("Location", SITE).end();
      }
    }
  }
);

/**
 * GET /sitemap.xml
 *
 * Without this Google has no way to discover 165 ad URLs — nothing on the site
 * links to them, because the navigation is painted into a canvas.
 */
exports.sitemapXml = onRequest(
  { region: "us-central1", memory: "256MiB", invoker: "public" },
  async (_req, res) => {
    try {
      const snap = await getFirestore()
        .collection("listings")
        .where("approvalStatus", "==", "approved")
        .limit(10000)
        .get();
      const urls = snap.docs.map((doc) => {
        const t = doc.data().createdAt;
        const iso =
          t && typeof t.toDate === "function"
            ? t.toDate().toISOString().slice(0, 10)
            : null;
        return `  <url><loc>${esc(`${SITE}/ad/${doc.id}`)}</loc>${
          iso ? `<lastmod>${iso}</lastmod>` : ""
        }<changefreq>weekly</changefreq></url>`;
      });
      res.set("Cache-Control", "public, max-age=3600");
      res.status(200).type("application/xml").send(
        `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>${SITE}/</loc><changefreq>daily</changefreq><priority>1.0</priority></url>
${urls.join("\n")}
</urlset>`
      );
    } catch (err) {
      console.error("sitemapXml failed", err);
      res.status(500).type("text/plain").send("sitemap unavailable");
    }
  }
);

// Exported for unit tests.
exports._internal = { esc, clamp, publicView, headTags, seoBody, renderShell };
