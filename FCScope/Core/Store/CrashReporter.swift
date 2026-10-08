import Foundation
import MetricKit

/// 크래시 수집 — 외부 SDK 없이 MetricKit 진단을 받아 Analytics(`crash` 이벤트)로 보낸다.
///
/// App Store Connect 의 크래시 보고는 "기기 분석 공유"에 동의한 사람만, 하루쯤 늦게 모인다.
/// MetricKit 은 iOS 15+ 에서 크래시 다음 실행에 진단을 바로 넘겨 준다 — 매일 트리아지가 전날 크래시를 볼 수 있게.
///
/// 보내는 것: 예외 종류·코드·시그널·종료 사유(60자로 잘림)와 그 빌드 번호. 콜스택·기기 식별자는 보내지 않는다.
/// 자세한 스택이 필요하면 Xcode Organizer 에서 같은 빌드의 크래시를 본다.
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.flatMap { $0.crashDiagnostics ?? [] }
        guard !crashes.isEmpty else { return }
        let rows: [[String: Any]] = crashes.prefix(5).map { c in
            var p: [String: Any] = ["version": c.metaData.applicationBuildVersion]
            if let t = c.exceptionType { p["exception"] = Self.machException(t.intValue) }
            if let code = c.exceptionCode { p["code"] = code.intValue }
            if let s = c.signal { p["signal"] = Self.signalName(s.intValue) }
            if let r = c.terminationReason { p["reason"] = String(r.prefix(60)) }
            return p
        }
        Task { @MainActor in
            for p in rows { Analytics.shared.track(.crash, p) }
            await Analytics.shared.flush()
        }
    }

    private static func machException(_ t: Int) -> String {
        switch t {
        case 1: return "EXC_BAD_ACCESS"
        case 2: return "EXC_BAD_INSTRUCTION"
        case 3: return "EXC_ARITHMETIC"
        case 5: return "EXC_SOFTWARE"
        case 6: return "EXC_BREAKPOINT"
        case 10: return "EXC_CRASH"
        case 11: return "EXC_RESOURCE"
        case 12: return "EXC_GUARD"
        default: return "EXC_\(t)"
        }
    }

    private static func signalName(_ s: Int) -> String {
        switch s {
        case 4: return "SIGILL"
        case 5: return "SIGTRAP"
        case 6: return "SIGABRT"
        case 8: return "SIGFPE"
        case 9: return "SIGKILL"
        case 10: return "SIGBUS"
        case 11: return "SIGSEGV"
        default: return "SIG\(s)"
        }
    }
}
