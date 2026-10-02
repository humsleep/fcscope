import { createRequire } from 'module';
const require = createRequire('/Users/hyukahn/workspace/fcscope/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
const b = await chromium.launch(); const p = await b.newPage();
const shots='/Users/hyukahn/workspace/fcscope-ios/docs/screenshots/';
const q = {
 '02-record.png':[[10,10],[10,1500],[150,670],[100,1950],[60,450],[300,1000],[60,1660],[200,2000]],
 '03-match-report.png':[[999,598],[900,598],[60,1165],[120,1100],[300,1500],[1000,630],[400,1165],[700,1165]],
 '05-report.png':[[140,1000]],
};
for (const [f,pts] of Object.entries(q)) {
  const d = 'data:image/png;base64,'+fs.readFileSync(shots+f).toString('base64');
  const r = await p.evaluate(async ({d,pts})=>{const i=new Image();i.src=d;await i.decode();const c=document.createElement('canvas');c.width=i.width;c.height=i.height;const x=c.getContext('2d');x.drawImage(i,0,0);return pts.map(([a,b])=>{const v=x.getImageData(a,b,1,1).data;return [a,b,'#'+[v[0],v[1],v[2]].map(n=>n.toString(16).padStart(2,'0')).join('')]})},{d,pts});
  console.log(f, JSON.stringify(r));
}
await b.close();
