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
    @State private var fcScore: Double?

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
                if m.me.forfeit { Text("몰수 경기").fcFont(12, weight: .semibold).foregroundStyle(FC.lose) }
            }

            possession

            HStack(spacing: 8) {
                statBox(m.opponent.map { "\(m.me.stats.shots) / \($0.stats.shots)" } ?? "\(m.me.stats.shots)", m.opponent == nil || typeSize.isAccessibilitySize ? "슛" : "슛 · 나/상대")
                // 옆 칸과 같은 형식인데 (나/상대)가 빠져 헷갈렸다(유저 패널 C)
                statBox(m.opponent.map { "\(m.me.stats.effectiveShots) / \($0.stats.effectiveShots)" } ?? "\(m.me.stats.effectiveShots)", m.opponent == nil || typeSize.isAccessibilitySize ? "유효슛" : "유효슛 · 나/상대")
                // verdict.score 는 0~100 게이지 값이라 FC 스코어(10점)가 아니다. 경기별 FC 스코어는 전적 응답(MatchSummary)에만
                // 있으므로 디스크 캐시에서 찾고(네트워크 0), 없으면(딥링크로 바로 들어온 경우) 경기 평점으로 대신한다.
                if let s = fcScore {
                    statBox(String(format: "%.1f", s), "FC 스코어", color: s >= 6.5 ? FC.win : s < 5 ? FC.lose : FC.ink)
                } else {
                    statBox(m.me.rating > 0 ? String(format: "%.1f", m.me.rating) : "-", "경기 평점", color: m.me.rating >= 7.5 ? FC.gold : FC.ink)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                FC.surface
                LinearGradient(colors: [tone.opacity(0.30), tone.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [tone.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 220)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tone.opacity(0.5), lineWidth: 1))
        .sensoryFeedback(.success, trigger: celebrated) { _, new in new }
        .task { await loadScore() }
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

    private func loadScore() async {
        let nick = m.me.nickname
        let path = "/api/v1/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"
        if let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path, query: ["type": String(m.matchType)]),
           let row = hit.value.matches.first(where: { $0.matchId == m.matchId }) {
            fcScore = row.score
        }
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
