import Foundation

/**
 시즌 아이콘 — "PTG", "25 UCL", "WB" 같은 약어는 게임을 오래 한 사람도 바로 못 알아본다.
 게임 안에서는 시즌마다 아이콘으로 보여 주므로, 같은 공식 아이콘을 쓴다.

 출처: 넥슨 공개 메타 `seasonid.json` (API 키 불필요, 153개 시즌, 아이콘은 30×24 PNG ≈ 5KB).
 선수 이미지와 같은 이유로 앱은 CDN 을 직접 부른다(서버 프록시 대역폭 0).
 시즌이 추가되면 메타에 자동으로 들어오므로 앱 업데이트 없이 따라간다.
 */
@MainActor
final class SeasonIcons {
    static let shared = SeasonIcons()

    private var map: [Int: URL] = [:]
    private var fetchedAt: Date?
    private var inFlight: Task<Void, Never>?

    private static let metaURL = URL(string: "https://open.api.nexon.com/static/fconline/meta/seasonid.json")!
    /// 시즌은 몇 주에 한 번 추가된다 — 7일이면 충분하고, 실패해도 옛 캐시를 계속 쓴다.
    private static let ttl: TimeInterval = 7 * 86_400
    private static var cacheFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("season-icons.json")
    }

    private init() { loadFromDisk() }

    /// 이미 아는 시즌이면 즉시 URL. 모르면 nil — 호출부가 `ensureLoaded()` 뒤에 다시 묻는다.
    func url(forSpid spid: Int) -> URL? { map[NexonCDN.seasonId(of: spid)] }

    func ensureLoaded() async {
        let stale = fetchedAt.map { Date().timeIntervalSince($0) > Self.ttl } ?? true
        guard map.isEmpty || stale else { return }
        if let inFlight {            // 화면에 배지가 수십 개여도 요청은 한 번만
            await inFlight.value
            return
        }
        let task = Task { await fetch() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private struct MetaRow: Decodable { let seasonId: Int; let seasonImg: String }

    private func fetch() async {
        var req = URLRequest(url: Self.metaURL)
        req.timeoutInterval = 10
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([MetaRow].self, from: data)
        else { return }   // 실패하면 배지는 기존 텍스트로 보인다
        var next: [Int: URL] = [:]
        for row in rows where !row.seasonImg.isEmpty {
            if let url = URL(string: row.seasonImg) { next[row.seasonId] = url }
        }
        guard !next.isEmpty else { return }
        map = next
        fetchedAt = Date()
        saveToDisk()
    }

    // MARK: 디스크 캐시 (앱을 다시 켜도 첫 화면부터 아이콘이 보이게)

    private struct Disk: Codable { var at: Date; var map: [String: String] }

    private func loadFromDisk() {
        guard let file = Self.cacheFile, let data = try? Data(contentsOf: file),
              let disk = try? JSONDecoder().decode(Disk.self, from: data) else { return }
        fetchedAt = disk.at
        map = disk.map.reduce(into: [:]) { acc, kv in
            if let id = Int(kv.key), let url = URL(string: kv.value) { acc[id] = url }
        }
    }

    private func saveToDisk() {
        guard let file = Self.cacheFile, let at = fetchedAt else { return }
        let disk = Disk(at: at, map: map.reduce(into: [:]) { $0[String($1.key)] = $1.value.absoluteString })
        try? JSONEncoder().encode(disk).write(to: file, options: .atomic)
    }
}
