import SwiftUI
import UIKit

/// 커뮤니티 로컬 상태 — 읽은 글 · 글쓰기 초안 · 배틀 내 표 · 서버 기능 감지 캐시.
///
/// `LocalPrefs`(앱 그룹, 위젯 공유)와 달리 앱 안에서만 쓰므로 표준 UserDefaults 에 둔다.
@Observable
@MainActor
final class CommunityPrefs {
    static let shared = CommunityPrefs()
    private let d = UserDefaults.standard

    /// 읽은 글 id — 최근 500개 링버퍼(SPEC 5절)
    private(set) var readIds: [String]
    private var readSet: Set<String>
    /// 구 서버(배틀 `mine` 미지원)용 기기 기준 내 표: postId → "A"/"B"
    private(set) var battlePicks: [String: String]
    /// 서버가 v2(인기 정렬·hot)를 지원하는지 마지막으로 본 값 — 다음 실행 때 인기 탭을 바로 그린다.
    var hotSupported: Bool { didSet { d.set(hotSupported, forKey: "cm.hotSupported") } }
    /// 서버가 `types=a,b`·`sort` 쿼리를 지원하는지(응답에 `sort` 키가 있는가)
    var groupFilterSupported: Bool { didSet { d.set(groupFilterSupported, forKey: "cm.groupFilter") } }

    private init() {
        let ids = UserDefaults.standard.stringArray(forKey: "cm.read") ?? []
        readIds = ids
        readSet = Set(ids)
        let ud = UserDefaults.standard
        battlePicks = (ud.dictionary(forKey: "cm.battle") as? [String: String]) ?? [:]
        hotSupported = ud.bool(forKey: "cm.hotSupported")
        groupFilterSupported = ud.bool(forKey: "cm.groupFilter")
    }

    func isRead(_ id: String) -> Bool { readSet.contains(id) }
    func markRead(_ id: String) {
        guard !readSet.contains(id) else { return }
        readIds.append(id)
        if readIds.count > 500 { readIds.removeFirst(readIds.count - 500) }
        readSet = Set(readIds)
        d.set(readIds, forKey: "cm.read")
    }

    func battlePick(_ postId: String) -> String? { battlePicks[postId] }
    func setBattlePick(_ postId: String, _ pick: String) {
        battlePicks[postId] = pick
        if battlePicks.count > 300 { battlePicks = Dictionary(uniqueKeysWithValues: battlePicks.suffix(300).map { ($0.key, $0.value) }) }
        d.set(battlePicks, forKey: "cm.battle")
    }

    // MARK: 글쓰기 초안

    struct Draft: Codable, Equatable {
        var type: String?
        var title = ""
        var body = ""
        var squad = ""
        var squadName: String?
        var squadB = ""
        var squadBName: String?
        var region = "전국(온라인)"
        var positions: [String] = []
        var contact = ""
        var extras: [String: String] = [:]
        var savedAt = Date()
        var isEmpty: Bool {
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    func loadDraft() -> Draft? {
        guard let data = d.data(forKey: "cm.draft"), let v = try? JSONDecoder().decode(Draft.self, from: data), !v.isEmpty else { return nil }
        return v
    }
    func saveDraft(_ v: Draft) {
        if v.isEmpty { clearDraft(); return }
        if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: "cm.draft") }
    }
    func clearDraft() { d.removeObject(forKey: "cm.draft") }
}

/// 커뮤니티가 쓰는 서버 호출을 한곳에 모은다. DEBUG 에선 `-communityMock <full|legacy|empty>` 인자로
/// 목 데이터(CommunityMock.swift)를 돌려준다 — 릴리스 빌드에는 목 경로가 컴파일되지 않는다.
@MainActor
enum CommunityAPI {
    /// 기기 id — 배틀 익명 투표자 키(서버가 IP 해시와 섞어 파생한다)
    static var deviceId: String { UIDevice.current.identifierForVendor?.uuidString ?? "anon-device" }

    static func list(_ query: [String: String]) async throws -> PostListResponse {
        #if DEBUG
        if let m = CommunityMock.active { return try await m.list(query) }
        #endif
        return try await APIClient.shared.get("/api/v1/community/posts", query: query)
    }

    static func detail(_ id: String) async throws -> PostDetailResponse {
        #if DEBUG
        if let m = CommunityMock.active { return try await m.detail(id) }
        #endif
        return try await APIClient.shared.get("/api/v1/community/posts/\(id)")
    }

    private static var squadCache: [String: Squad] = [:]
    static func squad(_ id: String) async throws -> Squad {
        if let s = squadCache[id] { return s }
        #if DEBUG
        if let m = CommunityMock.active { let s = try m.squad(id); squadCache[id] = s; return s }
        #endif
        let s: Squad = try await APIClient.shared.get("/api/squad/\(id)", auth: false)
        squadCache[id] = s
        return s
    }

    static func battle(_ postId: String) async throws -> BattleVotes {
        #if DEBUG
        if let m = CommunityMock.active { return m.battle(postId) }
        #endif
        return try await APIClient.shared.get("/api/community/battle", query: ["postId": postId, "voter": deviceId])
    }

    static func vote(_ postId: String, _ pick: String) async throws -> BattleVotes {
        #if DEBUG
        if let m = CommunityMock.active { return m.vote(postId, pick) }
        #endif
        return try await APIClient.shared.send("/api/community/battle", method: "POST", json: ["postId": postId, "pick": pick, "voter": deviceId])
    }

    enum LikeTarget { case post, comment }
    static func like(_ target: LikeTarget, _ id: String, on: Bool) async throws -> LikeResponse {
        #if DEBUG
        if let m = CommunityMock.active { return try m.like(target, id, on: on) }
        #endif
        let path = target == .post ? "/api/community/posts/\(id)/like" : "/api/community/comments/\(id)/like"
        return try await APIClient.shared.send(path, method: on ? "POST" : "DELETE")
    }

    static func addComment(postId: String, body: String, squadId: String?, parentId: String?) async throws -> String? {
        var json: [String: Any] = ["body": body]
        if let squadId, !squadId.isEmpty { json["squad_id"] = squadId }
        if let parentId { json["parent_id"] = parentId }
        #if DEBUG
        if let m = CommunityMock.active { return m.addComment(postId: postId, json: json) }
        #endif
        struct R: Decodable { let id: String? }
        let r: R = try await APIClient.shared.send("/api/community/posts/\(postId)/comments", method: "POST", json: json)
        return r.id
    }

    static func deleteComment(postId: String, commentId: String) async throws {
        #if DEBUG
        if let m = CommunityMock.active { m.deleteComment(postId: postId, commentId: commentId); return }
        #endif
        try await APIClient.shared.sendNoContent("/api/community/posts/\(postId)/comments", method: "DELETE", json: ["comment_id": commentId])
    }

    static func deletePost(_ id: String) async throws {
        #if DEBUG
        if let m = CommunityMock.active { m.deletePost(id); return }
        #endif
        try await APIClient.shared.sendNoContent("/api/community/posts/\(id)", method: "DELETE")
    }

    static func report(type: String, id: String, reason: String) async throws {
        #if DEBUG
        if CommunityMock.active != nil { return }
        #endif
        try await APIClient.shared.sendNoContent("/api/community/report", method: "POST", json: ["target_type": type, "target_id": id, "reason": reason])
    }

    static func createPost(_ json: [String: Any]) async throws -> String {
        #if DEBUG
        if let m = CommunityMock.active { return m.createPost(json) }
        #endif
        let r: IdBody = try await APIClient.shared.send("/api/community/posts", method: "POST", json: json)
        return r.id
    }

    static func profile() async throws -> ProfileResponse {
        #if DEBUG
        if let m = CommunityMock.active { return try m.profile() }
        #endif
        return try await APIClient.shared.get("/api/profile")
    }

    static func notifications() async throws -> NotificationsResponse {
        #if DEBUG
        if let m = CommunityMock.active { return m.notifications() }
        #endif
        return try await APIClient.shared.get("/api/me/notifications", query: ["since": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86_400))])
    }

    /// 로그인 여부 — 목 모드에선 "로그인 + 닉네임 있음" 으로 본다(작성 흐름 검수용).
    static var isLoggedIn: Bool {
        #if DEBUG
        if CommunityMock.active != nil { return true }
        #endif
        return AuthManager.shared.isLoggedIn
    }

    /// 0023 미적용 서버가 좋아요를 503 `not_ready` 로 거절했는가
    static func isNotReady(_ error: Error) -> Bool {
        if case .server(let code, _, let status, _)? = error as? APIError { return code == "not_ready" || status == 404 }
        return false
    }
}

/// 신고 사유 — App Store 1.2(UGC) 요구: 신고 · 차단 · 운영자 조치
enum ReportReason: String, CaseIterable, Identifiable {
    case spam, abuse, illegal, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .spam: return "스팸·도배·광고"
        case .abuse: return "욕설·비하·혐오"
        case .illegal: return "불법·음란·거래 유도"
        case .other: return "기타"
        }
    }
}

/// 신고 대상 (글/댓글)
struct ReportTarget: Identifiable, Equatable {
    let type: String   // "post" | "comment"
    let id: String
}
