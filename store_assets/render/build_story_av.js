// Assembles the final Urdu "story" promo: encodes the captured frames (frames_s)
// into H.264 video, synthesizes a soft C-G-Am-F chord-pad music bed for the full
// duration, delays each scene voiceover (sv*.mp3) to its start time from
// story_timing.json, mixes VO over the music, and muxes into ../story.mp4.
// Run after build_story.js + capture.js: node build_story_av.js
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FFBIN = 'C:\\Users\\dell\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\\ffmpeg-8.1.1-full_build\\bin';
const FFMPEG = path.join(FFBIN, 'ffmpeg.exe');
const STORE = path.resolve(__dirname, '..');
const FRAMES = path.join(__dirname, 'frames_s');
const FPS = 25;

const ff = (args) => execFileSync(FFMPEG, ['-y', '-hide_banner', '-loglevel', 'error', ...args], { stdio: 'inherit' });

const { total, timing } = JSON.parse(fs.readFileSync(path.join(__dirname, 'story_timing.json'), 'utf8'));
console.log(`Assembling ${total}s story video from ${timing.length} scenes...`);

// 1) Encode frames -> silent video.
const silent = path.join(__dirname, '_story_silent.mp4');
ff(['-framerate', String(FPS), '-i', path.join(FRAMES, 'f%05d.png'),
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'medium', silent]);
console.log('  video encoded');

// 2) Synthesize a soft chord-pad bed (C-G-Am-F, 4s each), looped to cover total.
const chords = {
  c: [261.63, 329.63, 392.00], // C major
  g: [196.00, 246.94, 293.66], // G major
  a: [220.00, 261.63, 329.63], // A minor
  f: [174.61, 220.00, 261.63], // F major
};
const CHORD_S = 4;
for (const [name, freqs] of Object.entries(chords)) {
  const expr = freqs.map((hz) => `0.28*sin(2*PI*${hz}*t)`).join('+');
  ff(['-f', 'lavfi', '-i', `aevalsrc=${expr}:d=${CHORD_S}:s=44100`,
      '-af', `afade=t=in:st=0:d=0.6,afade=t=out:st=${CHORD_S - 0.8}:d=0.8`,
      path.join(__dirname, `_ch_${name}.wav`)]);
}
// Concat list: C G Am F repeated enough to exceed total.
const reps = Math.ceil(total / (CHORD_S * 4)) + 1;
const seq = [];
for (let r = 0; r < reps; r++) seq.push('c', 'g', 'a', 'f');
const listFile = path.join(__dirname, '_chords.txt');
fs.writeFileSync(listFile, seq.map((n) => `file '${path.join(__dirname, `_ch_${n}.wav`).replace(/\\/g, '/')}'`).join('\n'));
const music = path.join(__dirname, '_music.wav');
// Concat, trim to total, warm it (lowpass), add gentle space (aecho), keep it low under VO.
ff(['-f', 'concat', '-safe', '0', '-i', listFile,
    '-af', `atrim=0:${total},lowpass=f=1100,aecho=0.8:0.7:60:0.25,volume=0.16,afade=t=out:st=${total - 1.5}:d=1.5`,
    music]);
console.log('  music bed synthesized');

// 3) Build mixed audio: each sv{i}.mp3 delayed to its start, amix'd over music.
const inputs = ['-i', music];
const voFilters = [];
const voLabels = ['[0:a]'];
let idx = 1;
for (const t of timing) {
  if (!t.file) continue;
  const fp = path.join(__dirname, t.file);
  if (!fs.existsSync(fp)) { console.warn(`  missing ${t.file}, skipping`); continue; }
  inputs.push('-i', fp);
  const ms = Math.round(t.start * 1000);
  voFilters.push(`[${idx}:a]adelay=${ms}|${ms},volume=1.7[v${idx}]`);
  voLabels.push(`[v${idx}]`);
  idx++;
}
const audio = path.join(__dirname, '_story_audio.m4a');
const filter = `${voFilters.join(';')};${voLabels.join('')}amix=inputs=${voLabels.length}:duration=longest:dropout_transition=0:normalize=0,alimiter=limit=0.95,aresample=44100[mix]`;
ff([...inputs, '-filter_complex', filter, '-map', '[mix]', '-c:a', 'aac', '-b:a', '192k', '-t', String(total), audio]);
console.log('  audio mixed');

// 4) Mux video + audio -> final.
const out = path.join(STORE, 'story.mp4');
ff(['-i', silent, '-i', audio, '-c:v', 'copy', '-c:a', 'copy', '-shortest', out]);
console.log('DONE -> ' + out);

// Cleanup intermediates.
for (const f of ['_story_silent.mp4', '_ch_c.wav', '_ch_g.wav', '_ch_a.wav', '_ch_f.wav', '_chords.txt', '_music.wav', '_story_audio.m4a']) {
  try { fs.unlinkSync(path.join(__dirname, f)); } catch (e) {}
}
