# Guideline 2.1 (Information Needed) 대응 — Build 12 / 2026-09-23

신규 개발자 계정에 오는 정형 요청이다. **앱을 고칠 필요는 없다.** 아래 두 가지를 하면 심사가 이어진다.

1. 물리 기기(실제 아이폰)에서 찍은 **화면 녹화**를 App Store Connect 심사 대화에 첨부
2. 아래 **답변 전문(영문)** 을 ① 심사 대화 답장 ② App Store Connect → 앱 심사 정보 → 메모(Notes) 양쪽에 붙여넣기

메모에 남겨 두면 다음 제출부터 같은 질문을 받지 않는다.

---

## 1. 화면 녹화 대본 (실제 iPhone, 최신 iOS, 3~5분)

시뮬레이터 녹화는 안 된다. 설정 › 제어 센터에 "화면 기록"을 추가해 녹화한다.
소리·자막은 없어도 되지만, 각 단계에서 **2초씩 멈춰** 화면이 보이게 한다.

| 순서 | 보여줄 것 | 비고 |
|---|---|---|
| 1 | 홈 화면에서 앱 아이콘을 탭해 **실행**(스플래시부터) | "launching the app" 요구사항 |
| 2 | 홈 검색창에 `보엠` 입력 → 전적 결과 | ATT 팝업이 여기서 뜬다 — **팝업까지 녹화** |
| 3 | 전적 탭 → 매치 하나 열기 → 매치 리포트(슛맵) 스크롤 | 핵심 기능 |
| 4 | 스쿼드 클리닉 / 픽 랭킹 한 번씩 | 핵심 기능 |
| 5 | 커뮤니티 탭 → 글 하나 열기 → **신고** 버튼 탭(사유 선택 화면까지) | UGC 신고 |
| 6 | 같은 글에서 **차단** 탭 → "차단한 사용자의 글이에요" 안내 → 차단 해제 | UGC 차단 |
| 7 | 내 정보 탭 → **로그인**(Sign in with Apple 전 과정) | 계정 생성/로그인 |
| 8 | 커뮤니티 닉네임 등록 → 글 또는 댓글 작성 → 게시된 것 확인 | UGC 생성 |
| 9 | 내 정보 → 설정 · 약관 · 계정 → 계정 → **계정 삭제** → 확인 → 로그아웃된 상태 | **필수**. Apple 로그인이면 Face ID가 한 번 더 뜨는 게 정상 |

- 유료 기능은 없다. 광고는 무료 앱의 배너·전면광고이므로 "paid content"에 해당하지 않는다.
- 9번은 실제로 계정이 지워진다. 삭제해도 되는 테스트 Apple ID로 녹화할 것.

## 2. 답변 전문 (영문 — 그대로 복사)

```
Thank you for the review. Below is the information requested.

1. SCREEN RECORDING
A screen recording captured on a physical iPhone running the latest iOS is attached to
this message. It starts with launching the app and covers: player record search, match
report, squad clinic, pick ranking, the community tab with the content reporting and
blocking mechanisms, Sign in with Apple, posting user-generated content, and the account
deletion flow.

2. PURPOSE AND TARGET AUDIENCE
FC Scope is an unofficial fan service that analyzes match records for "FC ONLINE", a
football game published by NEXON in South Korea. The target audience is Korean FC ONLINE
players.
Existing services in this category only list raw numbers. FC Scope diagnoses them: it
explains why a match was lost (shot maps, possession and pass data per match), compares
the user's players against aggregated statistics of top-ranked players, and evaluates the
user's squad. The value is that a player can see what to fix, not just what happened.
The app is not affiliated with or endorsed by NEXON or EA.

3. SETTING UP AND ACCESSING THE MAIN FEATURES
No account is required for the main features. On the Home tab, type a FC ONLINE user name
into the search box. Example user name that returns data: 보엠
From the search result you can open the Record tab (recent matches), tap any match to see
the match report, and use Squad Clinic and Pick Ranking from the tab bar.

Sign-in is required only to write in the community. We do not provide a demo account
because the app supports Sign in with Apple and Google Sign-In only, with no password
based accounts. The reviewer can sign in with any Apple ID; the app requests only the
name and email provided by Apple. After signing in, register a community nickname on the
My tab before posting.

Account deletion: My tab > "설정 · 약관 · 계정" (Settings, Terms, Account) > 계정 (Account)
> 계정 삭제 (Delete account). The account and its data are deleted immediately.

Community safety: a banned-word filter runs before a post is submitted, every post and
comment can be reported, any user can be blocked, posts above a report threshold are
hidden automatically, and reports are reviewed by the operator within 24 hours
(humsleep@naver.com).

4. EXTERNAL SERVICES USED
- NEXON Open API (https://openapi.nexon.com) - the sole source of FC ONLINE match and
  player data, and of player card images (NEXON CDN).
- Supabase (authentication, PostgreSQL database, storage) - our backend, hosted on Vercel.
- Sign in with Apple and Google Sign-In - authentication only.
- Google AdMob, with the Google User Messaging Platform for consent - advertising.
- Apple Push Notification service - match and weekly report notifications.
- YouTube public RSS feeds - links to FC ONLINE videos shown on the Home tab.
There is no payment processor (the app has no in-app purchase) and no AI service.

5. REGIONAL DIFFERENCES
The app functions consistently in all regions; there are no region-gated features. The
interface and content are in Korean only, and the underlying game data comes from the
Korean service of FC ONLINE, so the app is primarily useful to Korean users. Nothing is
blocked or changed based on the user's region.

6. THIRD-PARTY MATERIAL
All game data and player images are retrieved from NEXON's public Open API, which NEXON
provides for third-party services. We comply with its terms of use, including the
attribution requirement: the data source is credited inside the app and on our website,
and the app states that it is an unofficial fan service with no affiliation with NEXON or
EA. Access is authenticated with an API key issued to our developer account at
https://openapi.nexon.com. The app is not part of a regulated industry.
```

## 3. 제출 순서

1. 실제 아이폰으로 위 대본대로 녹화한다.
2. App Store Connect → 심사 메시지 → 답장에 **답변 전문 + 녹화 파일** 첨부.
3. 같은 글을 앱 심사 정보 → 메모(Notes)에도 붙여넣고 저장.
4. 빌드를 다시 올릴 필요는 없다. Build 12 그대로 심사가 이어진다.
