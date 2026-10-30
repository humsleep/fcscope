import StoreKit
import UIKit

/// App Store 리뷰 요청 — 기분 좋은 순간에만 묻는다(docs/STRATEGY-2026-11.md Phase 0).
///
/// 트리거: 카드 공유 완료 직후 · 3번째 방문 · 주간 성적표 푸시로 들어와 승률이 오른 내 전적을 봤을 때.
/// 3번째 방문·푸시 진입은 바로 묻지 않고 **경기가 있는 전적이 실제로 뜬 순간**까지 미룬다.
/// 에러가 난 직후(최근 10초)와 빈 결과에서는 절대 묻지 않는다. 한 앱 버전에 한 번만(시스템 상한은 연 3회).
@MainActor
enum ReviewPrompt {
    enum Trigger: String { case share, visit3 = "visit_3", weeklyUp = "weekly_up" }

    private static let visitsKey = "fcscope.review.visits"
    private static let askedVersionKey = "fcscope.review.askedVersion"
    private static let errorQuiet: TimeInterval = 10
    private static var lastErrorAt: Date?
    /// 콘텐츠가 뜰 때 물을 트리거(3번째 방문·주간 푸시)
    private static var pending: Trigger?
    /// 앱으로 돌아올 때 물을 트리거(인스타그램으로 나갔다 온 공유)
    private static var onReturn: Trigger?

    /// 화면에 올라올 때마다. newVisit 은 Analytics 의 방문 기준(30분)과 같다.
    static func appBecameActive(newVisit: Bool) {
        if let t = onReturn { onReturn = nil; ask(t) }
        guard newVisit else { return }
        let n = UserDefaults.standard.integer(forKey: visitsKey) + 1
        UserDefaults.standard.set(n, forKey: visitsKey)
        if n == 3 { pending = .visit3 }
    }

    static func openedFromWeeklyPush() { pending = .weeklyUp }
    static func askOnReturn(_ t: Trigger) { onReturn = t }

    /// API 실패마다(APIClient). 직후의 리뷰 요청을 막는다.
    static func noteError() { lastErrorAt = Date() }

    /// 전적이 경기와 함께 떴을 때(RecordView). 빈 결과에서는 부르지 않는다.
    static func recordShown(isMine: Bool, winRateUp: Bool) {
        guard let t = pending else { return }
        if t == .weeklyUp {
            guard isMine else { return }
            pending = nil
            if winRateUp { ask(t) }
        } else {
            pending = nil
            ask(t)
        }
    }

    static func ask(_ t: Trigger) {
        guard UserDefaults.standard.string(forKey: askedVersionKey) != AppConfig.appVersion, !recentError else { return }
        Task {
            // 공유 시트·전면광고가 닫히고 화면이 자리 잡은 뒤에 — 그 사이 에러가 나면 접는다.
            try? await Task.sleep(for: .seconds(1.5))
            guard !recentError,
                  let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }
            UserDefaults.standard.set(AppConfig.appVersion, forKey: askedVersionKey)
            AppStore.requestReview(in: scene)
            Analytics.shared.track(.reviewPrompt, ["trigger": t.rawValue])
        }
    }

    private static var recentError: Bool { lastErrorAt.map { Date().timeIntervalSince($0) < errorQuiet } ?? false }
}
