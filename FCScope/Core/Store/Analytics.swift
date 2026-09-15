import Foundation

/// 익명 사용 기록 — "무엇이 공유되고, 누가 돌아오는가"를 알기 위한 최소 측정.
///
/// 보내지 않는 것: 계정·이메일·구단주명·광고 식별자(IDFA)·기기 식별자(IDFV).
/// 설치 때 만든 무작위 UUID 하나로만 같은 기기의 재방문을 묶는다(앱을 지우면 사라진다).
/// 다른 회사의 앱·웹 데이터와 연결하지 않으므로 ATT(추적 동의) 대상이 아니다.
///
/// 이벤트는 모았다가 20개가 차거나 앱이 백그라운드로 갈 때 한 번에 보낸다 —
/// 탭마다 네트워크를 쓰면 배터리와 서버 쓰기가 낭비된다. 전송 실패는 조용히 넘긴다
/// (측정 때문에 앱이 느려지거나 에러가 보이면 안 된다).
@MainActor
final class Analytics {
    static let shared = Analytics()

    enum Event: String {
        case appOpen = "app_open"
        case search
        case recordView = "record_view"
        case sectionView = "section_view"
        case matchView = "match_view"
        case cardCreate = "card_create"
        case cardShare = "card_share"
        case interstitial
        case favoriteAdd = "favorite_add"
        case accountDelete = "account_delete"
    }

    private static let installKey = "fcscope.analytics.installId"
    private static let lastActiveKey = "fcscope.analytics.lastActiveAt"
    /// 백그라운드에 이만큼 있다가 돌아오면 새 방문으로 센다(재방문율 계산의 기준).
    private static let sessionGap: TimeInterval = 30 * 60
    private static let batchSize = 20
    private static let maxQueue = 200
    private static let iso = ISO8601DateFormatter()

    private let installId: String
    private var queue: [[String: Any]] = []
    private var flushing = false

    private init() {
        if let id = UserDefaults.standard.string(forKey: Self.installKey) {
            installId = id
        } else {
            let id = UUID().uuidString.lowercased()
            UserDefaults.standard.set(id, forKey: Self.installKey)
            installId = id
        }
    }

    /// 통계는 appstore 만 센다. 개발·TestFlight 기록이 섞이면 초기 수치가 부풀려진다.
    private var env: String { AppConfig.distribution.rawValue }

    func track(_ event: Event, _ props: [String: Any] = [:]) {
        queue.append(["name": event.rawValue, "props": props, "at": Self.iso.string(from: Date())])
        if queue.count > Self.maxQueue { queue.removeFirst(queue.count - Self.maxQueue) }
        if queue.count >= Self.batchSize { Task { await flush() } }
    }

    /// 앱이 화면에 올라올 때 호출. 콜드 스타트이거나 30분 넘게 떠나 있었으면 방문 1회.
    func appBecameActive() {
        let last = UserDefaults.standard.double(forKey: Self.lastActiveKey)
        if last == 0 || Date().timeIntervalSince1970 - last > Self.sessionGap {
            track(.appOpen)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastActiveKey)
    }

    /// 백그라운드로 갈 때 — 마지막 활동 시각을 남기고 쌓인 이벤트를 보낸다.
    func appWentBackground() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastActiveKey)
        Task { await flush() }
    }

    func flush() async {
        guard !flushing, !queue.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        let batch = Array(queue.prefix(50))
        queue.removeFirst(batch.count)
        let payload: [String: Any] = ["installId": installId, "appVersion": AppConfig.appVersion, "env": env, "events": batch]
        do {
            let _: OkBody = try await APIClient.shared.send("/api/v1/events", method: "POST", json: payload, auth: false)
        } catch APIError.network {
            // 오프라인 — 다음 기회에 다시 보낸다(상한은 track 이 지킨다)
            queue.insert(contentsOf: batch, at: 0)
        } catch {
            // 서버가 거부(4xx 등) — 같은 배치를 다시 보내도 결과가 같으니 버린다
        }
    }

    /// 공유 카드 파일명("fcscope-weekly-보엠")에서 카드 종류를 뽑는다.
    static func cardType(_ filename: String) -> String {
        let parts = filename.split(separator: "-")
        return parts.count > 1 ? String(parts[1]) : "card"
    }
}
