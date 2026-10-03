import SwiftUI

/**
 손맛 부품(UX-AUDIT-GENZ #7) — 숫자 카운트업·스코어 링·폼 블록 순차 등장.
 전부 "동작 줄이기"를 켜면 최종값을 바로 그린다(Skeleton 과 같은 규칙).
 */

/// 0 → 목표값으로 숫자가 올라가며 등장한다. `.numericText` 전환이라 자릿수가 굴러가듯 바뀐다.
/// `content` 에 현재 표시값을 넘긴다 — 서식(%, 소수점)은 호출부가 정한다.
struct CountUp<Label: View>: View {
    let target: Double
    var duration: Double = 0.7
    var delay: Double = 0
    @ViewBuilder var content: (Double) -> Label
    @State private var shown: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(shown ?? (reduceMotion ? target : 0))
            .contentTransition(.numericText(value: shown ?? 0))
            .onAppear { start() }
            .onChange(of: target) { _, _ in start() }
            // 낭독은 최종값으로 — 중간값을 읽지 않게
            .accessibilityElement(children: .combine)
    }

    private func start() {
        guard !reduceMotion else { shown = target; return }
        if shown == nil { shown = 0 }
        withAnimation(.snappy(duration: duration).delay(delay)) { shown = target }
    }
}

/// FC Scope 스코어 링(0~10). 색은 의미(티어 톤)를 따른다.
struct ScoreRing: View {
    let score: Double
    var color: Color
    var lineWidth: CGFloat = 5
    @State private var drawn: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(FC.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: drawn / 10)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            let t = min(10, max(0, score))
            if reduceMotion { drawn = t } else { withAnimation(.easeOut(duration: 0.9).delay(0.1)) { drawn = t } }
        }
        .onChange(of: score) { _, v in drawn = min(10, max(0, v)) }
        .accessibilityHidden(true)
    }
}

/// 최근 N경기 폼 블록 — 왼쪽이 오래된 경기, 오른쪽 끝이 가장 최근(외곽선). 공유 카드 FormStrip 과 같은 규칙.
/// 블록이 0.03초 간격으로 차례로 떠오른다.
struct FormBlocks: View {
    let matches: [MatchSummary]   // 최신순 그대로
    var count = 10
    var spacing: CGFloat = 4
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let recent = Array(matches.prefix(count).reversed())
        HStack(spacing: spacing) {
            ForEach(Array(recent.enumerated()), id: \.element.id) { i, m in
                let c = FC.resultColor(m.result)
                Text(m.result)
                    .fcFont(11, weight: .bold)
                    .foregroundStyle(m.result == "승" ? FC.tintInk : c)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(m.result == "승" ? c : c.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        if m.forfeit { RoundedRectangle(cornerRadius: 6).strokeBorder(FC.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
                    }
                    .overlay {
                        if i == recent.count - 1 { RoundedRectangle(cornerRadius: 8).strokeBorder(FC.ink.opacity(0.8), lineWidth: 1.5).padding(-2.5) }
                    }
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 6)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.3).delay(Double(i) * 0.03), value: appeared)
            }
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("최근 \(recent.count)경기, 과거부터 " + recent.map(\.result).joined(separator: " "))
    }
}
