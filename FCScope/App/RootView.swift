import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @State private var prefs = LocalPrefs.shared
    /// 콜드 스타트마다 한 번 인트로를 보여 준다.
    @State private var showIntro = true

    var body: some View {
        @Bindable var router = router
        Group {
            if !prefs.onboardingDone {
                OnboardingView()
            } else {
                TabView(selection: $router.tab) {
                    NavigationStack(path: $router.homePath) { HomeView().navigationDestination(for: Route.self) { RouteView(route: $0) } }
                        .tabItem { Label("전적", systemImage: "magnifyingglass") }.tag(Tab.home)
                    NavigationStack(path: $router.squadPath) { SquadBuilderView().navigationDestination(for: Route.self) { RouteView(route: $0) } }
                        .tabItem { Label("스쿼드", systemImage: "shield.lefthalf.filled") }.tag(Tab.squad)
                    NavigationStack(path: $router.metaPath) { MetaView().navigationDestination(for: Route.self) { RouteView(route: $0) } }
                        .tabItem { Label("픽 랭킹", systemImage: "chart.bar.fill") }.tag(Tab.meta)
                    NavigationStack(path: $router.communityPath) { CommunityView().navigationDestination(for: Route.self) { RouteView(route: $0) } }
                        .tabItem { Label("커뮤니티", systemImage: "person.2.fill") }.tag(Tab.community)
                    NavigationStack(path: $router.mePath) { MyPageView().navigationDestination(for: Route.self) { RouteView(route: $0) } }
                        .tabItem { Label("내 정보", systemImage: "person.crop.circle") }.tag(Tab.me)
                }
                // ATT 는 메인 탭이 처음 뜰 때 묻는다(2026-09-30 심사 거절 대응 — AdsManager 주석 참고).
                // 잠깐 기다리는 건 첫 화면이 그려지고 앱이 확실히 활성화된 뒤에 시스템 팝업을 띄우기 위해서다.
                // 인트로 위에 시스템 팝업이 겹치지 않게 인트로가 끝난 뒤에 센다.
                .task(id: showIntro) {
                    guard !showIntro else { return }
                    try? await Task.sleep(for: .seconds(1))
                    await AdsManager.shared.requestConsentOnLaunch()
                }
                // 탭 변경 햅틱은 제거 — router.tab 은 딥링크·"빌더로 열기" 같은 코드 경로에서도 바뀌어
                // 사용자가 누르지 않았는데 진동이 났다. 시스템 탭 바도 기본적으로 햅틱을 주지 않는다.
            }
        }
        .overlay {
            if showIntro {
                IntroView { showIntro = false }
                    .transition(.identity)
            }
        }
        .preferredColorScheme(nil)
        .onAppear { prefs.recordVisit() }
        .task {
            // 번들 선수 인덱스 로드(검색 서버 왕복 0) + 주 1회 신규 시즌 갱신
            await PlayerIndex.shared.load()
            await PlayerIndex.shared.refreshIfStale()
        }
    }
}
