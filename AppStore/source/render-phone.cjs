// Local ordinary-iPhone artwork renderer. Uses existing real-app captures; does not
// recapture the app or publish images. Generated HTML/PNGs are outputs, not source edits.
const fs = require('fs');
const path = require('path');
const deps = process.env.PITCHHARBOR_NODE_MODULES ||
  '/Users/cody/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const { chromium } = require(path.join(deps, 'playwright'));
const sharp = require(path.join(deps, 'sharp'));
const root = path.resolve(__dirname, '..');

// Trusted local copy. The titles intentionally include <br> for artwork line breaks.
const slides = [
  ['01-match-day', 'Every Match.<br>Under Control.', 'Score, time, players. Together on your touchline.'],
  ['02-smart-subs', 'The Right Player.<br>At the Right Time.', 'Review position-aware substitutions and bench rest.'],
  ['03-practice', 'Show the Play.<br>Make It Clear.', 'A full-field board for your next coaching moment.'],
  ['04-setup', 'Your Team.<br>Ready to Play.', 'A simple setup. Your players. Your plan.']
];

(async () => {
  fs.mkdirSync(path.join(root, 'iphone-medium'), { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.PITCHHARBOR_CHROME ||
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  });
  const page = await browser.newPage({
    viewport: { width: 1206, height: 2622 }, deviceScaleFactor: 1
  });

  // Validate each capture, compose the fixed-size artboard, then export opaque sRGB PNG.
  for (const [id, title, desc] of slides) {
    const source = path.join(root, 'captures', 'iphone', id + '.png');
    const meta = await sharp(source).metadata();
    if (meta.width !== 1206 || meta.height !== 2622) {
      throw Error('Expected real iPhone 16 Pro capture: ' + id);
    }
    const html = `<!doctype html><html lang="en"><meta charset="utf-8"><title>${id}</title><style>*{box-sizing:border-box}body{margin:0;width:1206px;height:2622px;overflow:hidden;background:#0b3b2e;color:#f7f8ef;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif}.brand{display:flex;align-items:center;gap:18px;margin:65px 72px;font-size:32px;font-weight:650}.brand img{width:64px;height:64px;border-radius:15px}h1{font-size:101px;line-height:1.04;letter-spacing:-4px;margin:0 72px 30px}p{font-size:33px;line-height:1.35;color:#b4d4c3;margin:0 72px;width:1010px}.screen{position:absolute;top:590px;left:160px;width:886px;height:1926px;border:10px solid #285846;border-radius:61px;overflow:hidden;box-shadow:0 30px 90px #0006;background:#0b3b2e}.screen img{display:block;width:100%;height:100%;object-fit:contain}.bottom{position:absolute;bottom:42px;left:72px;font-size:23px;color:#b4d4c3}</style><div class="brand"><img src="brand-icon.png" alt="">PitchHarbor</div><h1>${title}</h1><p>${desc}</p><div class="screen"><img src="../captures/iphone/${id}.png" alt="Real app screen"></div><div class="bottom">Your Team. Every Moment.</div></html>`;
    const doc = path.join(__dirname, 'phone-' + id + '.html');
    fs.writeFileSync(doc, html);
    await page.goto('file://' + doc);
    await page.evaluate(() => Promise.all([...document.images].map(i => i.decode())));
    const png = await page.screenshot();
    await sharp(png).removeAlpha().toColourspace('srgb').png()
      .toFile(path.join(root, 'iphone-medium', id + '.png'));
  }

  // Review gallery and machine-readable inventory for the generated image set.
  const cards = slides.map(([id, title]) =>
    `<a href="iphone-medium/${id}.png"><img src="iphone-medium/${id}.png" alt="${title.replace('<br>',' ')}"></a>`
  ).join('');
  fs.writeFileSync(path.join(root,'iphone.html'),`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PitchHarbor · iPhone Screenshots</title><style>body{background:#f3f5ef;color:#153d31;font:18px/1.5 system-ui;margin:36px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:20px}img{width:100%;border-radius:18px}a{color:inherit}</style><h1>Your Team. Every Moment.</h1><p>Four real-app screenshots for ordinary iPhone · 1206 × 2622 opaque PNG. Select a panel to open its upload-ready image. <a href="index.html">View the Duo Collection</a>.</p><main>${cards}</main></html>`);
  fs.writeFileSync(path.join(root, 'manifest-phone.json'), JSON.stringify(
    slides.map(([id, title, description]) => ({
      file: 'iphone-medium/' + id + '.png', source: 'captures/iphone/' + id + '.png',
      headline: title.replace('<br>', ' '), description,
      width: 1206, height: 2622, alpha: false
    })), null, 2
  ) + '\n');
  await browser.close();
  console.log('Rendered four 1206 × 2622 opaque iPhone App Store images.');
})();
