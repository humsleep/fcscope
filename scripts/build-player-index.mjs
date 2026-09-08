#!/usr/bin/env node
/**
 * 앱 번들용 선수 인덱스 생성 — 넥슨 spid.json(6.5MB, 88k행) → 압축 인덱스.
 *
 * 최적화 근거: 선수 검색은 서버가 6.5MB 인덱스를 인스턴스마다 메모리에 상주시키고
 * 매 요청 전체를 필터링한다(CPU). 앱이 인덱스를 내장하면 검색이 오프라인·즉시가 되고
 * 서버 왕복·CPU·메모리가 모두 0이 된다.
 *
 * 포맷(spid = seasonId * 1_000_000 + pid 이므로 spid 자체는 저장하지 않는다):
 *   { v, date, seasons: { [seasonId]: 시즌약칭 }, players: [[pid, 이름, [seasonId...]], ...] }
 *
 * 사용: node scripts/build-player-index.mjs [출력경로]
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { gzipSync } from 'node:zlib';

const SPID = 'https://open.api.nexon.com/static/fconline/meta/spid.json';
const SEASON = 'https://open.api.nexon.com/static/fconline/meta/seasonid.json';
const out = process.argv[2] ?? 'FCScope/Resources/players.json';

/** lib/nexon/players.ts shortSeason 과 동일 규칙 — 괄호 앞 토큰만 사용 */
function shortSeason(className) {
  return (className ?? '').split('(')[0].trim();
}

const [spidRes, seasonRes] = await Promise.all([fetch(SPID), fetch(SEASON)]);
if (!spidRes.ok || !seasonRes.ok) {
  console.error('넥슨 메타 조회 실패', spidRes.status, seasonRes.status);
  process.exit(1);
}
const cards = await spidRes.json();
const seasonList = await seasonRes.json();

const seasons = {};
for (const s of seasonList) {
  const n = shortSeason(s.className);
  if (n) seasons[s.seasonId] = n;
}

// pid 별 집계. 이름은 최신 시즌(가장 큰 spid) 기준 — 서버 getPlayerBySpid 와 동일.
const byPid = new Map();
for (const c of cards) {
  const pid = c.id % 1_000_000;
  const seasonId = Math.floor(c.id / 1_000_000);
  let e = byPid.get(pid);
  if (!e) {
    e = { pid, name: c.name, top: c.id, seasons: [] };
    byPid.set(pid, e);
  }
  if (c.id > e.top) {
    e.top = c.id;
    e.name = c.name; // 최신 시즌 표기 채택
  }
  e.seasons.push(seasonId);
}

const players = [...byPid.values()]
  .map((e) => [e.pid, e.name, [...new Set(e.seasons)].sort((a, b) => b - a)])
  .sort((a, b) => a[0] - b[0]);

const payload = {
  v: 1,
  date: new Date().toISOString().slice(0, 10),
  seasons,
  players,
};

const json = JSON.stringify(payload);
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, json);

const gz = gzipSync(Buffer.from(json), { level: 9 });
console.log(`카드 ${cards.length}장 → 선수 ${players.length}명, 시즌 ${Object.keys(seasons).length}종`);
console.log(`원본 spid.json ≈ 6.5MB → ${out} ${(json.length / 1024).toFixed(0)}KB (gzip ${(gz.length / 1024).toFixed(0)}KB, IPA 내부 압축 기준)`);
