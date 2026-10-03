// node render.mjs [prefix] — src/NN-*.html → ../NN-*.png (시트) + ../NN-*-<i>.png (폰 단독)
import { chromium } from '/Users/hyukahn/workspace/fcscope/node_modules/playwright/index.mjs';
import { readdirSync } from 'node:fs';
const dir = new URL('.', import.meta.url).pathname;
const only = process.argv[2];
const b = await chromium.launch();
for (const f of readdirSync(dir).filter(f => /^\d\d-.*\.html$/.test(f) && (!only || f.startsWith(only)))) {
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 2 });
  await p.goto('file://' + dir + f); await p.waitForLoadState('networkidle'); await p.waitForTimeout(400);
  const base = dir + '../' + f.replace('.html', '');
  await (await p.$('.sheet')).screenshot({ path: base + '.png' });
  const phones = await p.$$('.phone');
  for (let i = 0; i < phones.length; i++) await phones[i].screenshot({ path: `${base}-${String.fromCharCode(97 + i)}.png` });
  console.log('ok', f, phones.length); await p.close();
}
await b.close();
