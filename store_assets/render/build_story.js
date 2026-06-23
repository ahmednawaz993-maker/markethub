// Builds an animated Urdu story promo from the script: generates female Urdu
// voiceover per scene (ur-PK-UzmaNeural), measures each clip, lays out a timed
// HTML (start+end with the app icon), and writes a timing file for the audio
// step. Run: node build_story.js
const { EdgeTTS } = require('node-edge-tts');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FFPROBE = 'C:\\Users\\dell\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\\ffmpeg-8.1.1-full_build\\bin\\ffprobe.exe';
const STORE = path.resolve(__dirname, '..');

// Each scene: vo (Urdu narration, '' = no voice), body (inner HTML), pad (extra s).
const NAVY = '#173A6B', DEEP = '#0A1A33', GOLD = '#C9A227';
const icon = '<img class="icon" src="icon_512.png" alt="">';

const scenes = [
  { vo: 'آپ کے خواب، ہمارا مشن۔', pad: 1.2,
    body: `${icon}<div class="name">پاک <b>بازار</b></div><div class="tag">pakbazar24.com</div>` },
  { vo: 'میرا نام عائشہ ہے، میں کراچی میں رہتی ہوں۔', pad: 1,
    body: `<div class="avatar">👩</div><div class="big">عائشہ — کراچی</div>` },
  { vo: 'پہلے بازار جانا مشکل تھا — ٹریفک، بھیڑ، اور وقت کا ضیاع۔', pad: 1,
    body: `<div class="emojis">🚗 ⏰ 😩</div><div class="big">بازار جانا مشکل تھا</div>` },
  { vo: 'پھر میں نے پاک بازار ڈاؤن لوڈ کیا، اور سب کچھ بدل گیا۔', pad: 1,
    body: `${phone('🛍️','ہزاروں مصنوعات')}<div class="big">پھر سب بدل گیا</div>` },
  { vo: 'پسند کی چیزیں تلاش کیں، محفوظ ادائیگی کی، اور آرڈر مکمل۔', pad: 1,
    body: `<div class="ticks"><div>✅ آسان رجسٹریشن</div><div>✅ لاکھوں مصنوعات</div><div>✅ محفوظ ادائیگی</div><div>✅ تیز ترسیل</div></div>` },
  { vo: 'صرف تین دن میں آرڈر میرے دروازے پر، بالکل ویسا جیسا تصویر میں تھا۔', pad: 1,
    body: `<div class="emojis">📦 👗 ✨</div><div class="stars">★★★★★</div><div class="big">گھر بیٹھے خوشی</div>` },
  { vo: 'میرا نام حسن ہے، لاہور میں کپڑوں کا کاروبار کرتا ہوں۔', pad: 1,
    body: `<div class="avatar">👨</div><div class="big">حسن — لاہور</div>` },
  { vo: 'چھوٹی دکان، کم گاہک، اور بڑھتے ہوئے اخراجات۔', pad: 1,
    body: `<div class="emojis">🏪 📉</div><div class="big">کاروبار رُکا ہوا تھا</div>` },
  { vo: 'پھر پاک بازار پر فروخت شروع کی، اور لاکھوں گاہکوں تک پہنچا۔', pad: 1,
    body: `<div class="big"><span class="g">فروخت کنندہ</span> بنیں</div><div class="tag">لاکھوں گاہکوں تک پہنچیں</div>` },
  { vo: 'پہلے ہفتے پچاس آرڈرز، دوسرے ہفتے سو۔ میرا خاندان خوش ہے۔', pad: 1,
    body: `<div class="metrics"><div class="m"><b>50</b><span>پہلا ہفتہ</span></div><div class="m"><b>100</b><span>دوسرا ہفتہ</span></div><div class="m"><b>4.9★</b><span>ریٹنگ</span></div></div>` },
  { vo: 'آسان رجسٹریشن، محفوظ ادائیگی، تیز ترسیل، اور چوبیس گھنٹے سپورٹ۔', pad: 1,
    body: `<div class="feat6"><div>✅<span>رجسٹریشن</span></div><div>💳<span>ادائیگی</span></div><div>🚚<span>ترسیل</span></div><div>💬<span>سپورٹ</span></div><div>📊<span>ڈیش بورڈ</span></div><div>🔒<span>حفاظت</span></div></div>` },
  { vo: 'ہر خریدار خوش، ہر فروخت کنندہ کامیاب۔', pad: 1,
    body: `<div class="big">ہر خریدار <span class="g">خوش</span><br>ہر فروخت کنندہ <span class="g">کامیاب</span></div>` },
  { vo: 'آج ہی پاک بازار ڈاؤن لوڈ کریں۔', pad: 1.2,
    body: `<div class="big">آج ہی ڈاؤن لوڈ کریں</div><div class="url">pakbazar24.com</div><div class="tag">280+ شہروں میں خریدیں اور بیچیں</div>` },
  { vo: 'پاک بازار — آپ کے خوابوں کا بازار۔', pad: 1.4,
    body: `${icon}<div class="name">پاک <b>بازار</b></div><div class="tag">آپ کے خوابوں کا بازار</div>` },
];

function phone(emoji, label) {
  return `<div class="phone"><div class="pbar">🛍️ Pak<span style="color:${GOLD}">Bazar</span></div>` +
    `<div class="pcard"><div class="pim">${emoji}</div><div class="pl">${label}</div></div></div>`;
}

(async () => {
  const tts = new EdgeTTS({ voice: 'ur-PK-UzmaNeural', rate: '0%', pitch: '+2Hz' });
  const timing = [];
  let t = 0;
  for (let i = 0; i < scenes.length; i++) {
    const s = scenes[i];
    let dur = 3.0;
    if (s.vo) {
      const f = `sv${i}.mp3`;
      await tts.ttsPromise(s.vo, f);
      const d = parseFloat(execFileSync(FFPROBE, ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString().trim());
      dur = d + (s.pad || 0.8);
    }
    timing.push({ i, file: s.vo ? `sv${i}.mp3` : null, start: +t.toFixed(3), dur: +dur.toFixed(3) });
    t += dur;
    console.log(`scene ${i}: ${dur.toFixed(2)}s (start ${(t - dur).toFixed(2)})`);
  }
  const total = +t.toFixed(3);
  fs.writeFileSync('story_timing.json', JSON.stringify({ total, timing }, null, 2));

  // Build HTML with per-scene keyframes over `total`.
  let kf = '', divs = '';
  scenes.forEach((s, i) => {
    const { start, dur } = timing[i];
    const end = start + dur;
    const p = (x) => (x / total * 100).toFixed(3);
    const inA = p(start), inB = p(start + 0.5), outA = p(end - 0.5), outB = p(end);
    kf += `@keyframes sc${i}{0%{opacity:0;transform:translateY(26px)}${i === 0 ? '0%' : inA + '%'}{opacity:0;transform:translateY(26px)}${inB}%{opacity:1;transform:translateY(0)}${outA}%{opacity:1;transform:translateY(0)}${outB}%{opacity:0;transform:translateY(-18px)}100%{opacity:0}}\n`;
    divs += `<div class="scene" style="animation:sc${i} ${total}s linear infinite">${s.body}</div>\n`;
  });

  const html = `<!DOCTYPE html><html lang="ur" dir="rtl"><head><meta charset="UTF-8"><style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Noto Nastaliq Urdu','Jameel Noori Nastaleeq','Urdu Typesetting','Segoe UI',Tahoma,Arial,sans-serif;}
html,body{width:1920px;height:1080px;overflow:hidden;background:${DEEP};}
.stage{position:relative;width:1920px;height:1080px;background:radial-gradient(120% 120% at 50% 0%,${NAVY} 0%,${DEEP} 70%);color:#fff;overflow:hidden;}
.sheen{position:absolute;inset:-40%;background:conic-gradient(from 0deg,transparent 0 40%,rgba(201,162,39,.10) 50%,transparent 60% 100%);animation:spin 20s linear infinite;}
@keyframes spin{to{transform:rotate(360deg);}}
.wm{position:absolute;right:-120px;top:-120px;font-size:520px;color:rgba(201,162,39,.06);}
.scene{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:30px;opacity:0;padding:0 90px;}
.icon{width:230px;height:230px;border-radius:54px;box-shadow:0 24px 60px rgba(0,0,0,.45);}
.name{font-size:118px;font-weight:800;}.name b{color:${GOLD};}
.tag{font-size:48px;color:#dbe6f7;}
.big{font-size:96px;font-weight:800;line-height:1.3;max-width:1500px;}.big .g{color:${GOLD};}
.avatar{font-size:300px;}
.emojis{font-size:170px;letter-spacing:30px;}
.stars{font-size:90px;color:${GOLD};letter-spacing:10px;}
.ticks{display:flex;flex-direction:column;gap:30px;font-size:60px;}
.url{display:inline-block;background:${GOLD};color:${DEEP};font-size:64px;font-weight:800;padding:26px 64px;border-radius:70px;font-family:'Segoe UI',Arial;direction:ltr;}
.phone{width:380px;height:680px;border-radius:48px;background:${DEEP};border:12px solid #203a63;overflow:hidden;box-shadow:0 30px 80px rgba(0,0,0,.5);}
.phone .pbar{height:84px;background:linear-gradient(135deg,${DEEP},${NAVY});display:flex;align-items:center;justify-content:center;gap:10px;font-size:34px;font-weight:bold;font-family:'Segoe UI',Arial;}
.phone .pcard{margin:30px;background:#fff;border-radius:24px;overflow:hidden;color:#111;}
.phone .pim{height:320px;background:linear-gradient(135deg,#dbeafe,#93c5fd);display:flex;align-items:center;justify-content:center;font-size:170px;}
.phone .pl{padding:26px;font-size:38px;font-weight:bold;}
.metrics{display:flex;gap:60px;}
.metrics .m{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.15);border-radius:30px;padding:50px 60px;}
.metrics .m b{display:block;font-size:130px;color:${GOLD};font-family:'Segoe UI',Arial;}
.metrics .m span{font-size:40px;color:#cdddf2;}
.feat6{display:grid;grid-template-columns:repeat(3,1fr);gap:46px;}
.feat6 div{background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.14);border-radius:26px;width:380px;padding:40px;font-size:120px;display:flex;flex-direction:column;align-items:center;gap:18px;}
.feat6 div span{font-size:44px;}
.foot{position:absolute;bottom:42px;width:100%;text-align:center;font-size:32px;color:rgba(255,255,255,.5);font-family:'Segoe UI',Arial;}
${kf}</style></head><body><div class="stage"><div class="sheen"></div><div class="wm">★</div>
${divs}<div class="foot">pakbazar24.com</div></div></body></html>`;

  fs.writeFileSync(path.join(STORE, 'story.html'), html);
  console.log('TOTAL ' + total + 's, wrote story.html + story_timing.json');
})();
