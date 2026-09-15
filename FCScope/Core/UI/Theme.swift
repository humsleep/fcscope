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

// MARK: - 글자 크기 (Dynamic Type)

/// 사용자의 "글자 크기" 설정에 따른 배율.
///
/// iOS 는 사용자가 설정에서 글자 크기를 바꾸면 앱이 따라오길 기대한다. 고정 pt 로 찍으면
/// 크게 설정한 사용자에게는 그대로 작게 보인다. 이 앱은 스탯이 빽빽해서 특히 문제가 된다.
///
/// 배율은 Apple 의 body 텍스트 스타일(기본 17pt)이 각 단계에서 갖는 크기 비율을 그대로 쓴다.
/// 다만 접근성 단계(AX1~AX5, 최대 3.1배)를 그대로 따르면 표·차트가 무너지므로 **1.6배에서 멈춘다**
/// (AX1 수준). 완전한 접근성 대응은 화면별 레이아웃 재설계가 따로 필요하다.
enum TypeScale {
    static let maxFactor: CGFloat = 1.6

    /// 가독성 보정 — 앱 전체 본문이 iOS 기준으로 너무 작았다.
    ///
    /// 실측 분포: 12pt 63곳 · 13pt 45곳 · 11pt 22곳. iOS 에서 12pt 는 `caption`,
    /// 13pt 는 `footnote` 이고 **본문(body)은 17pt** 다. 즉 앱의 "본문"이 시스템
    /// 기준 캡션 크기였다. 10pt·8pt 는 Apple 최소 권장(11pt) 아래다.
    ///
    /// 각 호출부의 숫자를 일일이 바꾸면 화면 간 비율이 깨지므로, 상대 크기는 그대로 두고
    /// 여기서 한 번만 키운다. 큰 전광판 숫자(20pt 이상)는 이미 충분해 손대지 않는다.
    static func readable(_ size: CGFloat) -> CGFloat {
        guard size < 20 else { return size }
        return max(12, size * 1.15)
    }

    static func factor(_ size: DynamicTypeSize) -> CGFloat {
        let raw: CGFloat
        switch size {
        case .xSmall: raw = 0.82
        case .small: raw = 0.88
        case .medium: raw = 0.94
        case .large: raw = 1.0
        case .xLarge: raw = 1.12
        case .xxLarge: raw = 1.24
        case .xxxLarge: raw = 1.35
        default: raw = maxFactor   // accessibility1 이상
        }
        return min(raw, maxFactor)
    }
}

/// 시스템 폰트 + Dynamic Type. `.font(.system(size:weight:))` 대신 쓴다.
private struct FCSystemFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight
    func body(content: Content) -> some View {
        content.font(.pretendard(TypeScale.readable(size) * TypeScale.factor(typeSize), weight))
    }
}

/// Chakra Petch(전광판) + Dynamic Type.
private struct FCScoreboardFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight
    func body(content: Content) -> some View {
        content.font(.scoreboard(TypeScale.readable(size) * TypeScale.factor(typeSize), weight: weight))
    }
}

extension Font {
    /// `Text + Text` 연결 안처럼 **Font 값 자체**가 필요한 곳에서 쓴다.
    /// (뷰 모디파이어는 `some View` 를 돌려줘서 Text 연결이 깨진다.)
    /// 호출부에서 `@Environment(\.dynamicTypeSize)` 를 받아 넘긴다.
    static func fcScoreboard(_ size: CGFloat, _ typeSize: DynamicTypeSize, weight: Font.Weight = .bold) -> Font {
        .scoreboard(TypeScale.readable(size) * TypeScale.factor(typeSize), weight: weight)
    }

    /// 위와 같은 목적의 시스템 폰트 버전.
    static func fcFont(_ size: CGFloat, _ typeSize: DynamicTypeSize, weight: Font.Weight = .regular) -> Font {
        .pretendard(TypeScale.readable(size) * TypeScale.factor(typeSize), weight)
    }
}

extension View {
    /// 본문 폰트 — 사용자의 글자 크기 설정을 따른다.
    func fcFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(FCSystemFont(size: size, weight: weight))
    }
    /// 전광판 폰트 — 사용자의 글자 크기 설정을 따른다.
    func fcScoreboard(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        modifier(FCScoreboardFont(size: size, weight: weight))
    }
}

/// 전광판 숫자·섹션 라벨용 Chakra Petch (한글엔 사용하지 않는다).
/// **고정 크기가 필요한 곳(공유 카드 렌더 등)에서만 직접 쓴다.** 화면에는 `fcScoreboard(_:)` 를 쓴다.
extension Font {
    static func scoreboard(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .medium: name = "ChakraPetch-Medium"
        case .semibold: name = "ChakraPetch-SemiBold"
        default: name = "ChakraPetch-Bold"
        }
        // Chakra Petch 에는 한글 글리프가 없다. 그냥 두면 한글이 시스템 고딕으로 튀어
        // 한 줄 안에서 서체가 섞인다 → 한글은 Pretendard 가 이어받도록 cascade 를 건다.
        // fixedSize 성격: 크기는 TypeScale 이 이미 계산했으므로 시스템이 다시 키우지 않는다.
        guard let base = UIFont(name: name, size: size) else { return .pretendard(size, weight) }
        let fallback = UIFontDescriptor(fontAttributes: [.name: PretendardName.for(weight)])
        let desc = base.fontDescriptor.addingAttributes([.cascadeList: [fallback]])
        return Font(UIFont(descriptor: desc, size: size) as CTFont)
    }

    /// Pretendard — 토스·당근 등 국내 서비스가 표준처럼 쓰는 본문 서체(SIL OFL 1.1).
    /// 시스템 고딕(Apple SD Gothic Neo)보다 자간·숫자 폭이 고르고 작은 크기에서도 또렷하다.
    /// `fixedSize` 인 이유: 크기는 TypeScale 이 Dynamic Type 까지 반영해 계산하므로,
    /// `.custom(_:size:)` 를 쓰면 시스템이 한 번 더 키워 **이중으로 커진다**.
    static func pretendard(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(PretendardName.for(weight), fixedSize: size)
    }
}

enum PretendardName {
    static func `for`(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: return "Pretendard-Medium"
        case .semibold: return "Pretendard-SemiBold"
        case .bold, .heavy, .black: return "Pretendard-Bold"
        default: return "Pretendard-Regular"
        }
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
        // 영문 라벨("SHOT MAP")은 전광판 서체 + 넓은 자간이 멋있지만, 한글에 자간 2.5 를 주면
        // "이 번 주 성 적 표" 처럼 글자가 흩어져 읽기 어렵다. 한글이면 본문 서체·기본 자간으로.
        if text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
            Text(text).fcFont(12, weight: .semibold).foregroundStyle(color)
        } else {
            Text(text).fcScoreboard(12, weight: .semibold).kerning(2.5).foregroundStyle(color)
        }
    }
}

struct Chip: View {
    let text: String
    var color: Color = FC.muted
    var bg: Color = FC.surface2
    var body: some View {
        Text(text).fcFont(12, weight: .semibold).foregroundStyle(color)
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
                Text(label).fcFont(12).foregroundStyle(FC.muted)
                Text(value).fcScoreboard(20).foregroundStyle(color)
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
            Text("4:04").fcScoreboard(44).foregroundStyle(FC.surface2)
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
