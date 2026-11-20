const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 2 });
  await p.goto('file://' + __dirname + '/nav.html');
  await p.screenshot({ path: __dirname + '/nav-options.png', fullPage: true });
  for (const k of 'ABCDE') await (await p.$('#o' + k)).screenshot({ path: `${__dirname}/nav-${k}.png` });
  await b.close();
})();
