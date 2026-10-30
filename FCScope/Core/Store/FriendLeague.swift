import Foundation
import UserNotifications

/// 친구 리그 — 내 구단 + 즐겨찾기 구단주의 최근 7일 공식경기 순위(docs/STRATEGY-2026-11.md).
/// 서버 변경 없이 /api/v1/user 응답의 week 로 만든다. 순위 규칙은 LeagueRanking.swift.
@MainActor
enum FriendLeague {
    /// 지난번에 본(또는 알린) "나보다 위" 구단주 id — 새로 올라온 사람만 추월로 센다.
    private static let aboveKey = "fcscope.league.aboveMe"

    /// 나 + 즐겨찾기(대소문자 무시 중복 제거)
    static var members: [String] {
        let p = LocalPrefs.shared
        var seen = Set<String>()
        return ([p.myNickname].compactMap { $0 } + p.favorites).filter { seen.insert($0.lowercased()).inserted }
    }

    private static func path(_ nick: String) -> String {
        "/api/v1/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"
    }

    private static func entry(_ nick: String, _ o: UserOverview?) -> LeagueEntry {
        let mine = LocalPrefs.shared.myNickname?.caseInsensitiveCompare(nick) == .orderedSame
        guard let w = o?.week else { return LeagueEntry(nick: nick, isMe: mine) }
        return LeagueEntry(nick: nick, isMe: mine, games: w.games, win: w.win, draw: w.draw, lose: w.lose, winRate: w.winRate)
    }

    /// 디스크 캐시만으로(네트워크 0) — 홈 카드·화면 첫 그림.
    static func cachedRows() async -> [LeagueEntry] {
        var rows: [LeagueEntry] = []
        for n in members {
            let hit: (value: UserOverview, isFresh: Bool)? = await APIClient.shared.cachedValue(path(n), query: ["type": "50"])
            rows.append(entry(n, hit?.value))
        }
        return rankLeague(rows)
    }

    /// 모두 새로 받는다. 서버 팬아웃 제한(IP 당 분당 40)에 걸리지 않게 3명씩. 실패한 사람은 캐시 값으로.
    static func refreshedRows() async -> [LeagueEntry] {
        var rows: [LeagueEntry] = []
        let all = members
        for start in stride(from: 0, to: all.count, by: 3) {
            let chunk = Array(all[start..<min(start + 3, all.count)])
            let got = await withTaskGroup(of: (String, UserOverview?).self) { group in
                for n in chunk {
                    group.addTask {
                        let fresh: UserOverview? = try? await APIClient.shared.getAndCache(path(n), query: ["type": "50"], auth: false)
                        if let fresh { return (n, fresh) }
                        let hit: (value: UserOverview, isFresh: Bool)? = await APIClient.shared.cachedValue(path(n), query: ["type": "50"])
                        return (n, hit?.value)
                    }
                }
                var out: [String: UserOverview?] = [:]
                for await (n, o) in group { out[n] = o }
                return out
            }
            for n in chunk {
                let o = got[n] ?? nil
                // 홈 즐겨찾기 델타 배지도 같이 최신으로(BackgroundRefresh 와 같은 일)
                if let o { LocalPrefs.shared.recordForm(nick: o.profile.nickname, winRate: o.summary.winRate, score: o.score, streak: o.perf.currentStreak) }
                rows.append(entry(n, o))
            }
        }
        return rankLeague(rows)
    }

    /// 순위를 봤다 — 기준을 옮긴다. 지난번엔 없던 "나보다 위" 구단주를 돌려준다(첫 기록이면 빈 배열).
    @discardableResult
    static func noteStandings(_ ranked: [LeagueEntry]) -> [LeagueEntry] {
        guard let above = leagueAboveMe(ranked) else { return [] }
        let d = UserDefaults.standard
        let prev = d.stringArray(forKey: aboveKey).map(Set.init)
        d.set(above.map(\.id), forKey: aboveKey)
        guard let prev else { return [] }
        return above.filter { !prev.contains($0.id) }
    }

    /// 백그라운드 갱신 뒤 — 새로 나를 앞지른 친구가 있으면 로컬 알림. 알림 권한이 없으면 기준만 옮긴다.
    static func notifyOvertakes() async {
        let ranked = await cachedRows()
        let passed = noteStandings(ranked)
        guard let first = passed.first,
              let myRank = ranked.firstIndex(where: \.isMe).map({ $0 + 1 }) else { return }
        let center = UNUserNotificationCenter.current()
        guard [.authorized, .provisional, .ephemeral].contains(await center.notificationSettings().authorizationStatus) else { return }
        let content = UNMutableNotificationContent()
        content.title = "친구 리그 순위가 바뀌었어요"
        let who = passed.count > 1 ? "\(first.nick)님 외 \(passed.count - 1)명이" : "\(first.nick)님이"
        content.body = "\(who) 최근 7일 승률로 나를 앞질렀어요 (\(first.winRate)%). 지금 \(myRank)위예요."
        content.sound = .default
        content.userInfo = ["link": "fcscope://league"]
        try? await center.add(UNNotificationRequest(identifier: "league-overtake", content: content, trigger: nil))
    }
}
