import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
import path from 'path';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const OUT = process.env.OUTDIR || path.resolve(HERE, '..');
const SHOTS = path.join(HERE, 'clean') + '/';
const CARDS = '/Users/hyukahn/workspace/fcscope-ios/docs/cards/';
const W = 1320, H = 2868, N = 9;
const only = process.argv[2] ? process.argv[2].split(',') : null;
const THEMES = {
  lime:   { acc: '#C8F542', accbg: 'linear-gradient(90deg,#C8F542,#C8F542)', ring: '#C8F542', glow: 'rgba(200,245,66,.30)' },
  yellow: { acc: '#FFC23A', accbg: 'linear-gradient(90deg,#FFC23A,#FFC23A)', ring: 'linear-gradient(135deg,#FFC23A,#FF5A26)', glow: 'rgba(255,150,50,.30)' },
  grad:   { acc: '#FF7A45', accbg: 'linear-gradient(90deg,#F0287A 0%,#FF5A26 50%,#FFB23A 100%)', ring: 'linear-gradient(135deg,#6A35FF 0%,#E0218A 40%,#FF5A26 75%,#FFC23A 100%)', glow: 'rgba(224,33,138,.32)' },
};
const T = THEMES[process.env.THEME || 'grad'];

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
  const heat = [['#4A1FD6', .55, 1150], ['#E0218A', .30, 700], ['#FF5A26', .22, 420]];
  const glows = Array.from({ length: N }, (_, i) => {
    const cx = i * W + W / 2 + (i % 2 ? 230 : -230), cy = i % 2 ? 1500 : 1750;
    return heat.map(([c, o, r], k) => `<circle cx="${cx + (k ? (i % 2 ? -120 : 120) * k : 0)}" cy="${cy + k * 120}" r="${r}" fill="url(#h${k})"/>`).join('');
  }).join('');
  const pitch = Array.from({ length: Math.ceil(N / 2) }, (_, k) => {
    const cx = k * 2 * W + W;
    return `<circle cx="${cx}" cy="2500" r="520" fill="none" stroke="rgba(255,255,255,.05)" stroke-width="5"/>
            <line x1="${cx}" y1="0" x2="${cx}" y2="${H}" stroke="rgba(255,255,255,.03)" stroke-width="5"/>`;
  }).join('');
  const cyc = ['#6A35FF', '#E0218A', '#FF5A26', '#FFC23A', '#FF5A26', '#E0218A', '#6A35FF', '#E0218A'];
  const trStops = cyc.map((c, k) => `<stop offset="${k / (cyc.length - 1)}" stop-color="${c}"/>`).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${TW}" height="${H}" viewBox="0 0 ${TW} ${H}">
  <defs>
    ${heat.map(([c, o], k) => `<radialGradient id="h${k}"><stop offset="0" stop-color="${c}" stop-opacity="${o}"/><stop offset=".6" stop-color="${c}" stop-opacity="${o * .25}"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></radialGradient>`).join('')}
    <linearGradient id="bgl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1E1957"/><stop offset=".42" stop-color="#0A0922"/><stop offset="1" stop-color="#030309"/></linearGradient>
    <linearGradient id="tr" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="${TW}" y2="0">${trStops}</linearGradient>
    <filter id="blur"><feGaussianBlur stdDeviation="18"/></filter>
    <pattern id="dots" width="44" height="44" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="2" fill="rgba(255,255,255,.035)"/></pattern>
  </defs>
  <rect width="${TW}" height="${H}" fill="url(#bgl)"/>
  <rect width="${TW}" height="${H}" fill="url(#dots)"/>
  ${glows}${pitch}
  <path d="${d}" fill="none" stroke="url(#tr)" stroke-opacity=".45" stroke-width="28" filter="url(#blur)"/>
  <path d="${d}" fill="none" stroke="url(#tr)" stroke-opacity=".95" stroke-width="7" stroke-linecap="round"/>
  <path d="${d}" fill="none" stroke="#FFFFFF" stroke-opacity=".18" stroke-width="3" stroke-dasharray="2 26" stroke-linecap="round" transform="translate(0,60)"/>
</svg>`;
}

const ICON_F = '/Users/hyukahn/workspace/fcscope-ios/docs/store-v2/icon-v3/final/final-1024.png';
const ICON = fs.existsSync(ICON_F) ? uri(ICON_F) : null;
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
  html,body{width:${W}px;height:${H}px;overflow:hidden;background:#0A0922}
  body{font-family:'Pretendard',-apple-system,sans-serif;color:#fff;position:relative;
    background:url(${BG}) ${-i * W}px 0/${W * N}px ${H}px no-repeat;-webkit-font-smoothing:antialiased}
  .copy{position:absolute;left:0;right:0;top:${hero ? 190 : 210}px;text-align:center;padding:0 80px}
  .eyebrow{display:inline-flex;align-items:center;gap:16px;font-size:40px;font-weight:700;color:#fff;letter-spacing:-.01em;
    padding:14px 30px;border-radius:999px;background:rgba(255,255,255,.06);border:2px solid rgba(255,255,255,.14);backdrop-filter:blur(8px)}
  .eyebrow b{display:inline-block;width:16px;height:16px;border-radius:50%;background:${T.accbg};box-shadow:0 0 18px ${T.acc}}
  h1{margin-top:${hero ? 44 : 44}px;font-size:${hero ? 172 : 128}px;line-height:1.13;font-weight:800;letter-spacing:-.045em;word-break:keep-all}
  h1 em{font-style:normal;background:${T.accbg};-webkit-background-clip:text;background-clip:text;color:transparent;padding:0 .03em;margin:0 -.03em}
  p.sub{margin-top:${hero ? 40 : 34}px;font-size:${hero ? 52 : 48}px;font-weight:500;color:#B4B0D6;letter-spacing:-.02em;line-height:1.35}
  p.sub strong{color:#fff;font-weight:700}
  .phone{position:absolute;width:${SW + BEZ * 2}px;height:${SH + BEZ * 2}px;border-radius:${Math.round(168 * SCALE) + BEZ}px;padding:${BEZ}px;
    background:linear-gradient(145deg,#3a4350 0%,#151a21 18%,#0b0f14 50%,#1a2029 82%,#3a4350 100%);
    box-shadow:0 0 0 3px #2a313b inset,0 0 0 5px #05080c inset,0 80px 160px rgba(0,0,0,.65),0 0 140px rgba(106,53,255,.28);transform-origin:50% 30%}
  .screen{width:${SW}px;height:${SH}px;border-radius:${Math.round(168 * SCALE)}px;background-size:100% 100%;overflow:hidden}
  .btn{position:absolute;width:7px;background:#2b323c;border-radius:4px}
  .b1{left:-6px;top:300px;height:70px}.b2{left:-6px;top:420px;height:130px}.b3{left:-6px;top:580px;height:130px}.b4{right:-6px;top:460px;height:200px}
  .pop{position:absolute;background-repeat:no-repeat;box-shadow:0 50px 120px rgba(0,0,0,.7),0 0 0 2px rgba(255,255,255,.08)}
  .pop.ring{box-shadow:0 50px 120px rgba(0,0,0,.7),0 0 90px ${T.glow}}
  .pop.ring::before{content:'';position:absolute;inset:-5px;border-radius:inherit;padding:5px;background:${T.ring};
    -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude}
  .fade{position:absolute;left:0;right:0;bottom:0;height:260px;background:linear-gradient(to bottom,rgba(7,12,18,0),rgba(7,12,18,.85))}
  .tag{position:absolute;font-size:38px;font-weight:700;padding:18px 30px;border-radius:999px;background:rgba(18,15,46,.9);
    border:2px solid rgba(255,255,255,.1);box-shadow:0 30px 80px rgba(0,0,0,.55);display:flex;align-items:center;gap:14px;letter-spacing:-.02em}
  .tag i{font-style:normal;color:${T.acc}}
  .wm{display:inline-flex;align-items:center;font-size:48px;font-weight:800;letter-spacing:.02em}.wm .ic{width:96px;height:96px;border-radius:22px;margin-right:26px;box-shadow:0 12px 40px rgba(0,0,0,.5),0 0 0 2px rgba(255,255,255,.08)}.wm span{background:${T.accbg};-webkit-background-clip:text;background-clip:text;color:transparent}
  .card{position:absolute;border-radius:40px;overflow:hidden;box-shadow:0 60px 140px rgba(0,0,0,.7),0 0 0 2px rgba(255,255,255,.08)}
  .card img{display:block;width:100%;height:100%}
  </style></head><body>
  <div class="copy">
    ${hero ? `<div class="wm">${ICON ? `<img src="${ICON}" class="ic">` : ''}<span>FC</span>&nbsp;SCOPE</div>` : `<div class="eyebrow"><b></b>${eyebrow}</div>`}
    <h1>${title}</h1>
    <p class="sub">${sub}</p>
  </div>
  ${body}
  </body></html>`;
}

// ---------- frames ----------
function frames(s) {
  const PX = Math.round((W - (SW + BEZ * 2)) / 2), PY = 860;
  const F = [];
  const std = (name, eyebrow, title, sub, src, r, opt = {}) => {
    const px = PX, py = opt.py ?? PY;
    const w = opt.w ?? 1200;
    const [, cy] = onScreen(px, py, r[0], r[1]);
    F.push({ name, eyebrow, title, sub,
      body: phone({ src, x: px, y: py }) +
        pop({ src, r, x: opt.x ?? (W - w) / 2, y: cy + (opt.dy ?? -60), w, ring: true, radius: opt.radius ?? 50, rot: opt.rot ?? 0 }) + (opt.extra ?? '') });
  };

  // 1 HERO — match result + shot map
  {
    const px = PX + 40, py = 950;
    const [, sy] = onScreen(px, py, 50, 1215);
    const w = 1290;
    F.push({ name: '01-hero', hero: true,
      title: `감이 아니라,<br><em>데이터</em>로.`,
      sub: `내 슛과 상대 슛을 <strong>한 운동장</strong>에`,
      body: phone({ src: s.win, x: px, y: py, rot: 4 }) +
        pop({ src: s.win2, r: [24, 1240, 1296, 2140], x: (W - w) / 2, y: sy - 150, w, ring: true, radius: 56, rot: -4 }) });
  }
  std('02-form', '폼 티어', `지금 내 실력,<br><em>폼 티어</em>로`, `최근 경기 흐름으로 매기는 나의 폼 티어`, s.record2, [40, 400, 1280, 705], { w: 1240, dy: -60 });
  std('03-players', '선수 성적표', `<em>랭커 기록</em>과<br>비교한 내 선수`, `경기당 기록 · 패스 성공률을 상위 랭커와 나란히`, s.players, [250, 1932, 1290, 2510], { w: 1180, dy: -240 });
  std('04-why', '매치 리포트', `진 경기엔<br><em>이유와 처방</em>`, `슛 · 유효슛 · 점유로 짚는 ‘왜 졌을까’`, s.loss, [40, 1432, 1280, 1852], { w: 1240, dy: -50 });
  std('05-vs', '친구랑 VS', `친구랑 붙으면<br><em>누가 셀까</em>`, `최근 30경기로 폼 티어 · 득실 맞대결`, s.vs, [40, 830, 1280, 1440], { w: 1220, dy: -60 });
  std('06-community', '커뮤니티', `스쿼드 평가,<br><em>같이</em> 봐요`, `평가 · 배틀 · 클럽 모집 · 대회 게시판`, s.commd, [40, 1290, 1280, 1590], { w: 1220, dy: -40,
    extra: pop({ src: s.comml, r: [48, 505, 1272, 938], x: 50, y: 2140, w: 1220, ring: true, radius: 48 }) });
  std('07-meta', '픽 랭킹', `지금 랭커는<br><em>누굴</em> 쓸까`, `상위 랭커 선발 카드를 포지션별로, 매일 갱신`, s.meta, [48, 1250, 1272, 1830], { w: 1120, dy: -50 });
  std('08-squad', '스쿼드 빌더', `최근 선발,<br><em>그대로</em> 불러오기`, `내 공식경기 선발 11명이 한 번에 · 팀 프리셋`, s.squad, [40, 405, 870, 520], { w: 830 * 1.4, dy: -80, radius: 44 });
  {
    const cw = 820, ch = Math.round(cw * 1920 / 1080);
    const sw = 680, shh = Math.round(sw * 1920 / 1080);
    const top = 990;
    F.push({ name: '09-cards', eyebrow: '공유 카드',
      title: `스토리에 올리고,<br><em>QR</em>로 초대`,
      sub: `전적 · VS 카드에 App Store QR이 함께`,
      body: `
      <div class="card" style="left:30px;top:${top + 140}px;width:700px;height:${Math.round(700 * 1920 / 1080)}px;transform:rotate(-8deg)"><img src="${s.cuser}"></div>
      <div class="card" style="right:50px;top:${top + 40}px;width:720px;height:${Math.round(720 * 1920 / 1080)}px;transform:rotate(5deg);box-shadow:0 70px 160px rgba(0,0,0,.8),0 0 0 5px ${T.acc},0 0 110px ${T.glow}"><img src="${s.cvs}"></div>
      <div class="tag" style="left:50%;transform:translateX(-50%);top:${top + ch + 90}px;white-space:nowrap"><i>↗</i> 저장 · 공유 한 번에</div>` });
  }
  return F;
}

const browser = await chromium.launch();
const s = {};
for (const [k, f] of Object.entries({ win: 'win', win2: 'win2', record2: 'record2', players: 'players', loss: 'loss', vs: 'vs',
  commd: 'comm-detail', comml: 'comm-list', meta: 'meta', squad: 'squad', cuser: 'card-user', cvs: 'card-vs' })) s[k] = uri(SHOTS + f + '.png');
const list = frames(s);
const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
for (const [i, f] of list.entries()) {
  if (only && !only.some(o => f.name.startsWith(o))) continue;
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
