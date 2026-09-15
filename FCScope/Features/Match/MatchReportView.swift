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
            Analytics.shared.track(.matchView, ["cached": true])
            Haptic.medium()
            return
        }
        state = .loading
        do {
            state = .loaded(try await APIClient.shared.getAndCache(p, query: q, auth: false))
            Analytics.shared.track(.matchView, ["cached": false])
            Haptic.medium()
        }
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
                // 범례: 왼쪽 = 상대(왼쪽 골대 공격), 오른쪽 = 나(오른쪽 골대 공격)
                HStack(spacing: 6) {
                    if let o = m.opponent { shotLegend(o, tone: FC.lose) }
                    Spacer(minLength: 8)
                    shotLegend(m.me, tone: FC.accent)
                }
                ShotMapView(mine: m.me.shots, theirs: m.opponent?.shots ?? [], myTone: FC.accent, theirTone: FC.lose)
                Text("● 골 · ○ 노골 · 금색 골대 · 점을 누르면 시간·선수").fcFont(11).foregroundStyle(FC.muted)
            }
            if let p = m.potm {
                Panel(padding: 12) {
                    HStack(spacing: 12) {
                        PlayerImage(spid: p.spId, size: 56, radius: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("POTM").fcScoreboard(12, weight: .semibold).foregroundStyle(FC.gold).lineLimit(1)
                            // 한 줄: 구단주명 · 포지션 · 선수
                            (Text(p.side).foregroundStyle(FC.muted) + Text(" · \(p.positionLabel) · ").foregroundStyle(FC.muted) + Text(p.name).foregroundStyle(FC.ink).bold())
                                .font(.fcFont(15, typeSize)).lineLimit(1).minimumScaleFactor(0.75)
                        }
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
                ShareCardButton(match: m, label: "매치 카드")
            }
            // 리포트를 다 읽은 뒤의 자리 — 내용을 가리지 않아 거부감이 가장 적다.
            AdSlot()
        }.padding(16)
    }

    private func teamName(_ s: MatchSide, me: Bool) -> some View {
        Button { router.push(.user(s.nickname)) } label: { Text(s.nickname).fcFont(14, weight: .bold).foregroundStyle(me ? FC.accent : FC.ink).lineLimit(1).frame(maxWidth: .infinity) }.buttonStyle(.plain)
    }
    private func shotLegend(_ s: MatchSide, tone: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tone).frame(width: 8, height: 8)
            Text("\(s.nickname) 슛 \(s.stats.shots)(유효 \(s.stats.effectiveShots))")
                .fcFont(12, weight: .medium).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.8)
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
/// 슛맵 — **양 팀을 하나의 전체 운동장**에 그린다.
///
/// 이전에는 팀마다 공격 진영(하프 코트)을 따로 그려 두 장이 나왔다. 실제 경기는 한 경기이고
/// 서로 반대 방향으로 공격하므로, 한 장에 합쳐야 "누가 어디서 쐈는지"가 한눈에 들어온다.
///
/// 넥슨 좌표계: `x` = **전체 운동장 길이 방향**(0 = 내 골라인, 1 = 상대 골라인), `y` = 좌우 폭(0~1).
/// 실측으로 확인했다 — 8:2 경기 슛 9개가 전부 `inPenalty=true` 인데 x 가 0.87~0.97 이었고,
/// `inPenalty=false` 인 슛은 x=0.824 로 페널티 박스 경계(1 − 16.5/105 = 0.843) 바로 밖이었다.
/// 예전 코드는 x·y 를 반대로 읽어 슛이 터치라인에 붙고 운동장이 90° 돌아간 것처럼 보였다.
///
/// 팀마다 **자기 공격 방향 기준**이므로, 한 화면에 놓으려면 상대 팀을 180° 돌린다
/// (가로 반전 + 세로 반전). 가로만 뒤집으면 좌우가 거울처럼 어긋난다.
struct ShotMapView: View {
    let mine: [Shot]
    let theirs: [Shot]
    let myTone: Color
    let theirTone: Color
    @State private var selected: Shot?
    @State private var selectedIsMine = true

    /// 실제 축구장 비율(105 × 68). 하프 코트를 세로로 그리던 때의 1.35 와 달리 가로로 길다.
    static let pitchRatio: CGFloat = 105.0 / 68.0

    var body: some View {
        let sx = Self.scale(mine + theirs, \.x), sy = Self.scale(mine + theirs, \.y)
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack {
                    Canvas { ctx, size in Self.drawPitch(ctx, size, ground: FC.surface2, line: FC.line) }
                    // 내 슛 — 오른쪽 골대를 공격
                    ForEach(mine) { s in
                        dot(s, tone: myTone, isMine: true)
                            .position(Self.point(s, sx: sx, sy: sy, mine: true, in: g.size))
                    }
                    // 상대 슛 — 왼쪽 골대를 공격(180° 회전)
                    ForEach(theirs) { s in
                        dot(s, tone: theirTone, isMine: false)
                            .position(Self.point(s, sx: sx, sy: sy, mine: false, in: g.size))
                    }
                }
            }
            .aspectRatio(Self.pitchRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if let s = selected {
                Text("\(s.minute.map { "\($0)\' " } ?? "")\(s.player ?? "") — \(s.isGoal ? "골" : s.hitPost ? "골대" : "노골")\(s.inPenalty == true ? " · 박스 안" : "")")
                    .fcFont(12, weight: .semibold)
                    .foregroundStyle(selectedIsMine ? myTone : theirTone)
            }
        }
    }

    /// 넥슨이 0~1 로 줄 때도, 픽셀 좌표로 줄 때도 있어 최대값으로 정규화한다.
    static func scale(_ shots: [Shot], _ key: KeyPath<Shot, Double>) -> Double {
        let m = max(1, shots.map { abs($0[keyPath: key]) }.max() ?? 1)
        return m > 1.5 ? m : 1
    }

    static func point(_ s: Shot, sx: Double, sy: Double, mine isMine: Bool, in size: CGSize) -> CGPoint {
        let length = CGFloat(min(1, max(0, s.x / sx)))     // 1 = 상대 골라인
        let width = CGFloat(min(1, max(0, s.y / sy)))      // 좌우
        if isMine {
            // 나는 오른쪽 골대를 공격 — 전체 운동장 비율 그대로
            return CGPoint(x: length * size.width, y: width * size.height)
        }
        // 상대는 180° 회전 — 가로·세로 모두 반전해 왼쪽 골대를 공격
        return CGPoint(x: (1 - length) * size.width, y: (1 - width) * size.height)
    }

    private func dot(_ s: Shot, tone: Color, isMine: Bool) -> some View {
        Circle()
            .strokeBorder(s.hitPost ? FC.gold : tone, lineWidth: 2)
            .background(Circle().fill(s.isGoal ? (s.hitPost ? FC.gold : tone) : Color.clear))
            .frame(width: s.isGoal ? 14 : 11, height: s.isGoal ? 14 : 11)
            .shadow(color: s.isGoal ? tone.opacity(0.7) : .clear, radius: 5)
            .onTapGesture {
                Haptic.light()
                if selected?.id == s.id && selectedIsMine == isMine { selected = nil }
                else { selected = s; selectedIsMine = isMine }
            }
    }

    /// 가로로 긴 전체 운동장 — 양쪽 골대·페널티 박스, 가운데 하프라인과 센터서클.
    static func drawPitch(_ ctx: GraphicsContext, _ size: CGSize, ground: Color, line: Color, lineWidth: CGFloat = 1) {
        var field = Path(); field.addRect(CGRect(origin: .zero, size: size))
        ctx.fill(field, with: .color(ground))

        let w = size.width, h = size.height
        var lines = Path()
        lines.addRect(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))            // 터치라인
        lines.move(to: CGPoint(x: w / 2, y: 0))                                    // 하프라인
        lines.addLine(to: CGPoint(x: w / 2, y: h))
        let r = min(w, h) * 0.13
        lines.addEllipse(in: CGRect(x: w / 2 - r, y: h / 2 - r, width: r * 2, height: r * 2))  // 센터서클

        // 페널티 박스·골 에어리어 (실제 비율: 박스 16.5m 깊이 × 40.3m 폭)
        let boxDepth = w * 0.157, boxHeight = h * 0.593
        let areaDepth = w * 0.052, areaHeight = h * 0.269
        let goalDepth = w * 0.017, goalHeight = h * 0.108
        for left in [true, false] {
            let bx = left ? 0 : w - boxDepth
            lines.addRect(CGRect(x: bx, y: (h - boxHeight) / 2, width: boxDepth, height: boxHeight))
            let ax = left ? 0 : w - areaDepth
            lines.addRect(CGRect(x: ax, y: (h - areaHeight) / 2, width: areaDepth, height: areaHeight))
            let gx = left ? -goalDepth : w
            lines.addRect(CGRect(x: gx, y: (h - goalHeight) / 2, width: goalDepth, height: goalHeight))
        }
        ctx.stroke(lines, with: .color(line), lineWidth: lineWidth)
    }
}
