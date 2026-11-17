// Deterministic render: seek(t) per frame, PNG frames piped to ffmpeg.
//   node render.js <scene> <out-basename> [--crf 24] [--from s] [--to s] [--frames dir]
// Writes <out>.mp4 (H.264) unless --frames is given (PNG dump for QC). Needs the :8777 server (see still.js).
const { chromium } = require('playwright'); const { spawn } = require('child_process'); const fs = require('fs'), path = require('path');
const [,, scene, out, ...rest] = process.argv;
const a = {}; for (let i = 0; i < rest.length; i += 2) a[rest[i].replace(/^--/, '')] = rest[i + 1];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1920, height: 1300 }, deviceScaleFactor: 1 });
  p.on('pageerror', e => { console.error('PAGE ERROR', e.message); process.exit(1); });
  await p.goto(`http://localhost:8777/_src/motion/stage.html?scene=${scene}`);
  await p.waitForFunction(() => typeof window.seek === 'function');
  await p.evaluate(() => window.ready);                       // fonts + images decoded, or it throws
  const S = await p.evaluate(() => window.SCENE);
  const fps = S.fps, f0 = Math.round((+a.from || 0) * fps), f1 = Math.round((a.to ? +a.to : S.dur) * fps);
  if (a.frames) fs.mkdirSync(a.frames, { recursive: true });
  const ff = a.frames ? null : spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    '-c:v', 'libx264', '-preset', 'veryslow', '-crf', a.crf || '24', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', out + '.mp4'], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let f = f0; f < f1; f++) {
    await p.evaluate(t => window.seek(t), f / fps);
    const png = await p.screenshot({ type: 'png', clip: { x: 0, y: 0, width: S.w, height: S.h } });
    if (ff) { if (!ff.stdin.write(png)) await new Promise(r => ff.stdin.once('drain', r)); }
    else fs.writeFileSync(path.join(a.frames, String(f).padStart(5, '0') + '.png'), png);
  }
  if (ff) { ff.stdin.end(); await new Promise(r => ff.on('close', r)); }
  await b.close();
  console.log(scene, 'frames', f1 - f0);
})();
