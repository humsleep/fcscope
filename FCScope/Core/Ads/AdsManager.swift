import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import Observation

/// AdMob 초기화 + UMP 동의 + ATT. 회의 결정: 첫 실행 3일간 광고 0, ATT 는 첫 검색 결과를 본 뒤에만 요청.
@Observable
@MainActor
final class AdsManager {
    static let shared = AdsManager()
    private(set) var ready = false
    private var consentFlowDone = false

    private static let firstLaunchKey = "fcscope.firstLaunchAt"
    private static let gracePeriod: TimeInterval = 3 * 86_400

    private init() {
        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.firstLaunchKey)
        }
    }

    /// 광고를 보여도 되는가.
    /// 조건: 실제 AdMob 계정 값이 설정됨(테스트 ID 아님) + 설치 후 3일 경과(회의 결정).
    var canShowAds: Bool {
        guard AppConfig.admobConfigured, AppConfig.bannerAdUnit != nil else { return false }
        #if DEBUG
        return true
        #else
        let first = UserDefaults.standard.double(forKey: Self.firstLaunchKey)
        return Date().timeIntervalSince1970 - first > Self.gracePeriod
        #endif
    }

    /// 첫 유의미 화면(전적 결과) 이후 호출 — UMP(EEA 만 폼) → ATT → SDK 시작
    func requestConsentIfNeeded() async {
        guard canShowAds, !consentFlowDone else { return }
        consentFlowDone = true
        let params = RequestParameters()
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: params)
            if ConsentInformation.shared.formStatus == .available,
               let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first {
                try await ConsentForm.loadAndPresentIfRequired(from: root)
            }
        } catch {
            // 동의 정보 실패 → 비맞춤 광고로 진행
        }
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await start()
    }

    private func start() async {
        guard !ready else { return }
        await MobileAds.shared.start()
        ready = true
    }
}

/// 적응형 배너 (메타·커뮤니티 하단 전용 — 전적 화면엔 두지 않는다)
struct BannerAdView: UIViewRepresentable {
    let width: CGFloat
    func makeUIView(context: Context) -> BannerView {
        let v = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        v.adUnitID = AppConfig.bannerAdUnit ?? ""
        v.rootViewController = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        v.load(Request())
        return v
    }
    func updateUIView(_ uiView: BannerView, context: Context) {}
}

struct AdSlot: View {
    @State private var ads = AdsManager.shared
    var body: some View {
        if ads.ready && ads.canShowAds {
            GeometryReader { geo in
                BannerAdView(width: geo.size.width)
            }
            .frame(height: 60)
        }
    }
}
