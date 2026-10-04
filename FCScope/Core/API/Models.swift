import Foundation

// MARK: - /api/v1/user/:nickname

struct UserOverview: Decodable {
    let profile: UserProfile
    let matchType: Int
    let matchTabs: [MatchTab]
    let listOk: Bool
    let requested: Int
    let loaded: Int
    let summary: RecordSummary
    let avgRating: Double
    let score: Double
    let tier: ScoreTier
    let streak: StreakInfo
    let perf: PerfStats
    let diagnosis: Diagnosis
    let week: WeeklyRecap
    let rivals: [Rival]
    let nemesis: Rival?
    let matches: [MatchSummary]
    let cards: CardLinks
}

struct UserProfile: Decodable {
    let ouid: String
    let nickname: String
    let level: Int
    let divisions: [DivisionCard]
}

struct DivisionCard: Decodable, Identifiable {
    let matchType: Int
    let matchTypeName: String
    let division: Int
    let divisionName: String
    let date: String
    let iconUrl: String?
    var id: Int { matchType }
}

struct MatchTab: Decodable, Identifiable, Hashable {
    let type: Int
    let label: String
    var id: Int { type }
    static let defaults = [MatchTab(type: 50, label: "공식경기"), MatchTab(type: 52, label: "감독모드"), MatchTab(type: 40, label: "클래식 1on1")]
}

struct RecordSummary: Decodable {
    let played, win, draw, lose, winRate, goalsFor, goalsAgainst, avgPossession: Int
}

struct ScoreTier: Decodable { let label: String; let tone: String }

struct StreakInfo: Decodable {
    let text: String
    let color: String
    let icon: String
    let highlight: Bool
}

struct PerfStats: Decodable {
    let played: Int
    /// 몰수 제외 경기·승 (옛 서버 응답엔 없을 수 있음)
    let normalPlayed: Int?
    let normalWin: Int?
    let forfeits: Int?
    /// 몰수 제외 득실(옛 서버엔 없음) — summary 득실은 몰수 3:0 이 섞여 부호가 뒤집히기도 했다
    let goalsFor: Int?
    let goalsAgainst: Int?
    let winRate: Int
    let currentStreak: Int
    let bestWinStreak: Int
    let momentum: Int
    let avgRating: Double
    let cleanSheets: Int
    let scoreless: Int
    let bigWins: Int
    let bigLosses: Int
    let counterWins: Int
    let dominantLosses: Int
}

struct Rule: Decodable, Identifiable {
    let id: String
    let kind: String
    let tone: String
    let title: String
    let desc: String
}

struct Diagnosis: Decodable { let type: Rule?; let notes: [Rule] }

struct WeeklyRecap: Decodable {
    let games, win, draw, lose, winRate, bestStreak, goalsFor, goalsAgainst: Int
    let avgScore: Double
    let best: BestMatch?
    /// 30경기 상한에 걸려 "최근 7일"이 실제로는 "최근 30경기"인가(옛 서버엔 없음)
    let truncated: Bool?
    var label: String { truncated == true ? "최근 7일 중 최근 \(games)경기" : "최근 7일 \(games)경기" }
    struct BestMatch: Decodable { let matchId: String; let score: Double }
}

struct Rival: Decodable, Identifiable {
    let nickname: String
    let win, draw, lose, games, goalsFor, goalsAgainst: Int
    var id: String { nickname }
}

struct MatchSummary: Decodable, Identifiable, Hashable {
    let matchId: String
    let matchDate: String
    let matchType: Int
    let result: String
    let forfeit: Bool
    let me: Me
    let opponent: Opp?
    let score: Double
    var id: String { matchId }
    struct Me: Decodable, Hashable { let nickname: String; let goals: Int; let possession: Int; let rating: Double }
    struct Opp: Decodable, Hashable { let nickname: String; let goals: Int }
}

struct CardLinks: Decodable {
    let user: String
    let rank: String?
    let streak: String
    let weekly: String
    let rival: String?
}

// MARK: - report

struct ReportResponse: Decodable {
    let matchType: Int
    let listOk: Bool
    let report: MatchReport
    let insights: [Insight]
}
struct MatchReport: Decodable {
    let played, goalsFor, goalsAgainst: Int
    let avgRating: Double
    let timeBands: [TimeBand]
    let shotTypes: [ShotTypeStat]
    let form: [FormGame]
    let weekly: WeeklyForm?
}
struct TimeBand: Decodable, Identifiable { let label: String; let forGoals: Int; let againstGoals: Int; var id: String { label } }
struct ShotTypeStat: Decodable, Identifiable { let key: String; let label: String; let tries: Int; let goals: Int; var id: String { key } }
struct FormGame: Decodable { let diff: Int; let result: String; let label: String }
struct WeeklyForm: Decodable { let recentGames, recentWin, recentWinRate, prevGames: Int; let prevWinRate: Int?; let deltaWinRate: Int? }
struct Insight: Decodable, Identifiable { let tone: String; let text: String; var id: String { text } }

// MARK: - players

struct PlayersResponse: Decodable {
    let matchType: Int
    let sampleGames: Int
    let minGames: Int
    let squadRating: Double
    let squadVerdict: Verdict?
    let clinic: Clinic?
    let picks: PicksInfo?
    let players: [PlayerCard]
    let builderOwner: String
}
struct PicksInfo: Decodable { let date: String?; let topPickCount: Int; let total: Int; let cardUrl: String }
struct Verdict: Decodable {
    let tier: String; let label: String; let grade: String; let oneLiner: String; let color: String; let icon: String; let score: Double
}
struct Clinic: Decodable {
    let overall: Double
    let band: String
    let squadRating: Double
    let lines: [ClinicLine]
    let weakLinks: [ClinicPlayer]
    let strengths: [ClinicPlayer]
    let issues: [ClinicIssue]
    let rankerCoverage: Double
    let players: Int
    let sampleGames: Int
}
struct ClinicLine: Decodable, Identifiable { let line: String; let label: String; let count: Int; let avgRating: Double; let score: Double; var id: String { line } }
struct ClinicPlayer: Decodable, Identifiable { let spId: Int; let position: Int; let line: String; let games: Int; let avgRating: Double; let goals: Int; let assists: Int; var id: Int { spId } }
struct ClinicIssue: Decodable, Identifiable { let kind: String; let severity: String; let text: String; let spId: Int?; var id: String { kind + text } }
struct PlayerCard: Decodable, Identifiable {
    let spId: Int
    let mainPosition: Int
    let games: Int
    let avgRating: Double
    let goals: Int
    let assists: Int
    let goalsPerGame: Double
    let assistsPerGame: Double
    let passRate: Double
    let name: String
    let season: String
    let positionLabel: String
    let imageUrl: String
    let verdict: Verdict
    let ranker: RankerCompare?
    let topPick: Bool
    /// 누적 태클 성공 수(서버 PlayerAggregate 를 펼쳐 내려 원래부터 있던 필드). 수비 라인 랭커 비교용.
    let tackle: Int?
    var id: Int { spId }
    /// `tackle` 은 랭커 경기당 평균 태클(2026-10 서버 추가) — 옛 서버엔 없다.
    struct RankerCompare: Decodable { let goal: Double; let passRate: Int; let matchCount: Int; let tackle: Double? }
}

// MARK: - playstyle

struct PlaystyleResponse: Decodable { let matchType: Int; let result: PlaystyleResult; let shots: [Shot] }
struct PlaystyleResult: Decodable {
    let confidence: String
    let games: Int
    let controller: String
    let archetype: Archetype
    let axes: [Axis]
    let chips: [StyleChip]
    struct Archetype: Decodable { let id: String; let name: String; let tagline: String; let baseStrength: String; let baseWeakness: String }
    struct Axis: Decodable, Identifiable { let key: String; let label: String; let value: Double; let bipolar: Bool; let leftLabel: String?; let rightLabel: String?; let lowConf: Bool; var id: String { key } }
    struct StyleChip: Decodable, Identifiable { let text: String; let kind: String; var id: String { text } }
}
struct Shot: Decodable, Identifiable {
    let x: Double; let y: Double; let isGoal: Bool; let hitPost: Bool
    var minute: Int? = nil
    var player: String? = nil
    var inPenalty: Bool? = nil
    var id: String { "\(x),\(y),\(minute ?? 0),\(player ?? "")" }
}

// MARK: - match

struct MatchDetailResponse: Decodable {
    let matchId: String
    let matchDate: String
    let matchDateLabel: String
    let matchType: Int
    let matchTypeName: String
    let me: MatchSide
    let opponent: MatchSide?
    let verdict: Verdict
    let potm: Potm?
    let cardUrl: String
    struct Potm: Decodable { let spId: Int; let name: String; let positionLabel: String; let side: String; let rating: Double; let imageUrl: String }
}
struct MatchSide: Decodable {
    let ouid: String
    let nickname: String
    let result: String
    let forfeit: Bool
    let goals: Int
    let possession: Int
    let rating: Double
    let controller: String
    let stats: SideStats
    let shots: [Shot]
    let players: [MatchPlayerRow]
}
struct SideStats: Decodable {
    let shots, effectiveShots, passTry, passSuccess: Int
    let passRate: Int?
    let dribble, tackleTry, tackleSuccess, cornerKick, foul, yellowCards, redCards, offside: Int
}
struct MatchPlayerRow: Decodable, Identifiable {
    let spId: Int; let name: String; let position: Int; let positionLabel: String; let rating: Double; let goals: Int; let assists: Int; let imageUrl: String
    var id: String { "\(spId)-\(position)" }
}

// MARK: - meta / player

/// 서버의 `delta` 는 세 가지 뜻이다: 숫자(순위 변동) · `null`(어제 없던 신규 진입) · 키 없음(비교 불가).
/// 합성 Decodable 은 `Int??` 를 decodeIfPresent 로 풀어 `null` 을 바깥 nil(키 없음)로 뭉개 버린다 —
/// 그래서 NEW 배지가 한 번도 안 뜨고 "▲0" 이 찍혔다. 키 존재 여부와 null 을 따로 본다.
extension KeyedDecodingContainer {
    func decodeNullable<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T?? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return .some(nil) }
        return .some(try decode(T.self, forKey: key))
    }
}

struct MetaResponse: Decodable {
    let matchType: Int
    let date: String?
    let mover: Mover?
    let movers: [Mover]
    let lines: [MetaLine]
}
struct Mover: Decodable, Identifiable {
    let spId: Int; let position: Int; let line: String; let matchCount: Int
    let delta: Int??
    let name: String; let season: String; let positionLabel: String; let imageUrl: String
    let lineTitle: String?
    /// 선발 횟수(옛 서버엔 없음) — matchCount 는 넥슨 표본 수라 늘 20
    let usage: Int?
    var id: String { "\(spId)-\(position)" }
    var isNew: Bool { if case .some(.none) = delta { return true }; return false }
    var deltaValue: Int? { if case .some(.some(let d)) = delta { return d }; return nil }

    private enum CodingKeys: String, CodingKey { case spId, position, line, matchCount, delta, name, season, positionLabel, imageUrl, lineTitle, usage }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spId = try c.decode(Int.self, forKey: .spId); position = try c.decode(Int.self, forKey: .position)
        line = try c.decode(String.self, forKey: .line); matchCount = try c.decode(Int.self, forKey: .matchCount)
        delta = try c.decodeNullable(Int.self, forKey: .delta)
        name = try c.decode(String.self, forKey: .name); season = try c.decode(String.self, forKey: .season)
        positionLabel = try c.decode(String.self, forKey: .positionLabel); imageUrl = try c.decode(String.self, forKey: .imageUrl)
        lineTitle = try c.decodeIfPresent(String.self, forKey: .lineTitle)
        usage = try c.decodeIfPresent(Int.self, forKey: .usage)
    }
}
struct MetaLine: Decodable, Identifiable { let line: String; let title: String; let rows: [PickRow]; var id: String { line } }
struct PickRow: Decodable, Identifiable {
    let spId: Int; let position: Int; let matchCount: Int; let goalsPerMatch: Double; let passPct: Double
    /// 최근 경기에서 선발로 뛴 횟수(인기 순위 기준). 넥슨 matchCount 는 늘 20 이라 순위로 못 쓴다. 옛 서버엔 없음.
    let usage: Int?
    var count: Int { usage ?? matchCount }
    let delta: Int??
    let name: String; let season: String; let positionLabel: String; let imageUrl: String
    var id: String { "\(spId)-\(position)" }
    var isNew: Bool { if case .some(.none) = delta { return true }; return false }
    var deltaValue: Int? { if case .some(.some(let d)) = delta { return d }; return nil }

    private enum CodingKeys: String, CodingKey { case spId, position, matchCount, goalsPerMatch, passPct, usage, delta, name, season, positionLabel, imageUrl }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spId = try c.decode(Int.self, forKey: .spId); position = try c.decode(Int.self, forKey: .position)
        matchCount = try c.decode(Int.self, forKey: .matchCount)
        goalsPerMatch = try c.decode(Double.self, forKey: .goalsPerMatch); passPct = try c.decode(Double.self, forKey: .passPct)
        usage = try c.decodeIfPresent(Int.self, forKey: .usage)
        delta = try c.decodeNullable(Int.self, forKey: .delta)
        name = try c.decode(String.self, forKey: .name); season = try c.decode(String.self, forKey: .season)
        positionLabel = try c.decode(String.self, forKey: .positionLabel); imageUrl = try c.decode(String.self, forKey: .imageUrl)
    }
}
struct PlayerDetail: Decodable {
    let spid: Int
    let name: String
    let season: String
    let pid: Int?
    let seasons: [SeasonVariant]
    let imageUrl: String
    let ranker: RankerMeta
    struct RankerMeta: Decodable { let date: String?; let totalMatches: Int; let positions: [PositionStat] }
    struct PositionStat: Decodable, Identifiable {
        let position: Int; let matchCount: Int; let goal: Double; let assist: Double; let shoot: Double; let effectiveShoot: Double
        let passSuccess: Double; let passTry: Double; let dribbleSuccess: Double; let dribbleTry: Double; let tackle: Double; let block: Double
        let positionLabel: String; let passRate: Int?; let dribbleRate: Int?
        let playstyle: Playstyle?
        var id: Int { position }
        struct Playstyle: Decodable { let label: String; let emoji: String; let tone: String }
    }
}
struct SeasonVariant: Decodable, Identifiable, Hashable { let spid: Int; let season: String; var id: Int { spid } }
struct PlayerHit: Decodable, Identifiable, Hashable {
    let spid: Int; let pid: Int; let name: String; let season: String; let seasons: [SeasonVariant]
    var id: Int { spid }
}
struct PlayerSearchResponse: Decodable { let players: [PlayerHit] }

// MARK: - home

struct HomeResponse: Decodable {
    let demoNickname: String?
    let liveSearches: [String]
    let mover: Mover?
    let pickDate: String?
    let videos: [YtVideo]
    let posts: [HomePost]
}
struct YtVideo: Decodable, Identifiable { let id: String; let title: String; let channel: String; let url: String; let thumb: String }
struct HomePost: Decodable, Identifiable {
    let id: String; let type: String; let title: String; let createdAt: String; let commentCount: Int?
    enum CodingKeys: String, CodingKey { case id, type, title, createdAt = "created_at", commentCount = "comment_count" }
}

// MARK: - community

struct PostTypeInfo: Decodable, Identifiable, Hashable {
    let type: String; let label: String; let emoji: String; let blurb: String; let accent: String
    let fields: [String]; let template: String; let bodyLabel: String; let bodyPlaceholder: String
    /// 커뮤니티 v2(옵셔널) — 말머리 태그용 짧은 이름. 구 서버면 nil → 앱 내 매핑.
    var shortLabel: String? = nil
    var id: String { type }
}
struct PostAuthor: Decodable, Hashable { let id: String; let nickname: String; let verifiedNickname: String?; let isOperator: Bool? }
struct Post: Decodable, Identifiable, Hashable {
    let id: String
    let authorId: String
    let type: String
    let title: String
    let body: String
    let region: String?
    let positions: [String]
    let contact: String?
    let squadId: String?
    let meta: [String: String]
    let status: String
    let createdAt: String
    let commentCount: Int?
    let author: PostAuthor
    let typeLabel: String
    let typeEmoji: String
    let preview: String?
    let metaRows: [MetaRow]?
    let squadB: String?
    /// 커뮤니티 v2(옵셔널) — 0023 마이그레이션 전 서버에는 키가 없다. nil 이면 조회·추천 UI 를 숨긴다.
    var viewCount: Int? = nil
    var likeCount: Int? = nil
    /// 로그인 + 0023 후에만 온다
    var viewerLiked: Bool? = nil
    enum CodingKeys: String, CodingKey {
        case id, type, title, body, region, positions, contact, meta, status, author, typeLabel, typeEmoji, preview, metaRows, squadB, viewerLiked
        case authorId = "author_id", squadId = "squad_id", createdAt = "created_at", commentCount = "comment_count"
        case viewCount = "view_count", likeCount = "like_count"
    }
    struct MetaRow: Decodable, Hashable, Identifiable { let key: String; let label: String; let value: String; var id: String { key } }

    /// 첨부(내 전적 카드 · VS 카드) — 서버가 meta 에 평평한 문자열 키로 저장한다(웹 lib/community/attach.ts).
    /// 구버전 앱은 이 키들을 모르고 지나가며, 서버는 metaRows 에서 이 키들을 뺀다.
    var attach: PostAttach? { PostAttach(meta: meta) }
}

/// 글 첨부 — 구단주명만 저장하고, 카드는 화면이 열 때마다 최신 전적으로 그린다(라이브).
struct PostAttach: Codable, Hashable {
    enum Kind: String, Codable { case record, versus }
    var kind: Kind
    var me: String
    var with: String?
    var mode: Int = 50

    init(kind: Kind, me: String, with: String? = nil, mode: Int = 50) {
        self.kind = kind; self.me = me; self.with = with; self.mode = mode
    }
    init?(meta: [String: String]) {
        guard let k = meta["attach_kind"].flatMap(Kind.init(rawValue:)),
              let me = meta["attach_me"], !me.isEmpty else { return nil }
        let w = meta["attach_with"].flatMap { $0.isEmpty ? nil : $0 }
        if k == .versus && w == nil { return nil }
        self.init(kind: k, me: me, with: k == .versus ? w : nil, mode: meta["attach_mode"].flatMap(Int.init) ?? 50)
    }
    /// 구단주명 정리 — 서버 `cleanNickname`(웹 lib/community/attach.ts)과 같은 규칙:
    /// NFC → 앞뒤 공백 제거 → 길이 1~20(UTF-16 단위, JS `length` 와 같게) → 공백·경로/쿼리 문자·제어문자 거부.
    static func clean(_ raw: String) -> String? {
        let s = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(s.utf16.count) else { return nil }
        if s.range(of: #"[\s/\\?#%&<>"'`]"#, options: .regularExpression) != nil { return nil }
        if s.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) { return nil }
        return s
    }
    /// 같은 구단주인가 — 서버 `sameNickname` 과 같게 정리된 값끼리 대소문자만 무시.
    static func sameNickname(_ a: String, _ b: String) -> Bool { a.lowercased() == b.lowercased() }

    /// 작성 요청 본문(`attach`)
    var json: [String: Any] {
        var j: [String: Any] = ["kind": kind.rawValue, "me": me, "mode": mode]
        if let with { j["with"] = with }
        return j
    }
    /// meta 저장 형식(목 서버용)
    var metaEntries: [String: String] {
        var m = ["attach_kind": kind.rawValue, "attach_me": me, "attach_mode": String(mode)]
        if let with { m["attach_with"] = with }
        return m
    }
}
struct PostListResponse: Decodable {
    let page: Int; let totalPages: Int; let types: [PostTypeInfo]; let posts: [Post]
    /// 커뮤니티 v2(옵셔널) — 서버가 실제 적용한 정렬(new|hot|comments). 키가 없으면 구 서버(sort·types 쿼리 미지원).
    var sort: String? = nil
    /// 커뮤니티 v2(옵셔널) — 1페이지 "지금 뜨는 글" TOP 3. 0023 미적용이면 키가 없다.
    var hot: [Post]? = nil
}
struct Comment: Decodable, Identifiable {
    let id: String; let postId: String; let authorId: String; let body: String; let squadId: String?; let createdAt: String
    let author: CommentAuthor; let isOwn: Bool
    /// 커뮤니티 v2(옵셔널) — 1단 답글의 원 댓글 id · 좋아요. 0023 전 서버엔 키가 없다.
    var parentId: String? = nil
    var likeCount: Int? = nil
    var viewerLiked: Bool? = nil
    enum CodingKeys: String, CodingKey {
        case id, body, author, isOwn, viewerLiked
        case postId = "post_id", authorId = "author_id", squadId = "squad_id", createdAt = "created_at"
        case parentId = "parent_id", likeCount = "like_count"
    }
    struct CommentAuthor: Decodable { let id: String; let nickname: String; let isOperator: Bool?; var verifiedNickname: String? = nil }
}
struct PostDetailResponse: Decodable {
    let post: Post
    let comments: [Comment]
    let viewer: Viewer
    struct Viewer: Decodable { let loggedIn: Bool; let isOwner: Bool; let canComment: Bool }
}
/// 서버(`/api/community/battle`)는 소문자 `{"a":0,"b":0}` 로 내려준다 — 웹 BattleVote 도 같은 키를 읽는다.
/// 대문자 "A"/"B" 로 매핑하면 옵셔널이라 디코딩은 성공하지만 값이 항상 nil 이 된다(표 수가 늘 0).
/// v2 서버는 `mine` 으로 내 표를 돌려준다. 구 서버(키 없음)에선 앱이 로컬(CommunityPrefs)에 기억한다.
struct BattleVotes: Decodable {
    let a: Int?; let b: Int?
    /// 커뮤니티 v2(옵셔널) — 로그인 또는 ?voter= 일 때 내가 고른 쪽 "A"/"B", 아니면 null.
    var mine: String? = nil
}
/// 좋아요 토글 응답 — `POST/DELETE /api/community/{posts|comments}/:id/like`
struct LikeResponse: Decodable {
    let ok: Bool?; let liked: Bool
    var likeCount: Int? = nil
    enum CodingKeys: String, CodingKey { case ok, liked; case likeCount = "like_count" }
}

// MARK: - squad

struct SquadSlotModel: Codable, Identifiable, Hashable {
    let slotId: String
    let spid: Int
    let name: String
    var season: String?
    var x: Double?
    var y: Double?
    /// 표시용 사진 — 같은 선수(pid)의 다른 시즌 카드 사진, 또는 pid 자체(기본 사진). 없으면 카드(spid) 사진.
    var imageSpid: Int? = nil
    /// 이 자리만의 포지션 라벨(드래그로 옮겨 바뀐 경우). nil 이면 포메이션 기본 라벨.
    var pos: String? = nil
    var displaySpid: Int { imageSpid ?? spid }
    var id: String { slotId }
}
struct Squad: Decodable, Identifiable {
    let id: String
    let name: String
    let formation: String
    let slots: [SquadSlotModel]
    let teamTag: String?
    let createdAt: String?
}
struct PresetResponse: Decodable { let formation: String; let name: String; let teamTag: String; let slots: [SquadSlotModel] }
struct FromUserResponse: Decodable {
    let nickname: String; let formation: String; let matchDate: String?; let players: [ImportedPlayer]
    struct ImportedPlayer: Decodable, Identifiable { let spid: Int; let name: String; let pos: String; let season: String; var id: Int { spid } }
}

// MARK: - profile / me

struct ProfileResponse: Decodable {
    let profile: MyProfile?
    let posts: [MyPost]
    let squads: [MySquad]
    let snapshot: Snapshot?
    let snapshots: [FormPoint]
    struct MyProfile: Decodable { let id: String?; let nickname: String?; let verifiedNickname: String?; let verifiedOuid: String?
        enum CodingKeys: String, CodingKey { case id, nickname; case verifiedNickname = "verified_nickname", verifiedOuid = "verified_ouid" } }
    struct MyPost: Decodable, Identifiable { let id: String; let type: String; let title: String; let createdAt: String
        enum CodingKeys: String, CodingKey { case id, type, title; case createdAt = "created_at" } }
    struct MySquad: Decodable, Identifiable { let id: String; let name: String; let formation: String }
    struct Snapshot: Decodable { let winRate: Int; let avgRating: Double; let played: Int; let deltaWinRate: Int?; let deltaRating: Double?; let prevDate: String? }
    struct FormPoint: Decodable, Identifiable { let date: String; let winRate: Int; let avgRating: Double; var id: String { date } }
}
struct NotificationsResponse: Decodable {
    let total: Int
    let items: [Item]
    struct Item: Decodable, Identifiable { let postId: String; let title: String; let count: Int; var id: String { postId } }
}
