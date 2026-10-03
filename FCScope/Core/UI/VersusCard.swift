import SwiftUI

/**
 친구랑 VS — 두 구단주의 `/api/v1/user/:nickname` 응답만으로 만드는 비교(화면·스토리 카드 공용).
 추가 API 호출이 없다: 승률·득실·스코어·진단 유형은 전부 overview 안에 있고, 폼 티어는 앱이 계산한다(FormTier.swift).
 */
struct VersusComparison {
    let a: UserOverview
    let b: UserOverview

    enum Side { case a, b, tie, none }

    struct Row: Identifiable {
        let label: String
        let left: String
        let right: String
        let winner: Side
        var id: String { label }
    }

    var tierA: FormTier { a.formTier }
    var tierB: FormTier { b.formTier }

    /// 비교 행. `winner` 가 .none 인 행(요즘 흐름)은 점수에 넣지 않는다. `.tie`(차이 없음)도 어느 쪽에도 세지 않는다.
    var rows: [Row] {
        func cmp(_ x: Double, _ y: Double, higherBetter: Bool = true, eps: Double = 0.05) -> Side {
            if abs(x - y) < eps { return .tie }
            return (x > y) == higherBetter ? .a : .b
        }
        let f1 = { (v: Double) in String(format: "%.1f", v) }
        var out: [Row] = [
            Row(label: "승률", left: "\(a.summary.winRate)%", right: "\(b.summary.winRate)%",
                winner: cmp(Double(a.summary.winRate), Double(b.summary.winRate), eps: 0.5)),
        ]
        let tierWinner: Side
        if let pa = tierA.points, let pb = tierB.points { tierWinner = cmp(Double(pa), Double(pb), eps: 0.5) } else { tierWinner = .none }
        // 같은 티어끼리면 이름만으로는 누가 앞인지 안 보인다 — 폼 점수를 붙인다.
        func tierText(_ t: FormTier) -> String { t.level.map { "\($0.name) \(t.points ?? 0)" } ?? "배치 중" }
        out.append(Row(label: "폼 티어", left: tierText(tierA), right: tierText(tierB), winner: tierWinner))
        out.append(Row(label: "경기당 득점", left: f1(a.goalsForPerGame), right: f1(b.goalsForPerGame), winner: cmp(a.goalsForPerGame, b.goalsForPerGame)))
        out.append(Row(label: "경기당 실점", left: f1(a.goalsAgainstPerGame), right: f1(b.goalsAgainstPerGame), winner: cmp(a.goalsAgainstPerGame, b.goalsAgainstPerGame, higherBetter: false)))
        out.append(Row(label: "FC 스코어", left: f1(a.score), right: f1(b.score), winner: cmp(a.score, b.score)))
        // 서버 진단 유형은 "플레이스타일"(성향 분석 · 스타일 탭)과 다른 값이다 — 같은 이름을 쓰면 화면마다 내 타입이 달라 보였다(QA P1-4)
        out.append(Row(label: "요즘 흐름", left: a.diagnosis.type?.title ?? "-", right: b.diagnosis.type?.title ?? "-", winner: .none))
        return out
    }

    /// 이긴 항목 수 (a, b)
    var tally: (Int, Int) {
        rows.reduce((0, 0)) { acc, r in
            switch r.winner {
            case .a: return (acc.0 + 1, acc.1)
            case .b: return (acc.0, acc.1 + 1)
            default: return acc
            }
        }
    }

    /// 동점 항목 수 — "1 : 3"인데 여섯 줄이면 나머지는 어디 갔는지 보이게(유저 패널 A·C)
    var ties: Int { rows.filter { $0.winner == .tie }.count }
    /// "이긴 항목 1 · 3 · 동점 1" — 경기 스코어처럼 보이던 "1 : 3"을 항목 수로 읽히게 쓴다
    var tallyNote: String {
        let (x, y) = tally
        return ties > 0 ? "동점 \(ties)개는 어느 쪽에도 세지 않아요" : "\(x + y)개 항목 비교"
    }

    /// 판정 한 줄 — 진 쪽도 올릴 수 있게 조롱하지 않는다.
    var verdict: String {
        let (x, y) = tally
        if x == y { return "막상막하, 다음 판이 결승전" }
        let lead = x > y ? a.profile.nickname : b.profile.nickname
        return abs(x - y) >= 3 ? "\(lead) 압승" : "\(lead) 근소 우세"
    }

    var matchTypeName: String {
        a.matchTabs.first { $0.type == a.matchType }?.label ?? (a.matchType == 52 ? "감독모드" : a.matchType == 40 ? "클래식 1on1" : "공식경기")
    }
}

// MARK: - 스토리 카드 (1080×1920)

struct VersusCardView: View {
    let c: VersusComparison
    let images: CardImages

    var body: some View {
        let (x, y) = c.tally
        TemplateCard(chip: "친구랑 VS", o: c.a, images: images,
                     kicker: "\(c.matchTypeName) · 최근 \(c.a.summary.played) vs \(c.b.summary.played)경기",
                     cta: "너도 친구랑 붙어 봐 →", showNickname: false) {
            // 히어로 칸 높이는 260 고정(TemplateCard) — 넘치면 위 킥커를 덮는다. 128 + 16 + 112 ≈ 256.
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    side(c.a, align: .leading)
                    Text("VS").font(.scoreboard(44)).foregroundStyle(CardPalette.muted).frame(width: 96)
                    side(c.b, align: .trailing)
                }
                // "1 : 3"이 경기 스코어로 읽혔다 — 가운데에 "이긴 항목"을 밝히고 콜론 대신 가운뎃점
                HStack(alignment: .center, spacing: 28) {
                    Text("\(x)").font(.scoreboard(88)).foregroundStyle(x >= y ? CardPalette.ink : CardPalette.muted)
                    VStack(spacing: 2) {
                        Text("이긴 항목").font(.pretendard(26, .bold)).foregroundStyle(CardPalette.muted)
                        Text(c.ties > 0 ? "동점 \(c.ties) 제외" : " ").font(.pretendard(20)).foregroundStyle(CardPalette.muted)
                    }
                    Text("\(y)").font(.scoreboard(88)).foregroundStyle(y >= x ? CardPalette.ink : CardPalette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: 112)
            }
        } sub: {
            CardStampView(text: c.verdict, color: x == y ? CardPalette.tint : CardPalette.gold).frame(maxWidth: .infinity)
        } content: {
            VStack(spacing: 12) {
                ForEach(c.rows) { r in row(r) }
                Text("폼 티어는 FC Scope 가 최근 경기로 계산한 등급이에요 · 넥슨 공식 등급 아님")
                    .font(.pretendard(20)).foregroundStyle(CardPalette.muted).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
        }
    }

    private func side(_ o: UserOverview, align: HorizontalAlignment) -> some View {
        let t = o.formTier
        return VStack(alignment: align, spacing: 8) {
            NicknameTitle(text: o.profile.nickname, maxSize: 56, minSize: 32, boxHeight: 68, width: 428,
                          color: CardPalette.ink, alignment: align == .leading ? .leading : .trailing)
            HStack(spacing: 10) {
                Circle().fill(LinearGradient(colors: [t.level?.colors.0 ?? CardPalette.muted, t.level?.colors.1 ?? CardPalette.line], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Text(t.label).font(.pretendard(30, .bold)).foregroundStyle(CardPalette.ink)
            }
            .padding(.horizontal, 18).frame(height: 52)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .frame(width: 428, alignment: align == .leading ? .leading : .trailing)
    }

    private func row(_ r: VersusComparison.Row) -> some View {
        HStack(spacing: 0) {
            value(r.left, win: r.winner == .a, lose: r.winner == .b, align: .leading)
            Text(r.label).font(.pretendard(26, .semibold)).foregroundStyle(CardPalette.muted).frame(width: 240)
            value(r.right, win: r.winner == .b, lose: r.winner == .a, align: .trailing)
        }
        .padding(.horizontal, 28).frame(height: 92)
        .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(CardPalette.line, lineWidth: 2))
    }

    /// 앞선 값 = ink + 틴트 점, 뒤진 값 = muted. 초록·빨강은 쓰지 않는다 — 친구가 앞선 값이 내 카드에서 "좋음(초록)"으로
    /// 읽혔다(디자인 M9). 점은 값의 안쪽(라벨 쪽)에 둔다.
    private func value(_ s: String, win: Bool, lose: Bool, align: Alignment) -> some View {
        let ascii = s.unicodeScalars.allSatisfy(\.isASCII)
        return HStack(spacing: 12) {
            if win, align == .trailing { Circle().fill(CardPalette.tint).frame(width: 14, height: 14) }
            Text(s).font(ascii ? .scoreboard(48) : .pretendard(34, win ? .bold : .medium))
                .foregroundStyle(lose ? CardPalette.muted : CardPalette.ink).lineLimit(1).minimumScaleFactor(0.6)
            if win, align == .leading { Circle().fill(CardPalette.tint).frame(width: 14, height: 14) }
        }
        .frame(maxWidth: .infinity, alignment: align)
    }
}
