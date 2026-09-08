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
    var id: Int { spId }
    struct RankerCompare: Decodable { let goal: Double; let passRate: Int; let matchCount: Int }
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
    var id: String { "\(spId)-\(position)" }
    var isNew: Bool { if case .some(.none) = delta { return true }; return false }
    var deltaValue: Int? { if case .some(.some(let d)) = delta { return d }; return nil }
}
struct MetaLine: Decodable, Identifiable { let line: String; let title: String; let rows: [PickRow]; var id: String { line } }
struct PickRow: Decodable, Identifiable {
    let spId: Int; let position: Int; let matchCount: Int; let goalsPerMatch: Double; let passPct: Double
    let delta: Int??
    let name: String; let season: String; let positionLabel: String; let imageUrl: String
    var id: String { "\(spId)-\(position)" }
    var isNew: Bool { if case .some(.none) = delta { return true }; return false }
    var deltaValue: Int? { if case .some(.some(let d)) = delta { return d }; return nil }
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
    var id: String { type }
}
struct PostAuthor: Decodable, Hashable { let id: String; let nickname: String; let verifiedNickname: String? }
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
    enum CodingKeys: String, CodingKey {
        case id, type, title, body, region, positions, contact, meta, status, author, typeLabel, typeEmoji, preview, metaRows, squadB
        case authorId = "author_id", squadId = "squad_id", createdAt = "created_at", commentCount = "comment_count"
    }
    struct MetaRow: Decodable, Hashable, Identifiable { let key: String; let label: String; let value: String; var id: String { key } }
}
struct PostListResponse: Decodable { let page: Int; let totalPages: Int; let types: [PostTypeInfo]; let posts: [Post] }
struct Comment: Decodable, Identifiable {
    let id: String; let postId: String; let authorId: String; let body: String; let squadId: String?; let createdAt: String
    let author: CommentAuthor; let isOwn: Bool
    enum CodingKeys: String, CodingKey { case id, body, author, isOwn; case postId = "post_id", authorId = "author_id", squadId = "squad_id", createdAt = "created_at" }
    struct CommentAuthor: Decodable { let id: String; let nickname: String }
}
struct PostDetailResponse: Decodable {
    let post: Post
    let comments: [Comment]
    let viewer: Viewer
    struct Viewer: Decodable { let loggedIn: Bool; let isOwner: Bool; let canComment: Bool }
}
struct BattleVotes: Decodable { let a: Int?; let b: Int?; let mine: String? ; enum CodingKeys: String, CodingKey { case a = "A", b = "B", mine } }

// MARK: - squad

struct SquadSlotModel: Codable, Identifiable, Hashable {
    let slotId: String
    let spid: Int
    let name: String
    var season: String?
    var x: Double?
    var y: Double?
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
