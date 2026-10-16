const { chromium } = require('playwright');
const svg = require('./logo.svg.js');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  for (const [bg, out] of [[true, 'AppIcon.png'], [false, 'Logo.png']]) {
    await p.setContent(`<html><body style="margin:0;background:transparent">${svg(bg)}</body></html>`);
    await p.screenshot({ path: out, omitBackground: !bg, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
  }
  await b.close();
})();
