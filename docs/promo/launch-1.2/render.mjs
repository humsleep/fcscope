// 1.2 런칭 홍보영상 — scene.html 을 프레임 단위로 찍어 1080x1920 MP4 로 만든다.
// 사용: node render.mjs [preview]   (preview = 장면마다 한 장씩 찍어 확인)
// 재료: ../raw/launch12/clips/{rec,squad,calc}/*.jpg (시뮬레이터 녹화를 30fps 로 뽑은 것),
//       ../../store-v2/screenshots-v4/src/clean/*.png (다른 이용자 닉네임을 가린 스토어 캡처)
import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const CLIPS = path.resolve(HERE, '../raw/launch12/clips');
const CLEAN = path.resolve(HERE, '../../store-v2/screenshots-v4/src/clean');
const OUT = path.join(HERE, 'out');
const FPS = 30, DUR = 32;
const preview = process.argv[2] === 'preview';

const file = (f) => 'file://' + f;
const seq = (d) => fs.readdirSync(path.join(CLIPS, d)).filter((f) => f.endsWith('.jpg')).sort().map((f) => file(path.join(CLIPS, d, f)));
const A = {
  icon: file(path.resolve(HERE, '../../../FCScope/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')),
  cardUser: file(path.join(CLEAN, 'card-user.png')),
  cardVs: file(path.join(CLEAN, 'card-vs.png')),
  still: Object.fromEntries(['today', 'league', 'vs'].map((k) => [k, file(path.join(CLEAN, `${k}.png`))]).concat([['shot', file(path.join(CLEAN, 'win2.png'))]])),
  rec: seq('rec'), squad: seq('squad'), calc: seq('calc'),
};

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'frames'), { recursive: true });

const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
await p.goto('file://' + path.join(HERE, 'scene.html'));
await p.evaluate(() => document.fonts.ready);
await p.evaluate((a) => window.setup(a), A);

const times = preview ? [0.6, 1.5, 3.2, 5.6, 8.8, 11.6, 13.0, 14.9, 16.9, 20.4, 23.6, 26.8, 30.4]
  : Array.from({ length: FPS * DUR }, (_, i) => i / FPS);
for (const [i, t] of times.entries()) {
  await p.evaluate((t) => window.render(t), t);
  const name = preview ? `p-${t.toFixed(1).padStart(4, '0')}.jpg` : `${String(i).padStart(4, '0')}.jpg`;
  await p.screenshot({ path: path.join(OUT, 'frames', name), type: 'jpeg', quality: 94 });
  if (!preview && i % 120 === 0) console.log(`frame ${i}/${times.length}`);
}
await b.close();

if (preview) {
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-pattern_type', 'glob', '-i', path.join(OUT, 'frames/p-*.jpg'), '-vf', 'scale=270:-1,tile=7x2', path.join(OUT, 'preview.png')]);
  console.log('preview →', path.join(OUT, 'preview.png'));
} else {
  const mp4 = path.join(HERE, 'fcscope-1.2-promo.mp4');
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-framerate', String(FPS), '-i', path.join(OUT, 'frames/%04d.jpg'),
    '-f', 'lavfi', '-t', String(DUR), '-i', 'anullsrc=r=48000:cl=stereo',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-movflags', '+faststart',
    '-c:a', 'aac', '-b:a', '128k', '-shortest', mp4]);
  console.log('video →', mp4);
}
