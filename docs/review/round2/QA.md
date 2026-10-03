# QA Round 2 — TestFlight 게이트 (2026-10-04)

**판정: NEEDS WORK** — P0 없음. 다만 1라운드 수정 커밋이 **새 P1 두 건**을 만들었다(매치 히어로 문구 잘림, 전적 "마지막 경기" 슛맵 범례 좌우 반전).

대상: `fcscope-ios` HEAD `e668ce3` (1.1.0 build 17, 수정 커밋 `c93a055..3fb68a5`) · 서버: 프로덕션 `https://www.fcscope.xyz` (커뮤니티 v2)
스크린샷: `docs/review/round2/qa/` (`p1-*`/`p2-*` = 결함, `pass-*` = 통과 증거)

## 환경 · 실행한 것

| 항목 | 결과 |
|---|---|
| Debug 빌드 (`xcodegen generate` → `xcodebuild -derivedDataPath build-qa2`) | 성공, 경고 0 |
| Release 빌드(시뮬레이터, 같은 derivedData) | 성공. 앱·위젯 모두 `CFBundleVersion 17` ✅ |
| Release 바이너리 검사(바이트 단위, 한글 포함) | `communityMock`·`communityScreen`·`recordSection`·`fcscope.baseURL`·"카드 렌더 검증"·"온보딩 다시 보기"·목 닉네임(피파탐색이 등) → **전부 0건** ✅ (`localhost:9999`·`DEBUG_MENU` 는 supabase·AdMob SDK 문자열) |
| 시뮬레이터 | 새로 만든 "FCScope QA2"는 **시뮬레이터 패널 접근 승인이 나지 않아** 조작 불가 → 1라운드 QA 전용 기기 재사용: "FCScope QA"(iPhone 17, Debug, 앱 삭제·ATT 초기화 후 새로 설치) · "FCScope QA SE"(SE 3, Release, 라이트, AX5) |
| 콘솔 | `log stream`(12.4만 줄) — 크래시 0, SwiftUI 런타임 경고 0, `emitLocalSessionAsInitialSession` 경고 **0**(1라운드 18회). Error/Fault 340줄은 전부 시뮬레이터 시스템 소음(CoreHaptics·CoreTelephony·nw_connection) |
| 프로덕션 API 직접 확인 | 목록 `sort`·`hot` 키 있음, `sort=hot/comments`·`types=` 동작, 글 추천 비로그인 **401**, 상세 조회 시 `view_count` 0→1 증가(앱 UA) ✅ |

입력 제약: 시뮬레이터 텍스트 주입이 한글을 못 넣는다(도구 인코딩 오류) → 온보딩은 `SEPTEMBERSKY`, 보엠은 딥링크(`fcscope://user/보엠`)·"예시 리포트" 카드로 열었다.

## 1라운드 항목 재검증

| # | 판정 | 증거 |
|---|---|---|
| P0-1 혼합 서버 오판 | ✅ 해결. 실서버 v2에서 상세 "추천 0 · 조회 1", 목 `hybrid`에서 추천·조회 숨김 | `pass-like-loggedout-login-sheet.png`, 목 hybrid 직접 확인 |
| P0-2 빌드 번호 | ✅ 17 | `project.yml:24`, Release Info.plist |
| P1-1 검색창 2개 | ✅ 히어로 하나 + 최근 검색 드롭다운 | 홈 캡처(SE 라이트 포함) |
| P1-2 득실 기준 | ✅ 리포트 "28경기 득실 · 몰수 제외 79:74" = 헤더 2.8/2.6, ⓘ 팝오버로 기준 설명 | `pass-p1-2-forfeit-basis-popover.png` |
| P1-3 스토리 카드 골 수 | ✅(증상만) 카드에서 문구 빠짐. **원인은 남음** → P2-6 | `pass-storycard-user.png` |
| P1-4 VS 플레이스타일 | ✅ "요즘 흐름" 행, 카드엔 PLAYSTYLE | `pass-vs-result-naming.png` |
| P2-1 SE 몰수 각주 잘림 | ✅ | `pass-se-light-release-record-header.png` |
| P2-2 AX MY TYPE 잘림 | ✅ AX5에서 두 줄 다 보임 | SE AX5 캡처 |
| P2-3 엠블럼·버튼 | ◑ 버튼은 내비 메뉴로 이동 ✅ / 마스터2 엠블럼은 여전히 "마스" 글자(서버 `iconUrl: null`) | `p1-lastmatch-shotmap-legend-reversed.png` 상단 |
| P2-4 9x7 → 9×7 | ❌ **여전히 ×** → P2-1 | `p2-vs-9x7-still-multiply-sign.png` |
| P2-5 온보딩 키보드 | ◑ 코드상 해결(`onChange(of: page)`). 하드웨어 키보드라 화면 확인 불가 | `HomeView.swift:350` |
| P2-6 신고 사유 소실 | ✅ 사유 고르기 전에 로그인 시트 | 실서버 상세 ⋯ → 신고 |
| P2-7 전부 차단 문구 | ✅ "차단한 사용자의 글만 있어요" | `pass-p2-7-blocked-all-copy.png` |
| P2-8 스토리 피드백 | ✅ 탭 즉시 "만드는 중…" (시트까지 약 5초) | — |
| P2-9 ST→LW | ◑ 조사 ✅, **배치는 LS 카드에서 재현** → P2-2 | `p2-squad-ls-placed-at-lw.png` |
| P2-10 VS 묵은 캐시 | ◑ 코드만 확인(`VersusView.swift:58`), 네트워크 차단 재현은 안 함 | — |
| P2-11 빈 탭 CTA 중복 | ✅ 빈 상태에서 FAB 숨김 | 인기·클럽 빈 탭 |
| P2-12 supabase 경고 | ✅ 0회 | 콘솔 |
| P2-13 ⋯ 44×44 | ✅ 코드 | `CommentViews.swift:139` |

---

## P1 — 눈에 보이는 버그(이번 수정이 만든 회귀)

### P1-1. 매치 히어로 한 줄 문구에서 "승"·"패" 글자가 지워진다 — "승리 · 3골 차 대"
- **증거**: `p1-match-hero-liner-truncated-daeseung.png` (SEPTEMBERSKY 5:2 승).
- **원인**: `86596fc`의 중복 제거. `MatchResultHero.swift:47`이 `m.liner(after: [resultWord, m.me.result])`를 부르는데, `m.me.result`가 한 글자 "승"/"패"/"무"라서 `Copy.swift:88` `replacingOccurrences`가 **단어 속 글자까지** 지운다.
  - 같은 이유로 깨지는 문구: "3골 차 대승"→"3골 차 대", "점유 45%로 따낸 역습승"→"…역습", "GK ○○ 선방쇼로 지킨 승리"→"…지킨", "깔끔하게/안정감 있게 챙긴 승리"→"…챙긴", "3:3 치고받은 무승부"→"치고받은".
  - 대승·역전승처럼 자랑하고 싶은 경기일수록 깨진다.
- **재현**: 3골 차 이상 승리 경기 → 매치 리포트.
- **의심 파일**: `FCScope/Features/Match/MatchResultHero.swift:47`, `FCScope/Core/UI/Copy.swift:88` (`liner(after:)`). 공유 카드(`MatchCardView.swift:76`)는 "승리"만 빼서 이 증상은 없음.

### P1-2. 전적 "마지막 경기" 카드: 슛맵 범례가 점과 반대쪽에 있다
- **증거**: `p1-lastmatch-shotmap-legend-reversed.png`(다크, 승), `p1-lastmatch-shotmap-legend-reversed-se-ax5-light.png`(SE·라이트·AX5, 무).
- 보라 점(내 슛)은 **왼쪽**, 회색 점(상대)은 오른쪽인데 범례는 왼쪽 "감귤국지우 슛 5"(빨강), 오른쪽 "내 슛 11"(보라). 상대도 여전히 패배 빨강(`FC.lose`)이다.
- **원인**: `86596fc`에서 `MiniShotMap`이 공용 `ShotMapView.point`(나 왼쪽)로 바뀌었는데, `RecordView.swift:586-590`의 범례 순서와 색은 그대로다. 매치 리포트 큰 슛맵의 범례는 맞다.
- **재현**: 아무 구단주 → 전적 → 경기 탭 첫 카드.
- **의심 파일**: `FCScope/Features/Record/RecordView.swift:586-590`

---

## P2 — 다듬기

| # | 내용 | 증거 | 의심 파일 |
|---|---|---|---|
| P2-1 | **calt 끄기가 효과 없음**: VS 입력창·오류 문구에서 "zq9x7"이 "9×7"로 보인다(1라운드 P2-4 미해결). 기능 설정(type 36 / selector 1)이 Pretendard의 치환을 막지 못하거나, TextField·scoreboard cascade 경로에 적용되지 않는다 | `p2-vs-9x7-still-multiply-sign.png` | `Theme.swift:265-273`, `Font.scoreboard`의 Pretendard 폴백 |
| P2-2 | 선수 상세 → 빌더 배치: 랭커 포지션이 **LS**인 기라시가 빈 ST 대신 LW로 간다. 정확히 같은 슬롯만 찾고 LS/RS/CF→ST 같은 동의 포지션은 없음 | `p2-squad-ls-placed-at-lw.png` | `SquadBuilderView.swift` `place(_:line:pos:)` |
| P2-3 | 홈 "커뮤니티 최신" 제목 뒤로 흐린 "탭해서 / 최근 폼 / 확인" 글자가 겹쳐 남는다(내 구단 카드가 스냅샷을 받은 뒤 사라지지 않은 이전 뷰로 보임). 레이아웃이 바뀌어도 따라다님 | `p2-home-ghost-text-behind-community.png` | `HomeView.swift:198` `myFormCard`(전환 애니메이션) |
| P2-4 | 리포트 "슛 타입별 결정력" 골 합 88(73+14+1)이 같은 카드의 득실 79(몰수 제외)와 다르다. 몰수 경기 안의 슛까지 집계하는 것으로 보인다. 스토리 카드는 문구를 숨겼지만 리포트 탭에는 그대로 나온다(1라운드 P1-3 원인) | SEPTEMBERSKY 리포트 탭 · `/report` `shotTypes` | 서버 리포트 집계, `RecordSections.swift` |
| P2-5 | 리포트 "최근 7일 승률 46% ▲46": 비교 기간이 4경기·0%라 증가폭이 값과 같다. 표본이 적을 땐 증감을 숨기는 게 맞다 | `/report` `weekly.prevGames: 4` | `RecordSections.swift:41-43` |
| P2-6 | 승률 ⓘ 팝오버의 화살표가 승률 타일이 아니라 가운데 스코어 타일을 가리킨다 | `pass-p1-2-forfeit-basis-popover.png` | `RecordHeader.swift` 팝오버 앵커 |
| P2-7 | 스토리 카드에 "마스터2"와 "챔피언스"(감독모드 등급) 칩이 모드 표시 없이 나란히 나온다. 공식경기 카드에서 어느 쪽이 내 등급인지 헷갈림 | `pass-storycard-user.png` | `StoryCards.swift` 등급 칩 |
| P2-8 | 폼 티어 이름 "마스터"(70~79)가 넥슨 등급 "마스터2"와 같은 헤더에 함께 나와 혼동 여지 | `pass-form-tier-sheet.png` | `FormTier.swift` |
| P2-9 | 작성자 차단 직후 토스트 "보엠님을 차단했어요"가 "차단한 사용자의 글이에요" 배너 위에 겹친다. 차단은 확인 없이 즉시 실행 | 실서버 상세 ⋯ → 작성자 차단 | `PostDetailView.swift` 토스트 위치 |
| P2-10 | 마스터2 엠블럼 없음: 서버 `divisions[].iconUrl: null` → 앱은 "마스" 글자 대체 | `/api/v1/user/SEPTEMBERSKY` | 웹 디비전 아이콘 매핑 |
| P2-11 | AX5에서 매치 히어로 "유효슛 · 나/…"가 잘림 | SE AX5 보엠 3:3 | `MatchResultHero.swift` 스탯 타일 |

관찰(결함으로 확정하지 않음): 2:28 Debug 기기의 보엠 화면이 그보다 약 2시간 전 경기 2건(00:03 패, 00:15 무)을 빠뜨린 상태였다(37%·11승5무14패). 3분 뒤 SE와 API는 33%·10승6무14패. 앱은 새로 설치한 상태라 앱 캐시는 원인이 아니다. 서버나 엣지 캐시가 오래된 응답을 줬을 가능성이 있어 추적이 필요하다.

---

## 실서버 커뮤니티 v2 확인 내역
- 목록: 전체/인기 HOT/스쿼드/클럽·대회, 그룹 탭 "전체" 칩과 정렬(최신순↔댓글순) ✅, 인기 빈 상태 + FAB 숨김 ✅.
- 상세: 조회수 증가, 추천 캡슐 노출, 비로그인 추천 → 로그인 시트 ✅. 신고 → 로그인 먼저 ✅. 차단 → 목록 숨김, 설정에서 해제 ✅.
- **실데이터 한계**: 프로덕션은 글 4개(1페이지)에 댓글·추천 0, `hot: []`. 그래서 **무한 스크롤·BEST 규칙·답글 UI·HOT 박스는 목(`-communityMock full`)으로만 확인**했다. 2페이지 로드, "다 봤어요", BEST 2개(추천 14·6, 8개 이상 조건), 원래 자리 접힘, `@닉` 답글 배너가 동작했다(`pass-mock-best-replies.png`). 실서버에서 BEST·답글이 실제로 저장되고 표시되는지는 **검증하지 못했다**.

## 검증하지 못한 것(승인 근거로 쓰지 말 것)
로그인 후 흐름 전부(추천·댓글·답글 `parent_id` 저장·신고 전송·글쓰기·계정 삭제·알림): 서명 없는 시뮬레이터 빌드라 테스트 계정이 없다. 그 밖에 VoiceOver 실구동, 위젯 표시, 푸시, VS 네트워크 실패 재현, 온보딩 소프트 키보드 화면 확인.

## 다음 라운드 통과 조건
1. P1-1 수정: 3골 차 대승·역습승·GK 선방승·무승부 문구 각 1건 캡처.
2. P1-2 수정: 마지막 경기 카드 범례가 점과 같은 쪽, 상대는 중립색. 다크·라이트 각 1장.
3. 9x7 렌더 캡처(입력창·제목·카드).
4. 서명 빌드(TestFlight 내부)에서 실서버에 답글 1건 → API `parent_id` 확인, 추천 토글 확인.
