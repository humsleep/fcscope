import StoreKit
import UIKit

/// 앱 내 리뷰 요청 — 출시 직후 리뷰 0개가 제품 페이지 전환을 막고 있다(docs/store-v2/ASO-PLAN.md §5 #2).
///
/// 언제: 만족한 순간에만 묻는다.
/// - 공유 카드를 공유한 뒤 앱으로 돌아왔을 때(인스타로 넘어간 동안 요청하면 iOS 가 조용히 버린다)
/// - 설치 2일 이상 · 세 번째 방문부터, 기록이 있는 전적을 연 뒤
///
/// 얼마나: 같은 버전에서는 한 번, 시도 사이 최소 120일. iOS 자체 한도(365일 3회)는 그 위에 따로 걸린다.
/// 첫 실행·온보딩·전면광고 직후에는 어느 조건도 성립하지 않는다.
@MainActor
enum ReviewPrompt {
    private static let lastAtKey = "fcscope.review.lastAt"
    private static let lastVersionKey = "fcscope.review.lastVersion"
    private static let pendingKey = "fcscope.review.pendingShare"
    /// AdsManager.firstLaunchKey 와 같은 값(설치 시각).
    private static let firstLaunchKey = "fcscope.firstLaunchAt"
    private static let minGap: TimeInterval = 120 * 86_400
    private static let minInstallAge: TimeInterval = 2 * 86_400
    private static let minSessions = 3

    /// 공유 시트가 닫힐 때. 앱이 활성 상태가 아니면 다음 활성화 때 묻는다.
    static func shareCompleted() {
        guard eligible else { return }
        UserDefaults.standard.set(true, forKey: pendingKey)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            resumePending()
        }
    }

    /// scenePhase .active 마다 호출 — 공유하러 다른 앱에 갔다가 돌아온 경우.
    static func resumePending() {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return }
        guard eligible else { UserDefaults.standard.set(false, forKey: pendingKey); return }
        guard UIApplication.shared.applicationState == .active else { return }
        UserDefaults.standard.set(false, forKey: pendingKey)
        request(trigger: "share")
    }

    /// 기록이 있는 전적을 처음 그렸을 때.
    static func recordViewed() {
        let d = UserDefaults.standard
        let installed = d.double(forKey: firstLaunchKey)
        guard eligible, installed > 0,
              Date().timeIntervalSince1970 - installed >= minInstallAge,
              AdsManager.shared.sessionCount >= minSessions else { return }
        Task {
            // 화면이 다 그려진 뒤에 띄운다
            try? await Task.sleep(for: .seconds(2))
            guard eligible, UIApplication.shared.applicationState == .active else { return }
            request(trigger: "revisit")
        }
    }

    private static var eligible: Bool {
        let d = UserDefaults.standard
        if d.string(forKey: lastVersionKey) == AppConfig.appVersion { return false }
        return Date().timeIntervalSince1970 - d.double(forKey: lastAtKey) >= minGap
    }

    private static func request(trigger: String) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: lastAtKey)
        d.set(AppConfig.appVersion, forKey: lastVersionKey)
        Analytics.shared.track(.reviewPrompt, ["trigger": trigger])
        AppStore.requestReview(in: scene)
    }
}
