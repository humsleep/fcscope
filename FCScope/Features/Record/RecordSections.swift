import SwiftUI
import Charts

// MARK: - 종합 리포트

struct ReportSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let state: Loadable<ReportResponse>
    /// 득실을 헤더와 같은 기준(몰수 제외)으로 쓰기 위해 — 리포트 응답 득실은 몰수 3:0 이 섞여 부호까지 뒤집혔다(QA P1-2)
    var overview: UserOverview? = nil
    /// 섹션 오류에 재시도 버튼이 없어 탭을 바꿨다 돌아오거나 전체 새로고침을 해야 했다.
    var retry: (() -> Void)? = nil

    /// (경기 수, 득점, 실점, 몰수 제외 여부) — 헤더 "경기당 득점·실점"과 같은 몰수 제외 기준.
    /// 옛 서버(perf 득실 없음)면 리포트 값 그대로.
    private func goals(_ r: MatchReport) -> (games: Int, gf: Int, ga: Int, excl: Bool) {
        if let o = overview, let gf = o.perf.goalsFor, let ga = o.perf.goalsAgainst {
            let f = o.perf.forfeits ?? 0
            let games = o.perf.normalPlayed.flatMap { $0 > 0 ? $0 : nil } ?? o.summary.played
            return (games, gf, ga, f > 0)
        }
        return (r.played, r.goalsFor, r.goalsAgainst, false)
    }
    /// 슛 타입 골 합계 — 박스 안·박스 밖·PK 가 서로 겹치지 않는 분할이다(서버 report.ts: PK 는 박스 안/밖과 **따로** 센다).
    /// 헤딩·프리킥은 박스 안/밖의 부분집합이라 더하지 않는다.
    /// 합이 같은 카드의 득점(몰수 제외)보다 크면 옛 서버 집계(몰수 경기 슛 포함 — QA 2R P2-4)라 이 카드를 숨긴다.
    static func shotTypeGoals(_ st: [ShotTypeStat]) -> Int? {
        let parts = st.filter { ["inbox", "outbox", "penalty"].contains($0.key) }
        guard !parts.isEmpty, st.contains(where: { $0.tries > 0 }) else { return nil }
        return parts.reduce(0) { $0 + $1.goals }
    }

    /// 최근 7일 승률 증감 — 두 기간 모두 8판 이상일 때만. 표본이 작으면 증감은 소음이다.
    static let weeklyMinGames = 8
    static func weeklyDelta(_ w: WeeklyForm) -> Int? {
        guard w.recentGames >= weeklyMinGames, w.prevGames >= weeklyMinGames, w.prevWinRate != nil else { return nil }
        return w.deltaWinRate
    }

    var body: some View {
        switch state {
        case .idle, .loading: Skeleton(height: 260)
        case .failed(let e): ErrorState(title: "리포트를 불러오지 못했어요", message: e.localizedDescription, error: e, retry: retry)
        case .loaded(let r):
            if r.report.played == 0 {
                Panel { Text("이 매치 유형에는 분석할 경기가 없어요.").fcFont(14).foregroundStyle(FC.muted) }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("분석 리포트", color: FC.tint)
                            HStack(alignment: .lastTextBaseline, spacing: 20) {
                                let g = goals(r.report)
                                VStack(alignment: .leading) { Text(g.excl ? "\(g.games)경기 득실 · 몰수 제외" : "최근 \(g.games)경기 득실").fcText(.meta).foregroundStyle(FC.muted)
                                    (Text("\(g.gf)").foregroundStyle(FC.ink) + Text(" : ").foregroundStyle(FC.muted) + Text("\(g.ga)").foregroundStyle(FC.ink)).font(.fcScoreboard(24, typeSize)) }
                                VStack(alignment: .leading) { Text("평균 경기 평점").fcFont(12).foregroundStyle(FC.muted); Text(String(format: "%.2f", r.report.avgRating)).fcScoreboard(24).foregroundStyle(FC.ink) }
                                if let w = r.report.weekly, w.recentGames > 0 {
                                    // 증감은 두 기간 모두 표본이 있을 때만 — 지난 기간 4경기·0%면 "46% ▲46"처럼 값과 증감이 같아졌다(QA 2R P2-5)
                                    let d = Self.weeklyDelta(w)
                                    VStack(alignment: .leading) { Text("최근 7일 승률 · \(w.recentGames)판").fcFont(12).foregroundStyle(FC.muted)
                                        (Text("\(w.recentWinRate)%") + Text(d.map { $0 >= 0 ? " ▲\($0)" : " ▼\(-$0)" } ?? "").font(.fcScoreboard(13, typeSize)).foregroundStyle((d ?? 0) >= 0 ? FC.win : FC.lose)).font(.fcScoreboard(24, typeSize)).foregroundStyle(FC.ink) }
                                }
                            }
                            ForEach(r.insights) { i in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(i.tone == "good" ? "▲" : i.tone == "warn" ? "▼" : "◆").fcScoreboard(12).foregroundStyle(FC.tone(i.tone))
                                    Text(i.text).fcFont(13).foregroundStyle(FC.ink)
                                }
                            }
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("시간대별 득실")
                            Chart {
                                ForEach(r.report.timeBands) { b in
                                    BarMark(x: .value("시간", b.label), y: .value("득점", b.forGoals)).foregroundStyle(FC.tint).position(by: .value("구분", "득점"))
                                    BarMark(x: .value("시간", b.label), y: .value("실점", b.againstGoals)).foregroundStyle(FC.lose).position(by: .value("구분", "실점"))
                                }
                            }
                            .chartXAxis { AxisMarks { AxisValueLabel().font(.pretendard(10)).foregroundStyle(FC.muted) } }
                            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(FC.line); AxisValueLabel().foregroundStyle(FC.muted) } }
                            .frame(height: 160)
                            HStack(spacing: 12) {
                                legend(FC.tint, "득점"); legend(FC.lose, "실점")
                                Spacer(minLength: 4)
                                // 합계가 위 득실과 몇 골 다를 수 있다 — 기록 시간이 있는 골만 시간대에 들어간다
                                Text("골 시간이 기록된 골만 · 몰수 제외").fcText(.caption).foregroundStyle(FC.muted).lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                    }
                    // 광고 — "시간대별 득실" 뒤(디자인 5R: 요약과 그 차트를 광고가 가르지 않게). 위는 차트 범례(탭 불가).
                    AdSlot(placement: "record_report", reserve: true)
                    if let total = Self.shotTypeGoals(r.report.shotTypes), total <= goals(r.report).gf {
                        Panel {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("슛 타입별 결정력")
                                ForEach(r.report.shotTypes.filter { $0.tries > 0 }) { s in
                                    HStack {
                                        Text(s.label).fcFont(13).foregroundStyle(FC.ink).frame(width: 90, alignment: .leading)
                                        RatioBar(ratio: CGFloat(s.goals) / CGFloat(max(1, s.tries)), color: FC.tint, height: 8)
                                        Text("\(s.goals)/\(s.tries)").fcScoreboard(12).foregroundStyle(FC.muted).frame(width: 50, alignment: .trailing)
                                    }
                                }
                                // 기준을 밝힌다 — 위 득실과 맞춰 볼 수 있게. 헤딩·프리킥은 박스 안/밖에 이미 들어 있다.
                                Text("몰수 제외 · 박스 안 + 박스 밖 + PK = \(total)골 · 헤딩·프리킥은 그 안에 포함")
                                    .fcText(.caption).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("득실차 폼 (최신 → 과거)")
                            Chart {
                                ForEach(Array(r.report.form.enumerated()), id: \.offset) { i, g in
                                    BarMark(x: .value("경기", i), y: .value("득실", g.diff)).foregroundStyle(g.diff > 0 ? FC.win : g.diff < 0 ? FC.lose : FC.muted)
                                }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(FC.line); AxisValueLabel().foregroundStyle(FC.muted) } }
                            .frame(height: 120)
                        }
                    }
                }
            }
        }
    }
    private func legend(_ c: Color, _ t: String) -> some View { HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t).fcFont(11).foregroundStyle(FC.muted) } }
}

// MARK: - 선수 성적표

struct PlayersSection: View {
    /// 서버 band 코드(lib/squad-clinic.ts BAND_LABEL 과 같은 문구). 모르는 코드는 그대로 둔다(계약상 추가될 수 있음).
    static func bandLabel(_ band: String) -> String { FCCopy.squadBand(band) }
    @Environment(\.dynamicTypeSize) private var typeSize
    let state: Loadable<PlayersResponse>
    let nickname: String
    /// 대세픽 카드(v2)에 닉네임·레벨·등급을 싣기 위해
    var overview: UserOverview? = nil
    var retry: (() -> Void)? = nil
    @Environment(AppRouter.self) private var router
    /// 슛 타입 골 합계 — 박스 안·박스 밖·PK 가 서로 겹치지 않는 분할이다(서버 report.ts: PK 는 박스 안/밖과 **따로** 센다).
    /// 헤딩·프리킥은 박스 안/밖의 부분집합이라 더하지 않는다.
    /// 합이 같은 카드의 득점(몰수 제외)보다 크면 옛 서버 집계(몰수 경기 슛 포함 — QA 2R P2-4)라 이 카드를 숨긴다.
    static func shotTypeGoals(_ st: [ShotTypeStat]) -> Int? {
        let parts = st.filter { ["inbox", "outbox", "penalty"].contains($0.key) }
        guard !parts.isEmpty, st.contains(where: { $0.tries > 0 }) else { return nil }
        return parts.reduce(0) { $0 + $1.goals }
    }

    /// 최근 7일 승률 증감 — 두 기간 모두 8판 이상일 때만. 표본이 작으면 증감은 소음이다.
    static let weeklyMinGames = 8
    static func weeklyDelta(_ w: WeeklyForm) -> Int? {
        guard w.recentGames >= weeklyMinGames, w.prevGames >= weeklyMinGames, w.prevWinRate != nil else { return nil }
        return w.deltaWinRate
    }

    var body: some View {
        switch state {
        case .idle, .loading: Skeleton(height: 260)
        case .failed(let e): ErrorState(title: "성적표를 불러오지 못했어요", message: e.localizedDescription, error: e, retry: retry)
        case .loaded(let p):
            if p.players.isEmpty {
                Panel { Text(p.sampleGames == 0 ? "이 매치 유형에는 최근 경기 기록이 없어요." : "선수 성적표를 만들 표본이 부족해요 (\(p.minGames)경기 이상 출전 선수 없음).").fcFont(14).foregroundStyle(FC.muted) }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button { router.pendingSquadImport = .owner(p.builderOwner); router.tab = .squad } label: {
                        Panel(padding: 12) { HStack { Text("🛡️ 이 스쿼드 그대로 빌더로 열기").fcFont(14, weight: .semibold).foregroundStyle(FC.ink); Spacer(); Text("열기 →").fcScoreboard(13).foregroundStyle(FC.tint) } }
                    }.buttonStyle(.plain)
                    // "스쿼드 실전 가치" 판정 패널은 뺐다 — 클리닉 점수와 같은 재료(선수 평점)를 밈 등급으로 한 번 더 보여 줘
                    // 숫자만 늘었다. 응답 필드(squadVerdict·squadRating)는 계약상 그대로 받는다.
                    if let c = p.clinic { clinic(c, sampleGames: p.sampleGames) }
                    if let picks = p.picks {
                        Panel {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel("내 픽 vs 인기 픽")
                                HStack(alignment: .lastTextBaseline, spacing: 24) {
                                    VStack(alignment: .leading) { (Text("\(picks.topPickCount)") + Text("명").font(.fcScoreboard(14, typeSize)).foregroundStyle(FC.muted)).font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.ink); Text("인기 TOP10").font(.fcFont(12, typeSize)).foregroundStyle(FC.muted) }
                                    VStack(alignment: .leading) { (Text("\(picks.total - picks.topPickCount)") + Text("명").font(.fcScoreboard(14, typeSize)).foregroundStyle(FC.muted)).font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.ink); Text("TOP10 외").font(.fcFont(12, typeSize)).foregroundStyle(FC.muted) }
                                }
                                Text("내가 쓴 \(picks.total)명 중 포지션별 인기 TOP10과 겹치는 카드\(picks.date.map { " · \($0) 스냅샷" } ?? "") · 매일 갱신").fcFont(11).foregroundStyle(FC.muted)
                                if let overview { ShareCardButton(story: .pickMatch(overview, picks), label: "🔥 대세픽 카드", compact: true) }
                                else { ShareCardButton(spec: .pickMatch(nickname: nickname, picks: picks), label: "🔥 대세픽 카드", compact: true) }
                            }
                        }
                    }
                    // 광고 — "내 픽 vs 인기 픽" 뒤 · 선수 카드 앞(AD-PLACEMENT 1-2). 위 패널의 공유 버튼과 떨어지게 +8pt.
                    AdSlot(placement: "record_players", reserve: true).padding(.top, 8)
                    // 랭커 비교값이 하나도 없으면 "랭커 평균은…" 안내는 없는 기능을 설명하는 셈이라 뺀다.
                    Text("최근 \(p.sampleGames)경기 · \(p.minGames)경기 이상 출전 선수" + (p.players.contains { $0.ranker != nil } ? " · 랭커 평균은 같은 포지션 상위 랭커 기준" : "")).fcFont(12).foregroundStyle(FC.muted)
                    ForEach(Array(p.players.enumerated()), id: \.element.id) { i, pl in
                        card(pl)
                        // 선수 카드가 15장을 넘으면 15번째 뒤 1개 추가(깊은 자리 — 받은 뒤 편다)
                        if i == 14, p.players.count > 15 { AdSlot(placement: "record_players_2", format: .inline(maxHeight: 250)).padding(.vertical, 12) }
                    }
                }
            }
        }
    }

    private func clinic(_ c: Clinic, sampleGames: Int) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("스쿼드 클리닉")
                    Spacer()
                    Text("ⓘ 선수 평점(출전 가중) · 라인 균형 · 약한 고리 3축").fcFont(10).foregroundStyle(FC.muted)
                }
                HStack(alignment: .lastTextBaseline) {
                    (Text("\(Int(c.overall))") + Text("/100").font(.fcScoreboard(14, typeSize)).foregroundStyle(FC.muted)).font(.fcScoreboard(34, typeSize)).foregroundStyle(FC.ink)
                    // 점수 자체는 중립, 좋고 나쁨은 band 라벨 색으로만(라인 막대와 같은 60/40 컷)
                    Text(Self.bandLabel(c.band)).fcFont(12, weight: .semibold).foregroundStyle(c.overall >= 60 ? FC.win : c.overall < 40 ? FC.lose : FC.muted)
                    Spacer()
                    // c.sampleGames 는 선수×경기 출전 수라 "330경기"처럼 부풀어 보였다 — 실제 경기 수로 쓴다.
                    Text("최근 \(sampleGames)경기 · \(c.players)명").fcFont(11).foregroundStyle(FC.muted)
                }
                ForEach(c.lines) { l in
                    HStack {
                        Text(l.label).fcFont(13).foregroundStyle(FC.ink).frame(width: 60, alignment: .leading)
                        RatioBar(ratio: CGFloat(l.score) / 100, color: l.score >= 60 ? FC.win : l.score >= 40 ? FC.gold : FC.lose, height: 8)
                        Text(String(format: "%.2f", l.avgRating)).fcScoreboard(12).foregroundStyle(FC.muted).frame(width: 40, alignment: .trailing)
                    }
                }
                ForEach(c.issues) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(i.severity == "high" ? FC.lose : i.severity == "mid" ? FC.gold : FC.muted).frame(width: 6, height: 6).padding(.top, 6)
                        Text(i.text).fcFont(13).foregroundStyle(FC.ink)
                    }
                }
            }
        }
    }

    /// 랭커 대비 한 줄 — **포지션에 맞는 지표**로. 수비수·GK 에게 "경기당 골 +0.00" 은 늘 0 이라 의미가 없었다
    /// (USER-PANEL-GENZ 덕후 패널). 공격·2선은 골, 수비 라인(CB·FB·WB·DM)은 태클, GK 는 패스만 비교한다.
    /// 태클 비교는 서버 `ranker.tackle`(2026-10 추가)이 있을 때만 — 옛 서버 응답이면 그 칸을 숨긴다.
    static func rankerLine(_ p: PlayerCard, _ r: PlayerCard.RankerCompare) -> String? {
        let pos = p.positionLabel.uppercased()
        let pass = Int(p.passRate) - r.passRate
        let passPart = "패스 \(pass >= 0 ? "+" : "")\(pass)%p"
        let n = " (n=\(r.matchCount))"
        if pos == "GK" { return "랭커 대비 " + passPart + n }
        let defensive: Set<String> = ["CB", "LCB", "RCB", "SW", "LB", "RB", "LWB", "RWB", "CDM", "LDM", "RDM"]
        if defensive.contains(pos) {
            guard let rt = r.tackle, let t = p.tackle, p.games > 0 else { return "랭커 대비 " + passPart + n }
            return "랭커 대비 경기당 태클 \(String(format: "%+.2f", Double(t) / Double(p.games) - rt)) · " + passPart + n
        }
        return "랭커 대비 경기당 골 \(String(format: "%+.2f", p.goalsPerGame - r.goal)) · " + passPart + n
    }

    private func card(_ p: PlayerCard) -> some View {
        Button { router.push(.player(p.spId)) } label: {
            Panel(padding: 12) {
                HStack(spacing: 10) {
                    PlayerImage(spid: p.spId, size: 52, radius: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(p.name).fcFont(15, weight: .bold).foregroundStyle(FC.ink).lineLimit(1)
                            if !p.season.isEmpty { SeasonBadge(spid: p.spId, season: p.season) }
                            if p.topPick { Chip(text: "대세픽", color: FC.win, bg: FC.win.opacity(0.15)) }
                        }
                        Text("\(p.positionLabel) · \(p.games)경기 · ⚽\(p.goals) 🅰\(p.assists) · 패스 \(Int(p.passRate))%").fcFont(12).foregroundStyle(FC.muted)
                        if let r = p.ranker, let line = Self.rankerLine(p, r) {
                            Text(line).fcFont(11).foregroundStyle(FC.muted)
                        }
                        // 30경기 평균에 "오늘은 좀 아쉬웠다" 같은 한 경기용 밈 등급을 찍으면 뜻이 어긋난다 — 숫자(선수 평점)만 남긴다.
                    }
                    Spacer()
                    VStack(alignment: .trailing) { Text(String(format: "%.2f", p.avgRating)).fcScoreboard(20).foregroundStyle(p.avgRating >= 7.5 ? FC.gold : p.avgRating < 6 ? FC.lose : FC.ink); Text("선수 평점").fcFont(11).foregroundStyle(FC.muted) }
                }
            }
        }.buttonStyle(.plain)
    }
}

// MARK: - 플레이스타일

struct PlaystyleSection: View {
    /// 서버 controller 코드 → 표시 문구("unknown" 이 그대로 보였다)
    static func controllerLabel(_ c: String) -> String {
        ["gamepad": "패드", "keyboard": "키보드", "unknown": "조작 미확인"][c] ?? c
    }
    let state: Loadable<PlaystyleResponse>
    var retry: (() -> Void)? = nil
    /// 슛 타입 골 합계 — 박스 안·박스 밖·PK 가 서로 겹치지 않는 분할이다(서버 report.ts: PK 는 박스 안/밖과 **따로** 센다).
    /// 헤딩·프리킥은 박스 안/밖의 부분집합이라 더하지 않는다.
    /// 합이 같은 카드의 득점(몰수 제외)보다 크면 옛 서버 집계(몰수 경기 슛 포함 — QA 2R P2-4)라 이 카드를 숨긴다.
    static func shotTypeGoals(_ st: [ShotTypeStat]) -> Int? {
        let parts = st.filter { ["inbox", "outbox", "penalty"].contains($0.key) }
        guard !parts.isEmpty, st.contains(where: { $0.tries > 0 }) else { return nil }
        return parts.reduce(0) { $0 + $1.goals }
    }

    /// 최근 7일 승률 증감 — 두 기간 모두 8판 이상일 때만. 표본이 작으면 증감은 소음이다.
    static let weeklyMinGames = 8
    static func weeklyDelta(_ w: WeeklyForm) -> Int? {
        guard w.recentGames >= weeklyMinGames, w.prevGames >= weeklyMinGames, w.prevWinRate != nil else { return nil }
        return w.deltaWinRate
    }

    var body: some View {
        switch state {
        case .idle, .loading: Skeleton(height: 260)
        case .failed(let e): ErrorState(title: "플레이스타일을 불러오지 못했어요", message: e.localizedDescription, error: e, retry: retry)
        case .loaded(let p):
            let r = p.result
            VStack(alignment: .leading, spacing: 12) {
                Panel(highlight: FC.tint.opacity(0.4)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { SectionLabel("플레이스타일 · 베타", color: FC.tint); Spacer(); Chip(text: r.confidence == "ok" ? "신뢰도 보통" : r.confidence == "low" ? "신뢰도 낮음" : "데이터 부족") }
                        Text(r.archetype.name).fcFont(24, weight: .bold).foregroundStyle(FC.ink)
                        Text(r.archetype.tagline).fcFont(14).foregroundStyle(FC.muted)
                        HStack(spacing: 6) { Text("강점").fcFont(12, weight: .bold).foregroundStyle(FC.win); Text(r.archetype.baseStrength).fcFont(13).foregroundStyle(FC.ink) }
                        HStack(spacing: 6) { Text("취약").fcFont(12, weight: .bold).foregroundStyle(FC.lose); Text(r.archetype.baseWeakness).fcFont(13).foregroundStyle(FC.ink) }
                        Text("\(r.games)경기 · \(Self.controllerLabel(r.controller)) · 성향이지 실력 점수는 아니에요").fcFont(11).foregroundStyle(FC.muted)
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("5축 성향")
                        ForEach(r.axes) { a in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(a.label).fcFont(13, weight: .semibold).foregroundStyle(FC.ink); Spacer(); Text("\(Int(a.value))").fcScoreboard(12).foregroundStyle(a.lowConf ? FC.muted : FC.ink) }
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(FC.surface2)
                                        if a.bipolar { Rectangle().fill(FC.line).frame(width: 1).offset(x: g.size.width / 2) }
                                        Circle().fill(a.lowConf ? FC.muted : FC.tint).frame(width: 12, height: 12).offset(x: g.size.width * CGFloat(a.value) / 100 - 6)
                                    }
                                }.frame(height: 12)
                                if a.bipolar { HStack { Text(a.leftLabel ?? "").fcFont(10).foregroundStyle(FC.muted); Spacer(); Text(a.rightLabel ?? "").fcFont(10).foregroundStyle(FC.muted) } }
                            }
                        }
                    }
                }
                if !r.chips.isEmpty {
                    FlowLayout(spacing: 6) { ForEach(r.chips) { c in Chip(text: c.text, color: c.kind == "strength" ? FC.win : FC.lose, bg: (c.kind == "strength" ? FC.win : FC.lose).opacity(0.15)) } }
                }
                // 광고 — 5축 성향(과 강점·약점 칩, 탭 불가) 뒤 · 누적 슛맵 앞(AD-PLACEMENT 1-2)
                AdSlot(placement: "record_style", reserve: true)
                if !p.shots.isEmpty {
                    Panel { VStack(alignment: .leading, spacing: 8) { SectionLabel("누적 슛맵 · 최근 경기 내 슛 \(p.shots.count)개"); ShotMapView(mine: p.shots, theirs: [], myTone: FC.tint, theirTone: FC.lose) } }
                }
            }
        }
    }
}
