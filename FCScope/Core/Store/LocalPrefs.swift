import Foundation
import Observation

/// 기기 로컬 상태 — 최근 검색·즐겨찾기·내 구단주명·차단·방문 스트릭·즐겨찾기 폼 스냅샷.
/// 웹의 localStorage 역할. 위젯과 공유하려면 App Group 으로 옮긴다(Widgets 도입 시).
@Observable
@MainActor
final class LocalPrefs {
    static let shared = LocalPrefs()
    static let suite = UserDefaults(suiteName: "group.xyz.fcscope.app") ?? .standard

    var recentSearches: [String] { didSet { save("recent", recentSearches) } }
    var favorites: [String] { didSet { save("favorites", favorites) } }
    var myNickname: String? { didSet { Self.suite.set(myNickname, forKey: "myNickname") } }
    var blockedUsers: [String] { didSet { save("blocked", blockedUsers) } }
    var onboardingDone: Bool { didSet { Self.suite.set(onboardingDone, forKey: "onboardingDone") } }
    var attAsked: Bool { didSet { Self.suite.set(attAsked, forKey: "attAsked") } }
    /// 즐겨찾기 구단주별 최근 폼 스냅샷 (승률·연승) — 델타 배지 재료
    var formSnapshots: [String: FormSnapshot] { didSet { saveCodable("formSnapshots", formSnapshots) } }
    var streak: VisitStreak { didSet { saveCodable("streak", streak) } }

    struct FormSnapshot: Codable { var winRate: Int; var score: Double; var streak: Int; var updatedAt: Date; var prevWinRate: Int?; var form: [String]? }
    struct VisitStreak: Codable { var current: Int; var best: Int; var lastDay: String }

    private init() {
        recentSearches = Self.suite.stringArray(forKey: "recent") ?? []
        favorites = Self.suite.stringArray(forKey: "favorites") ?? []
        myNickname = Self.suite.string(forKey: "myNickname")
        blockedUsers = Self.suite.stringArray(forKey: "blocked") ?? []
        onboardingDone = Self.suite.bool(forKey: "onboardingDone")
        attAsked = Self.suite.bool(forKey: "attAsked")
        formSnapshots = Self.load("formSnapshots") ?? [:]
        streak = Self.load("streak") ?? VisitStreak(current: 0, best: 0, lastDay: "")
    }

    private func save(_ key: String, _ v: [String]) { Self.suite.set(v, forKey: key) }
    private func saveCodable<T: Encodable>(_ key: String, _ v: T) { if let d = try? JSONEncoder().encode(v) { Self.suite.set(d, forKey: key) } }
    private static func load<T: Decodable>(_ key: String) -> T? { guard let d = suite.data(forKey: key) else { return nil }; return try? JSONDecoder().decode(T.self, from: d) }

    func addRecent(_ nick: String) {
        var r = recentSearches.filter { $0.caseInsensitiveCompare(nick) != .orderedSame }
        r.insert(nick, at: 0)
        recentSearches = Array(r.prefix(10))
    }
    func isFavorite(_ nick: String) -> Bool { favorites.contains { $0.caseInsensitiveCompare(nick) == .orderedSame } }
    func toggleFavorite(_ nick: String) {
        if isFavorite(nick) { favorites.removeAll { $0.caseInsensitiveCompare(nick) == .orderedSame } }
        else { favorites = Array(([nick] + favorites).prefix(12)) }
    }
    func isBlocked(_ userId: String) -> Bool { blockedUsers.contains(userId) }
    func block(_ userId: String) { if !isBlocked(userId) { blockedUsers.append(userId) } }
    func unblock(_ userId: String) { blockedUsers.removeAll { $0 == userId } }

    /// 전적 조회 성공 시 폼 스냅샷 갱신 (즐겨찾기·내 구단주 델타 배지)
    func recordForm(nick: String, winRate: Int, score: Double, streak: Int, form: [String] = []) {
        let key = nick.lowercased()
        let prev = formSnapshots[key]
        formSnapshots[key] = FormSnapshot(winRate: winRate, score: score, streak: streak, updatedAt: Date(), prevWinRate: prev?.winRate, form: form.isEmpty ? prev?.form : form)
        WidgetBridge.reload()
    }
    func snapshot(for nick: String) -> FormSnapshot? { formSnapshots[nick.lowercased()] }

    /// 방문 스트릭(하루 1회)
    func recordVisit() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Asia/Seoul")
        let today = f.string(from: Date())
        if streak.lastDay == today { return }
        let yesterday = f.string(from: Date().addingTimeInterval(-86_400))
        let cur = streak.lastDay == yesterday ? streak.current + 1 : 1
        streak = VisitStreak(current: cur, best: max(streak.best, cur), lastDay: today)
    }
}
