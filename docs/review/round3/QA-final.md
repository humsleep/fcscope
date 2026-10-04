# QA Final — TestFlight 게이트 (2026-10-04)

**판정: READY (TestFlight 내부 배포 기준)** — P0·P1 없음. P2 3건은 배포를 막지 않는다. 다만 로그인 후 실제 글 등록은 이번에도 확인하지 못했으니, TestFlight 첫 빌드에서 직접 확인해야 한다(아래 "남은 확인").

대상: `fcscope-ios` HEAD `fa7239a` (1.1.0 build 17). 빌드는 Debug·Release 모두 `-derivedDataPath build-qa4`, 성공·경고 0.
기기: "FCScope QA"(iPhone 17, Debug) · "FCScope QA SE"(SE 3, **Release**, 삭제 후 새로 설치, 다크·라이트·AX5)
서버: 프로덕션 `https://www.fcscope.xyz`
증거: `docs/review/round3/qa-final/` (`pass-*`, `p2-*`, `cards/` 8장)

## 3라운드 항목 재검증

| # | 판정 | 증거 |
|---|---|---|
| P1-1 결승골 아닌 늦은 실점에 "막판" 문구 | ✅ `6abf6058…`(3:4)에 "상대는 유효슛 6개로 4골"만 남음. 83분 문구 사라짐 | `pass-r3p1-1-no-false-late-goal.png` |
| 사실 검증(독립 재실행) | ✅ 앱 로직을 파이썬으로 옮기고, 별도 검증기로 골 타임라인을 다시 계산했다. 10명 **패배 147경기, 문장 91개, 실패 0** | 아래 표 |
| P2-3 자책골 섞인 경기 | ✅ `6ab7bdb5…`(4:5)는 "5실점 중 1골은 상대 슛이 아닌 골(자책골 등)이었어요" 하나만 나옴. 결정력·시간 문구는 빠짐 | `pass-r3p2-3-own-goal-statement.png` |
| P2-1 선발 불러오기 | ✅ SEPTEMBERSKY: 벤제마·벨링엄 ST, 알라바 CAM, 발베르데 CDM. 수비형 MF가 최전방에 가지 않음 | `pass-r3p2-1-import-no-dm-upfront.png` |
| P2-2 홈 겹침 | ✅ Release 새 설치 → 온보딩 → 전적 → 홈으로 처음 돌아와도 겹침 없음 | `pass-r3p2-2-home-first-return-release-se.png` |
| P2-4 AX5 헤더 | ✅ 엠블럼 위, 이름 전체 표시, LV·내 구단은 아랫줄. CTA는 두 줄로 잘림 없음 | `pass-r3p2-4-ax5-header-name.png`, `pass-r3p2-4-ax5-cta-rows.png` |

"동점이던 N분, 결승골" 문장 13건은 골 타임라인을 직접 대조해 모두 사실임을 확인했다. 그중 연장(105·108분) 2건, 추가시간(90~93분) 6건이 있다. 예: Skyle17 3:4는 "3:3 동점이던 108분", 오후1시 0:1은 "0:0 동점이던 91분".

## 신규 기능

| 항목 | 판정 | 증거·근거 |
|---|---|---|
| 작은 광고 행(목록) | ✅ 3번째 행 뒤 320×50 + "AD" 표기 + 헤어라인. Debug(목)·Release(실서버) 모두 확인 | `pass-list-compact-ad-and-attach-glyphs.png`, `pass-release-se-light-community-ad.png` |
| 작은 광고 행(상세) | ✅ 댓글 머리 아래 1개 | `pass-detail-record-attach-and-compact-ad.png` |
| 광고를 받기 전에 접힘 | ✅ 실행 직후(SDK 준비 전) 목록 3·4행 사이에 빈칸이 없다가, 받은 뒤에 행이 생김. 코드도 `height == nil` → 높이 0·투명 0(`AdsManager.swift:308-322`) | 실행 8초·13초 시점 화면 비교 |
| 글쓰기 첨부 → 등록 → 상세(목) | ✅ "전적·VS" → VS 카드(SEPTEMBERSKY vs Skyle17) → 등록하면 목록 맨 위에 VS 글리프 → 상세 VS 카드 "5·0 · 40%·27% · 골드·브론즈" | `pass-compose-vs-attached.png`, `pass-posted-vs-attach-detail.png` |
| 첨부 카드 수치 | ✅ 보엠 vs 팔디 카드(33%·43%, 0·5)가 `/api/v1/user` 값과 VS 화면 결과와 일치 | `pass-detail-vs-attach.png` |
| 첨부 카드 탭 → 이동 | ✅ 전적 카드 → 전적 화면, VS 카드 → VS 화면(같은 값) | 기기 확인 |
| 목록 글리프 | ✅ 전적은 막대, VS는 두 사람 | `pass-list-compact-ad-and-attach-glyphs.png` |
| 요청 본문 형태 | ✅ `ComposeView.submit` → `attach: {kind, me, mode, with?}`(배틀 글 제외). 웹 `parseAttachInput`을 iOS 본문 그대로 넣어 실행하면 `attach_kind/me/mode/with` **문자열**로 변환된다. 잘못된 닉(`x/y`)·같은 닉은 null → 글은 첨부 없이 저장 | tsx 실행 결과 |
| 구버전 앱 호환 | ✅ 출시된 build 16(`3177f01`)은 `meta: [String:String]`을 디코딩만 하고 화면에 쓰지 않는다. 프로덕션 v1 목록 4글 모두 meta 값이 문자열. `metaRows`는 `publicMetaEntries`로 `attach_*`를 숨김(필드 추가·삭제 없음 = v1 계약 유지) | curl + `git grep 3177f01` |
| QR 8종 | ✅ 기기에서 `-renderCards SEPTEMBERSKY`로 직접 렌더 → CIDetector 디코드 **8/8** = `https://apps.apple.com/kr/app/id6812981907`. iTunes 조회로 FC Scope(`xyz.fcscope.app`)임을 확인, URL 200 | `cards/*.png` |
| 웹 카드 QR | ℹ️ 프로덕션 `/api/card/user/SEPTEMBERSKY`도 이미 같은 URL로 디코드된다. "a46a873 미배포"라는 전달과 다르니 배포 상태를 한 번 확인할 것 | — |

## Release 점검
- 바이너리 바이트 검색에서 `communityMock`·`communityScreen`·`communityAttach`·`communityPost`·`recordSection`·`renderCards`·`Documents/cards`·`fcscope.baseURL`·"카드 렌더 검증"·"온보딩 다시 보기"·목 닉네임·`hybrid` 모두 **0건**.
- 설정 화면에 개발 섹션 없음.
- 앱·위젯 `CFBundleVersion 17`, `1.1.0`.
- Info.plist에는 실제 AdMob 앱·배너 ID가 있다. 바이너리 안의 Google 테스트 ID는 App Store 외 배포판(TestFlight·시뮬레이터)에서 쓰는 설계다(`Config.swift` `servesRealAds`).
- 새로 설치한 Release에서 ATT 팝업 정상.

## P2(배포를 막지 않음)

| # | 내용 | 증거 | 의심 파일 |
|---|---|---|---|
| P2-1 | 스쿼드 공유 카드: QR 꼬리말을 넣느라 피치를 줄인 탓에 GK 아바타가 CB 줄의 시즌 배지(PTG·23KLeague)에 닿는다. GK 시즌 배지는 피치 아래 경계선에 걸친다 | `cards/squad.png` | `StoryCards.swift` 스쿼드 카드(피치 935) |
| P2-2 | 매치 히어로의 세 번째 타일이 경기에 따라 "FC 스코어"와 "경기 평점"으로 바뀐다(보엠 3:4는 "6.5 경기 평점", 다른 경기는 "3.6 FC 스코어"). 의도라면 문제없지만 라벨 기준을 확인할 것 | `pass-r3p1-1-no-false-late-goal.png` vs `pass-r3p2-3-own-goal-statement.png` | `MatchResultHero.swift` |
| P2-3 | VS 첨부의 같은 닉 판정: 서버는 대소문자를 무시해 `A` vs `a`를 거부하는데, 앱 시트는 그대로 통과시킨다. 이때 글은 첨부 없이 조용히 등록된다 | tsx 결과 | `AttachPickerSheet` 검증 |

## 남은 확인(검증하지 못함 — 승인 근거 아님)
- 로그인 후 실서버에 첨부 글 등록 → `meta.attach_*` 저장 → 웹·구버전 앱 표시. TestFlight 첫 빌드에서 1건 직접 확인 권장.
- 실기기 광고 실패(no-fill) 시 접힘은 코드와 시뮬레이터 로드 전 화면으로만 확인했다.
- VoiceOver, 위젯, 푸시.
