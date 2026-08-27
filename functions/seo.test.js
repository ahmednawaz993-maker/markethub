"use strict";

// Tests for the server-rendered ad page.
//   Run:  cd functions && node seo.test.js
// Exits non-zero if any assertion fails.
//
// The point of this file is one property above all others: NOTHING PRIVATE MAY
// REACH THE PAGE. This code exists because making the listings collection
// publicly readable would have published every seller's phone number, so a
// regression here would reintroduce exactly the leak it was written to avoid.
// The renderer takes a whole listing document — phone, coordinates and all —
// and every test below feeds it one and checks what comes out the other side.

const assert = require("assert");

// getFirestore() is only called inside a request handler, so requiring the
// module without a Firebase app is safe.
const { _internal } = require("./seo");
const { esc, clamp, publicView, headTags, seoBody, renderShell } = _internal;

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ok  ${name}`);
  } catch (e) {
    console.error(`FAIL  ${name}\n      ${e.message}`);
    process.exitCode = 1;
  }
}

/** A realistic document, shaped exactly like the live ones. */
const DOC = {
  title: "Royal Blue Pure Washing wear",
  price: "2800",
  description: "Stuff ke bhee garuntee hai aur Color ke bhii",
  city: "Attock",
  location: "sanjwal Buffa Cloth House", // a street address
  phone: "+923125611042", // THE thing that must never escape
  latitude: 33.7,
  longitude: 72.36,
  category: "Garments",
  subcategory: "Unstitched Fabric",
  condition: "New",
  sellerName: "Buffa Cloth House",
  userId: "XU598owx39XPAJBM3qcKXnPgIOu2",
  imageUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/a.jpg",
  images: ["https://firebasestorage.googleapis.com/v0/b/x/o/a.jpg"],
  approvalStatus: "approved",
};

const URL = "https://pakbazar24.com/ad/abc123";

console.log("seo.js");

test("the public view is an allowlist — no phone, no coordinates", () => {
  const v = publicView("abc123", DOC);
  const keys = Object.keys(v);
  for (const forbidden of [
    "phone",
    "latitude",
    "longitude",
    "userId",
    "location",
  ]) {
    assert.ok(!keys.includes(forbidden), `publicView leaked "${forbidden}"`);
  }
  assert.strictEqual(v.title, DOC.title);
  assert.strictEqual(v.city, "Attock");
});

test("a phone number cannot reach the rendered page", () => {
  // The strongest form of the check: render everything and search the output.
  const v = publicView("abc123", DOC);
  const out = headTags(v, URL) + seoBody(v, URL);
  for (const secret of [
    DOC.phone,
    "923125611042",
    "3125611042",
    String(DOC.latitude),
    String(DOC.longitude),
    DOC.location,
    DOC.userId,
  ]) {
    assert.ok(
      !out.includes(secret),
      `rendered page contains private value "${secret}"`
    );
  }
});

test("a field added to listings later does not become public by default", () => {
  // The allowlist is the guarantee. A denylist would have missed this.
  const v = publicView("abc123", {
    ...DOC,
    sellerCnic: "37405-1234567-1",
    buyerEmail: "someone@example.com",
  });
  const out = JSON.stringify(v) + headTags(v, URL) + seoBody(v, URL);
  assert.ok(!out.includes("37405-1234567-1"));
  assert.ok(!out.includes("someone@example.com"));
});

test("seller-written HTML is escaped, not executed", () => {
  // Titles and descriptions are user content served to every visitor, so the
  // check is per CONTEXT, not a substring scan of the whole page. The payload
  // text may legitimately survive inside the JSON-LD block (covered below);
  // what must never survive is the ability to START A TAG or CLOSE AN
  // ATTRIBUTE in HTML.
  const evil = {
    ...DOC,
    title: `<script>alert(1)</script>`,
    description: `" onload="alert(2)` + " <img src=x onerror=alert(3)>",
    sellerName: "</title><script>alert(4)</script>",
  };
  const v = publicView("abc123", evil);
  const head = headTags(v, URL);
  const body = seoBody(v, URL);

  // Everything outside the JSON-LD block is HTML, and must be escaped.
  const ldStart = head.indexOf("<script type=");
  const htmlOnly = head.slice(0, ldStart) + body;
  assert.ok(!htmlOnly.includes("<script"), "a tag was injected into HTML");
  assert.ok(!htmlOnly.includes("<img src=x"), "a tag was injected into HTML");
  // Exactly one — the one we wrote. A second would mean the seller name
  // closed it early.
  assert.strictEqual(
    (htmlOnly.match(/<\/title>/g) || []).length,
    1,
    "seller name closed the title"
  );
  assert.ok(!htmlOnly.includes(`onload="alert`), "an attribute was injected");
  assert.ok(htmlOnly.includes("&lt;script&gt;"), "expected escaped output");
});

test("the JSON-LD block cannot be broken out of", () => {
  // Inside <script type="application/ld+json"> the escaping rule is different:
  // HTML entities would corrupt the data, and the only escape is a literal
  // "</script". Every "<" becomes <, so no tag can begin, and JSON
  // stringification already neutralises quotes.
  const v = publicView("abc123", {
    ...DOC,
    description: `</script><img src=x onerror=alert(1)>`,
    title: `" } , "x": "`,
  });
  const head = headTags(v, URL);
  // Just the payload: what sits between the opening tag and its closer. The
  // closing </script> we wrote ourselves obviously contains a "<", so scanning
  // the whole block would only ever find our own tag.
  const OPEN = '<script type="application/ld+json">';
  const payload = head.slice(
    head.indexOf(OPEN) + OPEN.length,
    head.indexOf("</script>", head.indexOf(OPEN))
  );
  assert.ok(!payload.includes("<"), "an unescaped < survived in JSON-LD");
  assert.ok(payload.includes("\\u003c"), "expected < to be escaped");
  // ...and it is still valid JSON, so the structured data actually parses.
  const parsed = JSON.parse(payload);
  assert.strictEqual(parsed["@type"], "Product");
  // Proof nothing truncated it: the payload really is the whole object.
  assert.ok(parsed.description.includes("onerror"), "payload was cut short");
});

test("a title that closes the JSON-LD script cannot break out", () => {
  const v = publicView("abc123", { ...DOC, title: `x</script><script>y` });
  const out = headTags(v, URL);
  const ld = out.slice(out.indexOf("application/ld+json"));
  assert.ok(!ld.includes("</script><script>y"), "JSON-LD escaped early");
});

test("escaping covers every dangerous character", () => {
  assert.strictEqual(esc(`<>&"'`), "&lt;&gt;&amp;&quot;&#39;");
  assert.strictEqual(esc(null), "");
  assert.strictEqual(esc(undefined), "");
});

test("descriptions are clamped for the meta tag", () => {
  const long = "a".repeat(400);
  const v = publicView("abc123", { ...DOC, description: long });
  const out = headTags(v, URL);
  const m = out.match(/<meta name="description" content="([^"]*)"/);
  assert.ok(m, "no description meta");
  assert.ok(m[1].length <= 156, `description too long: ${m[1].length}`);
});

test("clamp collapses whitespace and never cuts mid-nothing", () => {
  assert.strictEqual(clamp("  a   b  ", 50), "a b");
  assert.strictEqual(clamp("abcdef", 4), "abc…");
});

test("the head carries what a crawler and a link preview need", () => {
  const v = publicView("abc123", DOC);
  const out = headTags(v, URL);
  for (const needle of [
    "<title>",
    'rel="canonical"',
    'property="og:title"',
    'property="og:image"',
    'property="og:url"',
    'name="twitter:card"',
    "application/ld+json",
    "PKR",
  ]) {
    assert.ok(out.includes(needle), `head is missing ${needle}`);
  }
  assert.ok(out.includes("Royal Blue"), "title not in head");
  assert.ok(out.includes("Attock"), "city not in head");
});

test("a sold ad is marked sold, not silently listed as available", () => {
  const v = publicView("abc123", { ...DOC, status: "sold" });
  const out = headTags(v, URL) + seoBody(v, URL);
  assert.ok(out.includes("SoldOut"), "schema should say SoldOut");
  assert.ok(out.includes("Sold"), "page should say Sold");
});

test("a listing with no images still renders a valid og:image", () => {
  const v = publicView("abc123", { ...DOC, imageUrl: "", images: [] });
  assert.ok(v.image.startsWith("https://"), `bad fallback image: ${v.image}`);
  assert.ok(headTags(v, URL).includes('property="og:image"'));
});

test("a non-http image url is rejected rather than rendered", () => {
  // javascript: in an <img src> is inert, but it has no business here.
  const v = publicView("abc123", {
    ...DOC,
    imageUrl: "javascript:alert(1)",
    images: ["javascript:alert(2)"],
  });
  assert.ok(!v.image.startsWith("javascript:"), "javascript: url survived");
  assert.ok(!seoBody(v, URL).includes("javascript:"));
});

test("rendering replaces the shell's title and splash, keeping the bootstrap", () => {
  const shell = `<!DOCTYPE html><html><head>
<title>PakBazar - Buy &amp; Sell in Pakistan</title>
<meta name="description" content="generic">
</head><body>
  <div id="pb-splash"><img src="splash_logo.png"></div>
  <script>
    window.addEventListener('flutter-first-frame', function () {
      var s = document.getElementById('pb-splash');
      if (s) { s.remove(); }
    });
  </script>
  <script src="flutter_bootstrap.js" async></script>
</body></html>`;
  const html = renderShell(shell, publicView("abc123", DOC), URL);

  assert.ok(!html.includes("Buy &amp; Sell in Pakistan"), "generic title kept");
  assert.ok(!html.includes('content="generic"'), "generic description kept");
  assert.ok(html.includes("Royal Blue"), "listing title missing");
  assert.ok(html.includes('id="pb-seo"'), "seo block missing");
  assert.ok(!html.includes('id="pb-splash"'), "splash not replaced");
  // The app must still boot: this page is for people too.
  assert.ok(html.includes("flutter_bootstrap.js"), "bootstrap dropped");
  // ...and the first-frame handler must now clear the block we inserted.
  assert.ok(html.includes("getElementById('pb-seo')"), "cleanup not rewired");
  assert.ok(!html.includes(DOC.phone), "phone reached the final HTML");
});

test("exactly one title and one canonical survive", () => {
  const shell = `<html><head><title>old</title></head><body><div id="pb-splash">x</div><script>var s = document.getElementById('pb-splash');</script></body></html>`;
  const html = renderShell(shell, publicView("abc123", DOC), URL);
  assert.strictEqual((html.match(/<title>/g) || []).length, 1);
  assert.strictEqual((html.match(/rel="canonical"/g) || []).length, 1);
});

console.log(`\n${passed} passed`);
if (process.exitCode) console.error("SOME TESTS FAILED");
