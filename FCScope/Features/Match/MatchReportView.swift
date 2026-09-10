import SwiftUI

struct MatchReportView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let matchId: String
    let me: String?
    @State private var state: Loadable<MatchDetailResponse> = .idle
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            switch state {
            case .idle, .loading: VStack(spacing: 10) { Skeleton(height: 140); Skeleton(height: 260) }.padding(16)
            case .failed(let e): ErrorState(title: (e as? APIError)?.code == "not_found" ? "매치를 찾을 수 없어요" : "매치 정보를 불러올 수 없어요", message: e.localizedDescription, retry: { Task { await load() } })
            case .loaded(let m): content(m)
            }
        }
        .fcScreen().navigationTitle("매치 리포트").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// 끝난 경기는 불변 데이터 → 캐시가 있으면 네트워크를 아예 치지 않는다.
    private func load() async {
        let p = "/api/v1/match/\(matchId)"
        let q = me.map { ["me": $0] } ?? [:]
        if let hit: (value: MatchDetailResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: q) {
            state = .loaded(hit.value)
            Haptic.medium()
            return
        }
        state = .loading
        do { state = .loaded(try await APIClient.shared.getAndCache(p, query: q, auth: false)); Haptic.medium() }
        catch { state = .failed(error) }
    }

    private func content(_ m: MatchDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("\(m.matchTypeName.uppercased()) · \(m.matchDateLabel)")
            Panel {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        teamName(m.me, me: true)
                        (Text("\(m.me.goals)").foregroundStyle(FC.ink) + Text(" : ").font(.fcScoreboard(18, typeSize)).foregroundStyle(FC.muted) + Text(m.opponent.map { "\($0.goals)" } ?? "-").foregroundStyle(FC.muted)).font(.fcScoreboard(36, typeSize))
                        if let o = m.opponent { teamName(o, me: false) } else { Spacer() }
                    }
                    if m.me.forfeit { Text("몰수 경기").fcFont(12).foregroundStyle(FC.lose) }
                    VerdictStamp(verdict: m.verdict, large: true, showLiner: true)
                    VStack(spacing: 3) {
                        GeometryReader { g in HStack(spacing: 0) { Rectangle().fill(FC.accent).frame(width: g.size.width * CGFloat(m.me.possession) / 100); Rectangle().fill(FC.lose.opacity(0.7)) } }.frame(height: 8).clipShape(Capsule())
                        HStack { Text("\(m.me.possession)%").foregroundStyle(FC.accent); Spacer(); Text("점유율").foregroundStyle(FC.muted); Spacer(); Text("\(100 - m.me.possession)%").foregroundStyle(FC.lose) }.fcScoreboard(12, weight: .semibold)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("SHOT MAP")
                shotBlock(m.me, tone: FC.accent)
                if let o = m.opponent { shotBlock(o, tone: FC.lose) }
                Text("● 채움=골 · ○ 외곽선=노골 · 금색=골대 · 점을 누르면 시간·선수").fcFont(11).foregroundStyle(FC.muted)
            }
            if let p = m.potm {
                Panel(padding: 12) {
                    HStack(spacing: 12) {
                        PlayerImage(spid: p.spId, size: 56, radius: 12)
                        VStack(alignment: .leading, spacing: 2) { SectionLabel("PLAYER OF THE MATCH", color: FC.gold); Text(p.name).fcFont(15, weight: .bold).foregroundStyle(FC.ink); Text("\(p.positionLabel) · \(p.side)").fcFont(12).foregroundStyle(FC.muted) }
                        Spacer()
                        Text(String(format: "%.1f", p.rating)).fcScoreboard(28).foregroundStyle(FC.gold)
                    }
                }
            }
            if let o = m.opponent {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("TEAM STATS")
                    Panel(padding: 12) {
                        VStack(spacing: 8) {
                            stat("슛 (유효)", "\(m.me.stats.shots) (\(m.me.stats.effectiveShots))", "\(o.stats.shots) (\(o.stats.effectiveShots))")
                            stat("패스 성공률", m.me.stats.passRate.map { "\($0)%" } ?? "-", o.stats.passRate.map { "\($0)%" } ?? "-")
                            stat("드리블", "\(m.me.stats.dribble)", "\(o.stats.dribble)")
                            stat("태클 성공", "\(m.me.stats.tackleSuccess)/\(m.me.stats.tackleTry)", "\(o.stats.tackleSuccess)/\(o.stats.tackleTry)")
                            stat("코너킥", "\(m.me.stats.cornerKick)", "\(o.stats.cornerKick)")
                            stat("파울 (경고)", "\(m.me.stats.foul) (\(m.me.stats.yellowCards))", "\(o.stats.foul) (\(o.stats.yellowCards))")
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("RATINGS")
                ratings(m.me)
                if let o = m.opponent { ratings(o) }
            }
            HStack {
                Button { router.push(.user(m.me.nickname)) } label: { Text("← \(m.me.nickname) 전적으로").fcFont(13).foregroundStyle(FC.muted) }
                Spacer()
                ShareCardButton(spec: .match(m), label: "매치 카드")
            }
        }.padding(16)
    }

    private func teamName(_ s: MatchSide, me: Bool) -> some View {
        Button { router.push(.user(s.nickname)) } label: { Text(s.nickname).fcFont(14, weight: .bold).foregroundStyle(me ? FC.accent : FC.ink).lineLimit(1).frame(maxWidth: .infinity) }.buttonStyle(.plain)
    }
    private func shotBlock(_ s: MatchSide, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) { Circle().fill(tone).frame(width: 8, height: 8); Text("\(s.nickname) — 슛 \(s.stats.shots) (유효 \(s.stats.effectiveShots))").fcFont(12, weight: .medium).foregroundStyle(FC.ink) }
            ShotMapView(shots: s.shots, tone: tone)
        }
    }
    private func stat(_ label: String, _ a: String, _ b: String) -> some View {
        HStack { Text(a).fcScoreboard(13, weight: .semibold).foregroundStyle(FC.accent).frame(width: 80, alignment: .leading); Spacer(); Text(label).fcFont(12).foregroundStyle(FC.muted); Spacer(); Text(b).fcScoreboard(13, weight: .semibold).foregroundStyle(FC.lose).frame(width: 80, alignment: .trailing) }
    }
    private func ratings(_ s: MatchSide) -> some View {
        Panel(padding: 10) {
            VStack(spacing: 6) {
                Text(s.nickname).fcFont(12, weight: .semibold).foregroundStyle(FC.muted).frame(maxWidth: .infinity, alignment: .leading)
                if s.players.isEmpty { Text("선수 기록 없음").fcFont(12).foregroundStyle(FC.muted) }
                ForEach(s.players) { p in
                    Button { router.push(.player(p.spId)) } label: {
                        HStack(spacing: 8) {
                            PlayerImage(spid: p.spId, size: 30, radius: 8)
                            Text(p.positionLabel).fcScoreboard(12, weight: .semibold).foregroundStyle(FC.muted).frame(width: 36, alignment: .leading)
                            (Text(p.name) + Text(p.goals > 0 ? " ⚽\(p.goals)" : "").foregroundStyle(FC.accent) + Text(p.assists > 0 ? " A\(p.assists)" : "").foregroundStyle(FC.muted)).font(.fcFont(13, typeSize)).foregroundStyle(FC.ink).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f", p.rating)).fcScoreboard(13).foregroundStyle(p.rating >= 7.5 ? FC.gold : p.rating < 6 ? FC.lose : FC.ink)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// 슛맵 — 하프 피치(공격 방향 위), 좌표 0~1 정규화(범위 이탈 시 최대값 스케일). 점 탭 → 라벨.
struct ShotMapView: View {
    let shots: [Shot]
    let tone: Color
    @State private var selected: Shot?
    var body: some View {
        let maxX = max(1, shots.map { abs($0.x) }.max() ?? 1), maxY = max(1, shots.map { abs($0.y) }.max() ?? 1)
        let sx = maxX > 1.5 ? maxX : 1, sy = maxY > 1.5 ? maxY : 1
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    Canvas { ctx, size in
                        var pitch = Path(); pitch.addRect(CGRect(origin: .zero, size: size))
                        ctx.fill(pitch, with: .color(FC.surface2))
                        let line = FC.line
                        var lines = Path()
                        lines.addRect(CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2))
                        lines.addRect(CGRect(x: size.width * 0.2, y: 0, width: size.width * 0.6, height: size.height * 0.28)) // 페널티 박스
                        lines.addRect(CGRect(x: size.width * 0.37, y: 0, width: size.width * 0.26, height: size.height * 0.1))
                        lines.addRect(CGRect(x: size.width * 0.44, y: -4, width: size.width * 0.12, height: 4)) // 골대
                        lines.addEllipse(in: CGRect(x: size.width / 2 - 40, y: size.height - 40, width: 80, height: 80))
                        ctx.stroke(lines, with: .color(line), lineWidth: 1)
                    }
                    ForEach(shots) { s in
                        let px = CGFloat(min(1, max(0, s.x / sx))) * w
                        let py = CGFloat(1 - min(1, max(0, s.y / sy))) * h
                        Circle()
                            .strokeBorder(s.hitPost ? FC.gold : tone, lineWidth: 2)
                            .background(Circle().fill(s.isGoal ? (s.hitPost ? FC.gold : tone) : Color.clear))
                            .frame(width: s.isGoal ? 14 : 11, height: s.isGoal ? 14 : 11)
                            .shadow(color: s.isGoal ? tone.opacity(0.7) : .clear, radius: 5)
                            .position(x: px, y: py)
                            .onTapGesture { Haptic.light(); selected = selected?.id == s.id ? nil : s }
                    }
                }
            }
            .aspectRatio(1.35, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if let s = selected {
                Text("\(s.minute.map { "\($0)' " } ?? "")\(s.player ?? "") — \(s.isGoal ? "골" : s.hitPost ? "골대" : "노골")\(s.inPenalty == true ? " · 박스 안" : "")").fcFont(12, weight: .semibold).foregroundStyle(FC.ink)
            }
        }
    }
}
