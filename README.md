# FC Scope — iOS 앱

FC온라인 전적·스쿼드 도구 [FC Scope](https://www.fcscope.xyz) 의 **iOS 네이티브 앱**(SwiftUI, iOS 17+).

웹 서비스와는 **저장소가 분리**되어 있습니다.

| 저장소 | 내용 |
|---|---|
| [humsleep/fconline](https://github.com/humsleep/fconline) | 웹(Next.js) + 앱이 호출하는 `/api/v1` 백엔드 |
| 이 저장소 | iOS 앱 (SwiftUI · WidgetKit) |

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

## 라이선스

폰트 Chakra Petch 는 SIL OFL — `FCScope/Resources/Fonts/OFL.txt`.
