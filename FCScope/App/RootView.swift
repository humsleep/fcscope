import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @State private var prefs = LocalPrefs.shared

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
                // 탭 변경 햅틱은 제거 — router.tab 은 딥링크·"빌더로 열기" 같은 코드 경로에서도 바뀌어
                // 사용자가 누르지 않았는데 진동이 났다. 시스템 탭 바도 기본적으로 햅틱을 주지 않는다.
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
