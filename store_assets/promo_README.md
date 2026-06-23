# PakBazar promo video

`promo.html` is a self-running, 20-second looping animated promo in the app's
navy + gold theme. It needs no internet (offline). Use it to produce a promo
video by screen-recording it.

## Scenes (20s loop)
1. Logo reveal — "PakBazar / Pakistan ka apna online bazaar"
2. "Buy & sell almost anything" + category pills
3. "Shop & sell safely" — Escrow / Verified members / In-app chat
4. "Sell in minutes" — phone mockup (Featured Honda Civic)
5. CTA — "Download PakBazar today" + pakbazar24.com

## How to record it (get an MP4)
1. Open `promo.html` in **Chrome**, press **F11** (full screen) so only the
   animation shows (it's designed for 1920×1080).
2. Record one full loop (~20s) with any screen recorder:
   - Windows: **Win + G** (Xbox Game Bar) → Record, or OBS Studio.
   - Or play it on a phone browser and use the phone's built-in screen record
     (good for a quick vertical-ish capture).
3. Trim to one clean loop in any editor (CapCut, Canva, Clipchamp — all free)
   and add background music if you like (use royalty-free audio).

## Where to use it
- **Google Play**: the "promo video" field needs a **YouTube URL** — upload the
  recording to YouTube (unlisted is fine) and paste the link.
- **Website hero** (pakbazar24.com), **Facebook/Instagram/TikTok reels**,
  **WhatsApp status** — great for a Pakistan audience.

## Rendered video
`promo.mp4` (1920×1080, H.264, 25fps, 20s) is the ready-to-use video. It now
includes a **synthesized royalty-free background track** (a soft C–G–Am–F chord
pad generated with ffmpeg — no licensing needed). To change the music, re-run
the ffmpeg synth/mux steps (or drop in your own audio file and mux it).

## Two ready videos
- `promo.mp4` — **landscape 1920×1080** (YouTube / Play promo / website).
- `promo_vertical.mp4` — **vertical 1080×1920** (Reels / Stories / TikTok / WhatsApp status).
Both 20s, H.264 + AAC, with the synthesized background music. Re-render with
`node render/capture.js <html> <w> <h> <outdir>` then the ffmpeg encode/mux steps.

## Notes
- Want different copy, products, music cues, or a voiceover script? Tell me and
  I'll adjust the scenes.
- For a fully-rendered MP4 directly (no screen recording), I'd need `ffmpeg`
  installed on the machine — then I can capture frames and stitch them.
