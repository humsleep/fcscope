import WidgetKit
enum WidgetKitReloader {
    static func reload(kind: String) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
}
