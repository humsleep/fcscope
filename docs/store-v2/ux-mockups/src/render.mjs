// node render.mjs  — src/*.html → ../*.png (Playwright, 웹 저장소 node_modules)
import { chromium } from '/Users/hyukahn/workspace/fcscope/node_modules/playwright/index.mjs';
import { readdirSync } from 'node:fs';
const dir = new URL('.', import.meta.url).pathname;
const only = process.argv[2];
const b = await chromium.launch();
for (const f of readdirSync(dir).filter(f => /^\d\d-.*\.html$/.test(f) && (!only || f.startsWith(only)))) {
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 2 });
  await p.goto('file://' + dir + f); await p.waitForLoadState('networkidle'); await p.waitForTimeout(400);
  const el = await p.$('.sheet');
  await el.screenshot({ path: dir + '../' + f.replace('.html', '.png') });
  console.log('ok', f); await p.close();
}
await b.close();
