import Foundation

/**
 최적화: API 응답 디스크 캐시 (stale-while-revalidate).

 전적 조회 1회는 서버에서 넥슨 API 를 최대 36번 순차 호출하고
 `match_cache` 에 최대 30행(1~2.5MB)을 쓴다. 같은 구단주를 다시 볼 때마다 이 비용이 반복된다.

 앱이 마지막 응답을 디스크에 두면 재방문 시 **즉시 화면을 그리고**(체감 지연 0)
 백그라운드에서만 갱신한다. 서버 요청 수와 Supabase 쓰기가 함께 줄어든다.
 */
actor ResponseCache {
    static let shared = ResponseCache()

    private let dir: URL?
    /// 신선하다고 보는 기간 — 이 안이면 네트워크를 아예 치지 않는다.
    static let freshWindow: TimeInterval = 120
    /// 이 기간이 지난 캐시는 화면에 쓰지 않는다(너무 오래된 전적 표시 방지).
    static let maxAge: TimeInterval = 3 * 86_400

    private init() {
        dir = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("api", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }

    private func fileURL(_ key: String) -> URL? {
        guard let dir else { return nil }
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(key.hashValue)
        return dir.appendingPathComponent(safe).appendingPathExtension("json")
    }

    struct Entry {
        let data: Data
        let age: TimeInterval
        var isFresh: Bool { age < ResponseCache.freshWindow }
    }

    func read(_ key: String) -> Entry? {
        guard let url = fileURL(key),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              let data = try? Data(contentsOf: url)
        else { return nil }
        let age = Date().timeIntervalSince(modified)
        guard age < Self.maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return Entry(data: data, age: age)
    }

    func write(_ key: String, data: Data) {
        guard let url = fileURL(key) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// 캐시 총 용량(설정 화면 표시용)
    func sizeBytes() -> Int {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
