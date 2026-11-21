// v5 — Privacy masks for raw captures: other users' nicknames -> neutral placeholders.
import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
import path from 'path';
const HERE = path.dirname(new URL(import.meta.url).pathname);
const RAW = path.join(HERE, 'raw'), OUT = path.join(HERE, 'clean');
fs.mkdirSync(OUT, { recursive: true });
const uri = f => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
const FONT = `<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css">`;

// box: [x0,y0,x1,y1] in image px; text replacement; align; size; weight; color; bg 'sample' samples pixel left of box
const JOBS = {
  // 홈·전적 "마지막 경기"의 상대 구단주명 → "상대"
  'home.png': [{ b: [478, 935, 760, 1010], h: '&nbsp;상대', size: 50, w: 800, c: '#111a14' }],
  'record.png': [{ b: [478, 1908, 760, 1983], h: '&nbsp;상대', size: 50, w: 800, c: '#111a14' }],
  // 친구 비교 — 공개 닉네임 → "친구"
  'vs.png': [
    { b: [282, 392, 640, 488], t: '친구', size: 68, w: 800, c: '#1e3a8a' },
    { b: [196, 650, 470, 742], t: '친구', size: 48, w: 400, c: '#111a14' },
    { b: [930, 878, 1240, 962], t: '친구', align: 'right', size: 54, w: 800, c: '#111a14' },
    { b: [440, 2468, 880, 2542], t: '친구 전적 보기', align: 'center', size: 44, w: 600, c: '#1e3a8a' },
  ],
};

const b = await chromium.launch();
const p = await b.newPage();
for (const [file, jobs] of Object.entries(JOBS)) {
  const src = uri(path.join(RAW, file));
  const dim = await p.evaluate(async (s) => { const i = new Image(); i.src = s; await i.decode(); return [i.width, i.height]; }, src);
  await p.setViewportSize({ width: dim[0], height: dim[1] });
  await p.setContent(`<!doctype html><html><head><meta charset="utf-8">${FONT}<style>*{margin:0;padding:0}body{position:relative;font-family:Pretendard,sans-serif;-webkit-font-smoothing:antialiased}img{position:absolute;left:0;top:0}
  .m{position:absolute;display:flex;align-items:center;white-space:nowrap;letter-spacing:-.01em}</style></head><body><img id="im" src="${src}"><canvas id="cv" style="display:none"></canvas></body></html>`);
  await p.evaluate(() => document.fonts.ready);
  await p.evaluate(async (jobs) => {
    const im = document.getElementById('im'); await im.decode();
    const cv = document.getElementById('cv'); cv.width = im.naturalWidth; cv.height = im.naturalHeight;
    const x = cv.getContext('2d'); x.drawImage(im, 0, 0);
    const px = (a, b2) => { const d = x.getImageData(a, b2, 1, 1).data; return `rgb(${d[0]},${d[1]},${d[2]})`; };
    for (const j of jobs) {
      const el = document.createElement('div'); el.className = 'm';
      if (j.circle) {
        const [cx, cy, r] = j.circle;
        Object.assign(el.style, { left: cx - r + 'px', top: cy - r + 'px', width: 2 * r + 'px', height: 2 * r + 'px', borderRadius: '50%', background: j.bg, justifyContent: 'center', color: j.c, fontSize: r * .78 + 'px', fontWeight: 700 });
      } else {
        const [x0, y0, x1, y1] = j.b;
        // horizontal gradient between left and right edge samples (handles gradient cards)
        const l = j.bgAt ? px(...j.bgAt) : px(Math.max(0, x0 - 4), (y0 + y1) >> 1), r = j.bgAt ? l : px(Math.min(cv.width - 1, x1 + 4), (y0 + y1) >> 1);
        Object.assign(el.style, { left: x0 + 'px', top: y0 + 'px', width: x1 - x0 + 'px', height: y1 - y0 + 'px', background: `linear-gradient(90deg,${l},${r})`,
          justifyContent: j.align === 'right' ? 'flex-end' : j.align === 'center' ? 'center' : 'flex-start', color: j.c, fontSize: j.size + 'px', fontWeight: j.w,
          paddingLeft: j.align ? '0' : '4px', paddingRight: j.align === 'right' ? '16px' : '0' });
      }
      if (j.h) el.innerHTML = j.h; else el.textContent = j.t; document.body.appendChild(el);
    }
  }, jobs);
  await p.waitForTimeout(200);
  await p.screenshot({ path: path.join(OUT, file) });
  console.log('masked', file);
}
// copy the rest untouched
for (const f of fs.readdirSync(RAW)) if (!JOBS[f]) fs.copyFileSync(path.join(RAW, f), path.join(OUT, f));
await b.close();
