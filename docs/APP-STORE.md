# iOS 앱 (App Store) 등록 가이드

> **2026-09-04 업데이트**: 제출 대상은 이 저장소 루트의 **SwiftUI 완전 네이티브 앱**이다(개발 가이드 `docs/NATIVE-APP.md`). 아래의 Capacitor 셸(`legacy-capacitor/`) 절차는 참고용으로 남긴다. 번들 ID·URL 스킴·엔타이틀먼트·개인정보 라벨·AdMob 설정은 두 앱이 동일하며, 네이티브 앱은 추가로 **App Group(`group.xyz.fcscope.app`)·Push Notifications·Background Modes(fetch/remote-notification)** Capability 와 **APNs 키(.p8)** 가 필요하다. Supabase 값은 `FCScope/Info.plist` 의 `FCSupabaseURL`/`FCSupabaseAnonKey`.

FC Scope iOS 앱은 **Capacitor 셸**이다 — `legacy-capacitor/` 의 네이티브 프로젝트가 WKWebView 로
`https://www.fcscope.xyz` 를 그대로 띄우고, 웹은 UA 토큰(`FCScopeApp/<버전>`)으로 "앱 모드"를 감지해
푸터 숨김·하단 광고 인셋·네이티브 로그인·네이티브 공유를 켠다. (Next.js SSR/API 라우트 때문에 정적 내보내기는 불가.)

```
legacy-capacitor/
  capacitor.config.ts     # appId xyz.fcscope.app, server.url, UA 토큰
  www/error.html          # 오프라인/연결 실패 화면
  ios/App/App/Info.plist  # ATT 문구, AdMob 앱 ID, URL 스킴(fcscope://), 세로 고정
  ios/App/App/App.entitlements  # Sign in with Apple, Associated Domains
```

> Capacitor 셸의 웹 쪽 앱 모드 코드(`lib/client/native.ts`, `app/components/NativeBridge.tsx` 등)는 네이티브 전환 후 웹 저장소에서 제거했다.
> 네이티브 앱이 계속 쓰는 웹 저장소 자산은 `/api/v1/*`, `app/api/me/delete/`, `app/.well-known/apple-app-site-association/`, `app/app-ads.txt/` 다.

---

## 0. 로컬 빌드·실행

```bash
cd mobile && npm install
npx cap sync ios
npx cap open ios          # Xcode 에서 실행 (또는 아래 xcodebuild)
```

시뮬레이터 빌드 (서명 없이):
```bash
cd mobile && npm run build:sim
```

로컬 개발 서버를 앱에서 보려면 (맥 LAN IP 로):
```bash
CAP_SERVER_URL=http://192.168.0.10:3000 npx cap sync ios
```

**버전 올리기**: `legacy-capacitor/package.json` version (UA 토큰) + Xcode `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` 을 함께.

---

## 1. Apple Developer 설정 (한 번)

1. **Identifiers → App IDs**: `xyz.fcscope.app` 등록. Capabilities: **Sign in with Apple**, **Associated Domains** 체크.
2. Xcode → App 타깃 → Signing & Capabilities → Team 선택 (자동 서명). 엔타이틀먼트 파일은 이미 연결돼 있음.
3. **팀 ID** 확인 (Membership 페이지) → Vercel 환경변수 `APPLE_TEAM_ID` 에 입력 → 재배포.
   배포 후 `https://www.fcscope.xyz/.well-known/apple-app-site-association` 이 JSON 을 돌려주면 유니버설 링크 준비 완료
   (공유 링크 탭 → 앱으로 열림). 앱을 **재설치**해야 iOS 가 파일을 다시 읽는다.

## 2. Supabase 설정

Authentication → URL Configuration → **Redirect URLs** 에 추가:
```
fcscope://auth/callback
fcscope://auth/callback?next=*
```
(앱의 Google 로그인은 시스템 브라우저 시트에서 진행 후 이 스킴으로 복귀한다.)

Authentication → Providers → **Apple** 활성화:
- **Client IDs** 에 번들 ID `xyz.fcscope.app` 추가 (네이티브 Sign in with Apple 은 번들 ID 가 client_id).
- Secret Key 는 웹에서 Apple 로그인을 쓸 때만 필요 — 앱 전용이면 비워도 됨.

> App Store 4.8: Google 로그인을 제공하므로 **Apple 로그인이 반드시** 있어야 한다. 로그인 페이지는 앱에서만 Apple 버튼을 노출한다.

## 3. AdMob 설정

1. AdMob 콘솔 → 앱 추가 (iOS, App Store 등록 전이면 "아직 미게시" 선택) → **앱 ID** (`ca-app-pub-xxx~yyy`).
2. 광고 단위 → **배너** 생성 → 광고 단위 ID (`ca-app-pub-xxx/zzz`).
3. `legacy-capacitor/ios/App/App/Info.plist` 의 `GADApplicationIdentifier` 를 **실제 앱 ID** 로 교체 (현재는 구글 테스트 앱 ID).
4. Vercel 환경변수:
   - `NEXT_PUBLIC_ADMOB_BANNER_IOS` = 배너 광고 단위 ID (미설정 시 프로덕션 앱엔 광고가 안 뜸)
   - `ADMOB_PUBLISHER_ID` = `pub-…` → `https://www.fcscope.xyz/app-ads.txt` 노출. App Store Connect 의 **마케팅 URL/개발자 웹사이트**를 `https://www.fcscope.xyz` 로 두면 AdMob 이 소유를 확인한다.
5. 동작: 첫 실행 시 UMP 동의(EEA 만) → **ATT 팝업**(문구는 Info.plist `NSUserTrackingUsageDescription`) → 하단 적응형 배너. 배너 높이만큼 탭바가 올라간다.
6. 심사 전 확인: 실제 광고 단위는 심사 중엔 "no fill" 이 흔하니, 광고가 안 떠도 레이아웃이 깨지지 않는지 확인 (배너 실패 시 인셋 0 처리됨).

## 4. App Store Connect

### 앱 정보
- 이름: **FC Scope** / 부제: FC온라인 전적·스쿼드 진단 랩
- 카테고리: 스포츠 (보조: 엔터테인먼트 또는 유틸리티)
- 개인정보처리방침 URL: `https://www.fcscope.xyz/privacy` / 이용약관: `https://www.fcscope.xyz/terms` (표준 EULA 사용)
- 연령 등급: 설문에서 도박/폭력 등 "없음". **"제한 없는 웹 액세스"는 아니오** (특정 도메인만 로드). 커뮤니티 때문에 **"사용자 생성 콘텐츠" 있음** → 12+ 권장.

### 앱 개인정보 (App Privacy) — 수집 항목 선언
| 데이터 | 유형 | 용도 | 사용자 연결 | 추적 |
|---|---|---|---|---|
| 이메일 주소 | 연락처 정보 | 앱 기능 | 예 | 아니오 |
| 이름 (Apple/Google 이 전달) | 연락처 정보 | 앱 기능 | 예 | 아니오 |
| 사용자 ID (소셜 식별자) | 식별자 | 앱 기능 | 예 | 아니오 |
| 사용자 콘텐츠 (게시물·댓글) | 사용자 콘텐츠 | 앱 기능 | 예 | 아니오 |
| 기기 ID (IDFA — ATT 허용 시) | 식별자 | 제3자 광고 | 아니오 | **예** |
| 대략적 위치 (IP 기반, AdMob) | 위치 | 제3자 광고 | 아니오 | 아니오 |
| 광고 데이터 · 제품 상호작용 | 사용 데이터 | 제3자 광고, 분석 | 아니오 | 아니오 |
| 충돌·성능 데이터 (AdMob SDK) | 진단 | 앱 기능 | 아니오 | 아니오 |

"추적"에 예가 있으므로 ATT 프롬프트가 구현돼 있어야 함 (돼 있음). 항목은 Google 의 [AdMob 개인정보 라벨 가이드](https://developers.google.com/admob/ios/data-disclosure) 와 대조해 최신화.

### 심사 노트 (App Review Information → Notes) 예시
```
FC Scope는 넥슨 공식 오픈API 기반의 EA SPORTS FC 온라인 전적 분석·스쿼드 진단 서비스입니다(비공식 팬 서비스).
- 전적 검색, 매치 리포트(슛맵), 스쿼드 빌더, 픽 랭킹 등 핵심 기능은 로그인 없이 이용 가능합니다.
  예시 구단주명: <운영자 계정 닉네임> → 홈 검색창에 입력.
- 로그인(Google/Apple)은 커뮤니티 글쓰기에만 필요합니다. 계정 삭제: 마이페이지 > 설정 > 계정 삭제.
- 커뮤니티: 게시물/댓글 신고 버튼, 사용자 차단(마이페이지에서 해제), 신고 누적 자동 숨김, 운영자 검토.
- 광고: Google AdMob 배너, ATT 프롬프트 구현.
- 앱은 자체 서비스 도메인(fcscope.xyz)만 로드하며, 네이티브 공유 시트·햅틱·Apple 로그인·유니버설 링크를 사용합니다.
```

### 스크린샷
6.9형(1320×2868) 필수 + 6.5형(1284×2778). 시뮬레이터(iPhone 17 Pro Max)에서 홈·전적·매치 리포트·스쿼드 빌더·커뮤니티 5장.

---

## 5. 심사 리스크와 대응

| 가이드라인 | 리스크 | 현재 대응 |
|---|---|---|
| **4.2 최소 기능** (웹 래퍼 거부) | 가장 큰 리스크. 심사자가 "사이트와 동일"이라고 판단할 수 있음 | 네이티브 로그인·공유·햅틱·광고·유니버설 링크·오프라인 화면. **거부 시**: 푸시 알림(내 글 새 댓글) 추가가 가장 효과적 — 다음 단계 |
| 4.8 Sign in with Apple | 필수 | 구현됨 (Supabase Apple provider 설정 필요) |
| 5.1.1(v) 계정 삭제 | 필수 | 마이페이지 > 설정 > 계정 삭제 (즉시) |
| 1.2 UGC | 신고·차단·연락처 | 신고 + 차단 + 문의 이메일 + 24시간 검토 약속(약관) |
| 5.1.2 ATT | 광고 추적 | ATT 프롬프트 + 개인정보 라벨 "추적: 예" |
| 2.5.x 성능 | 오프라인/네트워크 오류 | `www/error.html` 재시도 화면 |
| 4.1 / 5.2.x 지식재산 | NEXON·EA 자산 | 게임 데이터 출처 고지, "비공식 팬 서비스" 명시 (기존 웹과 동일). 앱 이름·아이콘에 EA/FC 로고 미사용 |

---

## 6. 개인정보처리방침 — 변경 요약 (v2, 2026-09-10 시행)

기존(2026-07-15) 방침은 웹 기준이라 앱 등록엔 부족했다. 보강한 항목:
- 광고(AdMob)·광고 식별자(IDFA)·ATT, 앱 접근권한 안내(정보통신망법 §22-2: 필수/선택 구분)
- Apple 로그인, Google Analytics(설정 시), 접속 기록, 검색 구단주명 서버 기록, 전적 스냅샷, 신고 내역
- 보유 기간표, 파기 절차, 제3자 제공(없음), 국외 이전 항목표(수탁자·국가·항목·기간)
- 계정 삭제 경로(앱 내 즉시), 차단 기능, 14세 미만, 자동 수집 장치 거부 방법, 안전성 확보 조치, 분쟁 기관 안내
- 로그인 동의 버전 `PRIVACY_VERSION = 2` (app/login/page.tsx)

**시행일 7일 전 공지** 약속이 있으므로 `/admin` 공지로 "9/10 개인정보처리방침·이용약관 개정" 배너를 띄운 뒤 배포할 것.

---

## 7. 출시 체크리스트

- [ ] Apple Developer: App ID + 두 Capability, Xcode 서명
- [ ] Vercel env: `APPLE_TEAM_ID`, `NEXT_PUBLIC_ADMOB_BANNER_IOS`, `ADMOB_PUBLISHER_ID`, (`NEXT_PUBLIC_IOS_BUNDLE_ID`)
- [ ] Supabase: Redirect URL `fcscope://auth/callback*`, Apple provider + 번들 ID
- [ ] Info.plist `GADApplicationIdentifier` 실제 값으로 교체
- [ ] 실기기 테스트: Google 로그인 복귀, Apple 로그인, 계정 삭제, 카드 공유, 배너 인셋, 유니버설 링크
- [ ] 개정 공지 배너 → 웹 배포 → 앱 Archive → TestFlight → 심사 제출
