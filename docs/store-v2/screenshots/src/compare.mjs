import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
const S = process.argv[2], OUTF = process.argv[3];
const u = f => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
const names = { lime: 'A · 라임 (앱 UI 색)', yellow: 'B · 옐로 #FFC23A', grad: 'C · 마젠타→오렌지 그라데이션' };
const cols = ['01-hero', '03-diagnosis', '06-cards'];
const html = `<body style="margin:0;background:#15131f;font-family:-apple-system,sans-serif;color:#fff;padding:24px">
${Object.entries(names).map(([t, n]) => `<div style="margin-bottom:22px"><div style="font-size:22px;font-weight:700;margin:0 0 10px 4px">${n}</div>
<div style="display:flex;gap:16px">${cols.map(c => `<img src="${u(`${S}/${t}/${c}.png`)}" style="width:300px;border-radius:14px">`).join('')}</div></div>`).join('')}</body>`;
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 3 * 300 + 2 * 16 + 48, height: 600 } });
await p.setContent(html); await p.waitForTimeout(400);
await p.screenshot({ path: OUTF, fullPage: true }); await b.close();
