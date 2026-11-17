// One still from the motion stage.  node still.js <scene> <out.png|jpg|webp> [--t 4.2] [--nocursor 1] [--scale 1]
// Needs a static server on :8777 serving docs/ (python3 -m http.server 8777 -d docs) and NODE_PATH pointing at Playwright.
const { chromium } = require('playwright');
const [,, scene, out, ...rest] = process.argv;
const a = {}; for (let i = 0; i < rest.length; i += 2) a[rest[i].replace(/^--/, '')] = rest[i + 1];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1920, height: 1100 }, deviceScaleFactor: +a.scale || 1 });
  p.on('pageerror', e => { console.error('PAGE ERROR', e.message); process.exitCode = 1; });
  await p.goto(`http://localhost:8777/_src/motion/stage.html?scene=${scene}${a.nocursor ? '&nocursor' : ''}`);
  await p.evaluate(() => window.ready);
  const S = await p.evaluate(() => window.SCENE);
  const ts = (a.t || '0').split(',').map(Number);
  for (const [i, t] of ts.entries()) {
    await p.evaluate(t => window.seek(t), t);
    const path = ts.length > 1 ? out.replace(/(\.\w+)$/, `-${String(t).replace('.', '_')}$1`) : out;
    await p.screenshot({ path, type: /\.jpe?g$/.test(path) ? 'jpeg' : 'png', ...( /\.jpe?g$/.test(path) ? { quality: 90 } : {}), clip: { x: 0, y: 0, width: S.w, height: S.h } });
  }
  await b.close();
})();
