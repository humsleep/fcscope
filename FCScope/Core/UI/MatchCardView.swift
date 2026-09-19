import SwiftUI

/// 매치 공유 카드 (1080×1920) — 매치 리포트 화면의 핵심을 한 장에 옮긴다.
///
/// 이전 카드는 스코어·점유율·유효슛·평점 네 가지뿐이라 "무슨 경기였는지"가 전해지지 않았다.
/// 리포트에서 사람들이 실제로 캡처하는 요소 — 판정, 슛맵, POTM, 팀 스탯 — 를 그대로 싣는다.
/// 공유 이미지이므로 뷰어 테마와 무관하게 항상 다크 팔레트이며, 글자 크기도 고정이다.
struct MatchCardView: View {
    let m: MatchDetailResponse

    // 인스타 스토리 안전영역(y 264~1560) 안에 전부 들어가게 배치한다 — v1 은 y 72부터 그려 헤더·스코어가 가려졌다.
    var body: some View {
        CardCanvas {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(chip: "\(m.matchTypeName) · \(m.matchDateLabel)")
                Spacer().frame(height: 20)
                scoreboard.frame(height: 130)
                Spacer().frame(height: 16)
                verdict.frame(height: 104)
                Spacer().frame(height: 24)
                shotMap
                Spacer().frame(height: 16)
                if let p = m.potm { potm(p).frame(height: 96) }
                Spacer().frame(height: 16)
                if let o = m.opponent { compare(o) }
                Spacer(minLength: 0)
                CardFooter(cta: "내 경기 리포트도 보기 →")
            }
        }
    }

    private var scoreboard: some View {
        HStack(alignment: .center, spacing: 16) {
            NicknameTitle(text: m.me.nickname, maxSize: 56, minSize: 32, boxHeight: 130, width: 330, color: CardPalette.lime, alignment: .leading)
            Text("\(m.me.goals) : \(m.opponent?.goals ?? 0)").font(.scoreboard(120)).foregroundStyle(CardPalette.ink)
                .lineLimit(1).fixedSize().frame(maxWidth: .infinity)
            NicknameTitle(text: m.opponent?.nickname ?? "-", maxSize: 56, minSize: 32, boxHeight: 130, width: 330, color: CardPalette.ink, alignment: .trailing)
        }
    }

    /// 점유율 · 슛(유효) · 패스 · 평점 — 내 값 : 상대 값
    private func compare(_ o: MatchSide) -> some View {
        let cells: [(String, String, String)] = [
            ("점유율", "\(m.me.possession)%", "\(o.possession)%"),
            ("슛(유효)", "\(m.me.stats.shots)(\(m.me.stats.effectiveShots))", "\(o.stats.shots)(\(o.stats.effectiveShots))"),
            ("패스", m.me.stats.passRate.map { "\($0)%" } ?? "-", o.stats.passRate.map { "\($0)%" } ?? "-"),
            ("평점", String(format: "%.1f", m.me.rating), String(format: "%.1f", o.rating)),
        ]
        return HStack(spacing: 16) {
            ForEach(cells, id: \.0) { c in
                VStack(spacing: 6) {
                    Text(c.0).font(.pretendard(22)).foregroundStyle(CardPalette.muted)
                    HStack(spacing: 6) {
                        Text(c.1).foregroundStyle(CardPalette.lime)
                        Text(":").foregroundStyle(CardPalette.muted)
                        Text(c.2).foregroundStyle(CardPalette.ink)
                    }
                    .font(.scoreboard(30)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(width: (CardLayout.contentWidth - 48) / 4, height: 100)
                .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 20))
            }
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


    /// 화면 슛맵과 같은 좌표 규칙(ShotMapView.point) — 나는 오른쪽, 상대는 180° 회전해 왼쪽.
    private var shotMap: some View {
        let theirs = m.opponent?.shots ?? []
        let all = m.me.shots + theirs
        let sx = ShotMapView.scale(all, \.x), sy = ShotMapView.scale(all, \.y)
        let size = CGSize(width: 880, height: 880 / ShotMapView.pitchRatio)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(m.opponent?.nickname ?? "상대") 슛 \(m.opponent?.stats.shots ?? 0)").foregroundStyle(CardPalette.lose)
                Spacer()
                Text("SHOT MAP").font(.scoreboard(28)).kerning(4).foregroundStyle(CardPalette.muted)
                Spacer()
                Text("\(m.me.nickname) 슛 \(m.me.stats.shots)").foregroundStyle(CardPalette.lime)
            }
            .font(.pretendard(28, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, s in
                    ShotMapView.drawPitch(ctx, s, ground: CardPalette.surface, line: CardPalette.line, lineWidth: 3)
                    for (shots, mine, color) in [(theirs, false, CardPalette.lose), (m.me.shots, true, CardPalette.lime)] {
                        for shot in shots {
                            let pt = ShotMapView.point(shot, sx: sx, sy: sy, mine: mine, in: s)
                            let r: CGFloat = shot.isGoal ? 16 : 12
                            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                            let tone = shot.hitPost ? CardPalette.gold : color
                            if shot.isGoal { ctx.fill(Path(ellipseIn: rect), with: .color(tone)) }
                            ctx.stroke(Path(ellipseIn: rect), with: .color(tone), lineWidth: 4)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: .infinity)
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


}
