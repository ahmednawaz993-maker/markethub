// Generates 5 Urdu voiceover clips (female ur-PK-UzmaNeural) for the promo.
const { EdgeTTS } = require('node-edge-tts');
const lines = [
  'پاک بازار، پاکستان کا اپنا آن لائن بازار۔',
  'گاڑیاں، موبائل، پراپرٹی اور بہت کچھ — آسانی سے خریدیں اور بیچیں۔',
  'محفوظ خریداری: ایسکرو، تصدیق شدہ صارفین اور اِن ایپ چیٹ کے ساتھ۔',
  'صرف چند منٹ میں اشتہار لگائیں اور پورے پاکستان کے خریداروں تک پہنچیں۔',
  'آج ہی پاک بازار ڈاؤن لوڈ کریں۔',
];
(async () => {
  const tts = new EdgeTTS({ voice: 'ur-PK-UzmaNeural', rate: '0%', pitch: '+2Hz' });
  for (let i = 0; i < lines.length; i++) {
    await tts.ttsPromise(lines[i], `vo${i + 1}.mp3`);
    console.log('vo' + (i + 1) + '.mp3 done');
  }
})();
