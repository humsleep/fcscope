import SwiftUI

/// 실행 인트로 — 앱 아이콘(원근 페널티 박스 + 골대 + 히트맵)을 선으로 그려 낸 뒤
/// 히트 글로우를 피우고, 페널티 스폿을 찍고, 워드마크를 띄우고 사라진다.
///
/// - 콜드 스타트마다 한 번(RootView 의 @State). 백그라운드 복귀에서는 다시 뜨지 않는다.
/// - 전체 약 1.4초. 탭하면 바로 넘어간다. "동작 줄이기"가 켜져 있으면 그리기 없이 짧게 페이드만 한다.
/// - 배경은 런치 스크린과 **같은 컬러셋**(`LaunchBackground`, 라이트 #EEF1F6 / 다크 #0A0922)을 직접 써서
///   이음새가 생길 수 없게 한다. 다크 값은 아이콘 배경의 남흑색 — 바꾸려면 컬러셋 하나만 바꾸면 된다.
/// - 도형 좌표는 `docs/store-v2/icon-v2/final/final.svg`(1024 기준)에서 그대로 가져왔다.
struct IntroView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    @State private var goalLine: CGFloat = 0
    @State private var box: CGFloat = 0
    @State private var goal: CGFloat = 0
    @State private var arc: CGFloat = 0
    @State private var netIn = false
    @State private var heat = false
    @State private var spot = false
    @State private var textIn = false
    @State private var leaving = false
    @State private var finished = false

    private var dark: Bool { scheme == .dark }
    /// 선 색 — 다크는 아이콘처럼 흰 유리선, 라이트는 아이콘 배경의 인디고로 뒤집는다(밝은 배경 위 흰 선은 안 보인다).
    private var lineColor: Color { dark ? .white : FCScopeMark.indigo }
    private var spotColor: Color { dark ? .white : FCScopeMark.indigo }

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            // 아이콘 왼쪽 위의 인디고 하이라이트. 런치 스크린은 단색이라 글로우와 함께 서서히 올린다.
            RadialGradient(
                colors: [FCScopeMark.indigo.opacity(dark ? 0.85 : 0.10), .clear],
                center: UnitPoint(x: 0.2, y: 0.05), startRadius: 0, endRadius: 560
            )
            .opacity(heat ? 1 : 0)

            VStack(spacing: 26) {
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

    private static let markWidth: CGFloat = 340

    private var mark: some View {
        let w = Self.markWidth
        let s = w / 1024
        return ZStack {
            lines(s: s)
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.24),
                        .init(color: .black, location: 0.76),
                        .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                )
                .shadow(color: dark ? .white.opacity(0.22) : .clear, radius: 6)

            Circle()
                .fill(spotColor)
                .frame(width: 2 * 27.3 * s, height: 2 * 27.3 * s)
                .shadow(color: dark ? Color(UIColor(hex: 0xFFF3C2)).opacity(0.9) : .clear, radius: 8)
                .position(FCScopeMark.point(512, 595, s))
                .scaleEffect(spot ? 1 : 0.2, anchor: UnitPoint(x: 0.5, y: (595 - FCScopeMark.viewY) / FCScopeMark.viewH))
                .opacity(spot ? 1 : 0)
        }
        .frame(width: w, height: FCScopeMark.viewH * s)
        // 글로우 캔버스는 블러 여유 때문에 마크보다 크다. ZStack 형제로 두면 선 도형의 제안 크기까지
        // 키워 버리므로 배경으로 붙여 마크 프레임(340pt)은 그대로 둔다.
        .background {
            // 미리 구운 이미지(scripts/render-intro-heat.swift). 라이트·다크 변형은 에셋 appearance 로 갈린다.
            Image("IntroHeat")
                .resizable()
                .frame(width: (1024 + 2 * FCScopeMark.heatPad) * s,
                       height: (FCScopeMark.viewH + 2 * FCScopeMark.heatPad) * s)
                .scaleEffect(heat ? 1 : 0.55)
                .opacity(heat ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private func lines(s: CGFloat) -> some View {
        let wide = StrokeStyle(lineWidth: 44 * s * 0.82, lineCap: .round, lineJoin: .round)
        let frame = StrokeStyle(lineWidth: 35.2 * s * 0.82, lineCap: .round, lineJoin: .round)
        return ZStack {
            // 골망 — 프레임이 서면 은은하게 들어온다
            FCScopeMark.NetFill().fill(lineColor.opacity(0.10)).opacity(netIn ? 1 : 0)
            FCScopeMark.Net().stroke(lineColor.opacity(0.32), lineWidth: 7 * s).opacity(netIn ? 1 : 0)
            FCScopeMark.NetBack()
                .stroke(lineColor.opacity(0.5), style: StrokeStyle(lineWidth: 11.4 * s, lineCap: .round, lineJoin: .round))
                .opacity(netIn ? 1 : 0)

            mirrored(FCScopeMark.goalLine, t: goalLine, style: wide)
            mirrored(FCScopeMark.penaltyBox, t: box, style: wide)
            mirrored(FCScopeMark.sixYard, t: box, style: wide)
            mirrored(FCScopeMark.dArc, t: arc, style: wide)
            mirrored(FCScopeMark.goalFrame, t: goal, style: frame)
        }
    }

    /// 좌우 대칭 도형 — 왼쪽 절반과 거울상을 같은 진행도로 동시에 그린다.
    private func mirrored(_ pts: [CGPoint], t: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            FCScopeMark.Polyline(points: pts, mirrored: false).trim(from: 0, to: t).stroke(lineColor, style: style)
            FCScopeMark.Polyline(points: pts, mirrored: true).trim(from: 0, to: t).stroke(lineColor, style: style)
        }
    }

    // MARK: - 워드마크

    private var wordmark: some View {
        VStack(spacing: 6) {
            // 로그인 화면과 같은 워드마크(Chakra Petch). 강조색은 아이콘 히트 그라디언트.
            (Text("FC ").foregroundStyle(FCScopeMark.heatText(light: !dark)) + Text("SCOPE").foregroundStyle(FC.ink))
                .font(.scoreboard(32))
                .tracking(1.5)
            (Text("감이 아니라, ") + Text("데이터").foregroundStyle(FCScopeMark.heatText(light: !dark)) + Text("로."))
                .fcFont(14, weight: .medium)
                .foregroundStyle(FC.muted)
        }
        .opacity(textIn ? 1 : 0)
        .offset(y: textIn ? 0 : 10)
    }

    // MARK: - 타임라인

    private func play() async {
        if reduceMotion {
            goalLine = 1; box = 1; goal = 1; arc = 1
            netIn = true; heat = true; spot = true; textIn = true
            try? await Task.sleep(for: .seconds(0.6))
            finish()
            return
        }
        // 전 과정을 한 트랜잭션의 delay 체인으로 건다. 콜드 스타트에서는 첫 프레임이 .task 시작보다
        // 0.5초쯤 늦게 그려지는데, Task.sleep 으로 단계를 나누면 벽시계가 먼저 흘러 스폿·워드마크가
        // 선보다 앞서 튀어나왔다(2026-10-03 시뮬레이터 녹화). delay 는 렌더 시점 기준이라 순서가 지켜진다.
        // 선: 골라인이 가운데서 양옆으로 → 박스가 위에서 내려와 아래 가운데서 닫힘 → 골대 → D 아크
        withAnimation(.easeOut(duration: 0.38)) { goalLine = 1 }
        withAnimation(.easeInOut(duration: 0.46).delay(0.08)) { box = 1 }
        withAnimation(.easeOut(duration: 0.36).delay(0.14)) { goal = 1 }
        withAnimation(.easeOut(duration: 0.34).delay(0.26)) { arc = 1 }
        withAnimation(.easeOut(duration: 0.3).delay(0.4)) { netIn = true }
        // 히트 글로우가 피어오르고, 페널티 스폿이 찍히고, 워드마크
        withAnimation(.easeOut(duration: 0.55).delay(0.42)) { heat = true }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55).delay(0.66)) { spot = true }
        withAnimation(.easeOut(duration: 0.35).delay(0.72), completionCriteria: .logicallyComplete) {
            textIn = true
        } completion: {
            Task {
                try? await Task.sleep(for: .seconds(0.06))
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

/// 앱 아이콘 도형 — `final.svg` 의 1024 좌표를 그대로 쓴다. 보이는 영역은 y 140…910.
enum FCScopeMark {
    static let indigo = Color(UIColor(hex: 0x1E1957))
    static let viewY: CGFloat = 140
    static let viewH: CGFloat = 770
    /// 블러가 잘리지 않게 히트 캔버스를 사방으로 넓히는 여백(아이콘 단위)
    static let heatPad: CGFloat = 320

    static func point(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: (y - viewY) * s)
    }

    // 왼쪽 절반(그리는 순서대로). 오른쪽은 x → 1024 - x 거울상.
    static let goalLine = [CGPoint(x: 512, y: 330), CGPoint(x: -60, y: 330)]
    static let penaltyBox = [CGPoint(x: 250, y: 330), CGPoint(x: -40, y: 760), CGPoint(x: 512, y: 760)]
    static let sixYard = [CGPoint(x: 347, y: 330), CGPoint(x: 327, y: 405), CGPoint(x: 512, y: 405)]
    static let goalFrame = [CGPoint(x: 387, y: 330), CGPoint(x: 387, y: 180), CGPoint(x: 512, y: 180)]
    static let dArc: [CGPoint] = [
        (281.7, 760.0), (289.7, 771.3), (298.2, 782.2), (307.1, 792.7), (316.6, 802.7), (326.5, 812.2),
        (336.8, 821.2), (347.6, 829.7), (358.7, 837.7), (370.2, 845.1), (382.0, 851.9), (394.1, 858.1),
        (406.5, 863.6), (419.2, 868.6), (432.0, 872.9), (445.1, 876.6), (458.3, 879.6), (471.6, 882.0),
        (485.0, 883.6), (498.5, 884.7), (512.0, 885.0),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    struct Polyline: Shape {
        let points: [CGPoint]
        let mirrored: Bool
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024
            var path = Path()
            for (i, p) in points.enumerated() {
                let q = FCScopeMark.point(mirrored ? 1024 - p.x : p.x, p.y, s)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            return path
        }
    }

    /// 골망 세로·가로줄
    struct Net: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024
            var path = Path()
            let cols: [(CGFloat, CGFloat)] = [(422.7, 432.7), (458.4, 464.4), (494.1, 496.1),
                                              (529.9, 527.9), (565.6, 559.6), (601.3, 591.3)]
            for (front, back) in cols {
                path.move(to: point(front, 180, s))
                path.addLine(to: point(back, 156.2, s))
                path.addLine(to: point(back, 296, s))
            }
            for y in [191.1, 226.1, 261.1] as [CGFloat] {
                path.move(to: point(401, y, s)); path.addLine(to: point(623, y, s))
            }
            return path
        }
    }

    /// 골대 뒤 프레임(원근)
    struct NetBack: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024
            var path = Path()
            path.move(to: point(387, 180, s)); path.addLine(to: point(401, 156.2, s)); path.addLine(to: point(401, 296, s))
            path.move(to: point(637, 180, s)); path.addLine(to: point(623, 156.2, s)); path.addLine(to: point(623, 296, s))
            path.move(to: point(401, 156.2, s)); path.addLine(to: point(623, 156.2, s))
            return path
        }
    }

    struct NetFill: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024
            return Path(CGRect(origin: point(401, 156.2, s), size: CGSize(width: 222 * s, height: 139.8 * s)))
        }
    }

    /// 워드마크 강조용 히트 그라디언트(마젠타 → 오렌지). 라이트는 대비를 위해 한 톤 진하게.
    static func heatText(light: Bool) -> LinearGradient {
        LinearGradient(
            colors: light
                ? [Color(UIColor(hex: 0xC2187A)), Color(UIColor(hex: 0xE04A12))]
                : [Color(UIColor(hex: 0xFF4FA3)), Color(UIColor(hex: 0xFF9A3A))],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
