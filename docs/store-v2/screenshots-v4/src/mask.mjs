// Privacy masks for raw captures: other users' nicknames -> neutral placeholders.
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
  'win.png': [
    { b: [1000, 548, 1240, 612], t: '상대', align: 'right', size: 50, w: 700, c: '#ffffff' },
    { b: [284, 1745, 1060, 1815], h: '<span style="color:#a8a4c4;font-weight:400">상대 · ST ·&nbsp;</span><span style="font-weight:700">크리스티아누 호날두</span>', size: 50, c: '#ffffff', bgAt: [270, 1700] },
    { b: [840, 1978, 1276, 2038], h: '<span style="color:#a8a4c4">●</span>&nbsp;상대 슛 7(유효 7)', align: 'right', size: 44, w: 500, c: '#ffffff', bgAt: [700, 2000] },
  ],
  'win2.png': [
    { b: [284, 1030, 1060, 1098], h: '<span style="color:#a8a4c4;font-weight:400">상대 · ST ·&nbsp;</span><span style="font-weight:700">크리스티아누 호날두</span>', size: 50, c: '#ffffff', bgAt: [270, 990] },
    { b: [840, 1255, 1276, 1316], h: '<span style="color:#a8a4c4">●</span>&nbsp;상대 슛 7(유효 7)', align: 'right', size: 44, w: 500, c: '#ffffff', bgAt: [700, 1280] },
    { b: [1090, 2342, 1240, 2402], t: '상대', align: 'right', size: 40, w: 600, c: '#a8a4c4' },
  ],
  'loss.png': [
    { b: [1060, 548, 1240, 612], t: '상대', align: 'right', size: 50, w: 700, c: '#ffffff' },
    { b: [284, 2195, 1000, 2265], h: '<span style="color:#a8a4c4;font-weight:400">상대 · RAM ·&nbsp;</span><span style="font-weight:700">알렉시스 산체스</span>', size: 50, c: '#ffffff', bgAt: [270, 2150] },
    { b: [905, 2428, 1276, 2488], t: '상대 슛 9(유효 8)', align: 'right', size: 44, w: 500, c: '#ffffff' },
  ],
  'vs.png': [
    { b: [282, 398, 560, 490], t: '친구', size: 68, w: 800, c: '#9b7bff' },
    { b: [196, 656, 400, 728], t: '친구', size: 50, w: 400, c: '#ffffff' },
    { b: [995, 880, 1235, 952], t: '친구', align: 'right', size: 56, w: 800, c: '#ffffff' },
    { b: [470, 2472, 850, 2540], t: '친구 전적 보기', align: 'center', size: 46, w: 600, c: '#9b7bff' },
  ],
  'card-vs.png': [
    { b: [800, 368, 1030, 450], t: '친구', align: 'right', size: 54, w: 800, c: '#ffffff' },
  ],
  'comm-detail.png': [
    { b: [300, 2026, 470, 2080], t: '중원장인', size: 42, w: 700, c: '#ffffff' },
    { b: [300, 2344, 660, 2398], h: '역습러&nbsp;&nbsp;<span style="color:#8a86ad;font-weight:400">8분 전</span>', size: 42, w: 700, c: '#ffffff' },
    { circle: [95, 2065, 48], t: '중', c: '#f0b23a', bg: '#3a2c1c' },
    { circle: [95, 2383, 48], t: '역', c: '#ff7d6b', bg: '#3a1e2a' },
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
