import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import Observation

/// AdMob 초기화 + UMP 동의 + ATT. 회의 결정: 첫 실행 3일간 배너 0, ATT 는 첫 검색 결과를 본 뒤에만 요청.
@Observable
@MainActor
final class AdsManager {
    static let shared = AdsManager()
    private(set) var ready = false
    private var consentFlowDone = false

    private static let firstLaunchKey = "fcscope.firstLaunchAt"
    /// 동의 절차(UMP → ATT)를 한 번이라도 끝낸 기기인가. 끝낸 기기는 다음 실행부터 앱이 뜨자마자 SDK 를 시작한다 —
    /// 그러지 않으면 실행마다 전적 화면을 한 번 열기 전까지 배너·전면 광고가 전혀 준비되지 않는다.
    private static let consentAskedKey = "fcscope.ads.consentAsked"
    private static let gracePeriod: TimeInterval = 3 * 86_400

    private init() {
        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.firstLaunchKey)
        }
    }

    /// 배너를 보여도 되는가.
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
        // SDK 시작은 유예 기간과 무관하게 한다 — 전면광고(검색 3회차부터)는 유예 기간을 따르지 않는다.
        // 배너 노출 여부는 여전히 canShowAds(설치 3일 유예)가 결정한다.
        guard AppConfig.admobConfigured, !consentFlowDone else { return }
        consentFlowDone = true
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            if ConsentInformation.shared.formStatus == .available, let root = Self.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: root)
            }
        } catch {
            // 동의 정보 갱신 실패 — 아래 canRequestAds 가 지난 세션에 받아 둔 동의 상태로 판단한다.
        }
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        UserDefaults.standard.set(true, forKey: Self.consentAskedKey)
        // EEA 에서 동의를 받지 못했으면 광고를 요청하지 않는다(AdMob 정책). 그 밖의 지역은 항상 true.
        guard ConsentInformation.shared.canRequestAds else { return }
        await start()
    }

    /// 앱이 활성화될 때 호출 — 예전에 동의 절차를 끝낸 기기만 SDK 를 바로 시작한다.
    /// 새로 설치한 기기는 가치를 보기 전에 시스템 팝업이 뜨지 않도록 첫 전적 화면을 기다린다.
    func resumeIfConsentAsked() async {
        guard UserDefaults.standard.bool(forKey: Self.consentAskedKey) else { return }
        await requestConsentIfNeeded()
    }

    private func start() async {
        guard !ready else { return }
        await MobileAds.shared.start()
        ready = true
        await preloadInterstitial()
    }

    // MARK: 전면 광고

    private var interstitial: InterstitialAd?
    private var interstitialLoadedAt: Date?
    private var loadingInterstitial = false
    private var loadFailures = 0
    private var presenting: InterstitialDelegate?
    /// 받아 둔 전면 광고는 1시간이 지나면 표시할 수 없다(Google). 여유를 두고 55분에 버린다.
    private static let interstitialTTL: TimeInterval = 55 * 60

    private var interstitialFresh: Bool {
        guard interstitial != nil, let at = interstitialLoadedAt else { return false }
        return Date().timeIntervalSince(at) < Self.interstitialTTL
    }

    /// 미리 받아 둔다 — 검색 버튼을 누른 순간 받기 시작하면 사용자가 로딩을 기다리게 된다.
    /// 실패하면 30초부터 두 배씩(최대 10분) 늦춰 몇 번만 다시 시도한다 — 광고 없음이 계속되면 요청을 아낀다.
    func preloadInterstitial() async {
        guard ready, !loadingInterstitial, !interstitialFresh, let unit = AppConfig.interstitialAdUnit else { return }
        interstitial = nil
        interstitialLoadedAt = nil
        loadingInterstitial = true
        do {
            interstitial = try await InterstitialAd.load(with: unit, request: Request())
            interstitialLoadedAt = Date()
            loadFailures = 0
            loadingInterstitial = false
        } catch {
            loadingInterstitial = false
            loadFailures += 1
            guard loadFailures <= 5 else { return }
            let delay = min(600, 30 * pow(2, Double(loadFailures - 1)))
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await self.preloadInterstitial()
            }
        }
    }

    /// 전면 광고를 띄우고 **닫힐 때까지 기다린다**. 준비된 광고가 없으면 즉시 돌아온다 —
    /// 광고 로딩 실패가 검색을 막으면 안 된다. 다음 광고 로딩도 기다리지 않는다.
    func showInterstitialIfReady() async {
        guard interstitialFresh, let ad = interstitial,
              let root = Self.topViewController(), root.view.window != nil, !root.isBeingDismissed else {
            Analytics.shared.track(.interstitial, ["result": "not_ready"])
            loadFailures = 0   // 사용자가 다시 광고 대상이 됐으니 멈춰 있던 재시도를 새로 시작한다
            Task { await preloadInterstitial() }
            return
        }
        Analytics.shared.track(.interstitial, ["result": "shown"])
        SearchGate.markAdShown()
        interstitial = nil
        interstitialLoadedAt = nil
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let delegate = InterstitialDelegate { cont.resume() }
            presenting = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(from: root)
        }
        presenting = nil
        Task { await preloadInterstitial() }
    }

    private static func topViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }
}

/// 전면 광고가 닫히거나 표시에 실패하면 한 번만 알린다.
final class InterstitialDelegate: NSObject, FullScreenContentDelegate {
    private var done: (() -> Void)?
    init(_ done: @escaping () -> Void) { self.done = done }
    private func finish() { done?(); done = nil }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { finish() }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { finish() }
}

/// 구단주명 검색 횟수 제한 — 하루 2회까지 무료, 3회차부터 전면 광고 후 검색.
///
/// - 날짜는 KST 기준으로 매일 초기화한다(평생 2회면 이틀째부터 모든 검색이 광고가 된다).
/// - 연속으로 광고를 보지 않도록 직전 광고 후 90초 안의 검색은 광고 없이 통과시킨다.
///   Google 정책도 전면 광고의 과도한 빈도를 금지하고, 몇 초 간격으로 광고가 뜨면 이탈한다.
/// - 대상은 **검색창에 직접 입력한 검색**뿐이다. 즐겨찾기·최근 검색·칩을 누르는 건 탐색이라 제외.
@MainActor
enum SearchGate {
    static let freePerDay = 2
    static let cooldown: TimeInterval = 90

    private static let dayKey = "fcscope.search.day"
    private static let countKey = "fcscope.search.count"
    private static let lastAdKey = "fcscope.search.lastAdAt"

    /// 이번 검색 전에 광고를 보여야 하는가. 호출하면 검색 1회로 센다.
    static func shouldShowAd(now: Date = Date()) -> Bool {
        let d = UserDefaults.standard
        let today = dayString(now)
        if d.string(forKey: dayKey) != today {
            d.set(today, forKey: dayKey)
            d.set(0, forKey: countKey)
        }
        let count = d.integer(forKey: countKey) + 1
        d.set(count, forKey: countKey)
        guard count > freePerDay else { return false }
        return now.timeIntervalSince1970 - d.double(forKey: lastAdKey) >= cooldown
    }

    /// 광고를 **실제로 띄웠을 때만** 쿨다운을 시작한다 — 준비가 안 돼 못 띄운 검색이 90초 무료 구간을 만들면 안 된다.
    static func markAdShown(now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastAdKey)
    }

    private static func dayString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// 적응형 배너 (메타·커뮤니티 하단 전용 — 전적 화면엔 두지 않는다)
struct BannerAdView: UIViewRepresentable {
    let width: CGFloat
    /// 받은 광고의 실제 높이. 실패하면 0 — 고정 60pt 는 큰 적응형 배너를 잘랐고, 광고가 없을 때 빈 칸을 남겼다.
    @Binding var height: CGFloat?
    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeUIView(context: Context) -> BannerView {
        let v = BannerView(adSize: largeAnchoredAdaptiveBanner(width: width))
        v.adUnitID = AppConfig.bannerAdUnit ?? ""
        v.rootViewController = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        v.delegate = context.coordinator
        v.load(Request())
        return v
    }
    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        private let height: Binding<CGFloat?>
        init(height: Binding<CGFloat?>) { self.height = height }
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            let h = max(bannerView.adSize.size.height, bannerView.frame.height)
            height.wrappedValue = h > 0 ? h : nil
        }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) { height.wrappedValue = 0 }
    }
}

/// 배너 자리 — 광고 크리에이티브는 대부분 흰 배경이라, 다크 화면 끝에 그냥 놓으면
/// "본문 카드"처럼 보이거나 탭바에 눌린 흰 덩어리로 보인다. 라벨 + 카드로 감싸 광고임을 분명히 하고
/// 탭바와 간격을 둔다. 광고가 없으면(height == 0) 자리까지 접는다.
struct AdSlot: View {
    @State private var ads = AdsManager.shared
    /// nil = 로딩 중(예상 높이만큼 자리 확보), 0 = 광고 없음(접힘)
    @State private var height: CGFloat?
    var body: some View {
        if ads.ready && ads.canShowAds, height != 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("광고").fcFont(10, weight: .semibold).foregroundStyle(FC.muted)
                GeometryReader { geo in
                    BannerAdView(width: geo.size.width - 16, height: $height)
                }
                .frame(height: height ?? 60)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(8)
            .background(FC.surface2, in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 4)
            .padding(.bottom, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("광고")
        }
    }
}
