import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import Observation
import WebKit

/// AdMob 초기화 + UMP 동의 + ATT. ATT 는 온보딩을 마치고 메인 탭이 처음 뜰 때 요청. 배너는 설치 직후부터(2026-09-20 운영자 결정 — 3일 유예 폐지).
/// ⚠️ 2026-09-30 심사 거절(2.1, iPad Air): ATT 를 "첫 전적 결과 이후"로 미뤘더니 검색을 하지 않은 심사자가 팝업을 끝내 못 봤다.
/// 가치를 먼저 보여 주려고 다시 늦추지 말 것 — 심사자가 앱을 열자마자 볼 수 있어야 한다.
@Observable
@MainActor
final class AdsManager {
    static let shared = AdsManager()
    private(set) var ready = false
    /// SDK 시작이 결정된 순간(동의 절차 끝) true — 이때부터 광고 자리를 미리 잡는다(준비 완료 시 콘텐츠가 밀리지 않게).
    /// SDK 를 시작하지 못하는 경로(첫 검색 전·EEA 동의 거부)에서는 false 라 빈 카드가 남지 않는다.
    private(set) var starting = false
    private var consentFlowDone = false

    private static let firstLaunchKey = "fcscope.firstLaunchAt"
    /// 동의 절차(UMP → ATT)를 한 번이라도 끝낸 기기인가. 끝낸 기기는 다음 실행부터 앱이 뜨자마자 SDK 를 시작한다 —
    /// 그러지 않으면 실행마다 전적 화면을 한 번 열기 전까지 배너·전면 광고가 전혀 준비되지 않는다.
    private static let consentAskedKey = "fcscope.ads.consentAsked"

    private init() {
        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.firstLaunchKey)
        }
    }

    /// 배너를 보여도 되는가.
    /// 조건: 실제 AdMob 계정 값이 설정됨(테스트 ID 아님). 설치 후 유예 기간은 없다.
    var canShowAds: Bool {
        AppConfig.admobConfigured && AppConfig.bannerAdUnit != nil
    }

    /// UMP(EEA 만 폼) → ATT → SDK 시작. 한 실행에 한 번만 돈다.
    func requestConsentIfNeeded() async {
        // SDK 시작은 유예 기간과 무관하게 한다 — 전면광고(검색 3회차부터)는 유예 기간을 따르지 않는다.
        // 배너 노출 여부는 canShowAds 가 결정한다.
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

    // MARK: 세션 카운터

    private static let sessionCountKey = "fcscope.sessionCount"
    /// 지금까지의 앱 사용 세션 수(이번 세션 포함). 첫 실행 또는 30분 넘게 떠났다 돌아오면 +1.
    var sessionCount: Int { UserDefaults.standard.integer(forKey: Self.sessionCountKey) }

    /// scenePhase .active 마다 호출. newVisit 은 Analytics 의 방문 판정(30분 간격)과 같다.
    /// 콜드 스타트만으로는 세지 않는다 — 온보딩 중에 앱을 껐다 켜기만 해도 "두 번째 세션"이 돼 첫 사용에 ATT 가 떴다(시뮬레이터 실측).
    func noteActive(newVisit: Bool) {
        guard newVisit else { return }
        UserDefaults.standard.set(sessionCount + 1, forKey: Self.sessionCountKey)
    }

    /// 메인 탭이 처음 뜰 때 호출(온보딩 이후). 앱이 활성 상태가 아니면 ATT 요청은 시스템이 조용히 무시하므로
    /// 활성 상태에서만 절차를 시작한다 — 비활성일 때 consentFlowDone 을 켜 버리면 이번 실행 내내 팝업이 다시 뜨지 않는다.
    func requestConsentOnLaunch() async {
        guard UIApplication.shared.applicationState == .active else { return }
        await requestConsentIfNeeded()
    }

    /// 앱이 활성화될 때 호출 — 예전에 동의 절차를 끝낸 기기만 SDK 를 바로 시작한다.
    /// 새로 설치한 기기는 가치를 보기 전에 시스템 팝업이 뜨지 않도록 첫 전적 화면을 기다린다.
    func resumeIfConsentAsked() async {
        guard UserDefaults.standard.bool(forKey: Self.consentAskedKey) else { return }
        // 아직 ATT 에 답하지 않았으면(팝업 중 앱이 종료된 경우 등) 여기서 묻지 않는다 — 실행 인트로 위에 팝업이 겹친다.
        // 그 경우는 인트로가 끝난 뒤 requestConsentOnLaunch 가 묻는다.
        guard ATTrackingManager.trackingAuthorizationStatus != .notDetermined else { return }
        await requestConsentIfNeeded()
    }

    private func start() async {
        guard !ready else { return }
        starting = true
        await MobileAds.shared.start()
        ready = true
        // 메인 탭 첫 슬롯을 미리 요청 — 응답이 오기 전에 사용자가 그 자리에 닿으면 빈 예약 카드만 보였다(QA 5R P1-3)
        if canShowAds { BannerStore.shared.preloadFirstScreens() }
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

/// 구단주명 검색 전면광고 — 하루 첫 검색은 무료, 두 번째 검색부터는 **직전 전면광고 후 90초가 지났을 때만**.
/// 하루 상한은 없다(2026-10-04 운영자 결정 — 0초 쿨다운은 상대 닉을 연달아 칠 때마다 광고가 떠
/// 유저 패널 5라운드 1순위 불만이었다).
///
/// - 날짜는 KST 기준으로 매일 초기화한다.
/// - 대상은 **검색창에 직접 입력한 검색**뿐이다. 즐겨찾기·최근 검색·칩을 누르는 건 탐색이라 제외.
@MainActor
enum SearchGate {
    /// 하루 무료 검색 수. 광고가 아직 로드되지 않았으면 그 검색은 광고 없이 지나간다(검색을 막지 않음).
    static let freePerDay = 1
    /// 전면광고 사이 최소 간격(초)
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

// MARK: - 배너 (docs/ads/AD-PLACEMENT.md)
//
// 한 줄 규칙: 보일 자리는 정확한 크기로 미리 잡고(R1), 안 보일 자리는 받은 뒤 편다(R4).
// 보고 있는 콘텐츠는 어떤 경우에도 움직이지 않는다(R2·R6).

/// 배너 크기 — 예약 슬롯은 폭만으로 높이가 정해지는 크기만 쓴다(예약 높이 = 실제 높이).
enum BannerFormat: Equatable {
    /// 큰 앵커 적응형 크기(폭 결정적) — 예약 슬롯(컨테이너 A)
    case anchored
    /// 인라인 적응형 + 최대 높이 — 깊은 슬롯(300×250급 소재 가능)
    case inline(maxHeight: CGFloat)
    /// 320×50 고정 — 커뮤니티 행(컨테이너 B)
    case banner320x50

    func adSize(width: CGFloat) -> AdSize {
        switch self {
        case .anchored: return largeAnchoredAdaptiveBanner(width: width)
        // 인라인은 폭 300pt 로 요청한다 — 컨테이너 전체 폭(약 360~390pt)으로 요청하면 300×250 소재가 웹뷰 안에서
        // 가운데 놓이고 양옆이 검은 기둥으로 칠해졌다(SDK 뷰 배경은 투명 — 검정은 소재 HTML 의 레터박스, 디자인 5R M1).
        // 300 폭이면 소재와 컨테이너가 같아 띠가 없다. 뷰는 카드 가운데 둔다.
        case .inline(let h): return inlineAdaptiveBanner(width: min(width, 300), maxHeight: h)
        case .banner320x50: return AdSizeBanner
        }
    }
    /// 예약 높이(받기 전 자리). inline 은 응답마다 높이가 달라 예약하지 않는다.
    func reservedHeight(width: CGFloat) -> CGFloat? {
        switch self {
        case .anchored: return largeAnchoredAdaptiveBanner(width: width).size.height
        case .banner320x50: return 50
        case .inline: return nil
        }
    }
}

/// 세션 단위 배너 상태 — R3: 연속 2회 무응답이면 이번 세션의 예약 슬롯은 접기 모드로.
@Observable
@MainActor
final class BannerSession {
    static let shared = BannerSession()
    private(set) var consecutiveNoFill = 0
    var reserveDisabled: Bool { consecutiveNoFill >= 2 }
    func noteFill() { consecutiveNoFill = 0 }
    func noteNoFill() { consecutiveNoFill += 1 }
}

/// 슬롯 이벤트 기록 — 배치별 노출을 나중에 비교하기 위해(광고 단위는 아직 하나, 운영자가 나중에 나눈다).
/// event: slot(화면 방문당 1회) · fill · nofill · timeout · visible(채워진 채 화면에 보인 첫 순간, 방문당 1회)
/// · impression(SDK) · collapse(실제로 접혀 사라질 때만). 이벤트 이름 `ad_slot` 은 서버 허용 목록(웹 lib/analytics/events.ts).
@MainActor
enum AdEvents {
    static func log(_ placement: String, _ event: String, format: BannerFormat? = nil, reserved: Bool? = nil, extra: [String: Any] = [:]) {
        var p: [String: Any] = ["placement": placement, "event": event]
        if let format { p["format"] = { switch format { case .anchored: "anchored"; case .inline: "inline"; case .banner320x50: "320x50" } }() }
        if let reserved { p["reserved"] = reserved }
        for (k, v) in extra { p[k] = v }
        #if DEBUG
        print("[ad] \(Date().timeIntervalSince1970) \(placement) \(event) \(extra)")
        #endif
        Analytics.shared.track(.adSlot, p)
    }
}

// MARK: - 배너 저장소
//
// 배너 요청을 SwiftUI 뷰 수명과 떼어 놓는다(QA 5R P1-1·P1-2). 예전엔 슬롯 뷰가 다시 만들어지면(LazyVStack·
// 데이터 갱신·탭 전환) 그 안의 BannerView 가 같이 사라져 요청이 끝나지 않았고, 타이머 Task 취소가 곧바로
// "시간 초과"로 처리돼 슬롯이 접혔다. 이제 배치(key)마다 BannerView 하나를 저장소가 들고 있고, 슬롯 뷰는
// 그것을 빌려 붙일 뿐이다. 뷰가 몇 번 다시 만들어져도 요청은 한 번, 결과는 그대로 남는다.

@Observable
@MainActor
final class BannerEntry: NSObject, BannerViewDelegate {
    enum State: Equatable { case loading, filled(CGSize), failed }
    let key: String
    let placement: String
    let format: BannerFormat
    let requestWidth: CGFloat
    private(set) var state: State = .loading
    let requestedAt = Date()
    @ObservationIgnored let view: BannerView
    /// 슬롯 뷰가 마지막으로 화면에 붙어 있던 시각 — 10초 넘게 비면 다음 등장을 새 방문으로 센다(slot·visible 중복 방지)
    @ObservationIgnored var lastHosted: Date?
    @ObservationIgnored var loggedVisibleThisVisit = false

    init(key: String, placement: String, format: BannerFormat, width: CGFloat) {
        self.key = key; self.placement = placement; self.format = format
        self.requestWidth = format == .banner320x50 ? 320 : (format.isInline ? min(width, 300) : width)
        // 인라인은 폭 300pt 로 요청한다 — 카드 전체 폭(약 360~390pt)으로 요청하면 300×250 소재 양옆을
        // 소재 HTML 이 검은 레터박스로 칠했다(디자인 5R M1). 300 폭이면 소재와 컨테이너가 같다.
        view = BannerView(adSize: format.adSize(width: requestWidth))
        super.init()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.adUnitID = AppConfig.bannerAdUnit ?? ""
        view.delegate = self
    }

    func load() {
        view.rootViewController = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        view.load(Request())
        // 20초 안에 응답이 없으면 실패로 본다(시뮬레이터 실측 응답 8~19초 · QA 5R P1-3)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled, self.state == .loading else { return }
            self.state = .failed
            AdEvents.log(self.placement, "timeout")
        }
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        let size = bannerView.adSize.size
        Self.clearWebBackgrounds(bannerView)
        state = .filled(CGSize(width: max(1, size.width), height: max(1, size.height)))
        BannerSession.shared.noteFill()
        AdEvents.log(placement, "fill", extra: ["height": Int(size.height), "ms": Int(Date().timeIntervalSince(requestedAt) * 1000)])
    }
    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        guard state == .loading else { return }
        state = .failed
        BannerSession.shared.noteNoFill()
        AdEvents.log(placement, "nofill", extra: ["code": (error as NSError).code, "msg": String(error.localizedDescription.prefix(50))])
    }
    func bannerViewDidRecordImpression(_ bannerView: BannerView) { AdEvents.log(placement, "impression") }

    /// 소재 HTML 이 투명한 부분 뒤의 웹뷰 바탕만 투명으로(소재 자체는 건드리지 않는다)
    static func clearWebBackgrounds(_ root: UIView) {
        var stack: [UIView] = [root]
        while let v = stack.popLast() {
            if let web = v as? WKWebView {
                web.isOpaque = false
                web.backgroundColor = .clear
                web.scrollView.backgroundColor = .clear
                web.underPageBackgroundColor = .clear
            }
            stack.append(contentsOf: v.subviews)
        }
    }
}

@MainActor
final class BannerStore {
    static let shared = BannerStore()
    private var entries: [String: BannerEntry] = [:]

    /// 배치(key)의 배너 — 없으면 만들고 바로 요청한다(R5: 화면 진입 즉시 요청).
    func entry(key: String, placement: String, format: BannerFormat, width: CGFloat) -> BannerEntry {
        if let e = entries[key], e.state != .failed || Date().timeIntervalSince(e.requestedAt) < 60 { return e }
        // 실패한 자리는 60초 뒤 다음 방문에서 다시 요청한다
        let e = BannerEntry(key: key, placement: placement, format: format, width: width)
        entries[key] = e
        e.load()
        return e
    }
    func existing(_ key: String) -> BannerEntry? { entries[key] }

    /// SDK 시작 직후 메인 탭 첫 슬롯을 미리 요청한다(QA 5R P1-3 — 응답이 8~19초라 화면에 닿기 전에 받아 두려고).
    func preloadFirstScreens() {
        let w = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 390
        let card = w - 52   // 화면 여백 16×2 + 카드 안쪽 10×2
        for p in ["home", "record_matches", "meta_1", "squad_builder"] { _ = entry(key: p, placement: p, format: .anchored, width: card) }
        _ = entry(key: "community_list", placement: "community_list", format: .banner320x50, width: 320)
    }
}

extension BannerFormat {
    var isInline: Bool { if case .inline = self { return true }; return false }
}

/// 저장소의 BannerView 를 빌려 붙이는 호스트. 뷰가 다시 만들어져도 같은 BannerView 를 옮겨 붙인다.
private struct BannerHost: UIViewRepresentable {
    let entry: BannerEntry
    func makeUIView(context: Context) -> UIView {
        let c = UIView(); c.backgroundColor = .clear
        attach(to: c)
        return c
    }
    func updateUIView(_ c: UIView, context: Context) { attach(to: c) }
    private func attach(to c: UIView) {
        let b = entry.view
        guard b.superview !== c else { return }
        b.removeFromSuperview()
        b.translatesAutoresizingMaskIntoConstraints = true
        b.frame = c.bounds
        b.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        c.addSubview(b)
        // 미리 받은 배너는 화면에 붙은 뒤 웹뷰가 다시 그려지며 바탕이 불투명으로 돌아왔다 — 붙일 때·직후에 다시 지운다
        BannerEntry.clearWebBackgrounds(b)
        Task { @MainActor in
            for delay in [0.3, 1.0, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                BannerEntry.clearWebBackgrounds(b)
            }
        }
    }
}

/// 슬롯이 지금 화면 안에 보이는가 · 화면 위로 지나갔는가(전역 좌표)
private struct ScreenVisibility: ViewModifier {
    let changed: (_ visible: Bool, _ above: Bool) -> Void
    func body(content: Content) -> some View {
        content.onGeometryChange(for: [Bool].self) { g in
            let f = g.frame(in: .global)
            let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds ?? CGRect(x: 0, y: 0, width: 400, height: 900)
            return [f.height > 0 ? f.intersects(screen) : (f.minY >= 0 && f.minY <= screen.maxY), f.maxY < 0]
        } action: { v in changed(v[0], v[1]) }
    }
}

/// 슬롯 공통 상태 — 접기·노출 판정(R1~R7, QA 5R 개정)
///
/// - 예약 슬롯: 받기 전엔 정확한 높이로 비워 둔다. **실패(무응답 또는 20초 무응답)한 뒤에도, 화면에 보이거나 이미 위로
///   지나간 자리는 접지 않는다**(보는 콘텐츠를 밀지 않는다). 아래쪽(아직 안 본) 자리만 접는다.
/// - 접기 슬롯: 받은 뒤 편다. 이미 화면 위로 지나간 뒤 받으면 이번 방문에서는 펴지 않는다.
/// - 이벤트: slot 은 방문당 1회, visible 은 채워진 채 화면에 보인 첫 순간 방문당 1회, collapse 는 실제로 접힐 때만.
private struct SlotModel {
    var visible = false
    var passed = false
    var collapsedLogged = false
    var suppressed = false

    @MainActor static func beginVisit(_ e: BannerEntry, reserved: Bool) {
        if e.lastHosted.map({ Date().timeIntervalSince($0) > 10 }) ?? true {
            e.loggedVisibleThisVisit = false
            AdEvents.log(e.placement, "slot", format: e.format, reserved: reserved)
        }
        e.lastHosted = Date()
    }
}

/// 배너 자리 — 컨테이너 A(카드형): 가로 여백 16 · 모서리 18 · 배경 surface2 · 위 라벨 "AD · 광고".
struct AdSlot: View {
    /// 배치 이름 — 분석 이벤트(ad_slot)에 실린다. 예: home, record_matches, match, meta_1
    var placement: String
    var reserve = false
    var format: BannerFormat = .anchored
    /// 같은 배치를 한 화면에 여러 번 둘 때 구분(목록 반복 슬롯 등)
    var instance: String = ""
    @State private var ads = AdsManager.shared
    @State private var session = BannerSession.shared
    @State private var model = SlotModel()
    @State private var entry: BannerEntry?
    @State private var reservedAtStart: Bool?

    private var useReserve: Bool { reservedAtStart ?? (reserve && !session.reserveDisabled && format.reservedHeight(width: 300) != nil) }
    private var key: String { instance.isEmpty ? placement : "\(placement)#\(instance)" }

    var body: some View {
        if ads.starting, ads.canShowAds {
            let filledSize: CGSize? = { if case .filled(let s) = entry?.state { return s }; return nil }()
            let loaded = filledSize != nil && !model.suppressed
            let failed = entry?.state == .failed
            // 접기: 실패했고(예약 슬롯이면 화면 밖 아래쪽일 때만) · 접기 슬롯은 받기 전엔 자리 없음
            let collapse = failed && !(useReserve && (model.visible || model.passed))
            if !collapse {
                let shown = loaded || useReserve
                VStack(alignment: .leading, spacing: shown ? 6 : 0) {
                    if shown { Text("AD · 광고").fcText(.caption, weight: .semibold).foregroundStyle(FC.muted) }
                    GeometryReader { geo in
                        // 배너 최소 폭(280pt) 이상일 때만 요청한다 — 전환 중 좁은 폭으로 만들면 영구 실패했다
                        if ads.ready, geo.size.width >= 280 {
                            let e = entry
                            Color.clear
                                .onAppear { if entry == nil { entry = BannerStore.shared.entry(key: key, placement: placement, format: format, width: geo.size.width) } }
                            if let e {
                                let sz = filledSize ?? e.format.adSize(width: e.requestWidth).size
                                // 받은 소재 크기로 프레임, 카드 가운데(검은 띠 방지 · 디자인 5R M1)
                                BannerHost(entry: e)
                                    .frame(width: min(geo.size.width, sz.width), height: sz.height)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .opacity(loaded ? 1 : 0)
                                    .allowsHitTesting(loaded)
                            }
                        }
                    }
                    .frame(height: loaded ? (filledSize?.height ?? 0) : (useReserve ? reservedHeight : 0))
                }
                .padding(.horizontal, 10).padding(.vertical, shown ? 10 : 0)
                .background(shown ? FC.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(shown ? 1 : 0)
                .animation(useReserve ? nil : .easeOut(duration: 0.25), value: loaded)
                .modifier(ScreenVisibility { v, above in
                    model.visible = v; model.passed = above
                    if let e = entry { e.lastHosted = Date() }
                    logVisibleIfNeeded()
                })
                .onChange(of: entry?.state) { _, st in
                    // 접기 슬롯이 이미 위로 지나간 뒤 받으면 이번엔 펴지 않는다(R6)
                    if case .filled = st, !useReserve, model.passed { model.suppressed = true }
                    logVisibleIfNeeded()
                }
                .onAppear {
                    if reservedAtStart == nil { reservedAtStart = reserve && !session.reserveDisabled && format.reservedHeight(width: 300) != nil }
                    if let e = entry ?? BannerStore.shared.existing(key) { entry = e; SlotModel.beginVisit(e, reserved: useReserve) }
                }
                .onChange(of: entry == nil) { _, isNil in if !isNil, let e = entry { SlotModel.beginVisit(e, reserved: useReserve) } }
                .onDisappear { entry?.lastHosted = Date() }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("광고")
                .accessibilityHidden(!shown)
            } else {
                Color.clear.frame(height: 0)
                    .onAppear {
                        if !model.collapsedLogged { model.collapsedLogged = true; AdEvents.log(placement, "collapse") }
                    }
            }
        }
    }

    private func logVisibleIfNeeded() {
        guard let e = entry, case .filled = e.state, model.visible, !model.suppressed, !e.loggedVisibleThisVisit else { return }
        e.loggedVisibleThisVisit = true
        AdEvents.log(placement, "visible")
    }

    private var reservedHeight: CGFloat {
        let w = entry?.requestWidth ?? (((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 390) - 52)
        return format.reservedHeight(width: w) ?? 0
    }
}

/// 커뮤니티 목록·상세용 **행형 배너(320×50, 컨테이너 B)** — 왼쪽 `AD` 알약, 배경 surface2, 위·아래 헤어라인.
/// 위아래 안쪽 여백 24pt — 글 행은 행 전체가 버튼이라 소재와 행 사이를 24pt 이상 띄운다(QA 5R P1-4 · 정책 P1).
/// 예약 높이 = 최종 높이(50 + 24×2) — SDK 준비 전후로 높이가 달라지지 않는다.
struct CompactAdRow: View {
    var placement: String
    var reserve = false
    var instance: String = ""
    static let gap: CGFloat = 24
    @State private var ads = AdsManager.shared
    @State private var session = BannerSession.shared
    @State private var model = SlotModel()
    @State private var entry: BannerEntry?
    @State private var reservedAtStart: Bool?

    private var useReserve: Bool { reservedAtStart ?? (reserve && !session.reserveDisabled) }
    private var key: String { instance.isEmpty ? placement : "\(placement)#\(instance)" }

    var body: some View {
        if ads.starting, ads.canShowAds {
            let loaded: Bool = { if case .filled = entry?.state { return !model.suppressed }; return false }()
            let failed = entry?.state == .failed
            let collapse = failed && !(useReserve && (model.visible || model.passed))
            if !collapse {
                let shown = loaded || useReserve
                HStack(spacing: 6) {
                    Text("AD").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(CM.faint)
                        .frame(width: 22, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(CM.faint.opacity(0.6), lineWidth: 1))
                    ZStack {
                        if let e = entry {
                            BannerHost(entry: e).opacity(loaded ? 1 : 0).allowsHitTesting(loaded)
                        }
                    }
                    .frame(width: 320, height: 50)
                    .onAppear {
                        if ads.ready, entry == nil { entry = BannerStore.shared.entry(key: key, placement: placement, format: .banner320x50, width: 320) }
                    }
                    .onChange(of: ads.ready) { _, r in
                        if r, entry == nil { entry = BannerStore.shared.entry(key: key, placement: placement, format: .banner320x50, width: 320) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, shown ? Self.gap : 0)
                .frame(height: shown ? 50 + Self.gap * 2 : 0)
                .background(shown ? FC.surface2.opacity(0.6) : Color.clear)
                .opacity(shown ? 1 : 0)
                .overlay(alignment: .top) { if shown { Rectangle().fill(CM.hair).frame(height: 1) } }
                .overlay(alignment: .bottom) { if shown { Rectangle().fill(CM.hair).frame(height: 1) } }
                .animation(useReserve ? nil : .easeOut(duration: 0.2), value: loaded)
                .modifier(ScreenVisibility { v, above in
                    model.visible = v; model.passed = above
                    entry?.lastHosted = Date()
                    logVisibleIfNeeded()
                })
                .onChange(of: entry?.state) { _, st in
                    if case .filled = st, !useReserve, model.passed { model.suppressed = true }
                    logVisibleIfNeeded()
                }
                .onAppear {
                    if reservedAtStart == nil { reservedAtStart = reserve && !session.reserveDisabled }
                    if let e = entry ?? BannerStore.shared.existing(key) { entry = e; SlotModel.beginVisit(e, reserved: useReserve) }
                }
                .onChange(of: entry == nil) { _, isNil in if !isNil, let e = entry { SlotModel.beginVisit(e, reserved: useReserve) } }
                .onDisappear { entry?.lastHosted = Date() }
                .background { if shown { GeometryReader { g in Color.clear.preference(key: AdRowFramesKey.self, value: [g.frame(in: .global)]) } } }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("광고")
                .accessibilityHidden(!shown)
            } else {
                Color.clear.frame(height: 0)
                    .onAppear { if !model.collapsedLogged { model.collapsedLogged = true; AdEvents.log(placement, "collapse") } }
            }
        }
    }

    private func logVisibleIfNeeded() {
        guard let e = entry, case .filled = e.state, model.visible, !model.suppressed, !e.loggedVisibleThisVisit else { return }
        e.loggedVisibleThisVisit = true
        AdEvents.log(placement, "visible")
    }
}

/// 커뮤니티 목록의 광고 행 프레임(전역) — 글쓰기 FAB 가 광고 행과 겹치는 동안 숨기기 위해(정책: 콘텐츠가 광고를 가리면 안 됨)
struct AdRowFramesKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}
