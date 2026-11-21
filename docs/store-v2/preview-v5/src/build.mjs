// App Store 앱 미리보기(886x1920, 30fps, 약 25초, 무음 스테레오) — 시뮬레이터 실제 녹화 클립(clips/)을 잘라 붙인다.
// 1) 배경·자막·화면 마스크를 PNG로 그린다(Pretendard)  2) ffmpeg로 클립 정리 → 합성.
// usage: node build.mjs   →  ../fcscope-preview-886x1920.mp4
import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const CLIPS = path.resolve(HERE, '../clips');
const TMP = path.join(HERE, 'out'); fs.mkdirSync(TMP, { recursive: true });
const PATCH_SRC = path.resolve(HERE, '../../screenshots-v5/src/clean/record.png'); // 상대 닉네임을 "상대"로 가린 같은 화면
const W = 886, H = 1920, FPS = 30;
const SW = 672, SX = (W - SW) / 2, SH = Math.round(SW * 2868 / 1320), SY = 420; // 화면 자리(자막 아래)
const FONT = `<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css">`;

// [클립, 시작, 끝, 끝 정지(초), 자막, 닉네임 가림 구간(클립 시간, 없으면 null)]
const SEG = [
  ['c1', 0.0, 3.8, 0, '내 전적,<br><em>한눈에</em>', [0, 3.8]],
  ['c1', 3.8, 7.6, 0, '약점은<br><em>리포트</em>로', null],
  ['c2', 0.4, 8.0, 0, '졌으면<br><em>왜 졌는지</em>', null],
  ['c3', 0.0, 0.066, 3.0, '이겨도<br><em>위험 신호</em>는 짚어요', null],
  ['c4', 0.0, 2.3, 0, '최근 선발,<br><em>그대로</em> 불러오기', null],
  ['c4', 7.9, 8.99, 1.4, '최근 선발,<br><em>그대로</em> 불러오기', null],
  ['c5', 3.6, 4.46, 2.4, '<em>등급 카드</em>로<br>스토리 자랑', [3.6, 4.05]],
];

const sh = (args) => execFileSync('ffmpeg', ['-v', 'error', '-y', ...args], { stdio: 'inherit' });

// ---------- 1. PNG 자산 ----------
const browser = await chromium.launch();
const pg = await browser.newPage({ viewport: { width: W, height: H } });
async function png(file, body, transparent = false) {
  await pg.setContent(`<!doctype html><html><head><meta charset="utf-8">${FONT}<style>*{margin:0;padding:0;box-sizing:border-box}
  html,body{width:${W}px;height:${H}px;overflow:hidden;background:${transparent ? 'transparent' : '#F3F5F0'};font-family:Pretendard,sans-serif;-webkit-font-smoothing:antialiased}
  h1{position:absolute;left:0;right:0;top:96px;text-align:center;font-size:80px;line-height:1.14;font-weight:800;letter-spacing:-.05em;color:#111A14}
  h1 em{font-style:normal;color:#11743C;position:relative;z-index:0}
  h1 em::after{content:'';position:absolute;left:-.04em;right:-.04em;bottom:.06em;height:.3em;z-index:-1;border-radius:.08em;background:rgba(212,245,90,.9)}
  </style></head><body>${body}</body></html>`, { waitUntil: 'networkidle' });
  await pg.evaluate(() => document.fonts.ready);
  await pg.screenshot({ path: path.join(TMP, file), omitBackground: transparent });
}
await png('bg.png', `<div style="position:absolute;inset:0;background:repeating-linear-gradient(90deg,#F3F5F0 0 110px,#EEF1EA 110px 220px)"></div>
  <div style="position:absolute;left:${SX - 10}px;top:${SY - 10}px;width:${SW + 20}px;height:${SH + 20}px;border-radius:84px;background:#0F1511;box-shadow:0 40px 90px rgba(17,26,20,.25)"></div>`);
// 화면 모서리 둥글게: 흰 = 보임
await pg.setViewportSize({ width: SW, height: SH });
await pg.setContent(`<body style="margin:0;background:#000"><div style="width:${SW}px;height:${SH}px;border-radius:74px;background:#fff"></div></body>`);
await pg.screenshot({ path: path.join(TMP, 'mask.png') });
await pg.setViewportSize({ width: W, height: H });
const caps = [...new Set(SEG.map(s => s[4]))];
for (const [i, c] of caps.entries()) await png(`cap${i}.png`, `<h1>${c}</h1>`, true);
await browser.close();

// ---------- 2. 구간 정리(1320x2868, 30fps) ----------
sh(['-i', PATCH_SRC, '-vf', 'crop=300:90:470:1900', path.join(TMP, 'patch.png')]);
const parts = [];
for (const [i, [clip, a, b, hold, , mask]] of SEG.entries()) {
  const out = path.join(TMP, `seg${i}.mp4`);
  // 입력 쪽 -ss 는 VFR 녹화에서 구간이 어긋났다 → 통째로 읽고 trim 으로 자른다(가림 구간도 클립 시간 기준)
  const base = `[0:v]setpts=PTS-STARTPTS,fps=${FPS}`;
  const tail = `trim=${a}:${b},setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=${hold},format=yuv420p[o]`;
  const graph = mask ? `${base}[v];[v][1:v]overlay=470:1900:enable='between(t,${mask[0]},${mask[1]})',${tail}` : `${base},${tail}`;
  sh(['-i', path.join(CLIPS, clip + '.mov'), ...(mask ? ['-i', path.join(TMP, 'patch.png')] : []),
    '-filter_complex', graph, '-map', '[o]', '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '14', out]);
  parts.push(out);
}
fs.writeFileSync(path.join(TMP, 'list.txt'), parts.map(p => `file '${p}'`).join('\n'));
sh(['-f', 'concat', '-safe', '0', '-i', path.join(TMP, 'list.txt'), '-c', 'copy', path.join(TMP, 'body.mp4')]);

// ---------- 3. 합성: 배경 + 둥근 화면 + 구간별 자막 ----------
const dur = (f) => parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString());
let t = 0; const capT = caps.map(() => []);
for (const [i, s] of SEG.entries()) { const d = dur(parts[i]); capT[caps.indexOf(s[4])].push([t, t + d]); t += d; }
const total = t;
const inputs = ['-loop', '1', '-i', path.join(TMP, 'bg.png'), '-i', path.join(TMP, 'body.mp4'), '-loop', '1', '-i', path.join(TMP, 'mask.png')];
caps.forEach((_, i) => inputs.push('-loop', '1', '-i', path.join(TMP, `cap${i}.png`)));
inputs.push('-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100');
let g = `[1:v]scale=${SW}:${SH}:flags=lanczos,format=rgba[s];[2:v]format=gray,scale=${SW}:${SH}[mk];[s][mk]alphamerge[sr];[0:v][sr]overlay=${SX}:${SY}[b0]`;
caps.forEach((_, i) => {
  const en = capT[i].map(([x, y]) => `between(t,${x.toFixed(3)},${y.toFixed(3)})`).join('+');
  g += `;[b${i}][${3 + i}:v]overlay=0:0:enable='${en}'[b${i + 1}]`;
});
g += `;[b${caps.length}]fps=${FPS},format=yuv420p[v]`;
const OUT = path.resolve(HERE, '../fcscope-preview-886x1920.mp4');
sh([...inputs, '-filter_complex', g, '-map', '[v]', '-map', `${3 + caps.length}:a`, '-t', total.toFixed(3),
  '-c:v', 'libx264', '-profile:v', 'high', '-level', '4.0', '-pix_fmt', 'yuv420p', '-b:v', '10M', '-maxrate', '12M', '-bufsize', '20M',
  '-c:a', 'aac', '-b:a', '256k', '-ar', '44100', '-movflags', '+faststart', OUT]);
console.log('wrote', OUT, total.toFixed(2) + 's');
