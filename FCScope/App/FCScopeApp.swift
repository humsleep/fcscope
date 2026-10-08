import SwiftUI
import GoogleMobileAds
import UserNotifications

@main
struct FCScopeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(FC.tint)
                .onOpenURL { url in
                    // 위젯은 widgetURL 에 src=widget 을 붙여 보낸다(FCScopeWidgets.swift). 로그인 콜백은 진입으로 세지 않는다.
                    let fromWidget = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "src" && $0.value == "widget" } == true
                    if url.host != "auth" { Analytics.shared.trackOpen(fromWidget ? .widget : .link, url: url) }
                    router.handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        Analytics.shared.trackOpen(.link, url: url)
                        router.handle(url: url)
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        AdsManager.shared.noteActive(newVisit: Analytics.shared.appBecameActive())
                        Task { await AdsManager.shared.resumeIfConsentAsked() }
                        ReviewPrompt.resumePending()
                    case .background: Analytics.shared.appWentBackground()
                    default: break
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register()
        CrashReporter.shared.start()
        // 토큰은 바뀔 수 있고, 서버에는 등록 시점의 구단주명이 저장된다 — 실행마다 다시 등록한다(Apple 권장).
        Task { @MainActor in await PushManager.shared.registerIfAuthorized() }
        #if DEBUG
        CardDebugExport.runIfRequested()
        CommunityDebugLaunch.prepare()
        #endif
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(token: deviceToken)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let link = response.notification.request.content.userInfo["link"] as? String, let url = URL(string: link) {
            await MainActor.run {
                Analytics.shared.trackOpen(.push, url: url)
                AppRouter.shared.handle(url: url)
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
