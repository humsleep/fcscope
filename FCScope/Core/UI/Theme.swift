import SwiftUI
import UIKit

/// 디자인 토큰 "S-spot 하이브리드"(docs/store-v2/ux-mockups/00-accent.png 옵션 C).
///
/// 색의 역할을 셋으로 나눈다 — 섞으면 "강조인지 승리인지"가 헷갈린다(라임 시절의 문제).
/// - `brand`(오렌지→마젠타 그라디언트): 브랜드 순간 전용. CTA·공유·선택 탭·히어로 카피. **데이터에 쓰지 않는다.**
/// - `tint`(바이올렛): 일반 강조. 링크·칩 선택·토글·내 쪽 시리즈.
/// - `win`·`lose`·`gold`: 데이터의 의미(좋음·나쁨·최상) 전용. 중립 숫자는 `ink`.
/// 라이트 대비(본문 위 AA): tint #6D3FE0 5.5:1 · win #0B7A55 4.9:1 · lose #C81E3A 5.4:1 · gold #A66A00 4.5:1.
/// 배경은 아이콘·런치 스크린과 같은 인디고 블랙(LaunchBackground 컬러셋과 같은 값) — 인트로→홈 이음새 없음.
enum FC {
    static let bg = dyn(0x0b0a1f, 0xf5f4fb)
    static let surface = dyn(0x14122e, 0xffffff)
    static let surface2 = dyn(0x1d1a40, 0xeceaf6)
    static let line = dyn(0x2a2656, 0xdcd8ec)
    static let ink = dyn(0xeeedf8, 0x15132b)
    static let muted = dyn(0xa6a2c8, 0x5e5a78)
    /// 일반 강조(바이올렛)
    static let tint = dyn(0x9b7bff, 0x6d3fe0)
    /// tint 를 **채운** 배경 위 글자. 다크 #9B7BFF 위 흰 글자는 3.1:1 이라 남흑색, 라이트 #6D3FE0 위는 흰색(6.1:1).
    static let tintInk = dyn(0x0b0a1f, 0xffffff)
    /// 브랜드 그라디언트 양 끝(다크 #F0502A→#E0218A · 라이트 #E8481C→#C8177A)
    static let brandStart = dyn(0xf0502a, 0xe8481c)
    static let brandEnd = dyn(0xe0218a, 0xc8177a)
    /// 그라디언트를 쓸 수 없는 곳(탭 바 선택색·SF 심볼 단색)용 브랜드 단색
    static let brandSolid = dyn(0xe8367a, 0xc8177a)
    /// 브랜드 그라디언트 위 글자 — 항상 흰색(17pt Bold 이상에서 3.6~5.4:1)
    static let brandInk = Color.white
    static var brand: LinearGradient {
        LinearGradient(colors: [brandStart, brandEnd], startPoint: .leading, endPoint: .trailing)
    }
    static let gold = dyn(0xf7c948, 0xa66a00)
    static let win = dyn(0x3ddc97, 0x0b7a55)
    static let draw = dyn(0xa6a2c8, 0x5e5a78)
    static let lose = dyn(0xff5470, 0xc81e3a)
    /// 피치 그라디언트 (스쿼드 빌더·공유 카드 공용). 라이트 모드에서도 잔디색은 고정.
    static let pitchTop = Color(UIColor(hex: 0x123322))
    static let pitchBottom = Color(UIColor(hex: 0x0d2419))

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
        case "info", "accent": return tint
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

/// 모서리 반경 토큰 — 카드(Panel)·행·컨트롤·칩 네 단계만 쓴다.
enum Radius {
    static let card: CGFloat = 14
    static let row: CGFloat = 12
    static let control: CGFloat = 10
    static let chip: CGFloat = 8
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
            .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(highlight ?? FC.line, lineWidth: 1))
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
    /// 버튼으로 쓰는 칩은 크게(.large) — 44pt 탭 영역 안에서 칩이 너무 작으면 줄 사이가 휑해 보인다.
    var size: Size = .regular
    enum Size { case regular, large }
    var body: some View {
        Text(text).fcFont(size == .large ? 13 : 12, weight: .semibold).foregroundStyle(color)
            .padding(.horizontal, size == .large ? 12 : 8).padding(.vertical, size == .large ? 8 : 4)
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
                // 세 칸이 나란히 좁아 xxxLarge 에서 "72 / 63" 이 숫자 중간에서 줄바꿈됐다.
                // 숫자는 쪼개지면 뜻이 바뀌므로 한 줄 고정 + 필요한 만큼만 축소한다.
                Text(value).fcScoreboard(20).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

/// ErrorState 장식 분기용. Theme.swift 는 위젯 타깃에도 들어가는데 위젯에는 APIClient(APIError)가 없다 —
/// 분류 기준만 프로토콜로 두고 앱 타깃(Components.swift)에서 APIError 가 채택한다.
protocol ErrorDecorating {
    var decorationIsNotFound: Bool { get }
    var decorationIsNetwork: Bool { get }
}

struct ErrorState: View {
    let title: String
    var message: String? = nil
    /// 장식 분기용. 502·오프라인에도 "4:04" 를 띄우면 "없는 페이지"로 오해한다 — 원인에 맞는 장식을 고른다.
    var error: Error? = nil
    var retry: (() -> Void)? = nil

    private enum Kind { case notFound, network, other }
    private var kind: Kind {
        if let d = error as? ErrorDecorating {
            return d.decorationIsNotFound ? .notFound : d.decorationIsNetwork ? .network : .other
        }
        if error is URLError { return .network }
        return .other
    }

    var body: some View {
        VStack(spacing: 10) {
            switch kind {
            case .notFound: Text("4:04").fcScoreboard(44).foregroundStyle(FC.surface2)
            case .network: Image(systemName: "wifi.exclamationmark").fcFont(36).foregroundStyle(FC.muted)
            case .other: Image(systemName: "exclamationmark.triangle").fcFont(36).foregroundStyle(FC.muted)
            }
            Text(title).fcFont(17, weight: .semibold).foregroundStyle(FC.ink)
            if let message { Text(message).fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center) }
            if let retry {
                Button("다시 시도", action: retry).buttonStyle(BrandButtonStyle())
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }
}

struct Skeleton: View {
    var height: CGFloat = 80
    @State private var on = false
    /// "동작 줄이기"를 켠 사용자에게 무한 반복 깜빡임은 멀미·주의 분산 요인이다 — 정지 상태로 둔다.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.row).fill(FC.surface2).frame(height: height)
            .opacity(on && !reduceMotion ? 0.5 : 1)
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true } } }
            .accessibilityLabel("불러오는 중")
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


/// 브랜드 CTA — 그라디언트 캡슐 + 흰 글자. "지금 이걸 누르세요" 버튼에만 쓴다(화면당 하나 정도).
struct BrandButtonStyle: ButtonStyle {
    var fullWidth = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fcFont(compact ? 14 : 16, weight: .bold)
            .foregroundStyle(FC.brandInk)
            .padding(.horizontal, compact ? 14 : 22)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 36 : 50)
            .background(FC.brand, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}
