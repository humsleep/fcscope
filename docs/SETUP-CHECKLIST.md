# 출시 전 준비 체크리스트 (운영자 전용)

코드로 할 수 있는 일은 끝났습니다. 여기 적힌 것은 **계정·키·결정**이라 제가 대신 할 수 없는 것들입니다.
값을 채워야 하는 위치까지 정확히 적었습니다.

> **저장소 구조**: 웹은 GitHub(`humsleep/fconline`), **앱은 로컬 전용**(`~/workspace/fcscope-ios`, 원격 없음).
> 앱은 자체 서버가 없어 웹 서버의 `/api/v1` 을 호출합니다 — 웹이 배포돼 있어야 앱이 동작합니다.

---

## 실행 순서 — 남은 것만

| # | 할 일 | 어디서 | 소요 |
|---|---|---|---|
| ✅ | ~~넥슨 키 재발급~~ · ~~0018·0019 마이그레이션~~ · ~~match_cache 정리~~ | | 완료 |
| 1 | 웹 저장소 `feat/app-backend-and-efficiency` 를 main 에 머지 → Vercel 배포 | GitHub | 5분 |
| 2 | Supabase Redirect URL·Apple provider 설정 | Supabase 대시보드 | 10분 |
| 3 | Vercel 환경변수 7개 추가 → 재배포 | Vercel | 15분 |
| 4 | Apple Developer: App ID·권한 4종·APNs 키 | developer.apple.com | 30분 |
| 5 | AdMob 계정·앱·배너 단위 생성 | AdMob | 20분 |
| 6 | Info.plist 4개 값 입력 → `xcodegen generate` | 로컬 | 5분 |
| 7 | Archive → TestFlight → 실기기 확인 | Xcode | 1시간 |

### ✅ DB 정리 결과 (2026-09-05)

| 항목 | 이전 | 이후 |
|---|---|---|
| match_cache | 1,664MB / 314,502행 | **93MB / 23,347행** |
| Supabase 무료 한도(500MB) | 초과 | 여유 |

앞으로 저장되는 행은 배열 패킹이 적용되어 행당 4,555B → 약 1,200B입니다.
30일 보관기간과 합치면 정상 상태에서 **30MB 안팎**으로 유지됩니다.

---

## 0. 지금 상태 요약

| 항목 | 상태 |
|---|---|
| 앱 빌드 (Debug/Release) | ✅ 통과 |
| 웹 빌드·테스트 229개 | ✅ 통과 |
| 서버 시크릿이 앱에 들어갔는지 | ✅ 없음 (전수 확인) |
| match_cache 용량 | ✅ 93MB (무료 한도 내) |
| 마이그레이션 0001~0018 | ✅ 전부 적용 |
| 마이그레이션 0019 (죽은 스키마) | ✅ 적용 완료 |
| Supabase 값 (앱) | ⬜ **비어 있음 — 채워야 로그인 동작** |
| AdMob 값 (앱) | ⬜ **구글 테스트 ID — 채워야 광고 수익** |

> 값이 비어 있어도 앱은 정상 실행됩니다. 로그인·커뮤니티만 잠기고, 광고는 릴리스에서 자동으로 꺼집니다.

---

## 1. 확인된 답변 (2026-09-04)

| 질문 | 답 | 남은 일 |
|---|---|---|
| Apple Developer 유료 가입 | ✅ 가입됨 | 완료 |
| Apple 팀 ID | `68BP5NY48R` | Vercel `APPLE_TEAM_ID`·`APNS_TEAM_ID` 두 곳에 입력 |
| 도메인 | `www.fcscope.xyz` 유지 | 없음 |
| 문의 이메일 | `boheme88@naver.com` 유지 | 없음 |
| 웹 광고 | ❌ 앱에만 게재 | Vercel 무료 유지 가능 |
| 예시 리포트 구단주명 | `보엠` | Vercel `NEXT_PUBLIC_DEMO_NICKNAME=보엠` |
| 이적시장 보정 표본 | — | 기능 자체를 제거했습니다(7번 참고) |

팀 ID `68BP5NY48R` 은 비밀 값이 아니라 앱 번들에도 들어가는 식별자입니다. 그대로 Vercel 두 변수에 넣으시면 됩니다.

### 왜 앱이 웹 도메인을 필요로 하나

앱에는 자체 서버가 없습니다. 넥슨 API 키는 서버에만 둬야 해서, 앱은 웹 서버의 `/api/v1` 을 호출합니다.
도메인이 앱 코드에 박혀 있는 곳은 다음 다섯 군데입니다.

| 위치 | 용도 |
|---|---|
| `Config.productionBase` | 모든 API 호출의 기준 주소 |
| `Config.termsURL` / `privacyURL` | 설정·로그인 화면의 약관 링크 |
| `Config.shareHost` | 공유 카드 하단에 찍히는 도메인 |
| `AppRouter.handle(url:)` | 공유 링크를 탭했을 때 앱으로 여는 판정 |
| 엔타이틀먼트 `applinks:` | 유니버설 링크 등록 |

도메인을 바꾸면 앱 업데이트를 새로 심사받아야 링크가 다시 붙습니다. 그래서 확정 여부를 여쭤본 것이고,
유지하신다면 더 하실 일은 없습니다.

---

## 2. Apple Developer 설정

1. **App ID 생성**: `xyz.fcscope.app`
2. **Capabilities 4개 체크**
   - Sign in with Apple
   - Associated Domains
   - Push Notifications
   - App Groups → `group.xyz.fcscope.app` 생성 후 연결
3. **APNs 키 생성**: Keys → 새 키 → Apple Push Notifications service 체크 → `.p8` 다운로드
   - 다운로드는 **한 번뿐**입니다. 안전한 곳에 보관하세요.
   - 여기서 나오는 **Key ID**와 **팀 ID**, `.p8` 파일 내용이 아래 4번에 들어갑니다.
4. Xcode에서 팀 선택 (`FCScope.xcodeproj` → Signing & Capabilities)

---

## 3. 앱에 넣을 값 — `FCScope/Info.plist`

지금 빈 문자열로 자리만 잡혀 있습니다. **여기 들어가는 값은 전부 공개해도 되는 값**입니다.

| 키 | 넣을 값 | 어디서 |
|---|---|---|
| `FCSupabaseURL` | `https://xxxx.supabase.co` | Supabase → Settings → API → Project URL |
| `FCSupabaseAnonKey` | `eyJ...` (anon public) | 같은 화면의 **anon public** 키 |
| `GADApplicationIdentifier` | `ca-app-pub-XXXX~YYYY` | AdMob → 앱 → 앱 설정 → 앱 ID |
| `FCAdMobBannerUnit` | `ca-app-pub-XXXX/ZZZZ` | AdMob → 광고 단위 → 배너 |

> ⚠️ **`service_role` 키는 절대 넣지 마세요.** anon 키만입니다. 두 키는 같은 화면에 나란히 있어 헷갈리기 쉽습니다.
> `service_role`은 데이터베이스 보안을 우회하는 키라 앱에 들어가면 누구나 추출할 수 있습니다.

값을 넣은 뒤 iOS 저장소 루트에서 `xcodegen generate` 를 다시 돌리면 됩니다.

---

## 4. Vercel 환경변수 (추가할 것만)

이미 등록하신 것 외에 새로 필요한 값입니다.

| 변수 | 값 | 용도 |
|---|---|---|
| `APPLE_TEAM_ID` | `68BP5NY48R` | 유니버설 링크 파일 생성 |
| `ADMOB_PUBLISHER_ID` | `pub-XXXXXXXX` | `/app-ads.txt` 노출, 광고 수익 보호 |
| `APNS_KEY_ID` | 10자리 키 ID | 푸시 발송 |
| `APNS_TEAM_ID` | `68BP5NY48R` | 푸시 발송 |
| `APNS_PRIVATE_KEY` | `.p8` 파일 **내용 전체** | 푸시 발송 |
| `APNS_BUNDLE_ID` | `xyz.fcscope.app` | 푸시 발송 |
| `NEXT_PUBLIC_DEMO_NICKNAME` | `보엠` | 앱 홈 "예시 리포트" 카드 |
| `NEXON_API_KEY` | ✅ 재발급 완료분 반영 여부만 확인 | 넥슨 오픈API 콘솔 |

`.p8` 내용은 `-----BEGIN PRIVATE KEY-----` 부터 끝까지 통째로 붙여넣으면 됩니다. 개행은 그대로 두어도 됩니다.

**넣으면 안 되는 것**: `NEXON_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `IP_HASH_SALT`, `CRON_SECRET` 은 이미 서버에만 있고 앱과 무관합니다.

---

## 5. Supabase 설정

1. **마이그레이션** — ✅ 0001~0019 전부 적용 완료. 남은 것 없음.
2. **용량 정리** — ✅ 완료 (1,664MB → 93MB).
3. **Authentication → URL Configuration → Redirect URLs** 에 추가
   ```
   fcscope://auth/callback
   fcscope://auth/callback?next=*
   ```
4. **Authentication → Providers → Apple** 활성화
   - Client IDs 에 `xyz.fcscope.app` 추가
   - Secret Key 는 웹에서 Apple 로그인을 쓸 때만 필요. 앱 전용이면 비워도 됩니다.

---

## 6. AdMob — 광고 형식 전략 (한국 기준)

### 형식별 수익성과 이 앱에서의 적합도

| 형식 | eCPM(티어1 기준) | FC Scope 적합도 |
|---|---|---|
| 보상형 | 최상위 | ⭐ 사용자가 자발적으로 봄. 보상 설계만 맞으면 최선 |
| 전면 | 6~12달러 | ❌ 세션이 짧고 "검색 → 결과" 가 핵심 동선이라 중간에 끼면 이탈 |
| 네이티브 | 1.5~4달러 | ⭐ 목록에 자연스럽게 섞임. 배너의 2~3배 참여율 |
| 배너 | 0.5~2달러 | ○ 보조 수입. 화면을 가리지 않는 곳만 |
| 앱 오픈 | 중상위 | ❌ 위젯·푸시로 들어온 맥락을 파괴 |

### 권장 조합

1. **네이티브 광고를 주력으로.** 픽 랭킹 목록과 커뮤니티 목록의 5~7번째 항목 자리에 카드 톤을 맞춰 넣습니다.
   배너보다 단가가 2~4배 높으면서 화면을 가리지 않습니다.
2. **보상형 광고를 보조로.** 이 앱에서 자연스러운 보상은 세 가지입니다.
   - 즐겨찾기 구단주 감시 슬롯 확장 (3명 → 5명, 24시간)
   - 공유 카드 프리미엄 템플릿 해금
   - 전적 강제 갱신 추가 횟수
   전부 "보고 나면 자랑거리가 생기는" 보상이라 자발적 시청률이 높습니다.
3. **적응형 배너는 픽 랭킹·커뮤니티 하단만.** 지금 구현된 형태입니다.
4. **전면 광고와 앱 오픈 광고는 넣지 않습니다.** 단가는 높지만 유저 패널이 명시적으로 반대했고,
   이 앱의 세션 구조와 맞지 않습니다.

> 지금 코드에는 배너만 붙어 있습니다. 네이티브·보상형은 추가 구현이 필요하니 원하시면 말씀해 주세요.

### 손익 관점

최적화 후 월 고정비가 약 8달러입니다. 배너만으로도 DAU 60~180명이면 넘습니다.
네이티브·보상형을 넣으면 그 문턱이 더 내려갑니다. **광고 형식을 고민하기 전에 비용을 줄인 것이 더 큰 효과였습니다.**

### 계정 설정

1. 계정 생성 후 iOS 앱 등록. App Store 등록 전이면 "아직 게시되지 않음" 선택
2. 배너 광고 단위 1개 생성
3. 위 3번·4번에 값 입력
4. App Store Connect 의 마케팅 URL을 `https://www.fcscope.xyz` 로 설정하면 `/app-ads.txt` 로 소유 확인이 됩니다

> 지금은 구글 테스트 ID라 **릴리스 빌드에서 광고가 자동으로 꺼집니다.** 실수로 테스트 광고를 출시해 정책 위반이 나는 것을 막는 안전장치입니다.

---

## 7. 이적시장 기능 제거 기록 (A안, 완료)

넥슨 `user/trade` 가 `ouid` 를 무시하고 API 키 소유자 본인의 거래만 반환하는 것이 확인되어 기능을 걷어냈습니다.

| 제거한 것 | |
|---|---|
| 웹 | `/market/[nickname]` 페이지, `TradeList`·`TradeSection`, 전적 페이지의 💰 배지와 이적시장 탭 |
| API | `/api/v1/user/[nickname]/market`, `getUserTrades`, `TradeRecord` |
| 로직 | `lib/market/diagnosis.ts` (진단 룰 100+개), `lib/nexon/bp.ts` (화폐 환산), `formatKoreanBP` |
| 앱 | 이적시장 화면·라우트·모델, `BPFormat` |
| 기타 | 하단 탭의 `/market` 매칭, 캐시 무효화, 관련 단위 테스트 41개 |

공용으로 쓰이던 `RuleTone` 타입은 `lib/diagnosis/tone.ts` 로 옮겼습니다. 공식경기 진단은 그대로 동작합니다.

되살리려면 이 커밋을 되돌리면 되지만, **API 제약이 바뀌지 않는 한 기능이 성립하지 않습니다.**

## 8. 배포 순서

1. 개인정보처리방침 개정 공지 게시 (**시행 7일 전** 약속이 약관에 있습니다)
2. Vercel 환경변수 입력 → 웹 배포
3. Supabase 마이그레이션 실행
4. Info.plist 값 입력 → `xcodegen generate` → Xcode Archive
5. TestFlight 업로드 → **실기기 확인**
   - Google 로그인 후 앱으로 복귀되는지
   - Apple 로그인
   - 전적 검색 (로컬에서는 넥슨 키가 없어 검증하지 못한 부분입니다)
   - 위젯 추가, 공유 카드 저장, 계정 삭제
6. 심사 제출. 심사 노트 문안은 `docs/APP-STORE.md` 에 있습니다

---

## 9. 나중에 — Cloudflare 이관 (지금은 하지 않음)

Vercel을 무료로 대체할 수 있습니다. Cloudflare Workers 가 OpenNext 어댑터로 Next.js 16 을 지원하고,
하루 10만 요청까지 무료이며 상업적 이용 제한이 없습니다. R2 도 같은 계정에서 씁니다.

**미리 알아둘 걸림돌 세 가지** (이관 시 손봐야 할 부분):

| 걸림돌 | 위치 | 대응 |
|---|---|---|
| `node:http2` 미지원 | `lib/push/apns.ts` | APNs 발송을 Workers 호환 방식으로 재작성 |
| `node:crypto` 서명 | 같은 파일의 JWT 생성 | WebCrypto 로 교체 |
| 공유 카드 이미지 생성 | `lib/card/render.tsx` (`next/og`) | Workers 동작 확인 필요 |

지금 당장 고치지 않는 이유: Vercel 에서는 정상 동작하고, 섣불리 바꾸면 푸시가 깨질 수 있습니다.
**앱 수익이 나기 시작하고 트래픽이 무료 한도에 근접할 때** 착수하는 것이 맞습니다.

## 9-1. 알려진 한계

- **전적 화면은 실데이터로 검증하지 못했습니다.** 넥슨 API 키가 로컬에 없어 오류 상태 화면만 확인했습니다. 배포 후 실기기 확인이 필요합니다.
- **콜드 조회는 여전히 최대 60초** 걸립니다. 2단계 조회로 체감은 개선했지만 넥슨 API가 병렬 호출을 막아 근본 단축은 어렵습니다.
- **`match_cache` 를 Cloudflare R2로 옮기는 최적화**가 남아 있습니다. 계정이 필요해 진행하지 않았습니다. 디스크 IO 장애의 구조적 해결책입니다.
