// Regenerates docs/assets/mode-centered.png and mode-compact.png from mockups.html,
// so the images in the README and on the site can't drift from the app's real UI.
//
//   npm i playwright && npx playwright install chromium
//   node docs/assets/make-mockups.js
//
// Shots are taken at 2x and written at 1400px wide, matching the existing assets.
const { chromium } = require('playwright');
const path = require('path');

const dir = __dirname;
const shots = [
  { id: 'centered', out: 'mode-centered.png' },
  { id: 'compact', out: 'mode-compact.png' },
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1400, height: 942 },
    deviceScaleFactor: 2,
  });
  await page.goto('file://' + path.join(dir, 'mockups.html'));
  await page.waitForTimeout(300);
  for (const { id, out } of shots) {
    const el = await page.$('#' + id);
    await el.screenshot({ path: path.join(dir, out) });
    console.log('wrote', out);
  }
  await browser.close();
})();
