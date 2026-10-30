import Foundation

/// 친구 리그 한 줄 — 최근 7일 공식경기 성적. 기록을 못 받았으면 games 0.
/// 순위 규칙은 의존성 없는 순수 함수로 둔다(scripts/check-league.sh 가 swiftc 로 단독 확인).
struct LeagueEntry: Identifiable, Equatable {
    /// 이보다 적게 뛰면 순위에서 뺀다 — 1경기 1승(100%)이 1위가 되지 않게.
    static let minGames = 3
    let nick: String
    let isMe: Bool
    var games = 0, win = 0, draw = 0, lose = 0, winRate = 0
    var id: String { nick.lowercased() }
    var qualified: Bool { games >= Self.minGames }
}

/// 3경기 이상 먼저 → 승률 → 승 수 → 경기 수 → 이름. 3경기 미만·기록 없음은 아래.
func rankLeague(_ rows: [LeagueEntry]) -> [LeagueEntry] {
    rows.sorted { a, b in
        if a.qualified != b.qualified { return a.qualified }
        if a.winRate != b.winRate { return a.winRate > b.winRate }
        if a.win != b.win { return a.win > b.win }
        if a.games != b.games { return a.games > b.games }
        return a.nick.localizedCompare(b.nick) == .orderedAscending
    }
}

/// 순위표에서 나보다 위인 구단주들. 내가 없거나 순위 밖(3경기 미만)이면 nil — 추월을 따질 수 없다.
func leagueAboveMe(_ ranked: [LeagueEntry]) -> [LeagueEntry]? {
    guard let i = ranked.firstIndex(where: \.isMe), ranked[i].qualified else { return nil }
    return Array(ranked[..<i])
}
