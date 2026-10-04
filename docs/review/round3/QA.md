# QA Round 3 — TestFlight 게이트 (2026-10-04)

**판정: NEEDS WORK** — 2라운드 P1 두 건은 고쳐졌다. 하지만 새 기능 "왜 졌을까"가 **사실이 아닌 문장**을 낸다(P1-1). 진 경기 화면에 사실처럼 단정하는 문구라 그대로 내보낼 수 없다.

대상: `fcscope-ios` HEAD `148fb69`(1.1.0 build 17, 수정 커밋 `a4e2b96`·`ea14c0e`·`c0d295c`·`b4ae97d`·`6a8b4d4`). 서버는 프로덕션 `https://www.fcscope.xyz`.
스크린샷: `docs/review/round3/qa/` (`p1-*`·`p2-*` = 결함, `pass-*` = 통과 증거)

## 환경
| 항목 | 결과 |
|---|---|
| 빌드 | `xcodegen` → Debug·Release 모두 `-derivedDataPath build-qa3`, 성공·경고 0 |
| 기기 | "FCScope QA"(iPhone 17, Debug, 다크) · "FCScope QA SE"(SE 3, **Release**, 앱 삭제 후 새로 설치, 다크·라이트·AX5) |
| Release 검사 | 목·디버그 문자열(`communityMock`·`communityScreen`·`communityPost`·`recordSection`·`fcscope.baseURL`·"카드 렌더 검증"·"샘플 전적 카드"·"온보딩 다시 보기"·목 닉네임) **0건**. 설정 화면에 "개발" 섹션 없음(`pass-release-settings-no-dev-section.png`). 앱·위젯 모두 `CFBundleVersion 17` |
| 콘솔 | 8.4만 줄. 크래시·SwiftUI 런타임 경고·supabase 경고 0. Error 줄은 전부 시뮬레이터 시스템 소음 |
| 데이터 대조 | `/api/v1/user` → `/api/v1/match` 를 스크립트로 내려받아, 앱의 `storyTag`/`matchLiner`/`heroLine`/`lossReasons` 로직을 그대로 옮겨 실경기 약 120건에 돌렸다(SEPTEMBERSKY·보엠·감귤국지우·공포의노란소세지·스에나) |

## 2라운드 항목 재검증
| # | 판정 | 증거 |
|---|---|---|
| P1-1 히어로 문구 잘림 | ✅ 실경기에 나온 문구 변형(대승·역습승·무실점·접전·안정감 승리·완벽 경기력·몰수승/패·난타전/치고받은/팽팽/0:0 무·1골 차 패·내용은 이겼다·꼬였던 판·한 끗) 모두 단어 손실 없음. 기기 확인: "승리 · 3골 차 대승" | `pass-r2p1-1-hero-bigwin.png`, `pass-ax5-match-hero-bigwin.png` |
| P1-2 마지막 경기 범례 | ✅ 내 슛은 왼쪽·보라, 상대는 오른쪽·회색 | `pass-r2p1-2-lastmatch-legend-fixed.png` |
| P2-1 9x7 | ✅ 입력칸과 오류 문구 모두 "zq9x7" 그대로 표시 | `pass-9x7-literal.png` |
| P2-2 LS → ST | ✅ 선수 상세에서 "세루 기라시를 ST에 배치했어요". 단, 선발 불러오기는 → 아래 P2-1 | `pass-squad-ls-to-st.png` |
| P2-3 홈 "탭해서 최근 폼 확인" 잔상 | ✅ 그 잔상은 사라짐. 다만 같은 계열의 겹침이 다른 자리에서 보임 → P2-2 | `pass-home-no-ghost.png` |
| P2-4 슛 타입 카드 | ✅ 합(88)이 득점(79)보다 커서 카드가 숨겨짐. 시간대 차트에는 "골 시간이 기록된 골만 · 몰수 제외" 기준이 붙고, 합이 79로 맞음 | `pass-report-shottype-hidden-7day-delta-hidden.png` |
| P2-5 7일 증감 최소 표본 | ✅ 비교 기간이 4판이라 "46%"만 표시, ▲ 없음 | 위와 같음 |
| P2-6 팝오버 앵커 | ✅ 승률 ⓘ 아래 | `pass-popover-anchor-and-master2-emblem.png` |
| P2-7 등급 칩 모드 | ✅(커밋·캡처 기준. 카드는 이번에 다시 열지 않음) | — |
| P2-9 차단 확인 + 토스트 | ✅ "보엠님을 차단할까요?" 확인 창이 뜨고, 토스트는 하단에 나와 배너와 겹치지 않음 | `pass-block-confirm.png`, `pass-block-toast-bottom.png` |
| P2-10 마스터2 엠블럼 | ✅ 왕관 + "마스터" + 단계 배지 2 | `pass-popover-anchor-and-master2-emblem.png` |
| P2-11 AX5 히어로 스탯 | ✅ "슛 / 유효슛 / FC 스코어" 잘림 없음 | `pass-ax5-match-hero-bigwin.png` |
| AX5 VS | ✅ 머리 부분이 세로로 쌓이고, 행 라벨이 위로 가서 가로 넘침 없음 | `pass-ax5-vs-rows.png` |
| 접힌 BEST 주인 줄 | ✅ (목) 아바타 + "피파탐색이 ↑ BEST로 올라간 댓글 · 펼치기" | `pass-best-collapsed-owner-line.png` |
| 댓글 수 보정 유지 | ✅ (목) 상세를 본 뒤 목록 [12]→[11], **앱을 재실행해도 [11] 유지** | `pass-comment-count-persisted-after-relaunch.png` |

---

## P1

### P1-1. "왜 졌을까"가 경기 데이터와 다른 사실을 말한다 — "83분 실점 — 막판 한 골에 갈렸어요"
- **증거**: `p1-loss-reason-false-late-goal-83min.png` (보엠 3:4 jskang12, 10.2 16:53, matchId `6abf6058fa4078c753fb89fa`)
- 골 기록: 보엠 10·59·**90**분, 상대 41·49·56·**83**분. 83분 실점으로 2:4가 됐고, 보엠이 90분에 만회해 3:4로 끝났다. **83분 골이 승부를 가른 게 아니다.** 결승골은 56분 골이다(그 뒤로 동점이 된 적이 없다).
- **원인**: `Copy.swift` `lossReasons` 7번 규칙이 "한 골 차 패배 + 80분 이후 상대 골 중 **가장 늦은 것**"만 본다. 그 골 직전에 동점이었는지는 확인하지 않는다.
- 같은 규칙의 다른 사례: 연장전이 있던 경기(보엠 3:4, 상대 골 99·105분)에서는 "105분 실점 — 막판"이 나온다. 이번 표본에서는 결승골이 맞았지만, 90분 기준이 아니라는 점은 정해 둘 필요가 있다.
- 실경기 약 120건 중 "막판" 문구 7건. 5건은 결승골이 맞고, 1건은 틀렸다(위 경기). 나머지 1건은 골 기록이 빠져 확인할 수 없다(아래 P2-3).
- **의심 파일**: `FCScope/Core/UI/Copy.swift` `lossReasons` 7번(막판 실점). 해당 실점 직전 스코어가 동점이었을 때만 내야 한다.

---

## P2

| # | 내용 | 증거 | 의심 파일 |
|---|---|---|---|
| P2-1 | 선발 불러오기 배치 오류: SEPTEMBERSKY의 실제 선발은 ST 벤제마·CF 벨링엄·LDM 알라바·RDM 발베르데·LM·RM인데, 앱은 4-1-2-1-2를 쓰고 **수비형 MF 알라바를 ST**에, 벨링엄을 CAM에 넣는다. 서버 `/api/squad/from-user`가 `formation: 41212`와 함께 CDM 2명을 준다(포메이션과 포지션이 맞지 않음). 앱의 마지막 폴백(3단계)은 포지션을 보지 않고 남은 자리를 채운다. 1.5단계도 슬롯 순서대로 돌기 때문에 CF가 ST보다 CAM을 먼저 가져간다 | `p2-squad-import-cdm-alaba-at-st.png` | `SquadBuilderView.swift` `place(players:)` 122-147, 서버 formation 추정 |
| P2-2 | 홈 "최근 검색" 칩이 "이런 것도 돼요" 제목·카드 위에 겹친다. 새로 설치한 Release(SE) → 온보딩 → 전적 → 홈으로 처음 돌아왔을 때 재현되고, 3초 넘게 유지됐다. 다른 탭에 갔다 오면 정상으로 돌아온다. 2라운드 잔상과 같은 계열(홈이 화면 밖일 때 시작된 삽입 애니메이션)로 보인다 | `p2-home-recent-search-overlap-first-return-se.png` | `HomeView.swift:48` `recentSection` 삽입(`.transaction` 미적용) |
| P2-3 | "상대는 유효슛 5개로 5골 — 상대 마무리가 날카로웠어요": 실제로는 상대 슛 기록상 골이 4개뿐이다. 5번째는 자책골 등 슛 없는 골로 보인다. 숫자는 맞지만 문장이 함의하는 사실이 틀렸다. 이 경기의 "90분 실점 — 막판" 문구도 빠진 골의 시각을 모르는 상태에서 나온 것이다 | `p2-loss-reason-5of5-but-4-goal-shots.png`, `p2-loss-reason-shotmap-4-goals.png`, `p2-loss-reason-se-light-release.png` (matchId `6ab7bdb579747d3b6658ed61`) | `Copy.swift` `lossReasons` 5·7번. 슛 기록 골 수 ≠ 스코어면 시간·결정력 문구를 빼야 함 |
| P2-4 | AX5 전적 헤더에서 구단주명이 통째로 "…"로 바뀌어 보이지 않는다. "스토리…", "🏆…" 버튼도 잘린다 | `p2-ax5-record-header-name-fully-ellipsized.png` | `RecordHeader.swift` 이름 줄·CTA 줄 |

## 스모크 회귀(프로덕션)
통과한 항목:
- Release 새로 설치 → 온보딩 3장 → ATT(`pass-att-release-se-dark.png`) → 전적.
- 매치 승·패, 공유 카드(`pass-match-share-card-bigwin.png`), VS(정상·없는 닉).
- 픽 랭킹 → 선수 상세 → 빌더.
- 커뮤니티 실서버: 목록 4탭, 상세, 차단·해제(`pass-release-se-light-community.png`).
- 목 상세(BEST·답글 배너), 내 정보·설정. 다크·라이트, SE, AX5.

검증하지 못한 것: 로그인 후 흐름 전부(서명 빌드·테스트 계정 없음). 프로덕션 커뮤니티는 여전히 글 4개·댓글 0이라, BEST·답글·무한 스크롤은 목으로만 확인했다. 공유 카드 8종 전수, VoiceOver, 위젯, 푸시도 하지 못했다.

## 다음 라운드 통과 조건
1. P1-1: 결승골이 아닌 늦은 실점 경기(위 matchId)에서 "막판" 문구가 사라진 캡처. 연장 경기의 기준도 명시.
2. P2-3: 슛 기록 골 수 ≠ 스코어인 경기(위 matchId)에서 결정력·시간 문구가 빠진 캡처.
3. P2-1: SEPTEMBERSKY 선발 불러오기에서 DM이 공격 자리에 들어가지 않는 캡처.
