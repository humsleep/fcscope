import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import Observation

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

/// 구단주명 검색 전면광고 — 하루 첫 검색만 무료, 두 번째 검색부터 매번(2026-09-20 운영자 결정).
///
/// - 날짜는 KST 기준으로 매일 초기화한다.
/// - ⚠️ 쿨다운 0: 연속 검색마다 광고가 뜬다. AdMob 은 과도한 빈도를 게재 제한 사유로 볼 수 있어,
///   노출 대비 이탈·수익을 보고 `cooldown` 을 다시 늘릴지 판단할 것(예전 값 90초).
/// - 대상은 **검색창에 직접 입력한 검색**뿐이다. 즐겨찾기·최근 검색·칩을 누르는 건 탐색이라 제외.
@MainActor
enum SearchGate {
    /// 하루 첫 검색만 무료, 두 번째 검색부터는 매번 전면광고(2026-09-20 운영자 결정).
    /// 광고가 아직 로드되지 않았으면 그 검색은 광고 없이 지나간다(검색을 막지 않음).
    static let freePerDay = 1
    static let cooldown: TimeInterval = 0

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
        case .inline(let h): return inlineAdaptiveBanner(width: width, maxHeight: h)
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
/// props: placement · event(slot/fill/nofill/visible/impression/collapse) · format · reserved
/// 이벤트 이름 `ad_slot` 은 서버 허용 목록(웹 lib/analytics/events.ts)에 있어야 저장된다.
@MainActor
enum AdEvents {
    static func log(_ placement: String, _ event: String, format: BannerFormat? = nil, reserved: Bool? = nil, extra: [String: Any] = [:]) {
        var p: [String: Any] = ["placement": placement, "event": event]
        if let format { p["format"] = { switch format { case .anchored: "anchored"; case .inline: "inline"; case .banner320x50: "320x50" } }() }
        if let reserved { p["reserved"] = reserved }
        for (k, v) in extra { p[k] = v }
        #if DEBUG
        print("[ad] \(placement) \(event) \(extra)")
        #endif
        Analytics.shared.track(.adSlot, p)
    }
}

struct BannerAdView: UIViewRepresentable {
    let width: CGFloat
    var format: BannerFormat = .anchored
    let placement: String
    /// 받은 광고의 실제 높이. 실패하면 0.
    @Binding var height: CGFloat?
    func makeCoordinator() -> Coordinator { Coordinator(height: $height, placement: placement) }
    func makeUIView(context: Context) -> BannerView {
        let v = BannerView(adSize: format.adSize(width: width))
        v.adUnitID = AppConfig.bannerAdUnit ?? ""
        v.rootViewController = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        v.delegate = context.coordinator
        v.load(Request())
        return v
    }
    func updateUIView(_ uiView: BannerView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        private let height: Binding<CGFloat?>
        private let placement: String
        init(height: Binding<CGFloat?>, placement: String) { self.height = height; self.placement = placement }
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            let h = max(bannerView.adSize.size.height, bannerView.frame.height)
            height.wrappedValue = h > 0 ? h : nil
            BannerSession.shared.noteFill()
            AdEvents.log(placement, "fill", extra: ["height": Int(h)])
        }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            height.wrappedValue = 0
            BannerSession.shared.noteNoFill()
            AdEvents.log(placement, "nofill", extra: ["code": (error as NSError).code, "msg": String(error.localizedDescription.prefix(50))])
        }
        func bannerViewDidRecordImpression(_ bannerView: BannerView) { AdEvents.log(placement, "impression") }
    }
}

/// 슬롯이 지금 화면 안에 보이는가(전역 좌표로 판정) — R2 "보고 있으면 접지 않는다", R6 "지나간 뒤 받으면 펴지 않는다"
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

/// 배너 자리 — 컨테이너 A(카드형): 화면 카드와 같은 가로 여백·모서리 18pt·배경 surface2, 위 라벨 "AD · 광고".
///
/// - `reserve: true`(첫 1.5화면 · R1): 폭 결정적 크기만큼 자리를 미리 잡는다. 6초 안에 못 받거나 실패하면 접되(R2),
///   그 순간 화면에 보이고 있으면 화면을 떠날 때 접는다. 세션에서 연속 2회 무응답이면 예약하지 않는다(R3).
/// - `reserve: false`(깊은 자리 · R4): 받은 뒤 편다. 슬롯이 이미 화면 위로 지나간 뒤 받으면 이번엔 펴지 않는다(R6).
///   요청은 슬롯이 만들어질 때(화면 진입) 바로 나간다(R5).
/// - SDK 시작 전이면 아무것도 그리지 않는다(R7).
struct AdSlot: View {
    /// 배치 이름 — 분석 이벤트(ad_slot)에 실린다. 예: home, record_matches, match, meta_1
    var placement: String
    var reserve = false
    var format: BannerFormat = .anchored
    @State private var ads = AdsManager.shared
    @State private var session = BannerSession.shared
    /// nil = 로딩 중, 0 = 광고 없음(접힘)
    @State private var height: CGFloat?
    @State private var timedOut = false
    @State private var visible = false
    @State private var passed = false
    /// 받았지만 이미 지나간 뒤라 이번 화면에선 펴지 않는다(R6)
    @State private var suppressed = false
    /// "visible"은 슬롯당 한 번만 기록한다(스크롤마다 쌓이지 않게)
    @State private var loggedVisible = false
    @State private var timerStarted = false
    /// 이번 화면에서 예약을 쓸지 — 처음 만들어질 때 한 번 정한다(세션 학습이 중간에 바뀌어도 보이는 자리는 그대로)
    @State private var reservedAtStart: Bool?

    private var useReserve: Bool { reservedAtStart ?? (reserve && !session.reserveDisabled && format.reservedHeight(width: 300) != nil) }
    /// 무응답(0) 또는 시간 초과면 접는다 — 단 예약 자리가 보이는 중이거나 이미 위로 지나갔으면 그대로 둔다(R2)
    private var collapsed: Bool {
        let failed = height == 0 || (timedOut && height == nil)
        guard failed else { return false }
        return !useReserve || (!visible && !passed)
    }

    var body: some View {
        // R2: 예약 슬롯이 시간 안에 못 받으면 접되, 보이는 중(visible)이거나 이미 위로 지나간(passed) 자리는 접지 않는다 —
        // 위쪽 자리가 접히면 지금 보고 있는 콘텐츠가 위로 끌려 올라간다. 아래쪽(아직 안 본) 자리만 접는다.
        if ads.starting, ads.canShowAds, !collapsed {
            let loaded = (height ?? 0) > 0 && !suppressed
            let shown = loaded || useReserve
            VStack(alignment: .leading, spacing: shown ? 6 : 0) {
                if shown { Text("AD · 광고").fcText(.caption, weight: .semibold).foregroundStyle(FC.muted) }
                GeometryReader { geo in
                    // 폭이 0 으로 오면 잘못된 크기로 요청해 실패한다 — 폭이 잡힌 뒤에만 만든다.
                    if ads.ready, geo.size.width > 100 {
                        // 배너 뷰 자체에는 요청 크기만큼의 프레임을 준다 — 높이 0 프레임의 인라인 배너는
                        // "Invalid ad width or height" 로 실패했다. 받기 전에는 투명·터치 불가로 두고(겉 프레임이 0이라 자리는 안 차지한다),
                        // 받은 뒤 겉 프레임이 실제 높이로 펴진다.
                        BannerAdView(width: geo.size.width, format: format, placement: placement, height: $height)
                            .frame(width: geo.size.width, height: height.flatMap { $0 > 0 ? $0 : nil } ?? format.adSize(width: geo.size.width).size.height, alignment: .top)
                            .opacity(loaded ? 1 : 0)
                            .allowsHitTesting(loaded)
                    }
                }
                .frame(height: loaded ? (height ?? 0) : (useReserve ? reservedHeight : 0))
                // 배너는 클리핑하지 않는다 — AdChoices 아이콘이 잘리면 소재 변형(정책 위반)
            }
            .padding(.horizontal, 10).padding(.vertical, shown ? 10 : 0)
            .background(shown ? FC.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(shown ? 1 : 0)
            .animation(useReserve ? nil : .easeOut(duration: 0.25), value: loaded)
            .modifier(ScreenVisibility { v, above in
                visible = v; passed = above
                if v, loaded, !loggedVisible { loggedVisible = true; AdEvents.log(placement, "visible") }
            })
            .onChange(of: height) { _, h in
                // R6: 접기 슬롯이 이미 화면 위로 지나간 뒤 받으면 펴지 않는다(보이는 콘텐츠가 밀린다)
                if let h, h > 0, !useReserve, passed { suppressed = true }
            }
            .task {
                if reservedAtStart == nil { reservedAtStart = reserve && !session.reserveDisabled && format.reservedHeight(width: 300) != nil }
                AdEvents.log(placement, "slot", format: format, reserved: useReserve)
            }
            // R2: 요청 후 6초 안에 못 받으면 접는다. 시계는 SDK 가 준비되고 슬롯이 처음 화면에 들어온 뒤부터 —
            // 딥링크로 다른 화면이 바로 덮은 홈처럼 아직 배치되지 않은 슬롯이 미리 접히지 않게.
            .task(id: ads.ready && (visible || timerStarted)) {
                guard useReserve, ads.ready, visible || timerStarted, !timerStarted else { return }
                timerStarted = true
                try? await Task.sleep(for: .seconds(6))
                if height == nil { timedOut = true; AdEvents.log(placement, "collapse", extra: ["reason": "timeout"]) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("광고")
            .accessibilityHidden(!shown)
        }
    }

    private var reservedHeight: CGFloat {
        let w = ((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 390) - 52
        return format.reservedHeight(width: w) ?? 0
    }
}

/// 커뮤니티 목록·상세용 **행형 배너(320×50, 컨테이너 B)** — 왼쪽 `AD` 알약, 위아래 12pt + 위·아래 1pt 헤어라인,
/// 배경 surface2 로 글 행과 구별한다(운영자 결정 2026-10-04 · AD-PLACEMENT 1-6).
/// `reserve: true` 는 목록 첫 슬롯만(첫 화면 · LazyVStack 이라 늦게 펴지면 손가락 아래에서 밀린다).
struct CompactAdRow: View {
    var placement: String
    var reserve = false
    @State private var ads = AdsManager.shared
    @State private var session = BannerSession.shared
    @State private var height: CGFloat?
    @State private var timedOut = false
    @State private var visible = false
    @State private var passed = false
    @State private var timerStarted = false
    @State private var reservedAtStart: Bool?

    private var useReserve: Bool { reservedAtStart ?? (reserve && !session.reserveDisabled) }
    private var collapsed: Bool {
        let failed = height == 0 || (timedOut && height == nil)
        guard failed else { return false }
        return !useReserve || (!visible && !passed)
    }

    var body: some View {
        if ads.starting, ads.canShowAds, !collapsed {
            let loaded = (height ?? 0) > 0
            let shown = loaded || useReserve
            HStack(spacing: 6) {
                Text("AD").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(CM.faint)
                    .frame(width: 22, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(CM.faint.opacity(0.6), lineWidth: 1))
                if ads.ready {
                    BannerAdView(width: 320, format: .banner320x50, placement: placement, height: $height)
                        .frame(width: 320, height: 50)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, shown ? 12 : 0)
            .frame(height: shown ? nil : 0)
            .background(shown ? FC.surface2.opacity(0.6) : Color.clear)
            .opacity(shown ? 1 : 0)
            .overlay(alignment: .top) { if shown { Rectangle().fill(CM.hair).frame(height: 1) } }
            .overlay(alignment: .bottom) { if shown { Rectangle().fill(CM.hair).frame(height: 1) } }
            .animation(useReserve ? nil : .easeOut(duration: 0.2), value: loaded)
            .modifier(ScreenVisibility { v, above in visible = v; passed = above })
            .task {
                if reservedAtStart == nil { reservedAtStart = reserve && !session.reserveDisabled }
                AdEvents.log(placement, "slot", format: .banner320x50, reserved: useReserve)
            }
            .task(id: ads.ready && (visible || timerStarted)) {
                guard useReserve, ads.ready, visible || timerStarted, !timerStarted else { return }
                timerStarted = true
                try? await Task.sleep(for: .seconds(6))
                if height == nil { timedOut = true; AdEvents.log(placement, "collapse", extra: ["reason": "timeout"]) }
            }
            .background { if shown { GeometryReader { g in Color.clear.preference(key: AdRowFramesKey.self, value: [g.frame(in: .global)]) } } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("광고")
            .accessibilityHidden(!shown)
        }
    }
}

/// 커뮤니티 목록의 광고 행 프레임(전역) — 글쓰기 FAB 가 광고 행과 겹치는 동안 숨기기 위해(정책: 콘텐츠가 광고를 가리면 안 됨)
struct AdRowFramesKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}
