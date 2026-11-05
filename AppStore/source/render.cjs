// Local Duo screenshot-artwork renderer. Inputs are trusted project slide metadata,
// real simulator captures, and artboards.css; outputs are generated HTML, PNGs, and a manifest.
// This does not launch the app, take device captures, or upload anything to App Store Connect.
const fs = require('fs');
const path = require('path');

// Reuse the local rendering toolchain, with overrides for another developer's machine.
const deps = process.env.PITCHHARBOR_NODE_MODULES ||
  '/Users/cody/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const { chromium } = require(path.join(deps, 'playwright'));
const sharp = require(path.join(deps, 'sharp'));
const root = path.resolve(__dirname, '..');
const slides = JSON.parse(fs.readFileSync(path.join(__dirname, 'slides.json'), 'utf8'));
const css = fs.readFileSync(path.join(__dirname, 'artboards.css'), 'utf8');
const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');

// Decorative background shared by the generated artboards.
const pattern = `<svg class="pitch-art" viewBox="0 0 2853 2007" fill="none" aria-hidden="true"><path d="M-160 1610L860 590L1880 1610L860 2630Z" stroke="currentColor" stroke-width="4"/><circle cx="2850" cy="510" r="560" stroke="currentColor" stroke-width="4"/><circle cx="2850" cy="510" r="390" stroke="currentColor" stroke-width="4"/><path d="M2700 0V2007M0 1960H2853" stroke="currentColor" stroke-width="2"/></svg>`;

(async () => {
  fs.mkdirSync(path.join(root, 'duo-inner'), { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.PITCHHARBOR_CHROME ||
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  });
  const page = await browser.newPage({
    viewport: { width: 2853, height: 2007 }, deviceScaleFactor: 1
  });
  const results = [];

  // Validate capture size before composing a slide. Headlines intentionally contain
  // local <br> markup; do not substitute untrusted external content into this template.
  for (let i = 0; i < slides.length; i++) {
    const s = slides[i];
    const source = path.join(root, 'captures', s.id + '.png');
    const meta = await sharp(source).metadata();
    if (meta.width !== 2853 || meta.height !== 2007) {
      throw Error(`Wrong Duo capture dimensions: ${s.id}: ${meta.width}x${meta.height}`);
    }
    const html = `<!doctype html><html lang="en"><meta charset="utf-8"><title>${s.feature} — PitchHarbor</title><style>${css}</style><main class="artboard ${s.theme}">${pattern}<div class="ambient"></div><div class="topline"><div class="brand"><img src="brand-icon.png" alt="">PitchHarbor</div><div class="section"><i></i>${s.feature}<span class="number">${String(i+1).padStart(2,'0')} / 08</span></div></div><div class="copy"><h1>${s.headline}</h1><p>${s.description}</p></div><div class="rail"></div><span class="rail-label">Your Team. Every Moment.</span><div class="screen"><img src="../captures/${s.id}.png" alt="${s.feature} in the PitchHarbor app on iPhone Duo"></div><span class="edition">iPhone Duo · Inner Display</span></main></html>`;
    const htmlPath = path.join(__dirname, s.id + '.html');
    fs.writeFileSync(htmlPath, html);
    await page.goto('file://' + htmlPath);
    await page.evaluate(() => Promise.all([...document.images].map(im => im.decode())));
    await page.evaluate(() => document.fonts.ready);

    // Catch horizontal headline overflow and remove alpha from the final upload image.
    const clipped = await page.evaluate(() =>
      [...document.querySelectorAll('.copy h1,.copy p')]
        .filter(e => e.scrollWidth > e.clientWidth).map(e => e.textContent)
    );
    if (clipped.length) throw Error('Overflow: ' + clipped.join(', '));
    const output = path.join(root, 'duo-inner', s.id + '.png');
    await page.screenshot({ path: output });
    const finalMeta = await sharp(output).metadata();
    if (finalMeta.hasAlpha) {
      await sharp(output).removeAlpha().png().toFile(output + '.rgb.png');
      fs.renameSync(output + '.rgb.png', output);
    }
    results.push({
      file: 'duo-inner/' + s.id + '.png', width: 2853, height: 2007, alpha: false,
      source: 'captures/' + s.id + '.png', headline: s.headline.replace(/<[^>]+>/g, '')
    });
    console.log('Rendered ' + s.id);
  }

  // The gallery and manifest make exported assets reviewable without opening each PNG.
  const cards = slides.map((s, i) =>
    `<a class="tile" href="duo-inner/${s.id}.png"><img src="duo-inner/${s.id}.png" alt="${escape(s.feature)}"><div><span>${String(i+1).padStart(2,'0')} — ${s.feature}</span><small>2853 × 2007 PNG</small></div></a>`
  ).join('');
  const gallery = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PitchHarbor — App Store Screenshots</title><style>*{box-sizing:border-box}body{margin:0;background:#edf0e9;color:#123d30;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif}header{padding:56px 60px 32px;max-width:1800px;margin:auto}header p{font-size:20px;color:#566d60;max-width:1000px;line-height:1.5}header h1{font-size:48px;letter-spacing:-1.8px;margin:10px 0}.eyebrow{font-size:14px;font-weight:700;letter-spacing:2px}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:32px;padding:0 60px 60px;max-width:1800px;margin:auto}.tile{color:inherit;text-decoration:none;display:block;border-radius:18px;overflow:hidden;background:#fff;box-shadow:0 8px 24px #0b3c2d0d}.tile img{width:100%;display:block}.tile div{display:flex;justify-content:space-between;gap:15px;padding:18px 22px;font-size:17px;font-weight:600}.tile small{font-size:13px;font-weight:400;white-space:nowrap;color:#6a796f}footer{padding:0 60px 48px;font-size:15px;color:#64796b;max-width:1800px;margin:auto}@media(max-width:760px){header{padding:28px}header h1{font-size:32px}main{grid-template-columns:1fr;padding:0 24px 30px}.tile div{font-size:14px}.tile small{display:none}footer{padding:24px}}</style><header><div class="eyebrow">PITCHHARBOR / APP STORE COLLECTION</div><h1>Your Team. Every Moment.</h1><p>Eight feature screenshots for iPhone Duo. Real app screens, a consistent visual identity, and clear coaching benefits. Select an image to open its full-resolution export. <a href="iphone.html">View the Ordinary iPhone Collection</a>.</p></header><main>${cards}</main><footer>Recommended order: 01–08. Duo inner display · English (US) · Opaque PNG. The source captures use disposable example content; Release installs start with your own team.</footer></html>`;
  fs.writeFileSync(path.join(root, 'index.html'), gallery);
  fs.writeFileSync(path.join(root, 'manifest.json'), JSON.stringify(results, null, 2) + '\n');
  await page.setViewportSize({ width: 1800, height: 1200 });
  await page.goto('file://' + path.join(root, 'index.html'));
  await page.evaluate(() => Promise.all([...document.images].map(im => im.decode())));
  await page.screenshot({ path: path.join(root, 'collection-preview.png'), fullPage: true });
  await browser.close();
})();
