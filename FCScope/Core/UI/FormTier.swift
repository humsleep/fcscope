import SwiftUI

/**
 FC Scope **폼 티어** — 앱이 계산하는 "요즘 폼" 등급. 넥슨 공식 등급이 아니다.

 왜 필요한가: 넥슨 API 는 현재 등급을 주지 않고 `maxdivision`(역대 최고 등급 + 달성일)만 준다.
 그래서 전적 헤더의 자랑거리가 "2020. 5. 24. 달성"이 되어 버렸다(UX-AUDIT-GENZ #4·#10, 패널 A "틀딱 인증").
 최근 경기만으로 매번 다시 계산되는 등급을 따로 둔다. 공식 등급과 헷갈리지 않게
 **이름에 넥슨 등급명(챔피언스·월드클래스·프로…)을 쓰지 않고**, 화면에는 항상 "폼"을 붙인다.

 ## 공식 (결정적 · 같은 입력이면 항상 같은 결과)

 입력은 `/api/v1/user/:nickname` 한 번의 응답(최근 최대 30경기, 화면의 매치 유형)뿐이다 — 추가 호출 없음.

 ```
 W  = 승률(%)                              summary.winRate — 앱 전체와 같은 몰수 포함 기준
 GD = 경기당 득실차                         (perf.goalsFor − perf.goalsAgainst) / perf.normalPlayed — 몰수(3:0) 제외
 S  = FC Scope 스코어(0~10)                 서버 score

 승률 점수   = clamp(W, 0, 100) × 0.50                    → 0 ~ 50
 득실 점수   = clamp((GD + 2) / 4, 0, 1) × 25             → GD −2 이하 0 · 0 이면 12.5 · +2 이상 25
 스코어 점수 = clamp(S, 0, 10) × 2.5                      → 0 ~ 25
 폼 점수     = 반올림(승률 점수 + 득실 점수 + 스코어 점수)  → 0 ~ 100 정수
 ```

 | 폼 점수 | 0–29 | 30–39 | 40–49 | 50–59 | 60–69 | 70–79 | 80–100 |
 |---|---|---|---|---|---|---|---|
 | 티어 | 브론즈 | 실버 | 골드 | 플래티넘 | 다이아 | 마스터 | 레전드 |

 - 기준점: 승률 50% · 득실 0 · 스코어 5.0 인 "딱 평균" 유저 = 25 + 12.5 + 12.5 = **50 → 플래티넘 하한**.
   절반이 이기고 절반이 지는 게임이라 평균을 가운데(4번째/7)에 둔다.
 - 승률에 절반을 주는 이유: 결과가 가장 직관적이고 유저가 납득한다. 득실·스코어는 "운으로 이긴 판"과
   "내용으로 이긴 판"을 가른다(같은 승률이면 내용이 좋은 쪽이 위).
 - **최소 표본 10경기.** 그 아래는 "배치 중"(N/10)으로만 보여 준다 — 3경기 3승으로 레전드가 되는 일을 막는다.
 - **"상위 X%"는 표시하지 않는다.** 앱이 아는 건 조회된 구단주들의 응답뿐이고, 전체 유저 분포를 대표하는
   표본(기준선)이 없다. 근거 없는 백분위를 만들지 않는다. 서버가 분포를 집계하게 되면 그때 붙인다.
 */
struct FormTier: Equatable {
    enum Level: Int, CaseIterable, Comparable {
        case bronze, silver, gold, platinum, diamond, master, legend

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var name: String {
            switch self {
            case .bronze: "브론즈"
            case .silver: "실버"
            case .gold: "골드"
            case .platinum: "플래티넘"
            case .diamond: "다이아"
            case .master: "마스터"
            case .legend: "레전드"
            }
        }
        /// 이 티어의 하한 점수
        var floor: Int { [0, 30, 40, 50, 60, 70, 80][rawValue] }
        var next: Level? { Level(rawValue: rawValue + 1) }

        static func of(points: Int) -> Level {
            allCases.last { points >= $0.floor } ?? .bronze
        }

        /// 배지 색 — 금속 느낌의 두 색. 티어는 "좋고 나쁨"이 있는 값이라 데이터 색 규칙 밖의 전용 팔레트를 쓴다.
        var colors: (Color, Color) {
            switch self {
            case .bronze: (Color(hex: 0xC98A5B), Color(hex: 0x8A5232))
            case .silver: (Color(hex: 0xD7DCE6), Color(hex: 0x8E97A8))
            case .gold: (Color(hex: 0xF7C948), Color(hex: 0xC48A12))
            case .platinum: (Color(hex: 0x6EE7D8), Color(hex: 0x1F9E9A))
            case .diamond: (Color(hex: 0x8CC8FF), Color(hex: 0x3B6FE0))
            case .master: (Color(hex: 0xC6A6FF), Color(hex: 0x7A3FE0))
            case .legend: (Color(hex: 0xFF8A4C), Color(hex: 0xE0218A))
            }
        }
        var symbol: String {
            switch self {
            case .bronze, .silver, .gold: "shield.fill"
            case .platinum, .diamond: "diamond.fill"
            case .master: "crown.fill"
            case .legend: "flame.fill"
            }
        }
    }

    static let minGames = 10

    let games: Int
    /// 표본 부족이면 nil(배치 중)
    let points: Int?
    let level: Level?
    /// 계산 입력 — 설명 시트(산식 풀이)에 그대로 보여 준다
    let winRate: Int
    let goalDiffPerGame: Double
    let score: Double

    /// 항목별 점수(설명 시트용) — points() 와 같은 식
    var parts: (win: Double, goal: Double, score: Double) {
        (Double(min(100, max(0, winRate))) * 0.5,
         min(1, max(0, (goalDiffPerGame + 2) / 4)) * 25,
         min(10, max(0, score)) * 2.5)
    }

    var isPlacement: Bool { level == nil }
    /// 다음 티어까지 남은 점수(레전드·배치 중이면 nil)
    var pointsToNext: Int? {
        guard let p = points, let next = level?.next else { return nil }
        return next.floor - p
    }
    var label: String { level.map { "폼 \($0.name)" } ?? "폼 배치 중" }

    /// 순수 함수 — 테스트·미리보기에서 직접 부른다.
    static func points(winRate: Int, goalDiffPerGame: Double, score: Double) -> Int {
        let w = Double(min(100, max(0, winRate))) * 0.5
        let gd = min(1, max(0, (goalDiffPerGame + 2) / 4)) * 25
        let s = min(10, max(0, score)) * 2.5
        return Int((w + gd + s).rounded())
    }

    init(games: Int, winRate: Int, goalDiffPerGame: Double, score: Double) {
        self.games = games
        self.winRate = winRate
        self.goalDiffPerGame = goalDiffPerGame
        self.score = score
        if games >= Self.minGames {
            let p = Self.points(winRate: winRate, goalDiffPerGame: goalDiffPerGame, score: score)
            points = p
            level = Level.of(points: p)
        } else {
            points = nil
            level = nil
        }
    }
}

extension UserOverview {
    /// 몰수 제외 경기당 득실차 — 몰수(3:0)가 섞이면 득실 부호가 뒤집힌다(데이터 감사 M1). 옛 서버는 summary 로 대체.
    var goalDiffPerGame: Double {
        let gf = perf.goalsFor ?? summary.goalsFor, ga = perf.goalsAgainst ?? summary.goalsAgainst
        let games = perf.normalPlayed.flatMap { $0 > 0 ? $0 : nil } ?? summary.played
        return Double(gf - ga) / Double(max(1, games))
    }
    var goalsForPerGame: Double {
        let gf = perf.goalsFor ?? summary.goalsFor
        let games = perf.normalPlayed.flatMap { $0 > 0 ? $0 : nil } ?? summary.played
        return Double(gf) / Double(max(1, games))
    }
    var goalsAgainstPerGame: Double {
        let ga = perf.goalsAgainst ?? summary.goalsAgainst
        let games = perf.normalPlayed.flatMap { $0 > 0 ? $0 : nil } ?? summary.played
        return Double(ga) / Double(max(1, games))
    }
    var formTier: FormTier {
        FormTier(games: summary.played, winRate: summary.winRate, goalDiffPerGame: goalDiffPerGame, score: score)
    }
}

// MARK: - 배지

/// 폼 티어 배지 — 금속 그라디언트 방패 + "폼 골드". 공식 등급이 아님을 라벨이 말한다.
struct FormTierBadge: View {
    let tier: FormTier
    var size: Size = .regular
    /// 탭 가능한 배지(설명 시트를 여는 버튼 안)에만 ⓘ 를 붙인다
    var showInfo = false
    enum Size { case compact, regular }

    var body: some View {
        HStack(spacing: size == .compact ? 4 : 6) {
            emblem
            Text(tier.label).fcRender(size == .compact ? 12 : 13, .bold).foregroundStyle(FC.ink).lineLimit(1).fixedSize()
            if let p = tier.points, size == .regular {
                // "40"만 있으면 상위 40%인지 40점인지 몰랐다(유저 패널 A) — 단위를 붙인다. 탭하면 산식 시트.
                Text("\(p)점").fcText(.meta, weight: .semibold).foregroundStyle(FC.muted).monospacedDigit()
            } else if tier.isPlacement {
                Text("\(tier.games)/\(FormTier.minGames)").fcScoreboard(12, weight: .semibold).foregroundStyle(FC.muted)
            }
            if showInfo {
                Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
            }
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .background(FC.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.isPlacement
            ? "FC Scope 폼 티어 배치 중, \(tier.games)경기 중 \(FormTier.minGames)경기 필요"
            : "FC Scope 폼 티어 \(tier.level?.name ?? ""), \(tier.points ?? 0)점")
    }

    private var stroke: LinearGradient {
        let (a, b) = tier.level?.colors ?? (FC.line, FC.line)
        return LinearGradient(colors: [a.opacity(0.9), b.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
    }

    private var emblem: some View {
        let d: CGFloat = size == .compact ? 18 : 22
        return ZStack {
            if let l = tier.level {
                Circle().fill(LinearGradient(colors: [l.colors.0, l.colors.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: l.symbol).font(.system(size: d * 0.5, weight: .bold)).foregroundStyle(.white.opacity(0.92))
            } else {
                Circle().strokeBorder(FC.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                Image(systemName: "hourglass").font(.system(size: d * 0.45, weight: .bold)).foregroundStyle(FC.muted)
            }
        }
        .frame(width: d, height: d)
    }
}

/// 배지를 누르면 산식 시트 — "골드 40"이 몇 점 만점이고 무엇으로 계산했는지(유저 패널 A·C).
struct FormTierButton: View {
    let tier: FormTier
    var size: FormTierBadge.Size = .regular
    @State private var show = false
    var body: some View {
        Button { Haptic.light(); show = true } label: {
            FormTierBadge(tier: tier, size: size, showInfo: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("폼 티어 계산 방법 보기")
        .sheet(isPresented: $show) { FormTierInfoSheet(tier: tier) }
    }
}

struct FormTierInfoSheet: View {
    let tier: FormTier
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        FormTierBadge(tier: tier)
                        Spacer()
                    }
                    Text("폼 티어는 FC Scope 가 **최근 \(tier.games)경기**만으로 매번 다시 계산하는 \"요즘 폼\" 등급이에요. 넥슨 공식 등급(챔피언스·월드클래스 등)과는 달라요.")
                        .fcText(.callout).foregroundStyle(FC.ink).fixedSize(horizontal: false, vertical: true)
                    if tier.isPlacement {
                        Text("10경기를 채우면 등급이 나와요. 지금 \(tier.games)경기예요.")
                            .fcText(.callout).foregroundStyle(FC.muted)
                    } else {
                        breakdown
                    }
                    ladder
                    Text("승률이 절반, 득실과 FC 스코어가 4분의 1씩이에요. 승률 50% · 득실 0 · 스코어 5.0 인 딱 평균이면 50점(플래티넘 시작)이에요.")
                        .fcText(.meta).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(FC.bg.ignoresSafeArea())
            .navigationTitle("폼 티어는 이렇게 계산해요").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var breakdown: some View {
        let p = tier.parts
        let gd = tier.goalDiffPerGame
        return VStack(spacing: 0) {
            row("승률 \(tier.winRate)%", "× 0.5", p.win, of: 50)
            Divider().overlay(FC.line)
            row("경기당 득실 \(gd >= 0 ? "+" : "")\(String(format: "%.1f", gd))", "−2 ~ +2 → 0 ~ 25", p.goal, of: 25)
            Divider().overlay(FC.line)
            row("FC 스코어 \(String(format: "%.1f", tier.score))", "× 2.5", p.score, of: 25)
            Divider().overlay(FC.line)
            HStack {
                Text("합계").fcText(.callout, weight: .bold).foregroundStyle(FC.ink)
                Spacer()
                Text("\(tier.points ?? 0)점 / 100").fcScoreboard(16).foregroundStyle(FC.ink)
            }
            .padding(.vertical, 10)
            if let next = tier.level?.next, let gap = tier.pointsToNext {
                Text("다음 등급 \(next.name)까지 \(gap)점").fcText(.meta, weight: .semibold).foregroundStyle(FC.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(FC.line, lineWidth: 1))
    }

    private func row(_ label: String, _ rule: String, _ value: Double, of max: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).fcText(.callout, weight: .semibold).foregroundStyle(FC.ink)
                Text(rule).fcText(.caption).foregroundStyle(FC.muted)
            }
            Spacer()
            Text("\(String(format: "%.1f", value)) / \(max)").fcScoreboard(14, weight: .semibold).foregroundStyle(FC.ink).monospacedDigit()
        }
        .padding(.vertical, 10)
    }

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("등급 구간").fcText(.label).foregroundStyle(FC.muted)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(FormTier.Level.allCases, id: \.self) { l in
                    let on = l == tier.level
                    let upper = l.next.map { "\($0.floor - 1)" } ?? "100"
                    Text("\(l.name) \(l.floor)~\(upper)")
                        .fcText(.meta, weight: on ? .bold : .regular)
                        .foregroundStyle(on ? FC.ink : FC.muted)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(on ? FC.tint.opacity(0.14) : FC.surface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? FC.tint : .clear, lineWidth: 1.2))
                }
            }
        }
    }
}

#if DEBUG
/// 테스트 타깃이 없어 공식의 경계값을 여기서 고정한다 — 미리보기를 열면 실패한 줄이 빨갛게 보인다.
enum FormTierChecks {
    struct Case { let name: String; let w: Int; let gd: Double; let s: Double; let games: Int; let expect: FormTier.Level? }
    static let cases: [Case] = [
        Case(name: "딱 평균 → 플래티넘 하한", w: 50, gd: 0, s: 5.0, games: 30, expect: .platinum),
        Case(name: "전패·득실 −3·0점 → 브론즈", w: 0, gd: -3, s: 0, games: 30, expect: .bronze),
        Case(name: "전승·득실 +3·10점 → 레전드", w: 100, gd: 3, s: 10, games: 30, expect: .legend),
        Case(name: "30%·−0.4·4.3 → 실버", w: 30, gd: -0.4, s: 4.3, games: 30, expect: .silver),
        Case(name: "보엠(2026-10-03) 30%·+0.3·4.3 → 골드 40", w: 30, gd: 0.3, s: 4.3, games: 30, expect: .gold),
        Case(name: "60%·+0.8·6.5 → 다이아", w: 60, gd: 0.8, s: 6.5, games: 30, expect: .diamond),
        Case(name: "9경기 → 배치 중", w: 100, gd: 3, s: 10, games: 9, expect: nil),
    ]
    static func run() -> [(String, Bool, String)] {
        cases.map { c in
            let t = FormTier(games: c.games, winRate: c.w, goalDiffPerGame: c.gd, score: c.s)
            return (c.name, t.level == c.expect, "\(t.points.map(String.init) ?? "-")점 · \(t.label)")
        }
    }
}

#Preview("폼 티어 공식 검사") {
    ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(FormTierChecks.run(), id: \.0) { name, ok, got in
                HStack {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(ok ? FC.win : FC.lose)
                    Text(name).fcFont(13)
                    Spacer()
                    Text(got).fcFont(12).foregroundStyle(FC.muted)
                }
            }
            Divider()
            ForEach(FormTierChecks.cases, id: \.name) { c in
                FormTierBadge(tier: FormTier(games: c.games, winRate: c.w, goalDiffPerGame: c.gd, score: c.s))
            }
        }
        .padding()
    }
    .background(FC.bg)
}
#endif
