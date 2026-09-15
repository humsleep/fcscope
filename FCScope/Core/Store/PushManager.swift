import Foundation
import UserNotifications
import UIKit
import BackgroundTasks

/// APNs 토큰 등록 → 서버(/api/v1/devices). 주간 리캡·메타 요약·내 글 댓글 푸시는 서버 크론이 보낸다.
@MainActor
final class PushManager {
    static let shared = PushManager()
    private init() {}

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        let nick = LocalPrefs.shared.myNickname
        Task {
            try? await APIClient.shared.sendNoContent("/api/v1/devices", method: "POST", json: [
                "token": hex, "platform": "ios", "nickname": nick as Any, "appVersion": AppConfig.appVersion,
                "favorites": LocalPrefs.shared.favorites,
            ])
        }
    }
}

/// 백그라운드 갱신 — 즐겨찾기·내 구단주의 폼 스냅샷을 미리 받아 홈 델타 배지·위젯을 최신으로.
enum BackgroundRefresh {
    static let id = "xyz.fcscope.app.refresh"
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule()
            let work = Task { await refreshAll(); task.setTaskCompleted(success: true) }
            task.expirationHandler = { work.cancel() }
        }
        schedule()
    }
    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: id)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
    @MainActor
    static func refreshAll() async {
        let prefs = LocalPrefs.shared
        let nicks = ([prefs.myNickname].compactMap { $0 } + prefs.favorites).prefix(4)
        for n in nicks {
            if let o: UserOverview = try? await APIClient.shared.get("/api/v1/user/\(n.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? n)", auth: false) {
                prefs.recordForm(nick: o.profile.nickname, winRate: o.summary.winRate, score: o.score, streak: o.perf.currentStreak)
            }
        }
        // 위젯 갱신은 recordForm 이 내 구단주 값이 바뀐 경우에만 한다(급상승 위젯은 자체 6시간 타임라인).
    }
}

/// 위젯 타임라인 갱신 — 종류별로만 다시 그린다(reloadAllTimelines 는 모든 위젯의 갱신 예산을 쓴다).
enum WidgetBridge {
    /// FCScopeWidgets.swift 의 StaticConfiguration kind 와 같아야 한다.
    enum Kind: String { case myForm = "MyFormWidget", mover = "MoverWidget" }
    static func reload(_ kind: Kind) {
        #if canImport(WidgetKit)
        WidgetKitReloader.reload(kind: kind.rawValue)
        #endif
    }
}
