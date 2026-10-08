import WidgetKit
enum WidgetKitReloader {
    static func reload(kind: String) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    /// 홈·잠금 화면에 올라간 위젯 수(kind 별). 실패하면 빈 사전.
    static func installedCounts(_ done: @escaping @Sendable ([String: Int]) -> Void) {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let infos = (try? result.get()) ?? []
            done(Dictionary(infos.map { ($0.kind, 1) }, uniquingKeysWith: +))
        }
    }
}
