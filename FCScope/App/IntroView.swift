import SwiftUI

/// 실행 인트로 — 앱 아이콘(플라스크 + 공)을 선으로 그려 낸 뒤 워드마크를 띄우고 사라진다.
///
/// - 콜드 스타트마다 한 번(RootView 의 @State). 백그라운드 복귀에서는 다시 뜨지 않는다.
/// - 전체 약 1.4초. 탭하면 바로 넘어간다. "동작 줄이기"가 켜져 있으면 그리기 없이 짧게 페이드만 한다.
/// - 런치 스크린(LaunchBackground = #0A1119)과 같은 색에서 시작해 이음새가 보이지 않게 한다.
///   라이트 모드여도 인트로는 브랜드 다크 고정이다.
struct IntroView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: CGFloat = 0
    @State private var ballIn = false
    @State private var textIn = false
    @State private var leaving = false
    @State private var finished = false

    private static let bg = Color(UIColor(hex: 0x0a1119))
    private static let glow = Color(UIColor(hex: 0x17304a))
    private static let lime = Color(UIColor(hex: 0xc8f542))
    private static let muted = Color(UIColor(hex: 0x9aabc0))

    var body: some View {
        ZStack {
            Self.bg
            RadialGradient(colors: [Self.glow.opacity(0.9), .clear], center: .top, startRadius: 0, endRadius: 520)
            VStack(spacing: 22) {
                ZStack {
                    FCScopeMark.Outline()
                        .trim(from: 0, to: draw)
                        .stroke(Self.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    FCScopeMark.Ball()
                        .fill(Self.lime)
                        .scaleEffect(ballIn ? 1 : 0.2)
                        .opacity(ballIn ? 1 : 0)
                }
                .frame(width: 120, height: 120)
                .shadow(color: Self.lime.opacity(ballIn ? 0.35 : 0), radius: 24)

                VStack(spacing: 6) {
                    // 로그인 화면과 같은 워드마크(Chakra Petch, "FC " 라임 + "SCOPE" 흰색)
                    (Text("FC ").foregroundStyle(Self.lime) + Text("SCOPE").foregroundStyle(.white))
                        .font(.scoreboard(32))
                        .tracking(1.5)
                    (Text("감이 아니라, ") + Text("데이터").foregroundStyle(Self.lime) + Text("로."))
                        .fcFont(14, weight: .medium)
                        .foregroundStyle(Self.muted)
                }
                .opacity(textIn ? 1 : 0)
                .offset(y: textIn ? 0 : 10)
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

    private func play() async {
        if reduceMotion {
            draw = 1; ballIn = true; textIn = true
            try? await Task.sleep(for: .seconds(0.6))
            finish()
            return
        }
        withAnimation(.easeInOut(duration: 0.6)) { draw = 1 }
        try? await Task.sleep(for: .seconds(0.4))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { ballIn = true }
        try? await Task.sleep(for: .seconds(0.15))
        withAnimation(.easeOut(duration: 0.35)) { textIn = true }
        try? await Task.sleep(for: .seconds(0.55))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.3)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            onFinish()
        }
    }
}

/// 앱 아이콘 도형(1024 기준 좌표를 프레임에 맞춰 축소). 아이콘 PNG 와 같은 비율이다.
enum FCScopeMark {
    fileprivate static func map(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
        // 아이콘 안의 도형 영역(x 268…756, y 226…852)을 정사각형 프레임 가운데에 놓는다.
        let box = CGRect(x: 250, y: 220, width: 526, height: 640)
        let s = min(rect.width / box.width, rect.height / box.height)
        let ox = rect.midX - box.midX * s, oy = rect.midY - box.midY * s
        return { x, y in CGPoint(x: ox + x * s, y: oy + y * s) }
    }

    /// 플라스크(뚜껑·목·몸통)와 공의 바큇살 — 선으로 그린다.
    struct Outline: Shape {
        func path(in rect: CGRect) -> Path {
            let p = FCScopeMark.map(rect)
            let s = min(rect.width / 526, rect.height / 640)
            var path = Path()
            // 몸통 원 — 목과 만나는 위쪽에서 시작해 한 바퀴
            path.addArc(center: p(512, 610), radius: 222 * s, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
            // 목
            path.move(to: p(445, 390)); path.addLine(to: p(445, 255))
            path.move(to: p(578, 390)); path.addLine(to: p(578, 255))
            // 뚜껑
            path.move(to: p(400, 252)); path.addLine(to: p(625, 252))
            // 바큇살
            path.move(to: p(512, 418)); path.addLine(to: p(512, 512))
            path.move(to: p(340, 540)); path.addLine(to: p(428, 572))
            path.move(to: p(684, 540)); path.addLine(to: p(596, 572))
            path.move(to: p(408, 762)); path.addLine(to: p(460, 674))
            path.move(to: p(616, 762)); path.addLine(to: p(564, 674))
            return path
        }
    }

    /// 가운데 오각형(공의 패널) — 채운다.
    struct Ball: Shape {
        func path(in rect: CGRect) -> Path {
            let p = FCScopeMark.map(rect)
            var path = Path()
            path.move(to: p(512, 520))
            path.addLine(to: p(592, 578))
            path.addLine(to: p(562, 672))
            path.addLine(to: p(462, 672))
            path.addLine(to: p(432, 578))
            path.closeSubpath()
            return path
        }
    }
}
