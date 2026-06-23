// Generates Play Store screenshot HTML for phone (1080x1920) and fluid
// landscape (tablet/desktop) in the PakBazar navy+gold theme. Render to PNG
// via Chrome headless. Offline-safe (gradients + emoji, no remote images).
const fs = require('fs');
const path = require('path');
const out = path.join(__dirname, 'gen');
fs.mkdirSync(out, { recursive: true });

const NAVY = '#173A6B', DEEP = '#0A1A33', GOLD = '#C9A227', BG = '#eff1f2';
const grads = [
  'linear-gradient(135deg,#dbeafe,#93c5fd)',
  'linear-gradient(135deg,#dcfce7,#bbf7d0)',
  'linear-gradient(135deg,#fef3c7,#fde68a)',
  'linear-gradient(135deg,#ede9fe,#ddd6fe)',
  'linear-gradient(135deg,#ffe4e6,#fecdd3)',
  'linear-gradient(135deg,#cffafe,#a5f3fc)',
  'linear-gradient(135deg,#fae8ff,#f5d0fe)',
  'linear-gradient(135deg,#e0e7ff,#c7d2fe)',
];

// ---- Phone (portrait, 1080x1920, fixed px) -------------------------------
const phoneCss = `
*{margin:0;padding:0;box-sizing:border-box;font-family:Arial,Helvetica,sans-serif;}
html,body{width:1080px;height:1920px;background:${BG};overflow:hidden;}
.status{height:46px;background:${DEEP};color:#fff;display:flex;align-items:center;justify-content:space-between;padding:0 34px;font-size:26px;}
.bar{background:linear-gradient(135deg,${DEEP},${NAVY});color:#fff;padding:28px 30px;display:flex;align-items:center;gap:16px;}
.bar .loc{font-size:36px;font-weight:bold;flex:1;}.bar .ico{font-size:40px;}
.logo{display:flex;align-items:center;gap:14px;font-size:42px;font-weight:bold;}
.logo .bag{width:60px;height:60px;border-radius:15px;background:${GOLD};display:flex;align-items:center;justify-content:center;font-size:34px;}
.gold{color:${GOLD};}
.search{margin:26px 30px;background:#fff;border-radius:60px;padding:30px 38px;color:#777;font-size:34px;box-shadow:0 4px 14px rgba(0,0,0,.08);}
.headline{font-size:48px;font-weight:bold;color:#111;margin:26px 30px 6px;}
.sub{font-size:30px;color:#666;margin:0 30px 18px;}
.cats{display:flex;gap:24px;padding:0 30px 6px;overflow:hidden;}
.cat{text-align:center;width:160px;}
.cat .c{width:130px;height:130px;border-radius:50%;background:#e8eef7;display:flex;align-items:center;justify-content:center;font-size:64px;margin:0 auto 12px;}
.cat span{font-size:27px;color:#333;}
.promo{margin:24px 30px;border-radius:28px;background:linear-gradient(120deg,${NAVY},#2E5AA0);color:#fff;padding:46px;position:relative;overflow:hidden;}
.promo h2{font-size:52px;}.promo p{font-size:31px;margin-top:10px;color:#dbe6f7;}
.promo .pill{display:inline-block;margin-top:26px;background:${GOLD};color:${NAVY};padding:14px 30px;border-radius:40px;font-weight:bold;font-size:28px;}
.promo .star{position:absolute;right:60px;top:40px;font-size:150px;color:rgba(201,162,39,.3);}
.sec{font-size:40px;font-weight:bold;color:#111;margin:30px 30px 18px;}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px;padding:0 30px;}
.card{background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 4px 12px rgba(0,0,0,.08);}
.card .img{height:240px;display:flex;align-items:center;justify-content:center;font-size:96px;position:relative;}
.card .feat{position:absolute;top:14px;left:14px;background:${GOLD};color:${NAVY};font-size:20px;font-weight:bold;padding:6px 14px;border-radius:8px;}
.card .v{position:absolute;top:14px;right:14px;background:#fff;color:${NAVY};font-size:20px;font-weight:bold;padding:6px 12px;border-radius:8px;}
.card .b{padding:16px 18px;}.card .p{font-size:36px;font-weight:bold;color:#111;}
.card .t{font-size:27px;color:#444;margin:4px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.card .l{font-size:23px;color:#888;}
.chips{display:flex;gap:18px;padding:0 30px 10px;flex-wrap:wrap;}
.chip{background:#fff;border:2px solid ${NAVY};color:${NAVY};border-radius:40px;padding:14px 28px;font-size:28px;}
.chip.on{background:${NAVY};color:#fff;}
.panel{background:#fff;margin:26px 30px;border-radius:26px;padding:40px;box-shadow:0 6px 18px rgba(0,0,0,.07);}
.big{height:560px;margin:0 30px;border-radius:26px;display:flex;align-items:center;justify-content:center;font-size:300px;position:relative;}
.price{font-size:64px;font-weight:bold;color:${NAVY};}
.ttl2{font-size:44px;color:#222;margin:10px 0 6px;}.loc2{font-size:30px;color:#888;}
.badges{display:flex;flex-wrap:wrap;gap:14px;margin:24px 0;}
.badge{font-size:27px;font-weight:bold;padding:12px 22px;border-radius:12px;}
.bg-g{background:#dcfce7;color:#15803d;}.bg-d{background:#fef3c7;color:#a16207;}.bg-b{background:#dbeafe;color:#1d4ed8;}
.btn{text-align:center;font-size:36px;font-weight:bold;padding:30px;border-radius:20px;margin-top:20px;}
.btn-g{background:${GOLD};color:${NAVY};}.btn-n{background:${NAVY};color:#fff;}.btn-o{border:3px solid ${NAVY};color:${NAVY};}
.fld{background:#f5f7fa;border:2px solid #e2e6ea;border-radius:16px;padding:26px 24px;font-size:30px;color:#555;margin-bottom:22px;}
.fld b{color:#222;}
.msg{display:flex;margin:18px 0;}.msg.me{justify-content:flex-end;}
.bub{max-width:72%;padding:24px 30px;border-radius:26px;font-size:30px;}
.bub.them{background:#e9edf2;color:#222;border-bottom-left-radius:6px;}
.bub.me2{background:${NAVY};color:#fff;border-bottom-right-radius:6px;}
.safebar{background:#FFF3CD;color:#7a5b00;font-size:26px;padding:24px 30px;margin:0 30px 10px;border-radius:14px;}
.kpi{background:linear-gradient(135deg,${NAVY},#2E5AA0);color:#fff;border-radius:24px;padding:40px;margin:24px 30px;}
.kpi .lbl{font-size:30px;color:#cdddf2;}.kpi .val{font-size:78px;font-weight:bold;}
.mrow{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin:0 30px;}
.mcard{background:#fff;border-radius:18px;padding:28px;box-shadow:0 4px 12px rgba(0,0,0,.06);}
.mcard .mv{font-size:44px;font-weight:bold;color:${NAVY};}.mcard .ml{font-size:26px;color:#888;}
.barrow{display:flex;align-items:center;gap:18px;margin:16px 30px;}
.barrow .lab{width:120px;font-size:26px;color:#555;}
.barrow .track{flex:1;height:40px;background:#e6eaef;border-radius:8px;overflow:hidden;}
.barrow .fill{display:block;height:40px;background:${NAVY};border-radius:8px;}
.nav{position:absolute;bottom:0;left:0;right:0;height:130px;background:#fff;box-shadow:0 -4px 18px rgba(0,0,0,.1);display:flex;align-items:center;justify-content:space-around;}
.nav div{text-align:center;font-size:22px;color:#999;}.nav div.on{color:${NAVY};}.nav .ic{font-size:40px;display:block;}
.sell{position:absolute;bottom:74px;left:50%;transform:translateX(-50%);width:120px;height:120px;border-radius:50%;background:${NAVY};color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:0 6px 18px rgba(0,0,0,.25);}
.sell .plus{font-size:54px;line-height:1;}.sell .ts{font-size:20px;font-weight:bold;}
`;

// ---- Wide (fluid landscape, vmin sizing) ---------------------------------
const wideCss = `
*{margin:0;padding:0;box-sizing:border-box;font-family:Arial,Helvetica,sans-serif;}
html,body{width:100vw;height:100vh;background:${BG};overflow:hidden;}
.top{height:8vmin;background:linear-gradient(135deg,${DEEP},${NAVY});display:flex;align-items:center;gap:2.4vmin;padding:0 3.6vmin;color:#fff;}
.logo{display:flex;align-items:center;gap:1.3vmin;font-size:3.4vmin;font-weight:bold;}
.logo .bag{width:5.2vmin;height:5.2vmin;border-radius:1.3vmin;background:${GOLD};display:flex;align-items:center;justify-content:center;font-size:3vmin;}
.gold{color:${GOLD};}
.search{flex:1;background:#fff;border-radius:4vmin;padding:1.8vmin 2.8vmin;color:#888;font-size:2.4vmin;max-width:64vmin;}
.acts{margin-left:auto;display:flex;gap:2.6vmin;font-size:3vmin;align-items:center;}
.sell{background:${GOLD};color:${NAVY};font-weight:bold;font-size:2.4vmin;padding:1.4vmin 2.8vmin;border-radius:3vmin;}
.wrap{display:flex;height:92vh;}
.side{width:26vmin;background:#fff;padding:2.4vmin 0;border-right:1px solid #e6e8ea;}
.side .h{font-size:2vmin;color:#999;padding:0 2.6vmin 1.2vmin;letter-spacing:1px;}
.side .it{display:flex;align-items:center;gap:1.4vmin;padding:1.5vmin 2.6vmin;font-size:2.5vmin;color:#333;}
.side .it.on{background:#eef3fb;color:${NAVY};font-weight:bold;border-left:.5vmin solid ${NAVY};}
.side .it .e{font-size:2.9vmin;}
.main{flex:1;padding:2.8vmin 3.4vmin;overflow:hidden;}
.headline{font-size:4.4vmin;font-weight:bold;color:#111;margin-bottom:.6vmin;}
.sub{font-size:2.5vmin;color:#666;margin-bottom:2vmin;}
.promo{border-radius:2.4vmin;background:linear-gradient(120deg,${NAVY},#2E5AA0);color:#fff;padding:4vmin;position:relative;overflow:hidden;margin-bottom:2.6vmin;}
.promo h2{font-size:4.6vmin;}.promo p{font-size:2.5vmin;margin-top:1vmin;color:#dbe6f7;}
.promo .pill{display:inline-block;margin-top:2.2vmin;background:${GOLD};color:${NAVY};padding:1.2vmin 2.6vmin;border-radius:3vmin;font-weight:bold;font-size:2.4vmin;}
.promo .star{position:absolute;right:8vmin;top:4vmin;font-size:13vmin;color:rgba(201,162,39,.3);}
.sec{font-size:3.4vmin;font-weight:bold;color:#111;margin:2.4vmin 0 1.6vmin;}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(34vmin,1fr));gap:2.2vmin;}
.card{background:#fff;border-radius:1.8vmin;overflow:hidden;box-shadow:0 .6vmin 1.6vmin rgba(0,0,0,.08);}
.card .img{height:20vmin;display:flex;align-items:center;justify-content:center;font-size:9vmin;position:relative;}
.card .feat{position:absolute;top:1.2vmin;left:1.2vmin;background:${GOLD};color:${NAVY};font-size:1.7vmin;font-weight:bold;padding:.6vmin 1.2vmin;border-radius:.8vmin;}
.card .v{position:absolute;top:1.2vmin;right:1.2vmin;background:#fff;color:${NAVY};font-size:1.8vmin;font-weight:bold;padding:.6vmin 1vmin;border-radius:.8vmin;}
.card .b{padding:1.6vmin 1.8vmin;}.card .p{font-size:3vmin;font-weight:bold;color:#111;}
.card .t{font-size:2.4vmin;color:#444;margin:.5vmin 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.card .l{font-size:2vmin;color:#888;}
.chips{display:flex;gap:1.6vmin;margin-bottom:2vmin;flex-wrap:wrap;}
.chip{background:#fff;border:.25vmin solid ${NAVY};color:${NAVY};border-radius:4vmin;padding:1.2vmin 2.6vmin;font-size:2.4vmin;}
.chip.on{background:${NAVY};color:#fff;}
.two{display:flex;gap:3vmin;}
.big{flex:1.3;border-radius:2.4vmin;display:flex;align-items:center;justify-content:center;font-size:30vmin;position:relative;}
.big .feat{position:absolute;top:2.4vmin;left:2.4vmin;background:${GOLD};color:${NAVY};font-size:2.6vmin;font-weight:bold;padding:1vmin 2.2vmin;border-radius:1vmin;}
.panel{flex:1;background:#fff;border-radius:2.4vmin;padding:4vmin;box-shadow:0 .8vmin 2.4vmin rgba(0,0,0,.07);}
.price{font-size:6.4vmin;font-weight:bold;color:${NAVY};}
.ttl2{font-size:4vmin;color:#222;margin:1.2vmin 0 .6vmin;}.loc2{font-size:2.6vmin;color:#888;}
.badges{display:flex;flex-wrap:wrap;gap:1.4vmin;margin:2.6vmin 0;}
.badge{font-size:2.5vmin;font-weight:bold;padding:1vmin 2vmin;border-radius:1vmin;}
.bg-g{background:#dcfce7;color:#15803d;}.bg-d{background:#fef3c7;color:#a16207;}.bg-b{background:#dbeafe;color:#1d4ed8;}
.btn{text-align:center;font-size:3.2vmin;font-weight:bold;padding:2.4vmin;border-radius:1.6vmin;margin-bottom:1.6vmin;}
.btn-g{background:${GOLD};color:${NAVY};}.btn-n{background:${NAVY};color:#fff;}.btn-o{border:.3vmin solid ${NAVY};color:${NAVY};}
.formwrap{max-width:90vmin;margin:0 auto;}
.fld{background:#f5f7fa;border:.25vmin solid #e2e6ea;border-radius:1.4vmin;padding:2.2vmin;font-size:2.7vmin;color:#555;margin-bottom:2vmin;}
.fld b{color:#222;}
.chatwrap{max-width:120vmin;margin:0 auto;}
.safebar{background:#FFF3CD;color:#7a5b00;font-size:2.4vmin;padding:2vmin 2.6vmin;border-radius:1.2vmin;margin-bottom:2vmin;}
.msg{display:flex;margin:1.6vmin 0;}.msg.me{justify-content:flex-end;}
.bub{max-width:60%;padding:2vmin 2.6vmin;border-radius:2.4vmin;font-size:2.7vmin;}
.bub.them{background:#e9edf2;color:#222;border-bottom-left-radius:.5vmin;}
.bub.me2{background:${NAVY};color:#fff;border-bottom-right-radius:.5vmin;}
.kpi{background:linear-gradient(135deg,${NAVY},#2E5AA0);color:#fff;border-radius:2.4vmin;padding:4vmin;margin-bottom:2.6vmin;}
.kpi .lbl{font-size:2.8vmin;color:#cdddf2;}.kpi .val{font-size:8vmin;font-weight:bold;}
.mrow{display:grid;grid-template-columns:repeat(auto-fill,minmax(30vmin,1fr));gap:2vmin;margin-bottom:2.6vmin;}
.mcard{background:#fff;border-radius:1.8vmin;padding:2.8vmin;box-shadow:0 .4vmin 1.2vmin rgba(0,0,0,.06);}
.mcard .mv{font-size:4vmin;font-weight:bold;color:${NAVY};}.mcard .ml{font-size:2.4vmin;color:#888;}
.barrow{display:flex;align-items:center;gap:1.8vmin;margin:1.4vmin 0;}
.barrow .lab{width:14vmin;font-size:2.4vmin;color:#555;}
.barrow .track{flex:1;height:3.4vmin;background:#e6eaef;border-radius:.8vmin;overflow:hidden;}
.barrow .fill{display:block;height:3.4vmin;background:${NAVY};border-radius:.8vmin;}
.cardrow{display:flex;align-items:center;gap:2vmin;background:#f6f8fa;border-radius:2vmin;padding:2.4vmin;}
.cardrow .av{width:8vmin;height:8vmin;border-radius:50%;background:${NAVY};color:#fff;display:flex;align-items:center;justify-content:center;font-size:4vmin;}
`;

const cardP = (g, e, p, t, l, feat, ver) =>
  `<div class="card"><div class="img" style="background:${g}">${e}${feat ? '<span class="feat">FEATURED</span>' : ''}${ver ? '<span class="v">&#10003; Verified</span>' : ''}</div><div class="b"><div class="p">${p}</div><div class="t">${t}</div><div class="l">&#128205; ${l}</div></div></div>`;

const cat = (e, n) => `<div class="cat"><div class="c">${e}</div><span>${n}</span></div>`;
const sideIt = (e, n, on) => `<div class="it${on ? ' on' : ''}"><span class="e">${e}</span>${n}</div>`;

// Product data reused across screens
const prods = [
  [grads[0], '&#128663;', 'Rs 4,250,000', 'Honda Civic 2021', 'Karachi · 2d', true, true],
  [grads[7], '&#128241;', 'Rs 185,000', 'iPhone 13 Pro', 'Lahore · 5h', false, false],
  [grads[1], '&#127968;', 'Rs 32,000/mo', '2 Bed Apartment', 'Islamabad · 1d', false, false],
  [grads[2], '&#128095;', 'Rs 12,500', 'Nike Air Max', 'Faisalabad · 3h', false, true],
  [grads[3], '&#128187;', 'Rs 95,000', 'Dell XPS Laptop', 'Rawalpindi · 6h', false, false],
  [grads[4], '&#128719;', 'Rs 28,000', 'Wooden Sofa Set', 'Multan · 1d', false, false],
  [grads[5], '&#128247;', 'Rs 65,000', 'Canon DSLR', 'Karachi · 4h', false, false],
  [grads[6], '&#127947;', 'Rs 18,000', 'Treadmill', 'Lahore · 2d', false, false],
];

const cats = [['&#128663;', 'Motors'], ['&#127968;', 'Property'], ['&#128241;', 'Mobiles'], ['&#128421;', 'Electronics'], ['&#128188;', 'Jobs']];
const sideCats = [['&#128663;', 'Motors', 1], ['&#127968;', 'Property'], ['&#128241;', 'Mobiles & Tablets'], ['&#128421;', 'Electronics'], ['&#129681;', 'Home & Furniture'], ['&#128188;', 'Jobs'], ['&#128054;', 'Pets'], ['&#9917;', 'Sports']];

// Screen builders return {phone, wide}
const screens = {};

screens.home = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span class="ico">&#9825;</span><span class="ico">&#128276;</span></div>
  <div class="search">&#128269;&nbsp; Find cars, mobiles, property and more</div>
  <div class="cats">${cats.map(c => cat(c[0], c[1])).join('')}</div>
  <div class="promo"><span class="star">&#9733;</span><h2>Pakistan ka apna<br>online bazaar</h2><p>Buy &amp; sell safely with escrow</p><span class="pill">Explore deals</span></div>
  <div class="sec">Fresh recommendations</div>
  <div class="grid">${prods.slice(0, 4).map(p => cardP(...p)).join('')}</div>
  <div class="sell"><span class="plus">+</span><span class="ts">SELL</span></div>
  <div class="nav"><div class="on"><span class="ic">&#127968;</span>Home</div><div><span class="ic">&#128172;</span>Chats</div><div style="width:120px"></div><div><span class="ic">&#128203;</span>My Ads</div><div><span class="ic">&#128100;</span>Profile</div></div>`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span style="font-size:2.4vmin">&#128205; Karachi &#9662;</span><span class="search">&#128269; Find cars, mobiles, property and more…</span><span class="acts"><span>&#9825;</span><span>&#128276;</span><span class="sell">+ SELL</span></span></div>
  <div class="wrap"><div class="side"><div class="h">CATEGORIES</div>${sideCats.map(c => sideIt(c[0], c[1], c[2])).join('')}</div>
  <div class="main"><div class="promo"><span class="star">&#9733;</span><h2>Pakistan ka apna online bazaar</h2><p>Buy &amp; sell across 280+ cities — safely, with escrow &amp; verified members.</p><span class="pill">Explore deals</span></div>
  <div class="sec">Fresh recommendations</div><div class="grid">${prods.map(p => cardP(...p)).join('')}</div></div></div>`,
};

screens.search = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="loc">Search results</span><span class="ico">&#9662;</span></div>
  <div class="search">&#128269;&nbsp; Honda Civic</div>
  <div class="chips"><span class="chip on">All Pakistan</span><span class="chip">Under 5M</span><span class="chip">2018+</span><span class="chip">Verified</span></div>
  <div class="sec">128 results</div>
  <div class="grid">${[prods[0], prods[1], prods[4], prods[6]].map(p => cardP(...p)).join('')}</div>
  <div class="sell"><span class="plus">+</span><span class="ts">SELL</span></div>
  <div class="nav"><div><span class="ic">&#127968;</span>Home</div><div><span class="ic">&#128172;</span>Chats</div><div style="width:120px"></div><div><span class="ic">&#128203;</span>My Ads</div><div><span class="ic">&#128100;</span>Profile</div></div>`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span class="search">&#128269; Honda Civic</span><span class="acts"><span>&#9825;</span><span>&#128276;</span><span class="sell">+ SELL</span></span></div>
  <div class="main" style="height:92vh"><div class="chips"><span class="chip on">All Pakistan</span><span class="chip">Under Rs 5M</span><span class="chip">2018 onwards</span><span class="chip">Verified sellers</span><span class="chip">Newest first</span></div>
  <div class="sec">128 results for "Honda Civic"</div><div class="grid">${prods.map(p => cardP(...p)).join('')}</div></div>`,
};

const detailPanel = (cls) => `
  <div class="price">Rs 4,250,000</div><div class="ttl2">Honda Civic 2021 — Oriel</div><div class="loc2">&#128205; DHA Phase 6, Karachi · 2 days ago</div>
  <div class="badges"><span class="badge bg-g">&#10003; Verified seller</span><span class="badge bg-d">&#9733; Featured</span><span class="badge bg-b">&#128666; COD</span></div>
  ${cls === 'wide' ? '<div class="cardrow"><div class="av">A</div><div><div style="font-size:3vmin;font-weight:bold">Ahmed Motors</div><div style="font-size:2.4vmin;color:#C9A227">&#9733;&#9733;&#9733;&#9733;&#9733; 4.9 · 128 deals</div></div></div>' : ''}
  <div class="btn btn-g">&#128274; Buy securely with Escrow</div><div class="btn btn-n">&#128172; Chat with seller</div><div class="btn btn-o">&#127991; Make an offer</div>`;

screens.detail = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="loc">&#8592; Ad details</span><span class="ico">&#9825;</span></div>
  <div class="big" style="background:${grads[0]}">&#128663;<span class="feat" style="position:absolute;top:24px;left:24px;background:${GOLD};color:${NAVY};font-size:24px;font-weight:bold;padding:10px 20px;border-radius:10px">&#9733; FEATURED</span></div>
  <div class="panel">${detailPanel('phone')}</div>`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span class="search">&#128269; Find cars, mobiles, property…</span><span class="acts"><span>&#9825;</span><span>&#128276;</span><span class="sell">+ SELL</span></span></div>
  <div class="main" style="height:92vh"><div class="two"><div class="big" style="background:${grads[0]}">&#128663;<span class="feat">&#9733; FEATURED</span></div><div class="panel">${detailPanel('wide')}<div style="font-size:2.2vmin;color:#15803d;text-align:center;margin-top:1vmin">&#128737; Protected by PakBazar escrow</div></div></div></div>`,
};

const chatInner = `
  <div class="safebar">&#9888; Stay safe: keep chat &amp; payment on PakBazar. Never share OTPs or pay in advance.</div>
  <div class="msg"><div class="bub them">Is the Honda Civic still available?</div></div>
  <div class="msg me"><div class="bub me2">Yes it is! Would you like to see it?</div></div>
  <div class="msg"><div class="bub them">Can I pay safely through the app?</div></div>
  <div class="msg me"><div class="bub me2">Absolutely — we'll use PakBazar Escrow. You pay only when you confirm. &#128274;</div></div>
  <div class="msg"><div class="bub them">Great, let's do it &#128077;</div></div>`;

screens.chat = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="loc">Ahmed Motors<br><span style="font-size:24px;color:#cdddf2">Honda Civic 2021</span></span><span class="ico">&#128247;</span></div>
  <div style="padding:10px 30px">${chatInner}</div>`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span style="font-size:3vmin;margin-left:2vmin">Chat — Ahmed Motors</span><span class="acts"><span>&#128276;</span></span></div>
  <div class="main" style="height:92vh"><div class="chatwrap">${chatInner}</div></div>`,
};

const formInner = `
  <div class="fld"><b>Title:</b> Honda Civic 2021 Oriel</div>
  <div class="fld"><b>Category:</b> Motors › Cars</div>
  <div class="fld"><b>Price:</b> Rs 4,250,000</div>
  <div class="fld"><b>City:</b> Karachi &nbsp; &#128205; Add GPS location</div>
  <div class="fld"><b>Phone:</b> +92 300 1234567 *</div>
  <div class="fld" style="color:#999">&#128247; Add up to 8 photos…</div>
  <div class="btn btn-g">Submit ad for review</div>`;

screens.post = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="loc">Sell an item</span></div>
  <div class="headline" style="margin-top:20px">Post your ad in minutes</div>
  <div class="panel" style="margin-top:10px">${formInner}</div>`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span style="font-size:3vmin;margin-left:2vmin">Sell an item</span></div>
  <div class="main" style="height:92vh"><div class="formwrap"><div class="headline">Post your ad in minutes</div><div class="sub">Add photos, set your price, and reach buyers across Pakistan.</div><div class="panel">${formInner}</div></div></div>`,
};

const verifyInner = `
  <div class="fld" style="display:flex;align-items:center;gap:20px"><span style="font-size:50px">&#129331;</span><b>Live selfie</b> &nbsp;<span style="color:#15803d;margin-left:auto">Captured &#10003;</span></div>
  <div class="fld" style="display:flex;align-items:center;gap:20px"><span style="font-size:50px">&#128179;</span><b>CNIC (front)</b> &nbsp;<span style="color:#15803d;margin-left:auto">Captured &#10003;</span></div>
  <div class="fld"><b>Address:</b> House 12, DHA Phase 6, Karachi</div>
  <div class="fld" style="display:flex;align-items:center;gap:20px"><span style="font-size:50px">&#128196;</span><b>Proof of address</b> &nbsp;<span style="color:#15803d;margin-left:auto">Uploaded &#10003;</span></div>
  <div class="btn btn-g">Submit for verification</div>`;

screens.verify = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="loc">Verify identity</span></div>
  <div class="headline" style="margin-top:20px">Verified members, safer deals</div>
  <div class="sub">ID &amp; address verification builds trust.</div>
  <div class="panel">${verifyInner}</div>`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span style="font-size:3vmin;margin-left:2vmin">Identity &amp; Address Verification</span></div>
  <div class="main" style="height:92vh"><div class="formwrap"><div class="headline">Verified members, safer deals</div><div class="sub">ID &amp; address verification builds trust across the marketplace.</div><div class="panel">${verifyInner}</div></div></div>`,
};

const bars = [['Jan', 30], ['Feb', 55], ['Mar', 40], ['Apr', 75], ['May', 90], ['Jun', 100]];
const earnInner = (cls) => `
  <div class="kpi"><div class="lbl">Total earnings · after 2% commission</div><div class="val">Rs 482,300</div></div>
  <div class="mrow"><div class="mcard"><div class="mv">Rs 492,000</div><div class="ml">Gross sales</div></div><div class="mcard"><div class="mv">Rs 9,840</div><div class="ml">Commission</div></div><div class="mcard"><div class="mv">Rs 60,000</div><div class="ml">In escrow</div></div><div class="mcard"><div class="mv">37</div><div class="ml">Items sold</div></div></div>
  <div class="sec">Earnings — last 6 months</div>
  ${bars.map(b => `<div class="barrow"><span class="lab">${b[0]} 26</span><span class="track"><span class="fill" style="width:${b[1]}%"></span></span></div>`).join('')}`;

screens.earnings = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="loc">Sales &amp; Earnings</span></div>
  ${earnInner('phone')}`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span style="font-size:3vmin;margin-left:2vmin">Sales &amp; Earnings</span></div>
  <div class="main" style="height:92vh"><div class="formwrap" style="max-width:130vmin">${earnInner('wide')}</div></div>`,
};

const safeItems = [
  ['&#10003;', 'Every ad is reviewed before it goes live'],
  ['&#128274;', 'Secure escrow — pay only when you confirm receipt'],
  ['&#129331;', 'ID &amp; address verified members'],
  ['&#128737;', 'Scam detection &amp; easy reporting in chat'],
  ['&#9878;', 'Clear buyer &amp; seller rules, fair for both sides'],
];
const safeInner = safeItems.map(s => `<div class="fld" style="display:flex;align-items:center;gap:20px"><span style="font-size:46px">${s[0]}</span>${s[1]}</div>`).join('');

screens.safety = {
  phone: `
  <div class="status"><span>9:41</span><span>&#9679;&#9679;&#9679;&#9679; &#128246; &#128267;</span></div>
  <div class="bar"><span class="loc">Trust &amp; Safety</span></div>
  <div class="headline" style="margin-top:20px">Buy &amp; sell with confidence</div>
  <div class="sub">PakBazar protects buyers and sellers.</div>
  <div class="panel">${safeInner}</div>`,
  wide: `
  <div class="top"><span class="logo"><span class="bag">&#128717;</span>Pak<span class="gold">Bazar</span></span><span style="font-size:3vmin;margin-left:2vmin">Trust &amp; Safety</span></div>
  <div class="main" style="height:92vh"><div class="formwrap"><div class="headline">Buy &amp; sell with confidence</div><div class="sub">How PakBazar protects buyers and sellers at every step.</div><div class="panel">${safeInner}</div></div></div>`,
};

const order = ['home', 'search', 'detail', 'chat', 'post', 'verify', 'earnings', 'safety'];
const page = (css, body) => `<!DOCTYPE html><html><head><meta charset="UTF-8"><style>${css}</style></head><body>${body}</body></html>`;

order.forEach((k, i) => {
  const n = i + 1;
  fs.writeFileSync(path.join(out, `phone_${n}.html`), page(phoneCss, screens[k].phone));
  fs.writeFileSync(path.join(out, `wide_${n}.html`), page(wideCss, screens[k].wide));
});
console.log('Generated', order.length, 'phone + wide screens in', out);
