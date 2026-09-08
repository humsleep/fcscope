import SwiftUI
import UIKit

/// 디자인 토큰 "스타디움 나이트" — 웹 globals.css 와 동일 값. 라이트 모드는 웹 라이트 팔레트.
enum FC {
    static let bg = dyn(0x0a1119, 0xeef1f6)
    static let surface = dyn(0x101a26, 0xffffff)
    static let surface2 = dyn(0x182636, 0xe7ecf3)
    static let line = dyn(0x24374f, 0xd3dbe6)
    static let ink = dyn(0xeef2f8, 0x131b26)
    static let muted = dyn(0x9aabc0, 0x566579)
    static let accent = dyn(0xc8f542, 0x3f7d10)
    static let accentInk = dyn(0x0a1119, 0xffffff)
    static let gold = dyn(0xf2c14e, 0xa66a00)
    static let win = dyn(0x4ade80, 0x15803d)
    static let draw = dyn(0x9aabc0, 0x566579)
    static let lose = dyn(0xfb7185, 0xd61f45)

    private static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark)
        })
    }

    /// 톤 문자열(win/lose/gold/info/lime/muted/ink) → 색
    static func tone(_ name: String) -> Color {
        switch name {
        case "win", "lime", "good": return win
        case "lose", "warn": return lose
        case "gold": return gold
        case "info", "accent": return accent
        case "muted", "draw": return muted
        default: return ink
        }
    }
    static func resultColor(_ r: String) -> Color {
        switch r { case "승": return win; case "패": return lose; default: return draw }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// 전광판 숫자·섹션 라벨용 Chakra Petch (한글엔 사용하지 않는다).
extension Font {
    static func scoreboard(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .medium: name = "ChakraPetch-Medium"
        case .semibold: name = "ChakraPetch-SemiBold"
        default: name = "ChakraPetch-Bold"
        }
        return .custom(name, size: size)
    }
}

/// 카드 컨테이너 (웹 .panel)
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    var highlight: Color? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FC.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(highlight ?? FC.line, lineWidth: 1))
    }
}

/// 섹션 라벨 (자간 넓은 대문자 전광판 스타일)
struct SectionLabel: View {
    let text: String
    var color: Color = FC.muted
    init(_ text: String, color: Color = FC.muted) { self.text = text; self.color = color }
    var body: some View {
        Text(text).font(.scoreboard(12, weight: .semibold)).kerning(2.5).foregroundStyle(color)
    }
}

struct Chip: View {
    let text: String
    var color: Color = FC.muted
    var bg: Color = FC.surface2
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg, in: Capsule())
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var color: Color = FC.ink
    var body: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12)).foregroundStyle(FC.muted)
                Text(value).font(.scoreboard(20)).foregroundStyle(color)
            }
        }
    }
}

struct ErrorState: View {
    let title: String
    var message: String? = nil
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Text("4:04").font(.scoreboard(44)).foregroundStyle(FC.surface2)
            Text(title).font(.headline).foregroundStyle(FC.ink)
            if let message { Text(message).font(.subheadline).foregroundStyle(FC.muted).multilineTextAlignment(.center) }
            if let retry {
                Button("다시 시도", action: retry).buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }
}

struct Skeleton: View {
    var height: CGFloat = 80
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(FC.surface2).frame(height: height)
            .opacity(on ? 0.5 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true } }
    }
}

extension View {
    func fcScreen() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FC.bg.ignoresSafeArea())
            .toolbarBackground(FC.bg, for: .navigationBar)
            .toolbarBackground(FC.bg, for: .tabBar)
    }
}

enum Haptic {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
