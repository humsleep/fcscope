import SwiftUI

/**
 매치 리포트 결과 히어로(UX-AUDIT-GENZ #5, 목업 ux-mockups/03-match.png).

 랭겜 직후 앱을 여는 이유는 "방금 그 판" — 맨 위 한 장에 결과·스코어·핵심 3지표를 모은다.
 - 결과색 그라디언트 카드(승 민트 · 패 레드 · 무 회보라) — 결과는 "의미"라 데이터 색을 쓴다.
 - 스코어 64pt, 0부터 한 골씩 올라가는 카운트업. 동작 줄이기면 바로 최종값.
 - 이긴 경기만 성공 햅틱 1회(사용자가 결과를 처음 보는 순간). 패배·무승부에는 울리지 않는다.
 */
struct MatchResultHero: View {
    let m: MatchDetailResponse
    var onTapUser: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownMe = 0
    @State private var shownOpp = 0
    @State private var celebrated = false
    @State private var counted = false
    @State private var showScoreParts = false

    private var tone: Color { FC.resultColor(m.me.result) }
    private var resultWord: String {
        switch m.me.result { case "승": "승리"; case "패": "패배"; default: "무승부" }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                name(m.me.nickname, me: true)
                Text("FINAL").fcScoreboard(11, weight: .semibold).kerning(2).foregroundStyle(FC.muted).fixedSize()
                if let o = m.opponent { name(o.nickname, me: false) } else { Spacer().frame(maxWidth: .infinity) }
            }
            HStack(alignment: .center, spacing: 18) {
                Text("\(shownMe)").font(.fcScoreboard(64, typeSize)).foregroundStyle(FC.ink)
                    .contentTransition(.numericText(value: Double(shownMe)))
                Text(":").font(.fcScoreboard(36, typeSize)).foregroundStyle(FC.muted)
                Text(m.opponent.map { _ in "\(shownOpp)" } ?? "-").font(.fcScoreboard(64, typeSize))
                    .foregroundStyle(m.me.result == "승" ? FC.muted : FC.ink)
                    .contentTransition(.numericText(value: Double(shownOpp)))
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(resultWord), \(m.me.goals) 대 \(m.opponent?.goals ?? 0)")

            VStack(spacing: 4) {
                Text(m.heroLine(resultWord: resultWord)).fcFont(16, weight: .bold).foregroundStyle(tone)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                if m.me.forfeit { Text("몰수 경기 · 한쪽 이탈·연결 끊김").fcFont(12, weight: .semibold).foregroundStyle(FC.muted) }
            }

            possession

            HStack(spacing: 8) {
                statBox(m.opponent.map { "\(m.me.stats.shots) / \($0.stats.shots)" } ?? "\(m.me.stats.shots)", m.opponent == nil || typeSize.isAccessibilitySize ? "슛" : "슛 · 나/상대")
                // 옆 칸과 같은 형식인데 (나/상대)가 빠져 헷갈렸다(유저 패널 C)
                statBox(m.opponent.map { "\(m.me.stats.effectiveShots) / \($0.stats.effectiveShots)" } ?? "\(m.me.stats.effectiveShots)", m.opponent == nil || typeSize.isAccessibilitySize ? "유효슛" : "유효슛 · 나/상대")
                // 세 번째 칸은 항상 "경기 평점"(넥슨 matchDetail 의 내 평점). FC 스코어는 전적 응답(MatchSummary)에만 있어
                // 디스크 캐시 유무에 따라 칸 이름과 숫자가 바뀌었다(같은 경기가 "FC 스코어 6.8" ↔ "경기 평점 7.2" — QA 4R).
                // 경기 평점은 매치 응답에 늘 있어 추가 네트워크가 없다. 경기별 FC 스코어는 전적 경기 목록 행에 그대로 있다.
                // 경기력 — 전적 목록·헤더와 같은 숫자(UX 패널 2026-11 R3: 리포트에만 경기력이 없었다). 넥슨 평점은 아래 팀 스탯 표로.
                let sc = m.myScore
                // 누르면 계산 근거 — "승패를 다시 포장한 숫자"로 보였다(UX 패널 R3·R4). 무엇이 몇 점을 보탰는지 그대로 보인다.
                Button { Haptic.light(); showScoreParts = true } label: {
                    statBox(String(format: "%.1f", sc), m.me.forfeit ? "몰수 고정값" : "경기력 ⓘ", color: m.me.forfeit ? FC.muted : sc >= 6.5 ? FC.win : sc < 5 ? FC.lose : FC.ink)
                }
                .buttonStyle(.plain)
                .accessibilityHint("경기력 계산 근거 보기")
                .popover(isPresented: $showScoreParts, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("이 경기 경기력 \(String(format: "%.1f", sc))").fcText(.headline).foregroundStyle(FC.ink)
                        ForEach(m.scoreParts, id: \.label) { part in
                            HStack {
                                Text(part.label).fcText(.callout).foregroundStyle(FC.ink)
                                Spacer(minLength: 12)
                                Text(part.value).fcScoreboard(14).foregroundStyle(FC.muted)
                            }
                        }
                        Text("10점 만점 · 5~6.4가 평균").fcText(.meta).foregroundStyle(FC.muted)
                    }
                    .padding(16).frame(width: 300, alignment: .leading).background(FC.surface)
                    .presentationCompactAdaptation(.popover)
                }
            }
            // 핵심 숫자인데 뜻이 어디에도 없었다(UX 패널 R6 P2) — 칸 바로 아래 한 줄
            Text("유효슛 = 골문 안으로 간 슛(골 포함)").fcText(.meta).foregroundStyle(FC.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                FC.surface
                // 결과색(승·패) 옅은 단색 + 분필선 — 예전 방사형 글로우를 걷어냈다
                tone.opacity(0.10)
                PitchMarkings(color: tone.opacity(0.14))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tone.opacity(0.5), lineWidth: 1))
        .sensoryFeedback(.success, trigger: celebrated) { _, new in new }
        .task { await countUp() }
    }

    private func name(_ n: String, me: Bool) -> some View {
        Button { onTapUser(n) } label: {
            Text(n).fcFont(15, weight: .bold).foregroundStyle(me ? FC.tint : FC.ink).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: me ? .leading : .trailing)
                .frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n) 전적 보기")
    }

    private var possession: some View {
        VStack(spacing: 3) {
            // 나 = tint, 상대 = 중립 muted. 패배 빨강은 결과(패)와 나쁨에만 — 이긴 경기에도 빨강이 섞였다(디자인 M9)
            Rectangle().fill(FC.muted.opacity(0.45))
                .overlay(BarSegment(to: CGFloat(m.me.possession) / 100).fill(FC.tint))
                .frame(height: 8).clipShape(Capsule())
            HStack {
                Text("\(m.me.possession)%").foregroundStyle(FC.tint)
                Spacer(); Text("점유율").foregroundStyle(FC.muted); Spacer()
                Text("\(100 - m.me.possession)%").foregroundStyle(FC.muted)
            }
            .fcScoreboard(12, weight: .semibold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("점유율 \(m.me.possession)퍼센트")
    }

    private func statBox(_ value: String, _ label: String, color: Color = FC.ink) -> some View {
        VStack(spacing: 2) {
            Text(value).fcScoreboard(20).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).fcFont(11).foregroundStyle(FC.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(FC.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FC.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// 한 골씩 올라간다(최대 10단계, 0.07초 간격). 두 숫자를 같은 박자로 — 큰 쪽이 끝날 때 함께 멈춘다.
    @MainActor
    private func countUp() async {
        guard !counted else { return }
        counted = true
        let a = m.me.goals, b = m.opponent?.goals ?? 0
        if reduceMotion {
            shownMe = a; shownOpp = b
        } else {
            let steps = min(10, max(a, b))
            for i in 0...steps {
                if i > 0 { try? await Task.sleep(for: .milliseconds(70)) }
                guard !Task.isCancelled else { break }
                withAnimation(.snappy(duration: 0.18)) {
                    shownMe = steps == 0 ? a : min(a, Int((Double(a) * Double(i) / Double(steps)).rounded()))
                    shownOpp = steps == 0 ? b : min(b, Int((Double(b) * Double(i) / Double(steps)).rounded()))
                }
            }
            shownMe = a; shownOpp = b
        }
        if m.me.result == "승", !m.me.forfeit { celebrated = true }
    }
}


extension MatchDetailResponse {
    /// 이 경기의 경기력(0~10) — 서버 lib/nexon/score.ts matchScore 와 같은 식. 매치 응답엔 점수가 없어 여기서 계산한다.
    /// 식을 바꾸면 서버와 함께 바꿀 것(전적 목록의 숫자와 어긋난다).
    var myScore: Double {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
        let r = me.result
        if me.forfeit { return r == "승" ? 6 : r == "패" ? 3 : 5 }
        var s = r == "승" ? 6.5 : r == "패" ? 3.8 : 5.0
        s += clamp(Double(me.goals - (opponent?.goals ?? 0)), -4, 4) * 0.35
        if me.rating > 0 { s += clamp(me.rating - 6.7, -1.5, 1.5) * 0.8 }   // 6.7 = TEAM_RATING_MEDIAN
        s += clamp(Double(me.possession - 50) / 50, -1, 1) * 0.4
        return (clamp(s, 0, 10) * 10).rounded() / 10
    }
}


extension MatchDetailResponse {
    /// 경기력 계산 근거(myScore 와 같은 식) — 항목, 보탠 점수
    var scoreParts: [(label: String, value: String)] {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
        func signed(_ v: Double) -> String { v >= 0 ? String(format: "+%.2f", v) : String(format: "%.2f", v) }
        let r = me.result
        if me.forfeit { return [("몰수\(r) 고정값", String(format: "%.1f", r == "승" ? 6.0 : r == "패" ? 3.0 : 5.0))] }
        let base = r == "승" ? 6.5 : r == "패" ? 3.8 : 5.0
        let diff = me.goals - (opponent?.goals ?? 0)
        var parts: [(label: String, value: String)] = [("결과(\(r)) 기본", String(format: "%.1f", base))]
        parts.append(("점수 차 \(diff > 0 ? "+" : "")\(diff)골", signed(clamp(Double(diff), -4, 4) * 0.35)))
        if me.rating > 0 { parts.append(("넥슨 평점 \(String(format: "%.1f", me.rating)) (보통 6.7)", signed(clamp(me.rating - 6.7, -1.5, 1.5) * 0.8))) }
        parts.append(("점유율 \(me.possession)%", signed(clamp(Double(me.possession - 50) / 50, -1, 1) * 0.4)))
        return parts
    }

    /// 이긴 경기 "이렇게 이겼어요" — 이 경기 기록에서만 뽑은 최대 2줄. 진 경기는 서버 lossReasons 를 쓴다.
    var winReasons: [String] {
        guard me.result == "승", !me.forfeit, let o = opponent else { return [] }
        var out: [String] = []
        let eff = me.stats.effectiveShots
        if eff > 0, Double(me.goals) / Double(eff) >= 0.5 { out.append("유효슛 \(eff)개로 \(me.goals)골, 결정력이 좋았어요") }
        if o.stats.effectiveShots <= 2 { out.append("상대 유효슛을 \(o.stats.effectiveShots)개로 막았어요") }
        if me.stats.shots >= o.stats.shots + 3 { out.append("슛 \(me.stats.shots) 대 \(o.stats.shots), 기회를 더 많이 만들었어요") }
        // 슛에서 밀렸는데 "주도했어요"라고 칭찬하던 것(UX 패널 R6) — 슛이 뒤지지 않을 때만 주도라고 말한다
        if me.possession >= 56, me.stats.shots >= o.stats.shots { out.append("점유율 \(me.possession)%로 경기를 주도했어요") }
        else if me.possession <= 44 { out.append("점유율 \(me.possession)%로도 이겼어요, 역습이 통했어요") }
        if let p = potm, p.side == me.nickname { out.append("최우수 선수 \(p.name)(평점 \(String(format: "%.1f", p.rating)))이 경기를 이끌었어요") }
        return Array(out.prefix(2))
    }

    /// 이긴 경기에서도 상대가 앞선 지표 한 줄 — 칭찬만 하면 진단을 믿지 않는다(UX 패널 R6 "슛 4:7로 밀렸는데 주도").
    var winRisk: String? {
        guard me.result == "승", !me.forfeit, let o = opponent else { return nil }
        if o.stats.shots >= me.stats.shots + 3 { return "다만 슛은 \(me.stats.shots) 대 \(o.stats.shots)로 밀렸어요, 실점 위기가 많았어요" }
        if o.stats.effectiveShots > me.stats.effectiveShots { return "다만 유효슛은 \(me.stats.effectiveShots) 대 \(o.stats.effectiveShots)로 상대가 더 많았어요" }
        if o.possession >= 56 { return "다만 점유율은 \(o.possession)%로 상대가 더 오래 잡았어요" }
        return nil
    }
}
