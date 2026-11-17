// Renders every state of interface.html into shots/ at 2x.  NODE_PATH=$(npm root -g) node shoot.js [state ...]
const { chromium } = require('playwright'); const path = require('path');
const ALL = ['map', 'tree', 'types', 'largest', 'scanning', 'idle', 'search', 'duplicates', 'copy-setup', 'copy-running', 'copy-pace', 'copy-done', 'check-copy'];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 780 }, deviceScaleFactor: 2 });
  p.on('pageerror', e => { console.error('PAGE ERROR', e.message); process.exitCode = 1; });
  for (const s of process.argv.length > 2 ? process.argv.slice(2) : ALL) {
    await p.goto('file://' + path.join(__dirname, 'interface.html') + '?s=' + s);
    await p.evaluate(() => document.fonts.ready);
    await p.screenshot({ path: path.join(__dirname, 'shots', s + '.png') });
  }
  await b.close();
})();
