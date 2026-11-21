// v5 — 1.2.2 스토어 스크린샷(2026-11). 앱이 밝은 잔디 테마로 바뀌어 v4(어두운 네온)와 맞지 않았다.
// 밝은 크림 바탕 + 잔디 초록 프레임 교차, 큰 헤드라인 + 형광 마커 강조, 화면 일부를 확대해 띄운다.
// usage: node render.mjs [01,03]   (clean/ 는 mask.mjs 결과)
import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
import path from 'path';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const OUT = process.env.OUTDIR || path.resolve(HERE, '..');
const SHOTS = path.join(HERE, 'clean');
const W = 1320, H = 2868;
const only = process.argv[2] ? process.argv[2].split(',') : null;
const uri = (f) => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
const FONT = `<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css">`;
const ICON = uri('/Users/hyukahn/workspace/fcscope-ios/FCScope/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png');

// 앱 토큰(Theme.swift 라이트)
const C = { bg: '#F3F5F0', ink: '#111A14', muted: '#56635A', brand: '#11743C', brandDeep: '#0C5C2F', lime: '#D4F55A', line: '#D5DCD0', tint: '#1E3A8A' };

const SCALE = 0.74, BEZ = 16;
const SW = Math.round(W * SCALE), SH = Math.round(H * SCALE), R = Math.round(150 * SCALE);
const phone = ({ src, x, y, rot = 0 }) =>
  `<div class="phone" style="left:${x}px;top:${y}px;transform:rotate(${rot}deg)"><div class="screen" style="background-image:url(${src})"></div></div>`;
// 화면의 한 영역(원본 px)을 확대해 띄운다
function pop({ src, r: [x0, y0, x1, y1], x, y, w, rot = 0, ring = false, radius = 46 }) {
  const k = w / (x1 - x0), h = Math.round((y1 - y0) * k);
  return `<div class="pop${ring ? ' ring' : ''}" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;border-radius:${radius}px;transform:rotate(${rot}deg);
    background-image:url(${src});background-size:${W * k}px ${H * k}px;background-position:${-x0 * k}px ${-y0 * k}px"></div>`;
}
const at = (py, oy) => py + BEZ + oy * SCALE;   // 원본 y → 캔버스 y
const chip = (html, style, dark = false) => `<div class="chip${dark ? ' dark' : ''}" style="${style}">${html}</div>`;

function page({ eyebrow, title, sub, body, green = false, hero = false }) {
  const bg = green
    ? `repeating-linear-gradient(90deg,${C.brand} 0 165px,#147F43 165px 330px)`
    : `repeating-linear-gradient(90deg,${C.bg} 0 165px,#EEF1EA 165px 330px)`;
  const lineC = green ? 'rgba(255,255,255,.16)' : 'rgba(17,116,60,.10)';
  return `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:${W}px;height:${H}px;overflow:hidden}
  body{font-family:'Pretendard',-apple-system,sans-serif;position:relative;background:${bg};color:${green ? '#fff' : C.ink};-webkit-font-smoothing:antialiased}
  .pitch{position:absolute;inset:0;pointer-events:none}
  .copy{position:absolute;left:0;right:0;top:${hero ? 170 : 200}px;text-align:center;padding:0 70px}
  .eyebrow{display:inline-flex;align-items:center;gap:14px;font-size:40px;font-weight:700;letter-spacing:-.01em;padding:14px 32px;border-radius:999px;
    background:${green ? 'rgba(255,255,255,.14)' : '#fff'};color:${green ? '#fff' : C.brand};box-shadow:${green ? 'none' : '0 6px 24px rgba(17,26,20,.08)'}}
  .eyebrow b{width:16px;height:16px;border-radius:50%;background:${green ? C.lime : C.brand}}
  h1{margin-top:44px;font-size:${hero ? 150 : 126}px;line-height:1.12;font-weight:800;letter-spacing:-.05em;word-break:keep-all}
  h1 em{font-style:normal;color:${green ? C.lime : C.brand};position:relative;z-index:0}
  h1 em::after{content:'';position:absolute;left:-.04em;right:-.04em;bottom:.06em;height:.30em;z-index:-1;border-radius:.08em;
    background:${green ? 'rgba(212,245,90,.22)' : 'rgba(212,245,90,.85)'}}
  p.sub{margin-top:34px;font-size:48px;font-weight:500;letter-spacing:-.02em;line-height:1.35;color:${green ? 'rgba(255,255,255,.82)' : C.muted}}
  .wm{display:inline-flex;align-items:center;gap:24px;font-size:52px;font-weight:800;letter-spacing:.01em}
  .wm img{width:104px;height:104px;border-radius:24px;box-shadow:0 14px 40px rgba(0,0,0,.25)}
  .phone{position:absolute;width:${SW + BEZ * 2}px;height:${SH + BEZ * 2}px;border-radius:${R + BEZ}px;padding:${BEZ}px;background:#0F1511;
    box-shadow:0 0 0 3px #2B332D inset,0 70px 140px rgba(17,26,20,${green ? '.45' : '.22'});transform-origin:50% 30%}
  .screen{width:${SW}px;height:${SH}px;border-radius:${R}px;background-size:100% 100%;background-color:#fff}
  .pop{position:absolute;background-repeat:no-repeat;background-color:#fff;box-shadow:0 40px 100px rgba(17,26,20,.22),0 0 0 2px rgba(17,26,20,.05)}
  .pop.ring{box-shadow:0 40px 100px rgba(17,26,20,.25),0 0 0 6px ${C.lime},0 0 0 9px ${C.brand}}
  .chip{position:absolute;display:flex;align-items:center;gap:14px;white-space:nowrap;font-size:40px;font-weight:800;letter-spacing:-.02em;
    padding:20px 34px;border-radius:999px;background:#fff;color:${C.ink};box-shadow:0 24px 60px rgba(17,26,20,.20)}
  .chip i{font-style:normal;color:${C.brand}}
  .chip.dark{background:${C.ink};color:#fff}.chip.dark i{color:${C.lime}}
  .card{position:absolute;border-radius:44px;background-repeat:no-repeat;background-size:cover;box-shadow:0 60px 140px rgba(0,0,0,.40)}
  </style></head><body>
  <svg class="pitch" width="${W}" height="${H}"><g fill="none" stroke="${lineC}" stroke-width="6">
    <circle cx="${W / 2}" cy="${H - 250}" r="360"/><line x1="0" y1="${H - 250}" x2="${W}" y2="${H - 250}"/><circle cx="${W / 2}" cy="${H - 250}" r="10" fill="${lineC}"/></g></svg>
  <div class="copy">
    ${hero ? `<div class="wm"><img src="${ICON}">FC SCOPE</div>` : `<div class="eyebrow"><b></b>${eyebrow}</div>`}
    <h1>${title}</h1>
    <p class="sub">${sub}</p>
  </div>
  ${body}
  </body></html>`;
}

function frames(s) {
  const PX = Math.round((W - (SW + BEZ * 2)) / 2);
  const F = [];
  // 기본 틀: 가운데 폰 + 같은 자리 영역을 확대해 띄움
  const std = (name, o) => {
    const py = o.py ?? 900, w = o.w ?? 1220;
    const y = at(py, o.r[1]) + (o.dy ?? -40);
    F.push({ name, eyebrow: o.eyebrow, title: o.title, sub: o.sub, green: o.green,
      body: phone({ src: o.src, x: PX + (o.px ?? 0), y: py, rot: o.prot ?? 0 }) +
        pop({ src: o.src, r: o.r, x: o.x ?? (W - w) / 2, y, w, ring: o.ring ?? true, rot: o.rot ?? 0, radius: o.radius }) + (o.extra ? o.extra(y) : '') });
  };

  // 1 HERO — 전적(검색 결과 첫 장)
  {
    const py = 980, w = 1250, y = at(py, 740) - 60;
    F.push({ name: '01-record', green: true, hero: true,
      title: `내 전적,<br><em>한눈에</em>`,
      sub: `승률 · 경기력 · 최근 10경기 · 폼 티어`,
      body: phone({ src: s.record, x: PX, y: py }) +
        pop({ src: s.record, r: [60, 740, 1260, 1395], x: (W - w) / 2, y, w, rot: -2.5, ring: true }) +
        chip(`<i>●</i> 구단주명만 넣으면 끝`, `left:90px;top:${y + 880}px;transform:rotate(-3deg)`, true) });
  }
  std('02-loss', { eyebrow: '패배 리포트', src: s.loss, r: [48, 1512, 1272, 1932],
    title: `왜 졌는지<br><em>짚어줘요</em>`, sub: `유효슛 · 실점 시간 · 슛 위치로 본 원인과 한 줄 처방` });
  std('03-shotmap', { eyebrow: '슛맵', src: s.shotmap, r: [40, 340, 1280, 1400], py: 920, dy: -10,
    title: `내 슛과 상대 슛,<br><em>한 운동장</em>에`, sub: `채운 점은 골 · 점을 누르면 시간과 선수` });
  std('04-win', { eyebrow: '승리 리포트', src: s.win, r: [48, 1512, 1272, 1932],
    title: `이겨도<br><em>위험 신호</em>는 짚어요`, sub: `슛에서 밀린 승리엔 "다만…" 한 줄` });
  std('05-home', { eyebrow: '홈', src: s.home, r: [48, 822, 1272, 2120], w: 1120, dy: -30,
    title: `앱을 열면<br><em>마지막 경기</em>부터`, sub: `내 구단 승률 · 마지막 경기 슛맵 · 이번 주 성적` });
  std('06-players', { eyebrow: '스쿼드 클리닉', src: s.players, r: [48, 1500, 1272, 2115],
    title: `내 스쿼드<br><em>약한 라인</em>은?`, sub: `선수 평점으로 매긴 공격 · 미드 · 수비 · 골키퍼` });
  std('07-vs', { eyebrow: '친구 비교', src: s.vs, r: [48, 835, 1272, 1765], dy: -60,
    title: `친구랑 붙으면<br><em>누가 셀까</em>`, sub: `최근 30경기로 승률 · 폼 티어 · 득실 맞대결` });
  std('08-squad', { eyebrow: '스쿼드 빌더', src: s.squad, r: [48, 560, 1272, 2265], w: 1060, dy: -20,
    title: `최근 선발,<br><em>그대로</em> 불러오기`, sub: `공식경기 선발 11명이 한 번에 · 공유 링크까지` });
  // 9 공유 카드 — 초록 프레임: 카드 원본 + 아래 공유 버튼 줄
  {
    const cw = 820, k = cw / 706, ch = Math.round((1903 - 645) * k), top = 900, cx = (W - cw) / 2;
    F.push({ name: '09-cards', eyebrow: '공유 카드', green: true,
      title: `스토리에 올릴<br><em>내 등급 카드</em>`, sub: `카카오톡 · 인스타 스토리 · 앨범 저장`,
      body: `<div class="card" style="left:${cx}px;top:${top}px;width:${cw}px;height:${ch}px;transform:rotate(-3deg);
          background-image:url(${s.card});background-size:${W * k}px ${H * k}px;background-position:${-307 * k}px ${-645 * k}px"></div>` +
        pop({ src: s.card, r: [60, 1950, 1260, 2215], x: 60, y: top + ch + 40, w: 1200, ring: false, radius: 40 }) +
        chip(`<i>↗</i> QR로 친구 초대`, `right:110px;top:${top + ch - 160}px;transform:rotate(4deg)`, true) });
  }
  std('10-meta', { eyebrow: '픽 랭킹', src: s.meta, r: [48, 1415, 1272, 2580], w: 1120, dy: -60,
    title: `요즘 랭커가<br><em>많이 쓰는</em> 선수`, sub: `포지션별 선발 순위 · 매일 갱신` });
  return F;
}

const browser = await chromium.launch();
const s = {};
for (const f of fs.readdirSync(SHOTS)) if (f.endsWith('.png')) s[f.replace('.png', '')] = uri(path.join(SHOTS, f));
const list = frames(s);
const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
for (const f of list) {
  if (only && !only.some(o => f.name.startsWith(o))) continue;
  const p = await ctx.newPage();
  await p.setContent(page(f), { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(300);
  await p.screenshot({ path: path.join(OUT, f.name + '.png') });
  await p.close();
  console.log('rendered', f.name);
}
if (!only) {
  const imgs = list.map(f => uri(path.join(OUT, f.name + '.png')));
  const tw = 440, th = Math.round(tw * H / W), gap = 28;
  const p = await ctx.newPage();
  await p.setViewportSize({ width: list.length * tw + (list.length + 1) * gap, height: th + gap * 2 });
  await p.setContent(`<body style="margin:0;background:#1b1f26;display:flex;gap:${gap}px;padding:${gap}px">${imgs.map(u => `<img src="${u}" style="width:${tw}px;height:${th}px;border-radius:18px">`).join('')}</body>`);
  await p.waitForTimeout(300);
  await p.screenshot({ path: path.join(OUT, 'overview.png') });
  console.log('overview');
}
await browser.close();
