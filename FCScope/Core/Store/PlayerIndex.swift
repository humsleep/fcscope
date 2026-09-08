import Foundation

/**
 최적화: 선수 인덱스를 앱에 내장.

 서버는 넥슨 `spid.json`(6.5MB, 88k행)을 인스턴스마다 메모리에 상주시키고
 `/api/players/search` 요청마다 전체를 필터링한다(CPU 소모 + 콜드 인스턴스 지연).

 앱이 압축 인덱스(약 1.8MB, IPA 내부 gzip 592KB)를 내장하면
 검색이 오프라인·즉시가 되고 서버 왕복·CPU·메모리가 모두 0 이 된다.

 신규 시즌 카드는 앱 업데이트를 기다리지 않도록 주 1회 `/api/v1/player-index` 로 갱신한다.
 (번들 스냅샷보다 최신일 때만 내려받아 Application Support 에 저장)
 */
@MainActor
final class PlayerIndex {
    static let shared = PlayerIndex()

    private(set) var date: String = ""
    private var seasons: [Int: String] = [:]
    private var players: [Entry] = []
    private var loaded = false

    struct Entry {
        let pid: Int
        let name: String
        /// 최신순 시즌 ID
        let seasonIds: [Int]
        /// 검색용 소문자 이름
        let key: String
    }

    private struct Payload: Decodable {
        let v: Int
        let date: String
        let seasons: [String: String]
        /// [pid, 이름, [seasonId...]]
        let players: [PlayerRow]
    }

    /// 혼합 타입 배열 디코딩 (숫자, 문자열, 숫자배열)
    private struct PlayerRow: Decodable {
        let pid: Int
        let name: String
        let seasonIds: [Int]
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            pid = try c.decode(Int.self)
            name = try c.decode(String.self)
            seasonIds = try c.decode([Int].self)
        }
    }

    private var cacheURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("players-index.json")
    }

    /// 번들 스냅샷 또는 (더 최신이면) 내려받은 인덱스를 로드. 최초 1회만 파싱.
    func load() {
        guard !loaded else { return }
        loaded = true
        let bundleData = Bundle.main.url(forResource: "players", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        let cachedData = cacheURL.flatMap { try? Data(contentsOf: $0) }
        // 캐시가 번들보다 최신일 때만 채택
        let candidates = [cachedData, bundleData].compactMap { $0 }
        var best: Payload?
        for data in candidates {
            guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { continue }
            if best == nil || p.date > best!.date { best = p }
        }
        guard let payload = best else { return }
        date = payload.date
        seasons = Dictionary(uniqueKeysWithValues: payload.seasons.compactMap { k, v in Int(k).map { ($0, v) } })
        players = payload.players.map {
            Entry(pid: $0.pid, name: $0.name, seasonIds: $0.seasonIds, key: $0.name.lowercased())
        }
    }

    var isReady: Bool { !players.isEmpty }
    var count: Int { players.count }

    func seasonName(_ seasonId: Int) -> String { seasons[seasonId] ?? "S\(seasonId)" }
    func seasonName(spid: Int) -> String { seasonName(NexonCDN.seasonId(of: spid)) }

    /// 로컬 검색 — 접두 일치 우선, 그다음 부분 일치. 서버 `searchPlayers` 와 동일한 정렬 의도.
    func search(_ raw: String, limit: Int = 24) -> [PlayerHit] {
        load()
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2, !players.isEmpty else { return [] }
        var prefix: [Entry] = []
        var contains: [Entry] = []
        for e in players {
            if e.key.hasPrefix(q) { prefix.append(e) }
            else if e.key.contains(q) { contains.append(e) }
            if prefix.count >= limit { break }
        }
        let merged = (prefix + contains).prefix(limit)
        return merged.map { hit(from: $0) }
    }

    func player(spid: Int) -> PlayerHit? {
        load()
        let pid = NexonCDN.pid(of: spid)
        guard let e = players.first(where: { $0.pid == pid }) else { return nil }
        return hit(from: e)
    }

    private func hit(from e: Entry) -> PlayerHit {
        let spids = e.seasonIds.map { $0 * 1_000_000 + e.pid }
        let rep = spids.first ?? e.pid
        return PlayerHit(
            spid: rep,
            pid: e.pid,
            name: e.name,
            season: seasonName(spid: rep),
            seasons: spids.prefix(16).map { SeasonVariant(spid: $0, season: seasonName(spid: $0)) }
        )
    }

    // MARK: 주 1회 갱신 (신규 시즌 카드 반영)

    private static let checkedKey = "fcscope.playerIndexCheckedAt"

    func refreshIfStale() async {
        load()
        let last = UserDefaults.standard.double(forKey: Self.checkedKey)
        guard Date().timeIntervalSince1970 - last > 7 * 86_400 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.checkedKey)
        guard let (data, resp) = try? await URLSession.shared.data(from: AppConfig.absolute("/api/v1/player-index")),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let p = try? JSONDecoder().decode(Payload.self, from: data),
              p.date > date
        else { return }
        if let url = cacheURL { try? data.write(to: url, options: .atomic) }
        date = p.date
        seasons = Dictionary(uniqueKeysWithValues: p.seasons.compactMap { k, v in Int(k).map { ($0, v) } })
        players = p.players.map { Entry(pid: $0.pid, name: $0.name, seasonIds: $0.seasonIds, key: $0.name.lowercased()) }
    }
}
