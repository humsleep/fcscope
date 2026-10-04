// "왜 졌을까" 키네틱 쇼츠 — scene.html 을 프레임 단위로 찍어 1080x1920 MP4 로 만든다.
// 사용: node render.mjs [preview]   (preview = 몇 장만 찍어 확인)
import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const RAW = path.resolve(HERE, '../raw');
const OUT = path.join(HERE, 'out');
const FPS = 30, DUR = 20;
const preview = process.argv[2] === 'preview';

const png = (f) => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
const FR = path.join(RAW, 'f');

// 원본 캡처에서 필요한 부분만 잘라 둔다(상대 닉네임은 앱의 -maskOpponent 로 이미 "상대").
const crop = (src, dst, c) => { if (!fs.existsSync(dst)) execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', src, '-vf', `crop=${c}`, dst]); return dst; };
fs.mkdirSync(path.join(RAW, 'peek'), { recursive: true });
const A = {
  why: png(crop(path.join(RAW, 'report-top.png'), path.join(RAW, 'peek/why.png'), '1221:411:49:1434')),
  map: png(crop(path.join(RAW, 'shot-tap.png'), path.join(RAW, 'peek/map.png'), '1260:955:30:1255')),
  icon: png(path.join(RAW, 'icon.png')),
  frames: fs.readdirSync(FR).filter((f) => f.endsWith('.jpg')).sort().map((f) => 'file://' + path.join(FR, f)),
};

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'frames'), { recursive: true });

const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
await p.goto('file://' + path.join(HERE, 'scene.html'));
await p.evaluate((a) => window.setup(a), A);

const times = preview ? [0.3, 0.9, 1.6, 3.0, 4.2, 4.9, 6.5, 8.5, 10.9, 12.6, 14.3, 16.0, 18.5] : Array.from({ length: FPS * DUR }, (_, i) => i / FPS);
for (const [i, t] of times.entries()) {
  await p.evaluate((t) => window.render(t), t);
  const name = preview ? `p-${t.toFixed(1)}.jpg` : `${String(i).padStart(4, '0')}.jpg`;
  await p.screenshot({ path: path.join(OUT, 'frames', name), type: 'jpeg', quality: 94 });
  if (!preview && i % 60 === 0) console.log(`frame ${i}/${times.length}`);
}
await b.close();

if (preview) {
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-pattern_type', 'glob', '-i', path.join(OUT, 'frames/p-*.jpg'), '-vf', 'scale=270:-1,tile=7x2', path.join(OUT, 'preview.png')]);
  console.log('preview →', path.join(OUT, 'preview.png'));
} else {
  const mp4 = path.join(HERE, 'why-lost.mp4');
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-framerate', String(FPS), '-i', path.join(OUT, 'frames/%04d.jpg'),
    '-f', 'lavfi', '-t', String(DUR), '-i', 'anullsrc=r=48000:cl=stereo',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-movflags', '+faststart',
    '-c:a', 'aac', '-b:a', '128k', '-shortest', mp4]);
  console.log('video →', mp4);
}
