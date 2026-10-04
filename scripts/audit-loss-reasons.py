"""lossReasons 사실 검증 — FCScope/Core/UI/Copy.swift `lossReasons`·`decidingGoal` 의 파이썬 포트 + 독립 검증.

사용: 진 경기 상세 JSON 을 md/<matchId>_<ouid>.json 으로 받아 두고(예:
  curl -s "https://www.fcscope.xyz/api/v1/match/<id>?me=<ouid>" -o md/<id>_<ouid>.json)
  python3 scripts/audit-loss-reasons.py
결승골 문장은 양 팀 골 기록으로 스코어 흐름을 다시 세워 "마지막으로 동점을 깬 상대 골"과 맞는지 확인한다.
2026-10-04 실경기 114건(10명): 규칙 적중 164문장, 검증 실패 0.
Swift 규칙을 바꾸면 이 포트도 같이 바꿀 것.
"""
import json,glob
def reasons(d):
    m,o=d['me'],d['opponent']
    if m['result']!='패' or m['forfeit'] or not o or m['goals']>=o['goals']: return []
    ms,os_=m['stats'],o['stats']
    mlg=sum(s['isGoal'] for s in m['shots']); olg=sum(s['isGoal'] for s in o['shots'])
    myOK=len(m['shots'])==ms['shots'] and mlg==m['goals']; opOK=len(o['shots'])==os_['shots'] and olg==o['goals']
    out=[]
    if ms['shots']<=4 and ms['shots']<os_['shots']: out.append(('r1',f"슛 {ms['shots']}개로는 어려웠어요 — 상대는 {os_['shots']}개"))
    if ms['shots']>=6 and ms['effectiveShots']<=ms['shots'] and ms['effectiveShots']*3<=ms['shots']: out.append(('r2',f"슛 {ms['shots']}개 중 유효슛 {ms['effectiveShots']}개"))
    if myOK and ms['shots']>=5 and all(s.get('inPenalty') is not None for s in m['shots']):
        box=sum(1 for s in m['shots'] if s['inPenalty'] is True)
        if box*2<len(m['shots']): out.append(('r3',f"슛 {len(m['shots'])}개 중 박스 안 {box}개"))
    if myOK and ms['effectiveShots']>=5 and m['goals']<=ms['effectiveShots'] and m['goals']*4<=ms['effectiveShots']: out.append(('r4',f"유효슛 {ms['effectiveShots']}개에 {m['goals']}골"))
    if opOK and o['goals']>=2 and o['goals']<=os_['effectiveShots'] and o['goals']*2>=os_['effectiveShots']: out.append(('r5',f"상대는 유효슛 {os_['effectiveShots']}개로 {o['goals']}골"))
    if len(o['shots'])==os_['shots'] and olg<o['goals']: out.append(('r5b',f"{o['goals']}실점 중 {o['goals']-olg}골은 상대 슛이 아닌 골"))
    if m['possession']<=40: out.append(('r6',f"점유 {m['possession']}%"))
    w=deciding(d)
    if w and w[0]>=80: out.append(('r7',f"{w[1]}:{w[1]} 동점이던 {w[0]}분, 결승골"))
    return out[:2], out
def deciding(d):
    m,o=d['me'],d['opponent']
    if o['goals']-m['goals']!=1: return None
    mine=[s for s in m['shots'] if s['isGoal']]; th=[s for s in o['shots'] if s['isGoal']]
    if len(mine)!=m['goals'] or len(th)!=o['goals'] or len(m['shots'])!=m['stats']['shots'] or len(o['shots'])!=o['stats']['shots']: return None
    mm=[s.get('minute') for s in mine]; om=sorted(s.get('minute') for s in th)
    if None in mm or None in om: return None
    k=m['goals']; g=om[k]
    if g in mm: return None
    if k>0 and om[k-1]==g: return None
    if not all(x<g for x in mm): return None
    return (g,k)
# independent verification
def verify(d,tag,txt):
    m,o=d['me'],d['opponent']
    if tag=='r7':
        # replay full timeline; check the claimed goal: score before tied, after it opp leads to the end
        ev=sorted([(s['minute'],'me') for s in m['shots'] if s['isGoal']]+[(s['minute'],'op') for s in o['shots'] if s['isGoal']])
        a=b=0; last_tie_break=None
        for mi,who in ev:
            prev=(a,b)
            if who=='me': a+=1
            else: b+=1
            if prev[0]==prev[1] and who=='op': last_tie_break=(mi,prev[0])
            if a>=b: last_tie_break=None if a==b else last_tie_break
        assert (a,b)==(m['goals'],o['goals']), 'timeline mismatch'
        g,tie=int(txt.split('동점이던 ')[1].split('분')[0]),int(txt.split(':')[0])
        assert last_tie_break==(g,tie), f'claimed {(g,tie)} actual {last_tie_break}'
        mins=[x for x,_ in ev]; assert mins.count(g)==1,'ambiguous minute'
    if tag in('r4',): assert sum(s['isGoal'] for s in m['shots'])==m['goals']
    if tag=='r5': assert sum(s['isGoal'] for s in o['shots'])==o['goals'] and o['goals']<=o['stats']['effectiveShots']
    if tag=='r3': assert len(m['shots'])==m['stats']['shots']
    return True
n=0; tags={}; fails=0; samples=[]
for f in sorted(glob.glob('md/*.json')):
    d=json.load(open(f))
    if 'me' not in d: continue
    shown,allr=reasons(d); n+=1
    for t,txt in allr:
        tags[t]=tags.get(t,0)+1
        try: verify(d,t,txt)
        except AssertionError as e: fails+=1; print('FAIL',f,t,txt,e)
    samples.append((f.split('/')[-1][:24],[x[1] for x in shown]))
print('matches',n,'rule hits',tags,'fails',fails,'empty',sum(1 for s in samples if not s[1]))
for s in samples:
    if '6abf6058' in s[0] or '6ab7bdb5' in s[0]: print(s)
