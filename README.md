# FC Scope — iOS 앱

FC온라인 전적·스쿼드 도구 [FC Scope](https://www.fcscope.xyz) 의 **iOS 네이티브 앱**(SwiftUI, iOS 17+).

웹 서비스와는 **저장소가 분리**되어 있습니다.

| 저장소 | 위치 | 내용 |
|---|---|---|
| 웹 | [humsleep/fconline](https://github.com/humsleep/fconline) (GitHub) | 웹(Next.js) + 앱이 호출하는 `/api/v1` 백엔드 |
| 앱 | [humsleep/fcscope](https://github.com/humsleep/fcscope) (GitHub) | iOS 앱 (SwiftUI · WidgetKit) |

앱에는 자체 서버가 없습니다. 넥슨 API 키를 서버에만 두기 위해, 앱은 웹 서버의
`https://www.fcscope.xyz/api/v1` JSON 을 호출합니다.

## 구조

```
project.yml          # XcodeGen 정의 — FCScope.xcodeproj 는 생성물이라 커밋하지 않는다
FCScope/             # 앱 타깃 (App · Core · Features · Resources)
FCScopeWidgets/      # WidgetKit 익스텐션 — "내 폼", "오늘의 급상승"
scripts/             # build-player-index.mjs — 선수 인덱스(players.json) 생성
docs/                # 개발·심사·설정 가이드
legacy-capacitor/    # 폐기된 Capacitor 웹뷰 셸. 참고용 보관, 빌드 대상 아님
```

## 빌드

```bash
brew install xcodegen   # 최초 1회
xcodegen generate
open FCScope.xcodeproj
```

시뮬레이터 빌드:

```bash
xcodebuild -project FCScope.xcodeproj -scheme FCScope -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

## 문서

- [docs/NATIVE-APP.md](docs/NATIVE-APP.md) — 앱 구조·화면·의존성·빌드
- [docs/SETUP-CHECKLIST.md](docs/SETUP-CHECKLIST.md) — 출시 전 설정값 체크리스트(Info.plist·Supabase·AdMob·APNs)
- [docs/APP-STORE.md](docs/APP-STORE.md) — App Store 심사 대응
- [docs/COUNCIL-2026-09-NATIVE.md](docs/COUNCIL-2026-09-NATIVE.md) — 네이티브 전환 설계 회의록

## 설정값

`FCScope/Info.plist` 의 `FCSupabaseURL` · `FCSupabaseAnonKey` · `GADApplicationIdentifier` ·
`FCAdMobBannerUnitID` 는 **비어 있으면 기능이 꺼진 채로 동작**합니다(크래시 없음).
실제 값은 `docs/SETUP-CHECKLIST.md` 3번 참고.

## 웹 API 계약 (`/api/v1`)

앱은 웹의 `/api/v1` 12개 라우트를 그대로 디코딩한다(`FCScope/Core/API/Models.swift`, 420줄).
**버전 협상이 없다** — 앱은 서버가 주는 응답을 그대로 믿는다.

앱스토어에 이미 나간 구버전은 몇 달씩 살아 있으므로, 웹 쪽에서 v1 응답의 **필드를 지우거나
이름·타입을 바꾸면 그 순간 배포된 앱이 깨진다**(심사 때문에 즉시 고칠 수도 없다).

- 웹 규칙: v1 은 **필드 추가만**. 삭제·개명·타입 변경 금지. 없앨 필드는 `null` 로 계속 내려보낸다.
- 앱 규칙: 새로 읽는 필드는 **옵셔널로 선언**한다. 서버가 아직 안 주는 필드가 있어도 디코딩이 통째로 실패하지 않도록.
- 정말 깨야 하면 `/api/v2` 를 새로 만들고 v1 은 남긴다.

## 라이선스

폰트 Chakra Petch 는 SIL OFL — `FCScope/Resources/Fonts/OFL.txt`.
