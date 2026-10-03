# QA Round 1 — TestFlight 게이트 (2026-10-04)

**판정: NEEDS WORK**

대상: `fcscope-ios` HEAD `2441469` (a02258a 이후 13커밋) · 서버: 프로덕션 `https://www.fcscope.xyz`
스크린샷: `docs/review/round1/qa/` (`p0-*`/`p1-*`/`p2-*` = 결함, `pass-*` = 통과 증거)

## 환경 · 실행한 것

| 항목 | 결과 |
|---|---|
| Debug 빌드 (`xcodegen generate` → `xcodebuild … -derivedDataPath build-qa`) | 성공. 경고 2건(`CommunityMock.swift:72,106` String?→Any) |
| Release 빌드(시뮬레이터) | 성공. 위젯 익스텐션(`FCScopeWidgets.appex`) 두 구성 모두 컴파일·임베드 |
| Release 바이너리 디버그 문자열 검사 | `communityMock`·`communityScreen`·`renderCards`·`fcscope.baseURL`·"카드 렌더 검증"·"온보딩 다시 보기"·목 닉네임 → **전부 0건**. 목 경로는 컴파일에서 빠졌다 ✅ |
| 시뮬레이터 | 직접 만든 "FCScope QA"(iPhone 17, iOS 26.5, Debug) · "FCScope QA SE"(iPhone SE 3, Release) |
| 콘솔 | `log stream` 으로 앱 프로세스 오류 필터링(5.7k줄) — **크래시 0, SwiftUI 런타임 경고 0**. 키체인 오류는 서명 없는 시뮬레이터 빌드 때문이라 결함 아님 |
| 프로덕션 커뮤니티 API 직접 확인 | 아래 P0-1 참고 |

통과 확인: 콜드 스타트·인트로 → 온보딩 3장(보엠 닉 확인 ✓) → **ATT 팝업 노출**(Debug·Release 둘 다, `pass-att-prompt*.png`) → 전적(경기/스타일/리포트/선수, 공식/감독/1on1 빈 상태) → 매치 리포트 히어로 → 스토리 카드 2종 렌더 → 친구 VS(정상·같은 닉·없는 닉·네트워크 오류 각각 맞는 문구) → 픽 랭킹 → 선수 상세 → 빌더 배치·"내 최근 선발" 불러오기 → 커뮤니티(구 서버로 인기 탭 숨김, 그룹 탭은 첫 유형 칩으로 동작, 빈 탭 문구) → 상세 → 비로그인 추천·글쓰기 → 로그인 시트 → 신고 사유 → 로그인 시트 → 작성자 차단/설정에서 해제 → 목 `full`(무한 스크롤 2장·"다 봤어요", BEST·답글·답글 전송·배틀 투표), `legacy`, `empty` → 다크·라이트 → AX 글자 크기(SE).

**검증하지 못한 것**(증거 없음 → 승인 근거로 쓰지 말 것): 실제 로그인 후 흐름(서명 없는 빌드라 키체인 저장 불가, 테스트 계정 없음) — 실서버 댓글·추천·신고 전송·계정 삭제·알림 🔔. VoiceOver 실구동(코드상 라벨만 확인). 위젯 실제 표시(컴파일만). 푸시.

---

## P0 — 블로커 / 심사 리스크

### P0-1. 프로덕션이 "스키마 v2 + 코드 v1" 혼합 상태 — 앱이 v2 서버로 오판한다
- **증거**: `p0-prod-hybrid-like-button-shown.png`. 실측(curl):
  - `GET /api/v1/community/posts` → 글마다 `like_count`·`view_count` **있음**, 그러나 응답에 `sort`·`hot` **없음**
  - `POST /api/community/posts/:id/like`·`/comments/:id/like` → **404**
  - `GET /api/community/battle` → `{a,b}` (`mine` 없음)
  - 즉 0023 마이그레이션은 적용됐는데 웹 `aa5df85`(v2 백엔드)는 **배포 안 됨**.
- **영향**: `PostDetailModel.v2` 가 `likeCount != nil` 로 v2 를 판정 → 
  1. 모든 글에 "추천 0" 캡슐이 뜬다. 로그인 사용자가 누르면 404 → "추천은 곧 열려요" 토스트 후 사라짐.
  2. **답글이 깨진다**: v2 로 보고 `parent_id` 를 보내고 `@닉` 접두를 생략(`PostDetailView.swift` `submit`, 답글의 답글만 @ 붙임) → 구 라우트가 `parent_id` 를 버려 **누구에게 단 답글인지 사라진 평면 댓글**로 저장된다(되돌릴 수 없는 데이터).
  3. 조회수가 증가하지 않아 모든 글이 "조회 0".
- **재현**: 프로덕션으로 앱 실행 → 커뮤니티 → 아무 글 → "추천 0" 표시 확인. (로그인 후) 댓글 "답글 달기" → 전송 → 웹/API 에서 `parent_id` 없음 확인.
- **조치 후보**: TestFlight 배포 **전에** 웹 `npm run deploy` + `npm run verify:api`. 또는 앱의 v2 판정을 `like_count` 대신 목록 응답 `sort` 키(이미 `groupFilterSupported` 로 쓰는 신호)나 상세 응답의 명시적 플래그로 바꾼다.
- **의심 파일**: `FCScope/Features/Community/PostDetailView.swift` (`var v2`, `submit`), 웹 배포 상태.

### P0-2. 빌드 번호 16 재사용 위험(확인 필요)
- `project.yml` `CURRENT_PROJECT_VERSION: "16"` 은 `3177f01`(10-03 01:57, "1.0.1 build 16")에서 정해졌고 그 뒤 17커밋이 쌓였다. 16 이 이미 App Store Connect 에 올라갔다면 업로드가 거절된다. 올리기 전에 17 로 올렸는지 확인.
- **의심 파일**: `project.yml:24`

---

## P1 — 눈에 보이는 버그

### P1-1. 홈에 검색창이 두 개
- **증거**: `p1-home-two-search-fields.png`(라이트), `p1-home-two-search-fields-se-dark.png`(SE·다크 — 첫 화면의 40% 가 검색창 두 개).
- 내비 바 `.searchable("구단주명 검색")` + 히어로 `TextField("구단주명 입력")`. 같은 일을 하는 입력이 두 개라 어느 쪽을 써야 할지 모호하고, "이런 것도 돼요 → 전적·분석 리포트" 폴백은 위쪽(내비) 검색만 연다.
- **재현**: 온보딩 후 전적 탭.
- **의심 파일**: `FCScope/Features/Home/HomeView.swift` (`.searchable` + `hero`)

### P1-2. 득실 기준이 화면마다 다르다 — 부호까지 뒤집힌다
- **증거**: `p1-header-goals-excl-forfeit.png`(헤더 "경기당 득점 2.8 · 실점 2.5 · 몰수 제외" = +), `p1-report-goals-68-76-vs-header-2.8-2.5.png`(리포트 탭 "최근 30경기 득실 **68 : 76**" = −). 같은 리포트 카드 바로 아래 "시간대별 득실" 차트 합은 64:58 로 또 다르다.
- API: `summary` 68:76(몰수 포함) vs `perf` 65:58(몰수 제외). 리포트 탭이 `summary` 를 쓴다. `RecordView.swift:371` 주석(데이터 감사 M1 "몰수가 섞이면 득실 부호까지 뒤집혔다")이 고친 바로 그 문제가 리포트 탭에 남아 있다. "one win-rate basis everywhere" 커밋 범위 밖.
- **재현**: 보엠 → 리포트 탭.
- **의심 파일**: `FCScope/Features/Record/RecordSections.swift:24-25`

### P1-3. 공유 스토리 카드 "슛 171개 중 76골" — 실제 득점(68, 몰수 제외 65)보다 많다
- **증거**: `p1-storycard-76goals-vs-report-68.png`. 공개적으로 공유되는 카드라 수치 모순이 그대로 퍼진다(승부차기 골이 섞인 것으로 추정).
- **재현**: 보엠 → "스토리로 자랑".
- **의심 파일**: `FCScope/Core/UI/StoryCards.swift:~316-320` (`d.shotTotals`), 서버 슛 집계

### P1-4. 친구 VS 의 "플레이스타일" 행이 MY TYPE 을 보여 준다
- **증거**: `p1-vs-playstyle-row-shows-mytype.png`(VS: 플레이스타일 = "리빌딩 시즌") vs `p1-style-tab-playstyle-apbak.png`(스타일 탭·스토리 카드: 플레이스타일 = "압박 사냥꾼").
- 같은 사람의 "플레이스타일"이 화면마다 다르다.
- **재현**: 보엠 → 친구랑 비교 → 팔디.
- **의심 파일**: `FCScope/Core/UI/VersusCard.swift:43` (`diagnosis.type?.title` 에 "플레이스타일" 라벨)

---

## P2 — 다듬기

| # | 내용 | 증거 | 의심 파일 |
|---|---|---|---|
| P2-1 | iPhone SE 기본 글자에서 "실점 2.5 · 몰수 제…" — 기준을 알려 주는 "몰수 제외"가 잘린다 | `p2-se-record-tile-forfeit-qualifier-truncated.png` | `RecordHeader.swift:121` |
| P2-2 | AX 크기에서 MY TYPE 설명이 "승률 35%… 지금은 팀을…"으로 잘림 | `p2-ax-mytype-desc-truncated.png` | `RecordHeader.swift` MY TYPE 띠 |
| P2-3 | "내 구단으로" 버튼이 카드 모서리에 붙어 있음(`padding(.top, -12)`) · 마스터2 엠블럼이 없어 기본 방패(서버 `iconUrl: null`) | `p2-master-emblem-missing-makemine-cramped.png` | `RecordHeader.swift:218-222`, 웹 디비전 아이콘 매핑 |
| P2-4 | 구단주명의 "9x7" 이 "9×7" 로 표시됨(Pretendard 문맥 대체) — 입력창·결과 제목 모두 | `p2-nickname-9x7-rendered-as-multiply.png` | `fcFont` (폰트 기능 `calt` 끄기 검토) |
| P2-5 | 온보딩 2쪽에서 키보드를 띄운 채 3쪽으로 넘기면 키보드가 남는다 | `p2-onboarding-keyboard-stays-on-page3.png` | `HomeView.swift` `OnboardingView` |
| P2-6 | 신고: 사유를 고른 **뒤에** 로그인 시트 → 로그인해도 신고가 이어지지 않는다(사유 소실). 비로그인 심사자가 보면 신고가 막힌 것처럼 보일 수 있음(차단은 비로그인으로 동작해 1.2 요건은 충족) | `p2-report-reason-then-login-wall.png` | `CommunityView.swift` `ReportDialog.send` |
| P2-7 | 작성자를 차단해 목록이 비면 "아직 글이 없어요 · 첫 글의 주인공이…" — 글이 없는 게 아니라 숨긴 것 | `p2-blocked-all-shows-no-posts-copy.png` | `CommunityView.swift` `emptyCopy` |
| P2-8 | "스토리로 자랑" 탭 후 3초 이상 아무 반응 없이 시트가 늦게 뜬다(로딩 표시 없음) | `p2-story-card-no-feedback-3s.png` | `ShareCardButton` |
| P2-9 | 선수 상세 → 빌더 배치: ST 기라시가 빈 ST 대신 LW 에 들어감 · "세루 기라시을(를)" 조사 | `p2-squad-st-placed-at-lw-particle.png` | `SquadBuilderView.swift` 배치 로직 |
| P2-10 | 친구 VS: 캐시가 2분 지났고 네트워크가 실패하면 묵은 캐시가 있어도 오류만 보인다 | (네트워크 차단 재현: DEBUG `fcscope.baseURL=http://127.0.0.1:9`) | `VersusView.swift` `compare` |
| P2-11 | 빈 스쿼드 탭에 "글쓰기" CTA 와 FAB "글쓰기"가 동시에 | `p2-empty-tab-duplicate-compose-cta.png` | `CommunityView.swift` |
| P2-12 | supabase-swift 런타임 경고 `emitLocalSessionAsInitialSession` 미설정(18회) — 다음 메이저에서 동작 변경 | 콘솔 로그 | `AuthManager.swift` 클라이언트 옵션 |
| P2-13 | 댓글 `⋯` 탭 영역 44×32(스펙 44×44) | 코드 | `CommentViews.swift:133` |

---

## 이전 QA·스펙 대비

- SPEC 14절 "새 필드는 옵셔널, 없으면 UI 숨김" — 필드 **존재 여부**로 판정하는 설계가 P0-1 의 원인. 필드는 있는데 라우트가 없는 중간 상태를 가정하지 않았다.
- UX-AUDIT #1(광고 첫 3초 밖) ✅ 홈·전적에서 확인. #6(검색 히어로) — 히어로는 들어왔지만 기존 검색을 남겨 P1-1.
- 커밋 `0ce752d` "one win-rate basis everywhere" — 승률은 일관(헤더·카드·VS 33%)되지만 **득실**은 아님(P1-2).

## 다음 라운드에 필요한 증거
1. 웹 배포 후 `verify:api` 출력 + 실서버 상세에서 답글 1건 작성 → `parent_id` 저장 확인 스크린샷.
2. 서명된 빌드(TestFlight 내부)로 로그인 후 추천·답글·신고 전송·계정 삭제 화면.
3. 리포트 탭·스토리 카드 득실/골 수치가 헤더와 같은 기준이 된 캡처.
4. VoiceOver 켠 상태로 커뮤니티 목록 행·댓글 행 읽기 녹화.
