import Foundation
import UIKit

/// 익명 사용 기록 — "무엇이 공유되고, 누가 돌아오는가"를 알기 위한 최소 측정.
///
/// 보내지 않는 것: 계정·이메일·구단주명·광고 식별자(IDFA)·기기 식별자(IDFV).
/// 설치 때 만든 무작위 UUID 하나로만 같은 기기의 재방문을 묶는다(앱을 지우면 사라진다).
/// 다른 회사의 앱·웹 데이터와 연결하지 않으므로 ATT(추적 동의) 대상이 아니다.
///
/// 이벤트는 모았다가 20개가 차거나 앱이 백그라운드로 갈 때 한 번에 보낸다 —
/// 탭마다 네트워크를 쓰면 배터리와 서버 쓰기가 낭비된다. 전송 실패는 조용히 넘긴다
/// (측정 때문에 앱이 느려지거나 에러가 보이면 안 된다).
///
/// 유실 방지: 큐는 Caches 의 JSON 파일로 남겨 다음 실행에 이어 보내고(백그라운드 진입·전송 후 저장),
/// 백그라운드 전송은 beginBackgroundTask 로 보호한다. 오프라인·5xx·429 는 다시 보내고 그 밖의 4xx 만 버린다.
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
    /// 요청 1회 상한 — 서버(lib/analytics/events.ts MAX_EVENTS)가 20개 넘는 부분을 **조용히 잘라낸다**.
    private static let batchSize = 20
    private static let maxQueue = 200
    /// 재시도 가능한 실패 뒤 자동 전송(20개 도달)을 쉬는 시간. 백그라운드 전송은 이를 무시한다.
    private static let retryDelay: TimeInterval = 60
    private static let iso = ISO8601DateFormatter()

    private let installId: String
    private var queue: [[String: Any]] = []
    /// 전송 중인 배치 — 응답 전에 앱이 종료돼도 파일에 함께 남긴다.
    private var inFlight: [[String: Any]] = []
    private var flushing = false
    private var retryAt: Date?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("fcscope-analytics-queue.json")
    }

    private init() {
        if let id = UserDefaults.standard.string(forKey: Self.installKey) {
            installId = id
        } else {
            let id = UUID().uuidString.lowercased()
            UserDefaults.standard.set(id, forKey: Self.installKey)
            installId = id
        }
        // 지난 실행에서 못 보낸 이벤트 복원
        if let url = Self.fileURL, let data = try? Data(contentsOf: url),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            queue = Array(saved.suffix(Self.maxQueue))
        }
    }

    /// 통계는 appstore 만 센다. 개발·TestFlight 기록이 섞이면 초기 수치가 부풀려진다.
    /// 광고 단위와 같은 판정(AppConfig.distribution)을 쓴다 — Xcode·Ad-hoc 으로 설치한 Release 도 appstore 가 아니다.
    private var env: String { AppConfig.distribution.rawValue }

    func track(_ event: Event, _ props: [String: Any] = [:]) {
        queue.append(["name": event.rawValue, "props": props, "at": Self.iso.string(from: Date())])
        trim()
        if queue.count >= Self.batchSize, retryAt.map({ Date() >= $0 }) ?? true { Task { await flush() } }
    }

    /// 앱이 화면에 올라올 때 호출. 콜드 스타트이거나 30분 넘게 떠나 있었으면 방문 1회.
    /// 새 방문이면 true — 광고 동의(ATT) 시점을 세션 수로 미루는 데도 같은 기준을 쓴다.
    @discardableResult
    func appBecameActive() -> Bool {
        let last = UserDefaults.standard.double(forKey: Self.lastActiveKey)
        let newVisit = last == 0 || Date().timeIntervalSince1970 - last > Self.sessionGap
        if newVisit { track(.appOpen) }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastActiveKey)
        return newVisit
    }

    /// 백그라운드로 갈 때 — 마지막 활동 시각을 남기고, 큐를 파일에 저장한 뒤 쌓인 이벤트를 모두 보낸다.
    /// 백그라운드 태스크 없이 Task 만 띄우면 앱이 곧바로 정지돼 전송이 끊긴다.
    func appWentBackground() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastActiveKey)
        persist()
        guard !queue.isEmpty, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "fcscope.analytics.flush") { [weak self] in
            // 시간 초과 — 전송 중인 배치까지 파일에 남기고 태스크를 닫는다.
            MainActor.assumeIsolated { self?.persist(); self?.endBackgroundTask() }
        }
        Task {
            await flush(drain: true)
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// 한 배치(최대 20개)를 보낸다. `drain` 이면 큐가 빌 때까지(또는 재시도 대상 실패까지) 이어 보낸다.
    func flush(drain: Bool = false) async {
        guard !flushing, !queue.isEmpty else { return }
        flushing = true
        defer { flushing = false; persist() }
        repeat {
            let batch = Array(queue.prefix(Self.batchSize))
            queue.removeFirst(batch.count)
            inFlight = batch
            let payload: [String: Any] = ["installId": installId, "appVersion": AppConfig.appVersion, "env": env, "events": batch]
            var retry: TimeInterval?
            do {
                let _: OkBody = try await APIClient.shared.send("/api/v1/events", method: "POST", json: payload, auth: false)
            } catch APIError.network {
                retry = Self.retryDelay   // 오프라인 — 다음 기회에 다시 보낸다
            } catch APIError.server(_, _, let status, let after) where status >= 500 || status == 429 {
                retry = after.map(TimeInterval.init) ?? Self.retryDelay   // 서버 장애·과부하 — 일시적이다
            } catch {
                // 그 밖의 4xx·해석 실패 — 같은 배치를 다시 보내도 결과가 같으니 버린다
            }
            inFlight = []
            if let retry {
                queue.insert(contentsOf: batch, at: 0)
                trim()
                retryAt = Date().addingTimeInterval(retry)
                return
            }
            retryAt = nil
        } while drain && !queue.isEmpty
    }

    /// 상한을 넘으면 가장 오래된 것부터 버린다.
    private func trim() {
        if queue.count > Self.maxQueue { queue.removeFirst(queue.count - Self.maxQueue) }
    }

    /// 큐(+전송 중 배치)를 Caches 에 저장. 비었으면 파일을 지운다.
    private func persist() {
        guard let url = Self.fileURL else { return }
        let all = inFlight + queue
        if all.isEmpty { try? FileManager.default.removeItem(at: url); return }
        guard JSONSerialization.isValidJSONObject(all), let data = try? JSONSerialization.data(withJSONObject: all) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 공유 카드 파일명("fcscope-weekly-보엠")에서 카드 종류를 뽑는다.
    static func cardType(_ filename: String) -> String {
        let parts = filename.split(separator: "-")
        return parts.count > 1 ? String(parts[1]) : "card"
    }
}
