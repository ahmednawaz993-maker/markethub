// Captures deterministic frames of promo.html by driving the installed Chrome
// via puppeteer-core and setting each CSS animation's currentTime, then writes
// PNG frames for ffmpeg to encode. Usage: node capture.js
const puppeteer = require('puppeteer-core');
const fs = require('fs');
const path = require('path');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
// Args: [htmlFile] [width] [height] [outDir]
const HTML = process.argv[2] || 'promo.html';
const W = parseInt(process.argv[3] || '1920', 10);
const H = parseInt(process.argv[4] || '1080', 10);
const PROMO = 'file:///C:/MarketHubNew/markethub/store_assets/' + HTML;
const OUT = path.join(__dirname, process.argv[5] || 'frames');
const FPS = 25;
const DURATION_MS = parseInt(process.argv[6] || '20000', 10); // one full loop
const FRAMES = Math.round((DURATION_MS / 1000) * FPS);

(async () => {
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-sandbox', '--hide-scrollbars', '--force-device-scale-factor=1'],
    defaultViewport: { width: W, height: H, deviceScaleFactor: 1 },
  });
  const page = await browser.newPage();
  await page.goto(PROMO, { waitUntil: 'load' });
  // Pause all animations so we control the timeline frame-by-frame.
  await page.evaluate(() => {
    document.getAnimations().forEach((a) => { try { a.pause(); } catch (e) {} });
  });

  for (let i = 0; i < FRAMES; i++) {
    const t = i * (1000 / FPS);
    await page.evaluate((time) => {
      document.getAnimations().forEach((a) => {
        try { a.currentTime = time; } catch (e) {}
      });
    }, t);
    const name = 'f' + String(i).padStart(5, '0') + '.png';
    await page.screenshot({ path: path.join(OUT, name) });
  }

  await browser.close();
  console.log('Captured ' + FRAMES + ' frames to ' + OUT);
})();
