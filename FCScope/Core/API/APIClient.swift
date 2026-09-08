import Foundation

/// 서버 오류 코드 (lib/api/v1.ts ApiError.code 와 1:1)
enum APIError: LocalizedError {
    case server(code: String, message: String, status: Int, retryAfter: Int?)
    case network(Error)
    case decoding(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .server(_, let m, _, _): return m
        case .network: return "네트워크 연결을 확인해 주세요."
        case .decoding: return "응답을 해석하지 못했어요. 앱을 업데이트해 주세요."
        case .unauthorized: return "로그인이 필요해요."
        }
    }
    var code: String? { if case .server(let c, _, _, _) = self { return c }; return nil }
    var isUserNotFound: Bool { code == "user_not_found" }
}

private struct ServerErrorBody: Decodable { let error: String; let code: String? }

/// /api/v1 + 기존 /api 호출. Bearer 는 AuthManager 세션에서.
final class APIClient {
    static let shared = APIClient()
    private let session: URLSession
    let decoder: JSONDecoder

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 65 // 콜드 조회(넥슨 30경기) 대비
        cfg.requestCachePolicy = .useProtocolCachePolicy
        cfg.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 100 << 20)
        cfg.httpAdditionalHeaders = ["User-Agent": "FCScopeApp/\(AppConfig.appVersion) (native; iOS)"]
        session = URLSession(configuration: cfg)
        decoder = JSONDecoder()
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], auth: Bool = true) async throws -> T {
        try await request(path, method: "GET", query: query, body: nil, auth: auth)
    }

    // MARK: - stale-while-revalidate (디스크 캐시)

    private func cacheKey(_ path: String, _ query: [String: String]) -> String {
        let q = query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return q.isEmpty ? path : "\(path)?\(q)"
    }

    /// 디스크에 있는 마지막 응답. `isFresh` 가 true 면 네트워크를 생략해도 된다.
    func cachedValue<T: Decodable>(_ path: String, query: [String: String] = [:]) async -> (value: T, isFresh: Bool)? {
        guard let entry = await ResponseCache.shared.read(cacheKey(path, query)),
              let decoded = try? decoder.decode(T.self, from: entry.data)
        else { return nil }
        return (decoded, entry.isFresh)
    }

    /// 네트워크 GET + 성공 시 디스크 캐시 갱신.
    func getAndCache<T: Decodable>(_ path: String, query: [String: String] = [:], auth: Bool = true) async throws -> T {
        let data = try await requestData(path, method: "GET", query: query, body: nil, auth: auth)
        await ResponseCache.shared.write(cacheKey(path, query), data: data)
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decoding(error) }
    }

    func send<T: Decodable>(_ path: String, method: String, json: [String: Any]? = nil, auth: Bool = true) async throws -> T {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await request(path, method: method, query: [:], body: body, auth: auth)
    }

    /// 응답 본문이 필요 없는 요청
    func sendNoContent(_ path: String, method: String, json: [String: Any]? = nil) async throws {
        let _: EmptyBody = try await send(path, method: method, json: json)
    }

    func request<T: Decodable>(_ path: String, method: String, query: [String: String], body: Data?, auth: Bool) async throws -> T {
        if T.self == EmptyBody.self {
            _ = try await requestData(path, method: method, query: query, body: body, auth: auth)
            return EmptyBody() as! T
        }
        let data = try await requestData(path, method: method, query: query, body: body, auth: auth)
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decoding(error) }
    }

    private func requestData(_ path: String, method: String, query: [String: String], body: Data?, auth: Bool) async throws -> Data {
        var comps = URLComponents(url: AppConfig.absolute(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = (comps.queryItems ?? []) + query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        req.httpBody = body
        if auth, let token = await AuthManager.shared.accessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw APIError.network(error) }
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 { throw APIError.unauthorized }
        if status >= 400 {
            let parsed = try? decoder.decode(ServerErrorBody.self, from: data)
            let retry = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw APIError.server(code: parsed?.code ?? (status == 429 ? "rate_limited" : "upstream"),
                                  message: parsed?.error ?? defaultMessage(status), status: status, retryAfter: retry)
        }
        return data
    }

    func fetchData(_ path: String) async throws -> Data {
        var req = URLRequest(url: AppConfig.absolute(path))
        req.timeoutInterval = 60
        do {
            let (data, resp) = try await session.data(for: req)
            if let s = (resp as? HTTPURLResponse)?.statusCode, s >= 400 { throw APIError.server(code: "upstream", message: defaultMessage(s), status: s, retryAfter: nil) }
            return data
        } catch let e as APIError { throw e } catch { throw APIError.network(error) }
    }

    private func defaultMessage(_ status: Int) -> String {
        switch status {
        case 404: return "찾을 수 없어요."
        case 429: return "요청이 많아요. 잠시 후 다시 시도해 주세요."
        case 503: return "서비스 점검 중이에요."
        default: return "데이터를 불러오지 못했어요."
        }
    }
}

struct EmptyBody: Decodable { init() {} ; init(from decoder: Decoder) throws {} }
struct OkBody: Decodable { let ok: Bool? }
struct IdBody: Decodable { let id: String }
