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
                .tint(FC.accent)
                .onOpenURL { url in router.handle(url: url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handle(url: url) }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: Analytics.shared.appBecameActive()
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
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(token: deviceToken)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let link = response.notification.request.content.userInfo["link"] as? String, let url = URL(string: link) {
            await MainActor.run { AppRouter.shared.handle(url: url) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
