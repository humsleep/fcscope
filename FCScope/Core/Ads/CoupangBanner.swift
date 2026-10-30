import SwiftUI
import WebKit

/// 쿠팡 파트너스 다이나믹 배너(320×100) — 애드몹과 노출당 수익을 비교하는 실험 슬롯.
/// 노출·클릭은 feature_open(coupang_view_* / coupang_click_*)로 센다(서버 이벤트 허용 목록을 늘리지 않으려고).
struct CoupangBanner: View {
    var placement: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AD · 쿠팡").fcText(.caption, weight: .semibold).foregroundStyle(FC.muted)
            CoupangWebView(placement: placement)
                .frame(width: 320, height: 100)
                .frame(maxWidth: .infinity)
            // 공정위 추천·보증 심사지침 — 대가성 문구
            Text("이 배너는 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다.")
                .fcFont(11).foregroundStyle(FC.muted)
        }
        .padding(10)
        .background(FC.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { Analytics.shared.track(.featureOpen, ["feature": "coupang_view_\(placement)"]) }
    }
}

private struct CoupangWebView: UIViewRepresentable {
    let placement: String

    private static let html = """
    <!doctype html><html><head><meta name="viewport" content="width=320,initial-scale=1">
    <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}</style></head><body>
    <script src="https://ads-partners.coupang.com/g.js"></script>
    <script>new PartnersCoupang.G({"id":1045059,"template":"carousel","trackingCode":"AF1685303","width":"320","height":"100","tsource":""});</script>
    </body></html>
    """

    func makeCoordinator() -> Coordinator { Coordinator(placement: placement) }

    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.isScrollEnabled = false
        v.navigationDelegate = context.coordinator
        v.uiDelegate = context.coordinator
        v.loadHTMLString(Self.html, baseURL: AppConfig.productionBase)
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {}

    /// 상품 탭은 웹뷰 밖(쿠팡 앱·Safari)으로 연다 — 웹뷰 안에서 열면 24시간 구매 추적 쿠키가 남지 않는다.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let placement: String
        init(placement: String) { self.placement = placement }

        private func openOutside(_ url: URL?) {
            guard let url, url.scheme == "https" else { return }
            Analytics.shared.track(.featureOpen, ["feature": "coupang_click_\(placement)"])
            UIApplication.shared.open(url)
        }

        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if a.navigationType == .linkActivated { openOutside(a.request.url); decisionHandler(.cancel) } else { decisionHandler(.allow) }
        }

        // target="_blank" 링크
        func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            openOutside(a.request.url)
            return nil
        }
    }
}
