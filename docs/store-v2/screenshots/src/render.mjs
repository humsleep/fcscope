import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
import path from 'path';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const OUT = path.resolve(HERE, '..');
const SHOTS = '/Users/hyukahn/workspace/fcscope-ios/docs/screenshots/';
const CARDS = '/Users/hyukahn/workspace/fcscope-ios/docs/cards/';
const W = 1320, H = 2868, N = 7;
const only = process.argv[2];

const uri = (f) => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
const C = { bg: '#0A1119', card: '#101A26', card2: '#182636', lime: '#C8F542', red: '#FB7185', mute: '#8E9BAD' };
const FONT = `<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css">`;

// ---------- panoramic background (one wide SVG sliced per frame) ----------
function panorama() {
  const TW = W * N;
  // continuous trajectory crossing each frame border in the visible side gutters
  const pts = [];
  for (let i = 0; i <= N; i++) pts.push([i * W, i % 2 ? 1500 : 2350]);
  let d = `M -200 2100 C ${-100} 2300, ${pts[0][0] - 60} ${pts[0][1]}, ${pts[0][0]} ${pts[0][1]}`;
  for (let i = 1; i < pts.length; i++) {
    const [x0, y0] = pts[i - 1], [x1, y1] = pts[i];
    d += ` C ${x0 + 660} ${y0 + (i % 2 ? -900 : 900)}, ${x1 - 660} ${y1 + (i % 2 ? 900 : -900)}, ${x1} ${y1}`;
  }
  const glows = Array.from({ length: N }, (_, i) => {
    const cx = i * W + W / 2 + (i % 2 ? 260 : -260);
    return `<circle cx="${cx}" cy="${i % 2 ? 1100 : 1300}" r="900" fill="url(#g)"/>`;
  }).join('');
  const pitch = Array.from({ length: Math.ceil(N / 2) }, (_, k) => {
    const cx = k * 2 * W + W; // a center circle straddling every other border
    return `<circle cx="${cx}" cy="2500" r="520" fill="none" stroke="rgba(200,245,66,.07)" stroke-width="5"/>
            <line x1="${cx}" y1="0" x2="${cx}" y2="${H}" stroke="rgba(200,245,66,.04)" stroke-width="5"/>`;
  }).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${TW}" height="${H}" viewBox="0 0 ${TW} ${H}">
  <defs>
    <radialGradient id="g"><stop offset="0" stop-color="#C8F542" stop-opacity=".16"/><stop offset=".55" stop-color="#5FBF6A" stop-opacity=".05"/><stop offset="1" stop-color="#0A1119" stop-opacity="0"/></radialGradient>
    <linearGradient id="bgl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0C141E"/><stop offset=".5" stop-color="#0A1119"/><stop offset="1" stop-color="#070C12"/></linearGradient>
    <filter id="blur"><feGaussianBlur stdDeviation="18"/></filter>
    <pattern id="dots" width="44" height="44" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="2" fill="rgba(255,255,255,.035)"/></pattern>
  </defs>
  <rect width="${TW}" height="${H}" fill="url(#bgl)"/>
  <rect width="${TW}" height="${H}" fill="url(#dots)"/>
  ${glows}${pitch}
  <path d="${d}" fill="none" stroke="#C8F542" stroke-opacity=".35" stroke-width="26" filter="url(#blur)"/>
  <path d="${d}" fill="none" stroke="#C8F542" stroke-opacity=".85" stroke-width="7" stroke-linecap="round"/>
  <path d="${d}" fill="none" stroke="#FFFFFF" stroke-opacity=".18" stroke-width="3" stroke-dasharray="2 26" stroke-linecap="round" transform="translate(0,60)"/>
</svg>`;
}

const BG = 'data:image/svg+xml;base64,' + Buffer.from(panorama()).toString('base64');

// ---------- building blocks ----------
const SCALE = 0.755;             // screen scale inside the device
const SW = Math.round(W * SCALE), SH = Math.round(H * SCALE);
const BEZ = 20;
function phone({ src, x, y, rot = 0, visibleTo = null }) {
  return `<div class="phone" style="left:${x}px;top:${y}px;transform:rotate(${rot}deg)">
    <div class="btn b1"></div><div class="btn b2"></div><div class="btn b3"></div><div class="btn b4"></div>
    <div class="screen" style="background-image:url(${src})"></div>
  </div>`;
}
// zoomed crop popping out of the phone: region in ORIGINAL screenshot px
function pop({ src, r: [x0, y0, x1, y1], x, y, w, rot = 0, ring = false, radius = 44 }) {
  const k = w / (x1 - x0), h = Math.round((y1 - y0) * k);
  return `<div class="pop${ring ? ' ring' : ''}" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;border-radius:${radius}px;transform:rotate(${rot}deg);
    background-image:url(${src});background-size:${W * k}px ${H * k}px;background-position:${-x0 * k}px ${-y0 * k}px"></div>`;
}
// where a region of the screenshot sits on the canvas, given phone x/y
const onScreen = (px, py, ox, oy) => [px + BEZ + ox * SCALE, py + BEZ + oy * SCALE];

function page({ i, eyebrow, title, sub, body, hero = false }) {
  return `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:${W}px;height:${H}px;overflow:hidden;background:${C.bg}}
  body{font-family:'Pretendard',-apple-system,sans-serif;color:#fff;position:relative;
    background:url(${BG}) ${-i * W}px 0/${W * N}px ${H}px no-repeat;-webkit-font-smoothing:antialiased}
  .copy{position:absolute;left:0;right:0;top:${hero ? 230 : 210}px;text-align:center;padding:0 80px}
  .eyebrow{display:inline-flex;align-items:center;gap:16px;font-size:40px;font-weight:700;color:${C.lime};letter-spacing:-.01em;
    padding:14px 30px;border-radius:999px;background:rgba(200,245,66,.09);border:2px solid rgba(200,245,66,.28)}
  .eyebrow b{display:inline-block;width:14px;height:14px;border-radius:50%;background:${C.lime};box-shadow:0 0 18px ${C.lime}}
  h1{margin-top:${hero ? 40 : 44}px;font-size:${hero ? 156 : 128}px;line-height:1.13;font-weight:800;letter-spacing:-.045em;word-break:keep-all}
  h1 em{font-style:normal;color:${C.lime}}
  p.sub{margin-top:${hero ? 40 : 34}px;font-size:${hero ? 52 : 48}px;font-weight:500;color:#A3B0C2;letter-spacing:-.02em;line-height:1.35}
  p.sub strong{color:#fff;font-weight:700}
  .phone{position:absolute;width:${SW + BEZ * 2}px;height:${SH + BEZ * 2}px;border-radius:${Math.round(168 * SCALE) + BEZ}px;padding:${BEZ}px;
    background:linear-gradient(145deg,#3a4350 0%,#151a21 18%,#0b0f14 50%,#1a2029 82%,#3a4350 100%);
    box-shadow:0 0 0 3px #2a313b inset,0 0 0 5px #05080c inset,0 80px 160px rgba(0,0,0,.65),0 0 120px rgba(200,245,66,.10);transform-origin:50% 30%}
  .screen{width:${SW}px;height:${SH}px;border-radius:${Math.round(168 * SCALE)}px;background-size:100% 100%;overflow:hidden}
  .btn{position:absolute;width:7px;background:#2b323c;border-radius:4px}
  .b1{left:-6px;top:300px;height:70px}.b2{left:-6px;top:420px;height:130px}.b3{left:-6px;top:580px;height:130px}.b4{right:-6px;top:460px;height:200px}
  .pop{position:absolute;background-repeat:no-repeat;box-shadow:0 50px 120px rgba(0,0,0,.7),0 0 0 2px rgba(255,255,255,.08)}
  .pop.ring{box-shadow:0 50px 120px rgba(0,0,0,.7),0 0 0 4px ${C.lime},0 0 80px rgba(200,245,66,.35)}
  .fade{position:absolute;left:0;right:0;bottom:0;height:260px;background:linear-gradient(to bottom,rgba(7,12,18,0),rgba(7,12,18,.85))}
  .tag{position:absolute;font-size:38px;font-weight:700;padding:18px 30px;border-radius:999px;background:rgba(16,26,38,.92);
    border:2px solid rgba(255,255,255,.1);box-shadow:0 30px 80px rgba(0,0,0,.55);display:flex;align-items:center;gap:14px;letter-spacing:-.02em}
  .tag i{font-style:normal;color:${C.lime}}
  .wm{font-size:44px;font-weight:800;letter-spacing:.02em}.wm span{color:${C.lime}}
  .card{position:absolute;border-radius:40px;overflow:hidden;box-shadow:0 60px 140px rgba(0,0,0,.7),0 0 0 2px rgba(255,255,255,.08)}
  .card img{display:block;width:100%;height:100%}
  </style></head><body>
  <div class="copy">
    ${hero ? `<div class="wm"><span>FC</span> SCOPE</div>` : `<div class="eyebrow"><b></b>${eyebrow}</div>`}
    <h1>${title}</h1>
    <p class="sub">${sub}</p>
  </div>
  ${body}
  </body></html>`;
}

// ---------- privacy-cleaned capture of 03 (opponent nickname -> "상대") ----------
async function clean03(browser) {
  const html = `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>
  *{margin:0;padding:0}body{width:${W}px;height:${H}px;position:relative;font-family:'Pretendard',sans-serif;-webkit-font-smoothing:antialiased}
  img{position:absolute;left:0;top:0}
  .m{position:absolute;display:flex;align-items:center}
  </style></head><body><img src="${uri(SHOTS + '03-match-report.png')}">
  <div class="m" style="left:900px;top:560px;width:200px;height:80px;background:${C.card};justify-content:center;font-size:47px;font-weight:700;color:#fff;letter-spacing:-.01em">상대</div>
  <div class="m" style="left:40px;top:1140px;width:360px;height:56px;background:${C.bg};font-size:38px;font-weight:500;color:#fff;gap:14px;padding-left:10px">
    <span style="width:22px;height:22px;border-radius:50%;background:${C.red};display:inline-block"></span>상대 슛 6(유효 5)</div>
  </body></html>`;
  const p = await browser.newPage({ viewport: { width: W, height: H } });
  await p.setContent(html); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(300);
  const f = path.join(HERE, 'clean-03.png');
  await p.screenshot({ path: f }); await p.close();
  return f;
}

async function clean02(browser) {
  const html = `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>
  *{margin:0;padding:0}body{width:${W}px;height:${H}px;position:relative;font-family:'Pretendard',sans-serif;-webkit-font-smoothing:antialiased}
  img{position:absolute;left:0;top:0}</style></head><body><img src="${uri(SHOTS + '02-record.png')}">
  <div style="position:absolute;left:405px;top:1755px;width:440px;height:62px;background:${C.card};font-size:47px;font-weight:700;color:#fff;display:flex;align-items:center;padding-left:8px">vs 상대</div>
  </body></html>`;
  const p = await browser.newPage({ viewport: { width: W, height: H } });
  await p.setContent(html); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(300);
  const f = path.join(HERE, 'clean-02.png');
  await p.screenshot({ path: f }); await p.close();
  return f;
}

// ---------- frames ----------
function frames(s) {
  const PX = Math.round((W - (SW + BEZ * 2)) / 2), PY = 860;
  const F = [];

  // 1 HERO — record screen + floating KPI card + shot map
  {
    const px = PX, py = 920;
    const [kx, ky] = onScreen(px, py, 50, 395);
    const [mx, my] = onScreen(px, py, 85, 1895);
    F.push({ name: '01-hero', hero: true,
      title: `감이 아니라,<br><em>데이터</em>로.`,
      sub: `구단주명 하나로 <strong>최근 30경기</strong>를 진단해요`,
      body: phone({ src: s['02'], x: px, y: py }) +
        pop({ src: s['02'], r: [50, 395, 1272, 1128], x: kx - 70, y: ky - 40, w: (1272 - 50) * SCALE + 140, ring: true, radius: 52 }) +
        `<div class="tag" style="left:70px;top:2560px"><i>●</i> 로그인 없이 바로</div>
         <div class="tag" style="right:70px;top:2690px">공식경기 · 감독모드 · 1on1</div>` });
  }
  // 2 SHOT MAP
  {
    const px = PX, py = PY;
    const [sx, sy] = onScreen(px, py, 50, 1215);
    const w = 1200;
    F.push({ name: '02-shotmap', eyebrow: '매치 리포트',
      title: `내 슛과 상대 슛,<br><em>한 운동장</em>에`,
      sub: `골 · 노골 · 금색 골대까지 점 하나하나`,
      body: phone({ src: s['03c'], x: px, y: py }) +
        pop({ src: s['03c'], r: [24, 1126, 1296, 2012], x: (W - w) / 2, y: sy - 150, w, ring: true, radius: 48 }) });
  }
  // 3 PLAYERS vs RANKERS
  {
    const px = PX, py = PY;
    const [, cy] = onScreen(px, py, 50, 1590);
    const w = 1180;
    F.push({ name: '03-players', eyebrow: '선수 성적표',
      title: `<em>랭커 기록</em>과<br>비교한 내 선수`,
      sub: `경기당 골 · 패스 성공률을 상위 랭커와 나란히`,
      body: phone({ src: s['04'], x: px, y: py }) +
        pop({ src: s['04'], r: [30, 1575, 1290, 2118], x: (W - w) / 2, y: cy - 90, w, ring: true, radius: 48 }) });
  }
  // 4 SQUAD
  {
    const px = PX, py = PY;
    const [bx, by] = onScreen(px, py, 355, 533);
    F.push({ name: '04-squad', eyebrow: '스쿼드 빌더',
      title: `최근 선발,<br><em>그대로</em> 불러오기`,
      sub: `내 공식경기 선발 11명이 한 번에 · 팀 프리셋 20개`,
      body: phone({ src: s['06'], x: px, y: py }) +
        pop({ src: s['06'], r: [40, 522, 648, 638], x: px + BEZ + 40 * SCALE - 60, y: by - 70, w: 608 * 1.45, ring: true, radius: 44 }) });
  }
  // 5 PICK RANKING
  {
    const px = PX, py = PY;
    const [, ay] = onScreen(px, py, 50, 918);
    const w = 1200;
    F.push({ name: '05-meta', eyebrow: '픽 랭킹',
      title: `지금 랭커는<br><em>누굴</em> 쓸까`,
      sub: `상위 랭커 선발 카드를 포지션별로, 매일 갱신`,
      body: phone({ src: s['07'], x: px, y: py }) +
        pop({ src: s['07'], r: [48, 918, 1272, 1518], x: (W - w) / 2, y: ay - 70, w, ring: true, radius: 50 }) });
  }
  // 6 ANALYSIS REPORT
  {
    const px = PX, py = PY;
    const [, cy] = onScreen(px, py, 50, 557);
    const w = 1200;
    F.push({ name: '06-report', eyebrow: '분석 리포트',
      title: `언제 먹히는지,<br><em>데이터</em>가 알아요`,
      sub: `시간대별 득실 · 슛 타입별 결정력 · 최근 폼`,
      body: phone({ src: s['05'], x: px, y: py }) +
        pop({ src: s['05'], r: [48, 557, 1272, 1270], x: (W - w) / 2, y: cy - 60, w, ring: true, radius: 50 }) });
  }
  // 7 SHARE CARDS
  {
    const cw = 840, ch = Math.round(cw * 1920 / 1080);
    const sw = 680, shh = Math.round(sw * 1920 / 1080);
    const top = 880;
    F.push({ name: '07-cards', eyebrow: '공유 카드',
      title: `내 전적,<br><em>스토리</em>로 자랑`,
      sub: `전적 · 계급 · 대세픽 카드를 인스타 스토리 크기로`,
      body: `
      <div class="card" style="left:-120px;top:${top + 190}px;width:${sw}px;height:${shh}px;transform:rotate(-9deg);opacity:.92"><img src="${s.rank}"></div>
      <div class="card" style="right:-120px;top:${top + 190}px;width:${sw}px;height:${shh}px;transform:rotate(9deg);opacity:.92"><img src="${s.pick}"></div>
      <div class="card" style="left:${(W - cw) / 2}px;top:${top}px;width:${cw}px;height:${ch}px;box-shadow:0 70px 160px rgba(0,0,0,.8),0 0 0 4px ${C.lime},0 0 100px rgba(200,245,66,.3)"><img src="${s.user}"></div>
      <div class="tag" style="left:50%;transform:translateX(-50%);top:${top + ch + 60}px;white-space:nowrap"><i>↗</i> 저장 · 공유 한 번에</div>` });
  }
  return F;
}

const browser = await chromium.launch();
const s = {
  '02': uri(SHOTS + '02-record.png'), '04': uri(SHOTS + '04-players.png'), '05': uri(SHOTS + '05-report.png'),
  '06': uri(SHOTS + '06-squad.png'), '07': uri(SHOTS + '07-meta.png'),
  user: uri(CARDS + 'user.png'), rank: uri(CARDS + 'rank.png'), pick: uri(CARDS + 'pick.png'),
};
s['03c'] = uri(await clean03(browser));
s['02'] = uri(await clean02(browser));
const list = frames(s);
const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
for (const [i, f] of list.entries()) {
  if (only && !f.name.startsWith(only)) continue;
  const p = await ctx.newPage();
  const html = page({ i, ...f });
  fs.writeFileSync(path.join(HERE, f.name + '.html'), html);
  await p.setContent(html, { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(300);
  await p.screenshot({ path: path.join(OUT, f.name + '.png') });
  await p.close();
  console.log('rendered', f.name);
}
// contact sheet
if (!only) {
  const imgs = list.map(f => uri(path.join(OUT, f.name + '.png')));
  const tw = 440, th = Math.round(tw * H / W), gap = 28;
  const cw = list.length * tw + (list.length + 1) * gap;
  const p = await ctx.newPage();
  await p.setViewportSize({ width: cw, height: th + gap * 2 });
  await p.setContent(`<body style="margin:0;background:#1b1f26;display:flex;gap:${gap}px;padding:${gap}px">${imgs.map(u => `<img src="${u}" style="width:${tw}px;height:${th}px;border-radius:18px">`).join('')}</body>`);
  await p.waitForTimeout(300);
  await p.screenshot({ path: path.join(OUT, 'overview.png') });
  console.log('overview');
}
await browser.close();
