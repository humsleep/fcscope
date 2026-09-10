import SwiftUI
import Observation

enum Route: Hashable {
    case user(String)
    case match(id: String, me: String?)
    case player(Int)
    case post(String)
    case squad(String)
}

enum Tab: Int { case home, squad, meta, community, me }

/// 탭별 NavigationPath + 딥링크(유니버설 링크 / fcscope://) 파서.
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()
    var tab: Tab = .home
    var homePath = NavigationPath()
    var squadPath = NavigationPath()
    var metaPath = NavigationPath()
    var communityPath = NavigationPath()
    var mePath = NavigationPath()
    /// 스쿼드 빌더에 넘길 임포트 요청 (닉네임 또는 공유 코드)
    var pendingSquadImport: SquadImport?
    enum SquadImport: Hashable { case owner(String), load(String) }

    func push(_ r: Route) {
        switch tab {
        case .home: homePath.append(r)
        case .squad: squadPath.append(r)
        case .meta: metaPath.append(r)
        case .community: communityPath.append(r)
        case .me: mePath.append(r)
        }
    }
    func openUser(_ nick: String) { tab = .home; homePath.append(Route.user(nick)) }

    func handle(url: URL) {
        // 유니버설 링크(https://www.fcscope.xyz/...) 와 커스텀 스킴(fcscope://...) 을 같은 규칙으로 다룬다.
        // 스킴은 host 가 첫 경로 조각이라(`fcscope://user/보엠`) 앞에 붙여 준다.
        // 유니버설 링크는 Associated Domains 프로비저닝이 끝나야 동작하므로, 그전까지 공유·테스트 경로는 스킴뿐이다.
        var parts: [String]
        if url.scheme == "fcscope" {
            guard let host = url.host else { return }
            if host == "auth" { Task { _ = await AuthManager.shared.handleOpenURL(url) }; return }
            parts = [host] + url.pathComponents.filter { $0 != "/" }
        } else {
            guard let host = url.host, host.hasSuffix("fcscope.xyz") else { return }
            parts = url.pathComponents.filter { $0 != "/" }
        }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch parts.first {
        case "user": if parts.count > 1 { openUser(parts[1].removingPercentEncoding ?? parts[1]) }
        case "match": if parts.count > 1 { tab = .home; homePath.append(Route.match(id: parts[1], me: query("me"))) }
        case "player": if parts.count > 1, let spid = Int(parts[1]) { tab = .meta; metaPath.append(Route.player(spid)) }
        case "meta", "report": tab = .meta
        case "community":
            tab = .community
            if parts.count > 1 { communityPath.append(Route.post(parts[1])) }
        case "squad":
            tab = .squad
            if parts.count > 1 { squadPath.append(Route.squad(parts[1])) }
            else if let owner = query("owner") { pendingSquadImport = .owner(owner) }
            else if let load = query("load") { pendingSquadImport = .load(load) }
        case "me": tab = .me
        default: tab = .home
        }
    }
}

/// Route → 화면
struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .user(let nick): RecordView(nickname: nick)
        case .match(let id, let me): MatchReportView(matchId: id, me: me)
        case .player(let spid): PlayerDetailView(spid: spid)
        case .post(let id): PostDetailView(postId: id)
        case .squad(let id): SquadDetailView(squadId: id)
        }
    }
}
