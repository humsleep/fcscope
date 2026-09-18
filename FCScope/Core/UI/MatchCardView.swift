import SwiftUI

/// 매치 공유 카드 (1080×1920) — 매치 리포트 화면의 핵심을 한 장에 옮긴다.
///
/// 이전 카드는 스코어·점유율·유효슛·평점 네 가지뿐이라 "무슨 경기였는지"가 전해지지 않았다.
/// 리포트에서 사람들이 실제로 캡처하는 요소 — 판정, 슛맵, POTM, 팀 스탯 — 를 그대로 싣는다.
/// 공유 이미지이므로 뷰어 테마와 무관하게 항상 다크 팔레트이며, 글자 크기도 고정이다.
struct MatchCardView: View {
    let m: MatchDetailResponse

    private let pad: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            header
            scoreboard
            verdict
            possession
            shotMap
            if let p = m.potm { potm(p) }
            if let o = m.opponent { stats(o) }
            Spacer(minLength: 0)
            footer
        }
        .padding(pad)
        .frame(width: ShareCardView.width, height: ShareCardView.height, alignment: .topLeading)
        .background(
            ZStack {
                CardPalette.bg
                EllipticalGradient(colors: [CardPalette.lime.opacity(0.14), .clear],
                                   center: .init(x: 0.5, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.55)
            }
        )
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 12) {
                Text("FC").font(.scoreboard(40)).foregroundStyle(CardPalette.lime)
                Text("SCOPE").font(.scoreboard(40)).foregroundStyle(CardPalette.ink)
            }
            Spacer()
            Text("\(m.matchTypeName) · \(m.matchDateLabel)")
                .font(.pretendard(30, .semibold)).foregroundStyle(CardPalette.muted).lineLimit(1)
        }
    }

    private var scoreboard: some View {
        HStack(alignment: .center, spacing: 24) {
            Text(m.me.nickname).font(.pretendard(44, .bold)).foregroundStyle(CardPalette.lime)
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(m.me.goals) : \(m.opponent?.goals ?? 0)").font(.scoreboard(120)).foregroundStyle(CardPalette.ink)
                .lineLimit(1).fixedSize()
            Text(m.opponent?.nickname ?? "-").font(.pretendard(44, .bold)).foregroundStyle(CardPalette.ink)
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var verdict: some View {
        let color = CardPalette.verdict(m.verdict.color)
        return HStack(spacing: 28) {
            Text(m.verdict.grade).font(.scoreboard(72)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 6) {
                // 등급과 라벨이 같은 경기("승리 · 승리")는 한 번만 쓴다
                if m.verdict.label != m.verdict.grade {
                    Text(m.verdict.label).font(.pretendard(40, .bold)).foregroundStyle(color).lineLimit(1)
                }
                Text(m.verdict.oneLiner).font(.pretendard(30)).foregroundStyle(CardPalette.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(color.opacity(0.7), lineWidth: 3))
    }

    private var possession: some View {
        VStack(spacing: 12) {
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(CardPalette.lime).frame(width: g.size.width * CGFloat(m.me.possession) / 100)
                    Rectangle().fill(CardPalette.lose.opacity(0.75))
                }
            }
            .frame(height: 18).clipShape(Capsule())
            HStack {
                Text("\(m.me.possession)%").foregroundStyle(CardPalette.lime)
                Spacer()
                Text("점유율").foregroundStyle(CardPalette.muted)
                Spacer()
                Text("\(100 - m.me.possession)%").foregroundStyle(CardPalette.lose)
            }
            .font(.pretendard(30, .semibold))
        }
    }

    /// 화면 슛맵과 같은 좌표 규칙(ShotMapView.point) — 나는 오른쪽, 상대는 180° 회전해 왼쪽.
    private var shotMap: some View {
        let theirs = m.opponent?.shots ?? []
        let all = m.me.shots + theirs
        let sx = ShotMapView.scale(all, \.x), sy = ShotMapView.scale(all, \.y)
        let size = CGSize(width: ShareCardView.width - pad * 2, height: (ShareCardView.width - pad * 2) / ShotMapView.pitchRatio)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(m.opponent?.nickname ?? "상대") 슛 \(m.opponent?.stats.shots ?? 0)").foregroundStyle(CardPalette.lose)
                Spacer()
                Text("SHOT MAP").font(.scoreboard(28)).kerning(4).foregroundStyle(CardPalette.muted)
                Spacer()
                Text("\(m.me.nickname) 슛 \(m.me.stats.shots)").foregroundStyle(CardPalette.lime)
            }
            .font(.pretendard(28, .semibold)).lineLimit(1)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, s in
                    ShotMapView.drawPitch(ctx, s, ground: CardPalette.surface, line: CardPalette.line, lineWidth: 3)
                    for (shots, mine, color) in [(theirs, false, CardPalette.lose), (m.me.shots, true, CardPalette.lime)] {
                        for shot in shots {
                            let pt = ShotMapView.point(shot, sx: sx, sy: sy, mine: mine, in: s)
                            let r: CGFloat = shot.isGoal ? 20 : 15
                            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                            let tone = shot.hitPost ? CardPalette.gold : color
                            if shot.isGoal { ctx.fill(Path(ellipseIn: rect), with: .color(tone)) }
                            ctx.stroke(Path(ellipseIn: rect), with: .color(tone), lineWidth: 5)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func potm(_ p: MatchDetailResponse.Potm) -> some View {
        HStack(spacing: 28) {
            // ImageRenderer 는 .task 를 돌리지 않아 PlayerImage 는 늘 빈칸이었다 —
            // ShareCardButton 이 렌더 전에 prefetch 를 끝내 두므로 캐시에서 바로 꺼낸다(SquadCardView 와 동일).
            ZStack {
                Color.white.opacity(0.10)
                if let img = ImageCache.cached(spid: p.spId) { Image(uiImage: img).resizable().scaledToFill() }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("POTM").font(.scoreboard(30)).kerning(3).foregroundStyle(CardPalette.gold)
                // 한 줄: 구단주명 · 포지션 · 선수
                (Text("\(p.side) · \(p.positionLabel) · ").foregroundStyle(CardPalette.muted) + Text(p.name).foregroundStyle(CardPalette.ink))
                    .font(.pretendard(40, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            Text(String(format: "%.1f", p.rating)).font(.scoreboard(72)).foregroundStyle(CardPalette.gold)
        }
    }

    private func stats(_ o: MatchSide) -> some View {
        let rows: [(String, String, String)] = [
            ("슛 (유효)", "\(m.me.stats.shots) (\(m.me.stats.effectiveShots))", "\(o.stats.shots) (\(o.stats.effectiveShots))"),
            ("패스 성공률", m.me.stats.passRate.map { "\($0)%" } ?? "-", o.stats.passRate.map { "\($0)%" } ?? "-"),
            ("드리블", "\(m.me.stats.dribble)", "\(o.stats.dribble)"),
            ("태클 성공", "\(m.me.stats.tackleSuccess)/\(m.me.stats.tackleTry)", "\(o.stats.tackleSuccess)/\(o.stats.tackleTry)"),
            ("경기 평점", String(format: "%.1f", m.me.rating), String(format: "%.1f", o.rating)),
        ]
        return VStack(spacing: 12) {
            ForEach(rows, id: \.0) { r in
                HStack {
                    Text(r.1).font(.scoreboard(38)).foregroundStyle(CardPalette.lime).frame(width: 260, alignment: .leading)
                    Spacer()
                    Text(r.0).font(.pretendard(30, .semibold)).foregroundStyle(CardPalette.muted)
                    Spacer()
                    Text(r.2).font(.scoreboard(38)).foregroundStyle(CardPalette.lose).frame(width: 260, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
    }

    private var footer: some View {
        HStack {
            Text("FC온라인 전적·매치 리포트").font(.pretendard(28, .semibold)).foregroundStyle(CardPalette.muted)
            Spacer()
            Text(AppConfig.shareHost).font(.scoreboard(30)).foregroundStyle(CardPalette.lime)
        }
    }
}
