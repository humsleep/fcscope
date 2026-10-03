import SwiftUI

/// 실행 인트로 — 앱 아이콘 "S-spot"(그라디언트 S + 잘린 윗끝에서 튀어나온 공)을 그린다.
/// S 가 아래 끝에서 위 끝으로 공의 궤적처럼 그려지고, 잘린 윗끝에서 공이 제자리로 튀어나온 뒤
/// 워드마크가 뜨고 사라진다.
///
/// - 콜드 스타트마다 한 번(RootView 의 @State). 백그라운드 복귀에서는 다시 뜨지 않는다.
/// - 전체 약 1.3초. 탭하면 바로 넘어간다. "동작 줄이기"가 켜져 있으면 그리기 없이 짧게 페이드만 한다.
/// - 배경은 런치 스크린과 **같은 컬러셋**(`LaunchBackground`, 라이트 #F5F4FB / 다크 #0B0A1F — 앱 FC.bg 와 같은 값)을 직접 써서
///   인트로→홈 전환에도 이음새가 생길 수 없게 한다.
/// - 도형 좌표는 `docs/store-v2/icon-v3/final/mark.svg`(1024 기준)에서 가져왔다.
struct IntroView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    @State private var draw: CGFloat = 0
    @State private var glow = false
    @State private var ballIn = false
    @State private var textIn = false
    @State private var leaving = false
    @State private var finished = false

    private var dark: Bool { scheme == .dark }
    /// 공 색 — 다크는 아이콘처럼 흰색, 라이트는 아이콘 배경 인디고(밝은 배경 위 흰 공은 안 보인다).
    private var ballColor: Color { dark ? .white : SpotMark.indigo }

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            // 아이콘 왼쪽 위의 인디고 하이라이트. 런치 스크린은 단색이라 S 가 그려지는 동안 서서히 올린다.
            RadialGradient(
                colors: [SpotMark.highlight.opacity(dark ? 0.9 : 0.08), .clear],
                center: UnitPoint(x: 0.38, y: 0.12), startRadius: 0, endRadius: 520
            )
            .opacity(glow ? 1 : 0)

            VStack(spacing: 30) {
                mark
                wordmark
            }
            .scaleEffect(leaving ? 1.06 : 1)
        }
        .opacity(leaving ? 0 : 1)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FC Scope")
        .task { await play() }
    }

    // MARK: - 마크

    /// 1024 단위 → pt. S 높이(약 630단위)가 160pt 안팎이 되게.
    private static let s: CGFloat = 0.25

    private var mark: some View {
        let s = Self.s
        let spot = SpotMark.point(SpotMark.ball, s)
        let tip = SpotMark.point(SpotMark.topTerminal, s)
        return ZStack {
            // S 뒤의 은은한 마젠타 빛 — 블러 없이 방사 그라디언트만(블러는 콜드 스타트 첫 프레임을 막았다).
            RadialGradient(colors: [SpotMark.magenta.opacity(dark ? 0.32 : 0.16), .clear],
                           center: .center, startRadius: 0, endRadius: 150)
                .frame(width: 320, height: 320)
                .position(SpotMark.point(CGPoint(x: 512, y: 540), s))
                .opacity(glow ? 1 : 0)

            SpotMark.SPath()
                .trim(from: 0, to: draw)
                .stroke(SpotMark.gradient, style: StrokeStyle(lineWidth: 122 * s, lineCap: .butt, lineJoin: .round))

            // 공 — 잘린 윗끝에서 제자리로 튀어나온다
            Circle()
                .fill(ballColor)
                .frame(width: 2 * 68 * s, height: 2 * 68 * s)
                .shadow(color: dark ? .white.opacity(0.55) : SpotMark.magenta.opacity(0.35), radius: ballIn ? 10 : 0)
                .scaleEffect(ballIn ? 1 : 0.3)
                .position(ballIn ? spot : tip)
                .opacity(ballIn ? 1 : 0)
        }
        .frame(width: SpotMark.viewW * s, height: SpotMark.viewH * s)
    }

    // MARK: - 워드마크

    private var wordmark: some View {
        VStack(spacing: 6) {
            // 로그인 화면과 같은 워드마크(Chakra Petch). 강조색은 아이콘 그라디언트.
            (Text("FC ").foregroundStyle(SpotMark.textAccent(light: !dark)) + Text("SCOPE").foregroundStyle(FC.ink))
                .font(.scoreboard(32))
                .tracking(1.5)
            (Text("감이 아니라, ") + Text("데이터").foregroundStyle(SpotMark.textAccent(light: !dark)) + Text("로."))
                .fcFont(14, weight: .medium)
                .foregroundStyle(FC.muted)
        }
        .opacity(textIn ? 1 : 0)
        .offset(y: textIn ? 0 : 10)
    }

    // MARK: - 타임라인

    private func play() async {
        if reduceMotion {
            draw = 1; glow = true; ballIn = true; textIn = true
            try? await Task.sleep(for: .seconds(0.6))
            finish()
            return
        }
        // 전 과정을 한 트랜잭션의 delay 체인으로 건다. 콜드 스타트에서는 첫 프레임이 .task 시작보다
        // 0.5초쯤 늦게 그려지는데, Task.sleep 으로 단계를 나누면 벽시계가 먼저 흘러 뒤 단계가
        // 앞 단계보다 먼저 튀어나왔다(2026-10-03 시뮬레이터 녹화). delay 는 렌더 시점 기준이라 순서가 지켜진다.
        withAnimation(.easeInOut(duration: 0.55)) { draw = 1 }
        withAnimation(.easeOut(duration: 0.45).delay(0.25)) { glow = true }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.58).delay(0.5)) { ballIn = true }
        withAnimation(.easeOut(duration: 0.32).delay(0.62), completionCriteria: .logicallyComplete) {
            textIn = true
        } completion: {
            Task {
                try? await Task.sleep(for: .seconds(0.08))
                finish()
            }
        }
        // 안전망 — 완료 콜백이 어떤 이유로든 오지 않아도 인트로에 갇히지 않게.
        try? await Task.sleep(for: .seconds(3))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.28)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.28))
            onFinish()
        }
    }
}

/// 앱 아이콘 "S-spot" 도형 — mark.svg 의 1024 좌표.
///
/// SVG: `M562.94 270.37 A140 120 0 1 0 506 500 A156 134 0 1 1 370.90 701.00`, stroke 122, 공 (640.58, 346.92) r68.
/// 두 호를 중심 매개변수로 바꾸면 윗호 중심 (506,380) 반지름 (140,120), 아랫호 중심 (506,634) 반지름 (156,134).
/// 인트로는 공의 궤적처럼 **아래 끝 → 위 끝** 으로 그리므로 SVG 와 반대 방향으로 샘플링한다.
enum SpotMark {
    static let indigo = Color(UIColor(hex: 0x1E1957))
    static let highlight = Color(UIColor(hex: 0x28217A))
    static let magenta = Color(UIColor(hex: 0xE0218A))

    /// 보이는 영역(아이콘 단위) — S(305…723 × 200…830)와 공을 감싸는 상자
    static let viewX: CGFloat = 262, viewY: CGFloat = 180
    static let viewW: CGFloat = 500, viewH: CGFloat = 670

    static let ball = CGPoint(x: 640.58, y: 346.92)
    static let topTerminal = CGPoint(x: 562.94, y: 270.37)

    static func point(_ p: CGPoint, _ s: CGFloat) -> CGPoint {
        CGPoint(x: (p.x - viewX) * s, y: (p.y - viewY) * s)
    }

    /// 아이콘 세로 그라디언트: y 230 오렌지 → 마젠타 → y 860 바이올렛
    static let gradient = LinearGradient(
        colors: [Color(UIColor(hex: 0xFF5A26)), magenta, Color(UIColor(hex: 0x4A1FD6))],
        startPoint: UnitPoint(x: 0.5, y: (230 - viewY) / viewH),
        endPoint: UnitPoint(x: 0.5, y: (860 - viewY) / viewH)
    )

    struct SPath: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / SpotMark.viewW
            var path = Path()
            func add(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, from a0: Double, to a1: Double, first: Bool) {
                let n = 64
                for i in 0...n {
                    let t = (a0 + (a1 - a0) * Double(i) / Double(n)) * .pi / 180
                    let p = SpotMark.point(CGPoint(x: cx + rx * CGFloat(cos(t)), y: cy + ry * CGFloat(sin(t))), s)
                    if first && i == 0 { path.move(to: p) } else if i > 0 { path.addLine(to: p) }
                }
            }
            // 아랫호: 아래 끝(150°) → 가운데(-90°)
            add(cx: 506, cy: 634, rx: 156, ry: 134, from: 150, to: -90, first: true)
            // 윗호: 가운데(90° ≡ -270°) → 잘린 윗끝(-66.01°)
            add(cx: 506.01, cy: 380, rx: 140, ry: 120, from: -270, to: -66.01, first: false)
            return path
        }
    }

    /// 워드마크 강조용 그라디언트(마젠타 → 오렌지). 라이트는 대비를 위해 한 톤 진하게.
    static func textAccent(light: Bool) -> LinearGradient {
        LinearGradient(
            colors: light
                ? [Color(UIColor(hex: 0xC2187A)), Color(UIColor(hex: 0xE04A12))]
                : [Color(UIColor(hex: 0xFF4FA3)), Color(UIColor(hex: 0xFF9A3A))],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
