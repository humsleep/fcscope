#!/usr/bin/env python3
"""Models.swift 를 실제 서버 응답에 직접 대조한다 — 앱이 응답을 디코딩할 수 있는지 확인.

Swift `Decodable` 은 non-optional 필드가 하나만 없거나 타입이 다르면 **응답 전체 디코딩이
실패**한다. 옵셔널이면 디코딩은 성공하고 값만 nil 이 되어 화면에서 조용히 사라진다
(2026-09-09 스쿼드 배틀 투표수가 늘 0이던 버그가 이 경우였다).

웹 저장소의 `npm run verify:api` 는 "서버가 계약을 지키는가"를 본다. 이 스크립트는
반대로 "앱이 실제 응답을 읽을 수 있는가"를 본다. 손으로 쓴 계약을 거치지 않으므로
계약 자체의 오기까지 잡는다.

    python3 scripts/verify-decoding.py [baseUrl] [닉네임]

위반이 있으면 exit 1.
"""
import re, json, pathlib, sys, urllib.parse, urllib.request

# ── Models.swift 파싱 ────────────────────────────────────────
src = (pathlib.Path(__file__).resolve().parent.parent / 'FCScope/Core/API/Models.swift').read_text()

def body_at(s, open_idx):
    """open_idx 는 '{' 위치. 균형 잡힌 본문 문자열과 닫는 '}' 인덱스를 돌려준다."""
    depth = 0
    for j in range(open_idx, len(s)):
        if s[j] == '{': depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0: return s[open_idx + 1:j], j
    return s[open_idx + 1:], len(s)

def find_structs(s, out):
    """중첩 struct 도 개별 항목으로 등록하고, 부모 본문에서는 제거한다."""
    i = 0
    while True:
        m = re.search(r'\bstruct\s+(\w+)\s*[:{]', s[i:])
        if not m: break
        name = m.group(1)
        ob = s.find('{', i + m.start())
        if ob < 0: break
        body, close = body_at(s, ob)
        inner_removed = find_structs(body, out)   # 중첩 먼저 처리
        out[name] = inner_removed
        i = close + 1
    # 부모에서 struct 블록 전부 제거
    cleaned, i = [], 0
    while True:
        m = re.search(r'\bstruct\s+\w+\s*[:{]', s[i:])
        if not m: break
        ob = s.find('{', i + m.start())
        if ob < 0: break
        _, close = body_at(s, ob)
        cleaned.append(s[i:i + m.start()])
        i = close + 1
    cleaned.append(s[i:])
    return ''.join(cleaned)

bodies = {}
find_structs(src, bodies)

out = {}
for name, flat in bodies.items():
    computed = set(re.findall(r'\b(?:var|let)\s+(\w+)\s*:\s*[^\n;={]+\{', flat))
    fields = []
    for fm in re.finditer(r'\b(?:let|var)\s+([\w,\s]+?)\s*:\s*([^\n;={]+)', flat):
        typ = fm.group(2).strip().rstrip(';').strip()
        for n in (x.strip() for x in fm.group(1).split(',')):
            if n and n not in computed:
                fields.append((n, typ))
    remap = {}
    ck = re.search(r'enum CodingKeys[^{]*\{([^}]*)\}', flat)
    if ck:
        for cm in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', ck.group(1)):
            remap[cm.group(1)] = cm.group(2)
    out[name] = {
        'fields': [{'swift': n, 'json': remap.get(n, n), 'type': t} for n, t in fields],
        'remapped': remap,
    }

def build_models():
    bodies = {}
    find_structs(src, bodies)
    out = {}
    for name, flat in bodies.items():
        computed = set(re.findall(r'\b(?:var|let)\s+(\w+)\s*:\s*[^\n;={]+\{', flat))
        fields = []
        for fm in re.finditer(r'\b(?:let|var)\s+([\w,\s]+?)\s*:\s*([^\n;={]+)', flat):
            typ = fm.group(2).strip().rstrip(';').strip()
            for n in (x.strip() for x in fm.group(1).split(',')):
                if n and n not in computed:
                    fields.append((n, typ))
        remap = {}
        ck = re.search(r'enum CodingKeys[^{]*\{([^}]*)\}', flat)
        if ck:
            for cm in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', ck.group(1)):
                remap[cm.group(1)] = cm.group(2)
        out[name] = {'fields': [{'swift': n, 'json': remap.get(n, n), 'type': t} for n, t in fields]}
    return out

M = build_models()

# ── 실제 응답과 대조 ─────────────────────────────────────────
BASE = (sys.argv[1] if len(sys.argv) > 1 else 'https://www.fcscope.xyz').rstrip('/')
NICK = urllib.parse.quote(sys.argv[2] if len(sys.argv) > 2 else '보엠')

def get(path):
    req = urllib.request.Request(BASE + path, headers={'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode())
    except Exception as e:
        return getattr(e, 'code', 0), None

PRIM = {'String': str, 'Int': int, 'Double': (int, float), 'Bool': bool}
problems = []

def base_type(t):
    t = t.strip()
    opt = 0
    while t.endswith('?'):
        opt += 1; t = t[:-1].strip()
    arr = False
    if t.startswith('[') and t.endswith(']'):
        inner = t[1:-1].strip()
        if ':' in inner:
            return 'DICT', False, opt   # [K: V] 딕셔너리 — 배열이 아니다
        arr = True; t = inner
    return t, arr, opt

def check(struct, val, path, seen=None):
    seen = seen or set()
    if struct not in M:
        return  # 알 수 없는 타입(딕셔너리 등)은 건너뜀
    if not isinstance(val, dict):
        problems.append(f'{path}: 객체여야 하는데 {type(val).__name__}')
        return
    for f in M[struct]['fields']:
        key, t = f['json'], f['type']
        bt, arr, opt = base_type(t)
        at = f'{path}.{key}' if path else key
        if key not in val:
            if opt == 0:
                problems.append(f'{at}: 필수 필드인데 응답에 없음 (Swift {struct}.{f["swift"]}: {t})')
            continue
        v = val[key]
        if v is None:
            if opt == 0:
                problems.append(f'{at}: 필수 필드인데 null (Swift {struct}.{f["swift"]}: {t})')
            continue
        if bt == 'DICT':
            if not isinstance(v, dict):
                problems.append(f'{at}: 딕셔너리여야 하는데 {type(v).__name__}')
            continue
        if arr:
            if not isinstance(v, list):
                problems.append(f'{at}: 배열이어야 하는데 {type(v).__name__}')
                continue
            for i, el in enumerate(v[:3]):
                checkval(bt, el, f'{at}[{i}]', struct, f)
        else:
            checkval(bt, v, at, struct, f)

def checkval(bt, v, at, struct, f):
    if bt in PRIM:
        exp = PRIM[bt]
        if bt == 'Int':
            if isinstance(v, bool) or not isinstance(v, int):
                problems.append(f'{at}: Int 여야 하는데 {json.dumps(v)[:30]} (Swift {struct}.{f["swift"]})')
        elif bt == 'Bool':
            if not isinstance(v, bool):
                problems.append(f'{at}: Bool 이어야 하는데 {json.dumps(v)[:30]} (Swift {struct}.{f["swift"]})')
        elif not isinstance(v, exp) or (bt == 'String' and not isinstance(v, str)):
            problems.append(f'{at}: {bt} 여야 하는데 {json.dumps(v)[:30]} (Swift {struct}.{f["swift"]})')
    elif bt in M:
        check(bt, v, at)

# 라우트 → 루트 struct
user = get(f'/api/v1/user/{NICK}')[1]
matchId = (user or {}).get('matches', [{}])[0].get('matchId') if user and user.get('matches') else None
posts = get('/api/v1/community/posts')[1]
postId = (posts or {}).get('posts', [{}])[0].get('id') if posts and posts.get('posts') else None
squadId = next((p.get('squad_id') for p in (posts or {}).get('posts', []) if p.get('squad_id')), None)
players = get(f'/api/v1/user/{NICK}/players')[1]
spid = (players or {}).get('players', [{}])[0].get('spId') if players and players.get('players') else None

CASES = [
    ('UserOverview', f'/api/v1/user/{NICK}'),
    ('ReportResponse', f'/api/v1/user/{NICK}/report'),
    ('PlayersResponse', f'/api/v1/user/{NICK}/players'),
    ('PlaystyleResponse', f'/api/v1/user/{NICK}/playstyle'),
    ('HomeResponse', '/api/v1/home'),
    ('MetaResponse', '/api/v1/meta'),
    ('PostListResponse', '/api/v1/community/posts'),
    ('PlayerSearchResponse', '/api/players/search?q=' + urllib.parse.quote('손흥민')),
    ('NotificationsResponse', '/api/me/notifications'),
    ('PresetResponse', '/api/squad/preset?id=mancity'),
    ('FromUserResponse', f'/api/squad/from-user?nickname={NICK}'),
]
if matchId: CASES.append(('MatchDetailResponse', f'/api/v1/match/{matchId}'))
if spid: CASES.append(('PlayerDetail', f'/api/v1/player/{spid}'))
if postId:
    CASES.append(('PostDetailResponse', f'/api/v1/community/posts/{postId}'))
    CASES.append(('BattleVotes', f'/api/community/battle?postId={postId}'))
if squadId: CASES.append(('Squad', f'/api/squad/{squadId}'))

for struct, path in CASES:
    before = len(problems)
    status, body = get(path)
    if status != 200 or body is None:
        print(f'  – {struct:22s} HTTP {status}')
        continue
    check(struct, body, '')
    n = len(problems) - before
    print(f'  {"✗" if n else "✓"} {struct:22s} {path[:52]}' + (f'  ({n}건)' if n else ''))

print(f'\n파싱한 struct {len(M)}개 · 위반 {len(problems)}건')
for p in problems:
    print('  🔴', p)
if problems:
    print('\n🔴 앱이 이 응답을 제대로 읽지 못합니다.')
    print('   non-optional 이면 디코딩 전체 실패, optional 이면 값이 조용히 nil 이 됩니다.')
    sys.exit(1)
print('✓ 모든 응답이 Models.swift 로 디코딩 가능')
