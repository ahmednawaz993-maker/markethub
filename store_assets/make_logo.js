// Generates the PakBazar premium logo as HTML files with inline SVG.
// Render to PNG via Chrome headless. Palette: emerald #013318/#015127/#0A7D3B,
// metallic gold #C9A227. Mark: a shopping bag (marketplace) carrying a gold
// crescent + star (Pakistan), with a premium gold hairline frame.
const fs = require('fs');

function starPath(cx, cy, ro, ri, points = 5, rot = -90) {
  const pts = [];
  for (let i = 0; i < points * 2; i++) {
    const r = i % 2 === 0 ? ro : ri;
    const a = (rot + (i * 180) / points) * Math.PI / 180;
    pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return 'M' + pts.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(' L') + ' Z';
}

function emblem(cx, cy, s, shadow = true) {
  const bw = 360 * s, bh = 392 * s;
  const bx = cx - bw / 2, by = cy - bh / 2 + 28 * s;
  const rx = 56 * s;
  const hH = 132 * s;
  const h1x0 = bx + bw * 0.20, h1x1 = bx + bw * 0.44;
  const h2x0 = bx + bw * 0.56, h2x1 = bx + bw * 0.80;
  const sw = (30 * s).toFixed(1);
  const handle =
    `<path d="M${h1x0.toFixed(1)},${by.toFixed(1)} C${h1x0.toFixed(1)},${(by-hH).toFixed(1)} ${h1x1.toFixed(1)},${(by-hH).toFixed(1)} ${h1x1.toFixed(1)},${by.toFixed(1)}" fill="none" stroke="url(#gold)" stroke-width="${sw}" stroke-linecap="round"/>` +
    `<path d="M${h2x0.toFixed(1)},${by.toFixed(1)} C${h2x0.toFixed(1)},${(by-hH).toFixed(1)} ${h2x1.toFixed(1)},${(by-hH).toFixed(1)} ${h2x1.toFixed(1)},${by.toFixed(1)}" fill="none" stroke="url(#gold)" stroke-width="${sw}" stroke-linecap="round"/>`;
  const ecx = cx, ecy = by + bh * 0.52;
  const cr = 96 * s;
  const outc = [ecx - 14 * s, ecy];
  const cutc = [ecx + 34 * s, ecy - 24 * s];
  const starCx = ecx + 70 * s, starCy = ecy - 6 * s;
  const maskId = `cres${Math.round(cx)}_${Math.round(cy)}`;
  const crescent =
    `<circle cx="${outc[0].toFixed(1)}" cy="${outc[1].toFixed(1)}" r="${cr.toFixed(1)}" fill="white"/>` +
    `<circle cx="${cutc[0].toFixed(1)}" cy="${cutc[1].toFixed(1)}" r="${(cr*0.84).toFixed(1)}" fill="black"/>`;
  const sp = starPath(starCx, starCy, 50 * s, 21 * s);
  const flt = shadow ? ' filter="url(#soft)"' : '';
  return `
    <defs><mask id="${maskId}">${crescent}</mask></defs>
    <g${flt}>
      <rect x="${bx.toFixed(1)}" y="${by.toFixed(1)}" width="${bw.toFixed(1)}" height="${bh.toFixed(1)}" rx="${rx.toFixed(1)}" fill="url(#bagface)"/>
      <rect x="${bx.toFixed(1)}" y="${by.toFixed(1)}" width="${bw.toFixed(1)}" height="${bh.toFixed(1)}" rx="${rx.toFixed(1)}" fill="none" stroke="url(#gold)" stroke-width="${(5*s).toFixed(1)}" stroke-opacity="0.6"/>
    </g>
    ${handle}
    <rect x="0" y="0" width="1024" height="1024" fill="url(#gold)" mask="url(#${maskId})"/>
    <path d="${sp}" fill="url(#gold)"/>
  `;
}

const DEFS = `
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#04572a"/>
      <stop offset="0.5" stop-color="#015127"/>
      <stop offset="1" stop-color="#012e17"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.30" r="0.7">
      <stop offset="0" stop-color="#0A7D3B" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#0A7D3B" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0.25" y2="1">
      <stop offset="0" stop-color="#FBE9A8"/>
      <stop offset="0.42" stop-color="#E2BE5C"/>
      <stop offset="0.55" stop-color="#C9A227"/>
      <stop offset="1" stop-color="#9C7715"/>
    </linearGradient>
    <linearGradient id="bagface" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E9EAE3"/>
    </linearGradient>
    <filter id="soft" x="-40%" y="-40%" width="180%" height="180%">
      <feDropShadow dx="0" dy="20" stdDeviation="30" flood-color="#001a0c" flood-opacity="0.45"/>
    </filter>
  </defs>
`;

function page(svgInner, transparent = false) {
  const bg = transparent ? 'transparent' : '#015127';
  return '<!DOCTYPE html><html><head><meta charset="UTF-8">' +
    `<style>html,body{margin:0;padding:0;background:${bg};}svg{display:block;}</style></head><body>` +
    '<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">' +
    svgInner + '</svg></body></html>';
}

const icon = DEFS + `
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <rect width="1024" height="1024" fill="url(#glow)"/>
  <rect x="48" y="48" width="928" height="928" rx="190" fill="none" stroke="url(#gold)" stroke-opacity="0.5" stroke-width="6"/>
` + emblem(512, 512, 1.0);

const iconFg = DEFS + emblem(512, 512, 0.92, true);

fs.writeFileSync('store_assets/icon.html', page(icon));
fs.writeFileSync('store_assets/icon_fg.html', page(iconFg, true));
console.log('wrote store_assets/icon.html and store_assets/icon_fg.html');
