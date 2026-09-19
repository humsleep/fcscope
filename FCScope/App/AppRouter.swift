import SwiftUI
import Observation

enum Route: Hashable {
    case user(String)
    /// fromRecord: 전적 화면에서 연 경기. 리포트의 "← 전적으로"가 같은 전적을 한 번 더 쌓지 않고 뒤로 가게 한다.
    case match(id: String, me: String?, fromRecord: Bool = false)
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
    /// 스쿼드 빌더에 넘길 요청 (닉네임·공유 코드 임포트, 선수 1명 배치)
    ///
    /// 알림(NotificationCenter)으로 넘기면 스쿼드 탭을 아직 한 번도 열지 않은 세션에서는 받을 뷰가 없어 버려진다.
    /// 그래서 라우터에 남겨 두고 빌더가 나타날 때 꺼내 간다.
    var pendingSquadImport: SquadImport?
    enum SquadImport: Hashable {
        case owner(String), load(String)
        /// line: 선수가 주로 뛰는 라인(GK/DEF/MID/ATT). 모르면 nil → 빈 슬롯 아무 곳.
        case add(PlayerHit, line: String?)
    }

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
            // fcscope://auth/* 는 건드리지 않는다.
            //
            // signInWithOAuth 가 ASWebAuthenticationSession 을 직접 열고 콜백 교환까지 소유한다.
            // 여기서 같은 URL 을 한 번 더 교환하면 PKCE code verifier 가 이미 소비된 뒤라
            // "both auth code and code verifier should be non-empty" 로 실패한다.
            // (세션이 활성인 동안 iOS 는 콜백을 세션에만 전달하므로 이 경로는 원래 타지 않는다.)
            if host == "auth" { return }
            parts = [host] + url.pathComponents.filter { $0 != "/" }
        } else {
            // hasSuffix 는 "evilfcscope.xyz" 도 통과시켰다 — 정확한 호스트만.
            guard let host = url.host, host == "fcscope.xyz" || host == "www.fcscope.xyz" else { return }
            parts = url.pathComponents.filter { $0 != "/" }
        }
        // pathComponents 는 %2F 를 "/" 로 되살린다 — 그대로 API 경로에 끼우면 "../" 로 다른 API 를 가리킬 수 있었다.
        // 글·스쿼드·매치 ID 는 영숫자(와 - _)만, 구단주명은 경로 구분자·".." 만 막는다(한글 허용).
        if parts.count > 1 {
            let id = parts[1]
            let idRoutes: Set<String> = ["match", "community", "squad", "player"]
            if idRoutes.contains(parts[0]) {
                guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return }
            } else if id.contains("/") || id.contains("..") || (id.removingPercentEncoding ?? id).contains("/") {
                return
            }
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
            // /community/new 는 글쓰기 화면(웹) — 글 ID 가 아니다
            if parts.count > 1, parts[1] != "new" { communityPath.append(Route.post(parts[1])) }
        case "squad":
            tab = .squad
            if parts.count > 1 { squadPath.append(Route.squad(parts[1])) }
            else if let owner = query("owner") { pendingSquadImport = .owner(owner) }
            else if let load = query("load"), load.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil { pendingSquadImport = .load(load) }
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
        case .match(let id, let me, let fromRecord): MatchReportView(matchId: id, me: me, fromRecord: fromRecord)
        case .player(let spid): PlayerDetailView(spid: spid)
        case .post(let id): PostDetailView(postId: id)
        case .squad(let id): SquadDetailView(squadId: id)
        }
    }
}
