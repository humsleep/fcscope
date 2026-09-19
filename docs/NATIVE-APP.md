# FC Scope iOS 네이티브 앱

SwiftUI(iOS 17+) 완전 네이티브 앱. Capacitor 셸(`legacy-capacitor/`)의 후속이며, 웹 서버의 `/api/v1` JSON 을 사용한다.
회의 결정 사항은 `docs/COUNCIL-2026-09-NATIVE.md`, 스토어 등록 절차는 `docs/APP-STORE.md`.

## 구조

```
(저장소 루트)
  project.yml                 # XcodeGen — `xcodegen generate` 로 FCScope.xcodeproj 생성(커밋 안 함)
  FCScope/
    App/        FCScopeApp(진입·AppDelegate·푸시 수신) · AppRouter(탭 + 딥링크) · RootView(탭바/온보딩)
    Core/       Config · API/APIClient+Models · Auth/AuthManager(supabase-swift) · Ads/AdsManager(AdMob+UMP+ATT)
                Store/LocalPrefs(App Group UserDefaults) · Store/PushManager(APNs 등록, BGAppRefresh) · UI/Theme+Components
    Features/   Home(홈·온보딩) · Record(전적 5탭) · Match(매치 리포트·슛맵 Canvas) · Meta(픽 랭킹·선수 도감)
                Squad(빌더: 탭-배치·프리셋·닉네임 임포트·저장/공유) · Community(목록·상세·댓글·배틀 투표·글쓰기·신고/차단) · Me(마이페이지·로그인·프로필·설정·계정 삭제)
    Resources/  Assets(아이콘·색) · Fonts(Chakra Petch, OFL)
  FCScopeWidgets/  WidgetKit — "내 폼"(small/medium/잠금화면) · "오늘의 급상승"(small)
```

의존성(SPM): supabase-swift 2.55 · Nuke 13 · swift-package-manager-google-mobile-ads 13(UMP 포함). 차트는 Swift Charts.

## 빌드·실행

```bash
brew install xcodegen          # 최초 1회
xcodegen generate
open FCScope.xcodeproj         # 또는 아래 시뮬레이터 빌드
xcodebuild -project FCScope.xcodeproj -scheme FCScope -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

- 백엔드: 기본 `https://www.fcscope.xyz`. DEBUG 빌드는 설정 > 개발 > 백엔드 URL 로 `http://localhost:3001` 등 변경 가능.
- Supabase: `Info.plist` 의 `FCSupabaseURL` / `FCSupabaseAnonKey` 채우기(anon 키만, service_role 절대 금지). 비어 있으면 로그인 UI 가 "준비 중"으로 표시되고 나머지는 정상 동작.
- AdMob: `GADApplicationIdentifier`(현재 테스트 앱 ID) 와 `FCAdMobBannerUnit` 을 실제 값으로. DEBUG 는 항상 구글 테스트 배너.
- 버전: `project.yml` 의 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.

## 백엔드 계약 (`/api/v1`)

| 엔드포인트 | 화면 |
|---|---|
| `GET /api/v1/home` | 홈(라이브 검색·급상승·최신 글) · 위젯 |
| `GET /api/v1/user/:nick?type=` | 전적 히어로 + 경기 기록 탭 (프로필·요약·스코어·연승·주간·천적·진단·30경기) |
| `…/report` `…/players` `…/playstyle` | 종합 리포트 · 선수 성적표(클리닉·랭커 대조·판정) · 플레이스타일(5축·누적 슛맵) |
| `GET /api/v1/match/:id?me=` | 매치 리포트 |
| `GET /api/v1/meta?type=` · `GET /api/v1/player/:spid` | 픽 랭킹 · 선수 도감 |
| `GET /api/v1/community/posts` · `…/:id` | 커뮤니티 읽기 (쓰기·댓글·신고·배틀은 기존 `/api/community/*`, Bearer 인증) |
| `POST /api/v1/devices` | APNs 토큰 등록 (`device_tokens`, 마이그레이션 0018) |
| 기존 재사용 | `/api/players/search` `/api/squad*` `/api/profile*` `/api/me/*` `/api/card/*` `/api/player-image/*` `/api/refresh/*` |

인증: 앱은 supabase-swift 세션의 access_token 을 `Authorization: Bearer` 로 보낸다. 서버 `lib/supabase/server.ts` 가 Bearer 를 감지하면 PostgREST·`auth.getUser()` 모두 그 토큰으로 동작하므로 기존 라우트 수정 없이 웹(쿠키)·앱(Bearer) 이 공존한다.

오류 코드(`lib/api/v1.ts`): `user_not_found` `maintenance` `paused` `not_configured` `rate_limited`(Retry-After) `timeout` `upstream` `not_found` `bad_request` → 앱 `APIError`.

## 푸시

- 앱: 온보딩 3화면에서 권한 요청 → 토큰을 `/api/v1/devices` 에 등록(내 구단주명·즐겨찾기 포함).
- 서버: `lib/push/apns.ts`(HTTP/2 + ES256, 의존성 0) · 크론 `/api/cron/push-weekly`(일요일 21시 KST 주간 리캡, 주 3경기 미만은 미발송) · `/api/cron/push-meta`(금요일 18시 KST 메타 요약). `CRON_SECRET` fail-closed.
- env: `APNS_KEY_ID` `APNS_TEAM_ID` `APNS_PRIVATE_KEY`(.p8) `APNS_BUNDLE_ID` `APNS_SANDBOX`.
- 무효 토큰(410/BadDeviceToken)은 발송 시 자동 삭제.

## 위젯

App Group `group.xyz.fcscope.app` 의 UserDefaults(`myNickname`, `formSnapshots`)를 앱·위젯이 공유. 위젯은 3시간마다 `/api/v1/user/:nick` 를 직접 갱신하고, 앱은 전적 조회·백그라운드 갱신(BGAppRefresh, 4시간) 시 `WidgetCenter.reloadAllTimelines()`.
위젯 탭 → 유니버설 링크 URL → `AppRouter.handle(url:)`.

## 심사 대응 (구현 위치)

- 4.2 최소 기능: 위젯 2종, 푸시, 백그라운드 폼 갱신, 인스타 스토리 직결, 햅틱, Spotlight(2차).
- 4.8 Apple 로그인: `LoginView` — Apple 버튼이 Google 위, 동일 크기.
- 5.1.1(v) 계정 삭제: 설정 > 계정 삭제(2단계 확인) → `DELETE /api/me/delete`.
- 1.2 UGC: 글쓰기 시트 하단 정책 문구, 글/댓글 신고(4사유), 작성자 차단(로컬, 설정에서 해제), 서버 자동 숨김.
- 5.1.2 ATT: 첫 검색 결과를 본 뒤 `AdsManager.requestConsentIfNeeded()`(UMP → ATT). 배너는 설치 직후부터, 전면광고는 하루 두 번째 검색부터(2026-09-20 변경). 전적 화면엔 배너 없음(픽 랭킹·커뮤니티 하단만).

## 비용·성능 최적화 (2026-09-04 적용)

앱이 주 클라이언트가 되면서 서버가 대신 하던 일 상당수가 불필요해졌다. 적용한 4가지.

| 최적화 | 이전 | 이후 | 근거 |
|---|---|---|---|
| **이미지 CDN 직접 로드** | 선수 이미지 전량이 `/api/player-image` 프록시 경유. 전적 화면 1회 = 0.9~1.3MB | Vercel 대역폭 0 | 네이티브는 CORS 제약이 없다. 넥슨 CDN 실측: 인증·핫링크 차단 없이 200 |
| **공유 카드 로컬 렌더** | 서버 `next/og`(satori+resvg) — 함수 CPU 소모 1위 | 서버 CPU·대역폭 0 | 카드 데이터가 이미 앱의 API 응답 안에 있다 |
| **선수 인덱스 번들 내장** | 서버가 `spid.json` 6.5MB 상주 + 요청마다 전체 필터 | 검색 서버 왕복 0, 오프라인 동작 | 88k 카드 → 50,972명 압축(1.8MB, gzip 592KB) |
| **응답 디스크 캐시(SWR)** | 재방문마다 넥슨 36콜 + `match_cache` 30행 쓰기 반복 | 2분 내 재조회는 네트워크 0, 그 외엔 캐시 먼저 그리고 백그라운드 갱신 | 두 차례 DB 장애의 원인이 이 쓰기 증폭이었다 |

추가로 **콜드 조회 2단계**를 도입했다. `GET /api/v1/user/:nick?stage=profile` 이 넥슨 2콜만으로 프로필을 먼저 주고,
앱은 경기 30건(최대 60초)을 기다리는 동안 히어로를 렌더한다.

관련 코드: `Core/API/NexonCDN.swift` · `Core/UI/ShareCard.swift` · `Features/Squad/SquadCardView.swift` ·
`Core/Store/PlayerIndex.swift` · `Core/Store/ResponseCache.swift` · `Core/API/APIClient.swift`(cachedValue/getAndCache).

선수 인덱스 재생성(시즌 추가 시):
```bash
node scripts/build-player-index.mjs
```
앱은 주 1회 `/api/v1/player-index` 로 신규 시즌을 자동 반영하므로, 번들 갱신은 앱 업데이트 시에만 하면 된다.

**아직 남은 최적화(운영자 계정 필요)**: `match_cache` 를 Supabase Postgres 에서 Cloudflare R2 로 이관.
경기 상세는 불변이고 조회는 항상 PK 단건이라 jsonb 를 쓸 이유가 없다. R2 는 저장 10GB 무료 + 전송 과금 없음이라
Disk IO·WAL 부담이 구조적으로 사라진다. 그다음 단계는 넥슨 프록시를 Cloudflare Workers 로 옮기는 것(무료 10만 req/일).

## 2차 후보 (회의)
친구 리그(주간 승점표) · 시즌 업적/뱃지 · 라이벌 감시 푸시 · 오프라인 누적 분석(SwiftData) · Live Activity(스쿼드 배틀) · App Intents/Spotlight · 보상형 광고 · 자유 드래그 빌더.
