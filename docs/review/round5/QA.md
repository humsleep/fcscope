# QA — 1.1.0 build 19 (광고 개편) 게이트 (2026-10-04)

**판정: NEEDS WORK** — 핵심 첫 화면 슬롯 하나(전적 "경기" 탭)가 매번 사라지고, 예약 슬롯의 6초 접기 타이머가 설계와 달리 0~1초 만에 끝난다. 커뮤니티 행형 광고는 문서가 정한 24pt 간격을 지키지 않는다.

## 대상·방법
- `fcscope-ios` HEAD `3013589`. **작업 트리에 커밋 안 된 변경(AdsManager·HomeView·RecordSections)이 있어** `git archive HEAD` 로 뽑은 깨끗한 사본 + `xcodegen` 으로 빌드했다. `-derivedDataPath build-qa5`, Debug·Release 모두 성공, 앱 경고 0. 앱·위젯 `CFBundleVersion 19`.
- 다른 에이전트가 "FCScope Fix1 Max"를 같이 쓰고 있어(상태바 9:41 덮어쓰기, 내 실행 종료) 다른 기기로 옮겼다: "iPhone 17 Pro Max"(Debug, 새로 설치) · "RC-SE"(Release, 새로 설치, 라이트·다크·AX5).
- 광고 이벤트는 앱 stdout(`[ad] …`, DEBUG 전용)에 시각을 붙여 기록했다 → `qa/ad-events-timestamped.log`.
- 서버는 프로덕션, 커뮤니티 일부는 `-communityMock full`.

## P1 — 고치고 다시 확인할 것
| # | 내용 | 증거 |
|---|---|---|
| P1-1 | **`record_matches`(전적 경기 탭) 슬롯이 매번 사라진다.** 3번 들어가 3번 모두 `slot` → `collapse timeout`만 있고 fill·nofill이 끝까지 없다. 마지막 경기 카드 바로 뒤가 이전 경기 목록으로 붙어 있다. 문서가 "두 번째 화면 첫머리"로 정한 주 슬롯이다 | `qa/max-dark-06-FAIL-record-matches-slot-collapsed.png` |
| P1-2 | **예약 슬롯 타이머가 6초가 아니다.** `squad_builder` 는 slot 다음 1초, `community_list` 는 같은 초에 `collapse timeout`이 찍혔다. 의심 원인: `AdsManager.swift` 의 `try? await Task.sleep(for: .seconds(6))` 이 취소 오류를 삼키고 바로 `timedOut = true` 로 간다. 그래서 `.task(id:)` 가 취소되면(id 변경·뷰 사라짐) 곧바로 접힌다. 화면 밖 아래에 있던 슬롯은 그 자리에서 영구히 접힌다(P1-1의 유력한 원인). 화면에 보이던 슬롯은 접히지 않고 빈 카드로 남는다 | `qa/max-dark-11-FAIL-squad-builder-empty-reserved-card.png` (빈 카드) → 19초 뒤 채워짐 `-12-` |
| P1-3 | **시뮬레이터에서 실제로 받기까지 걸린 시간은 8~19초다**(players 8초, players_2 9초, style 17초, squad 19초). 6초 규칙(R2)이 제대로 동작하더라도 시야 밖 예약 슬롯 대부분이 접힌다. 실기기 지연은 측정하지 못했다. 시간 초과 값을 늘릴지 또는 화면 밖에서도 접지 않을지 결정이 필요하다 | log |
| P1-4 | **커뮤니티 행형 광고(컨테이너 B)는 광고 소재와 위·아래 글 행(행 전체가 버튼) 사이가 12~13pt뿐이다.** 문서 1-0의 "탭 영역과 24pt 이상"과 문서 1-6의 "12pt"가 서로 어긋나고, 구현은 12pt 쪽을 따랐다. 목록과 상세 첫 슬롯 모두 해당. 정책 P1(오클릭) 위험 | `qa/max-dark-16-community-row-ad-12pt-gap.png` |

## 통과
- **ATT가 첫 광고 요청보다 먼저 뜬다**(Debug·Release 새 설치). 팝업 뒤 홈에는 광고 자리가 없다(R7). UMP → ATT → `MobileAds.start` 순서는 코드로 확인. `-01-`·`-02-`·`se-light-release-01-att.png`
- **동의한 기기의 콜드 스타트**: 홈 슬롯이 첫 프레임부터 예약돼 있고, 채워질 때 아래 콘텐츠가 움직이지 않는다(12프레임). `-04-…12frames.png`
- 카드형 슬롯(홈·리포트·선수·스타일·매치·픽 랭킹 #1·스쿼드·VS)과 가장 가까운 탭 요소 사이는 43~129pt다(≥24). 스쿼드 피치와도 75pt 이상 떨어져 있다.
- 글쓰기 FAB는 광고 행 위에 오면 숨는다. `-15-`
- 온보딩·ATT·로그아웃 내 정보에는 광고가 없다. 작성·시트·빈/오류 상태는 코드에서 슬롯이 없음을 확인했다. `-01-`·`-14-`
- 광고 ID: Info.plist의 앱 ID·배너·전면이 모두 실제 값(`4073994600346533`)이다. 테스트 ID는 App Store가 아닌 배포판에서만 쓴다. Release 바이너리에서 DEBUG 훅(`communityMock`·`renderCards`·`recordSection`·`[ad]`)은 모두 0건.
- 분석 이벤트 빈도: 10분 동안 탐색해 34건이 쌓였고, 20건씩 묶어 보낸다. 서버 한도(30요청/분)와는 거리가 멀다. 과다 전송 아님.
- SE 라이트·AX5 다크(Release)에서 홈 광고 정상. `se-*`

## P2
- 300×250 인라인(VS·매치)은 양옆에 검은 기둥이 생긴다(`-18-`). 작업 트리에 수정이 있으나 HEAD에는 없다.
- 제자리에서 채워지는 예약 슬롯은 `visible` 이벤트를 남기지 않는다(홈: slot/fill/impression만 있음). 문서 5장의 "노출÷진입" 계산이 틀어진다. 보이는 채로 남은 슬롯에도 `collapse` 가 찍히고(report·meta_1·community_list), 화면에 다시 들어올 때마다 `slot` 이 또 찍힌다.
- `CompactAdRow(reserve:true)` 는 SDK 준비 전에 높이 40pt, 준비 후 74pt다. 예약 높이가 정확하지 않다(코드).
- 상세 첫 슬롯은 예약하지 않는다(R4). 짧은 글이면 화면 안에서 펴질 수 있다. 이번 캡처에서는 재현되지 않았다.

## 확인하지 못함
로그인 후 글쓰기·첨부 등록, 스쿼드 불러오기, EEA UMP 폼, 실기기 광고 지연, 실제 단위 노출(App Store 빌드).
