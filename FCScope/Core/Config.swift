import Foundation

/// 앱 전역 설정. 넥슨 API 키·Supabase service_role 등 **서버 시크릿은 앱에 절대 두지 않는다.**
/// 앱이 갖는 값은 공개해도 되는 것뿐이다: Supabase URL·anon 키, AdMob 단위 ID.
enum AppConfig {
    static let productionBase = URL(string: "https://www.fcscope.xyz")!

    /// 백엔드 주소. 개발 빌드에서만 설정 화면으로 바꿀 수 있다(릴리스에서는 고정).
    static var baseURL: URL {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "fcscope.baseURL"), let u = URL(string: s) { return u }
        #endif
        return productionBase
    }

    /// Info.plist 문자열. **빈 문자열은 미설정으로 취급한다.**
    /// (`as? String ?? 기본값` 은 빈 문자열이 nil 이 아니라서 기본값으로 넘어가지 않는다 —
    ///  과거 `URL(string: "")!` 강제 언래핑으로 실행 즉시 크래시할 수 있던 자리)
    private static func plist(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Supabase (공개 값만)

    static let supabaseURL: URL? = plist("FCSupabaseURL").flatMap { URL(string: $0) }
    static let supabaseAnonKey: String? = plist("FCSupabaseAnonKey")
    /// 둘 다 유효할 때만 로그인 UI를 노출한다. 미설정이어도 앱의 나머지는 정상 동작.
    static var supabaseConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }

    // MARK: 고정 값

    static let bundleId = "xyz.fcscope.app"
    static let oauthCallback = URL(string: "fcscope://auth/callback")!
    static let contactEmail = "boheme88@naver.com"
    static let termsURL = URL(string: "https://www.fcscope.xyz/terms")!
    static let privacyURL = URL(string: "https://www.fcscope.xyz/privacy")!
    static var appVersion: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "-" }
    /// 공유 카드 푸터에 찍히는 도메인 (웹 SITE_HOST 와 동일)
    static var shareHost: String { productionBase.host ?? "fcscope.xyz" }

    // MARK: AdMob

    /// 구글이 배포하는 테스트 ID 접두사 — 릴리스 빌드에 남아 있으면 광고를 띄우지 않는다.
    private static let googleTestPrefix = "ca-app-pub-3940256099942544"
    private static let googleTestBanner = "ca-app-pub-3940256099942544/2934735716"

    /// TestFlight 로 설치된 빌드인가. 영수증 파일 이름이 배포판과 다르다.
    ///
    /// TestFlight 는 Release 빌드라 그냥 두면 **실제 광고가 나간다**. 개발자가 테스트하며 누른
    /// 광고는 무효 트래픽으로 집계되고, 반복되면 AdMob 계정이 정지된다(복구가 까다롭다).
    /// 그래서 TestFlight 에서는 App Store 빌드와 같은 코드를 돌리되 광고만 테스트 단위로 바꾼다.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// 실제 광고를 내보내도 되는 빌드인가 — App Store 배포판만.
    private static var servesRealAds: Bool {
        #if DEBUG
        return false
        #else
        return !isTestFlight
        #endif
    }

    /// 배너 광고 단위. nil 이면 광고를 아예 초기화하지 않는다.
    static var bannerAdUnit: String? {
        guard servesRealAds else { return googleTestBanner }
        guard let id = plist("FCAdMobBannerUnit"), !id.hasPrefix(googleTestPrefix) else { return nil }
        return id
    }

    /// Info.plist 의 AdMob 앱 ID가 실제 계정 값인지. 테스트 값이면 릴리스에서 광고를 끈다
    /// (수익 0 + AdMob 정책 위반 방지).
    static var admobConfigured: Bool {
        guard servesRealAds else { return true }   // Debug·TestFlight 는 테스트 광고로 동작
        guard let appId = plist("GADApplicationIdentifier") else { return false }
        return !appId.hasPrefix(googleTestPrefix) && bannerAdUnit != nil
    }

    static func absolute(_ path: String) -> URL {
        if path.hasPrefix("http") { return URL(string: path) ?? baseURL }
        return URL(string: path, relativeTo: baseURL)!.absoluteURL
    }
}
