import SwiftUI
import Charts

// MARK: - 종합 리포트

struct ReportSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let state: Loadable<ReportResponse>
    /// 섹션 오류에 재시도 버튼이 없어 탭을 바꿨다 돌아오거나 전체 새로고침을 해야 했다.
    var retry: (() -> Void)? = nil
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
                            SectionLabel("분석 리포트", color: FC.accent)
                            HStack(alignment: .lastTextBaseline, spacing: 20) {
                                VStack(alignment: .leading) { Text("최근 \(r.report.played)경기 득실").fcFont(12).foregroundStyle(FC.muted)
                                    (Text("\(r.report.goalsFor)").foregroundStyle(FC.accent) + Text(" : ").foregroundStyle(FC.muted) + Text("\(r.report.goalsAgainst)").foregroundStyle(FC.lose)).font(.fcScoreboard(24, typeSize)) }
                                VStack(alignment: .leading) { Text("평균 경기 평점").fcFont(12).foregroundStyle(FC.muted); Text(String(format: "%.2f", r.report.avgRating)).fcScoreboard(24).foregroundStyle(FC.gold) }
                                if let w = r.report.weekly, let d = w.deltaWinRate {
                                    VStack(alignment: .leading) { Text("최근 7일 승률").fcFont(12).foregroundStyle(FC.muted)
                                        (Text("\(w.recentWinRate)%") + Text(d >= 0 ? " ▲\(d)" : " ▼\(-d)").font(.fcScoreboard(13, typeSize)).foregroundStyle(d >= 0 ? FC.win : FC.lose)).font(.fcScoreboard(24, typeSize)).foregroundStyle(FC.ink) }
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
                                    BarMark(x: .value("시간", b.label), y: .value("득점", b.forGoals)).foregroundStyle(FC.accent).position(by: .value("구분", "득점"))
                                    BarMark(x: .value("시간", b.label), y: .value("실점", b.againstGoals)).foregroundStyle(FC.lose).position(by: .value("구분", "실점"))
                                }
                            }
                            .chartXAxis { AxisMarks { AxisValueLabel().font(.pretendard(10)).foregroundStyle(FC.muted) } }
                            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(FC.line); AxisValueLabel().foregroundStyle(FC.muted) } }
                            .frame(height: 160)
                            HStack(spacing: 12) { legend(FC.accent, "득점"); legend(FC.lose, "실점") }
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("슛 타입별 결정력")
                            ForEach(r.report.shotTypes.filter { $0.tries > 0 }) { s in
                                HStack {
                                    Text(s.label).fcFont(13).foregroundStyle(FC.ink).frame(width: 90, alignment: .leading)
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(FC.surface2)
                                            Capsule().fill(FC.accent).frame(width: g.size.width * CGFloat(s.goals) / CGFloat(max(1, s.tries)))
                                        }
                                    }.frame(height: 8)
                                    Text("\(s.goals)/\(s.tries)").fcScoreboard(12).foregroundStyle(FC.muted).frame(width: 50, alignment: .trailing)
                                }
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
    static func bandLabel(_ band: String) -> String {
        ["top": "최상위 스쿼드", "strong": "상위권 스쿼드", "balanced": "안정권 스쿼드", "building": "성장형 스쿼드", "rebuild": "재정비 필요"][band] ?? band
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    let state: Loadable<PlayersResponse>
    let nickname: String
    var retry: (() -> Void)? = nil
    @Environment(AppRouter.self) private var router
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
                        Panel(padding: 12) { HStack { Text("🛡️ 이 스쿼드 그대로 빌더로 열기").fcFont(14, weight: .semibold).foregroundStyle(FC.ink); Spacer(); Text("열기 →").fcScoreboard(13).foregroundStyle(FC.accent) } }
                    }.buttonStyle(.plain)
                    // "스쿼드 실전 가치" 판정 패널은 뺐다 — 클리닉 점수와 같은 재료(선수 평점)를 밈 등급으로 한 번 더 보여 줘
                    // 숫자만 늘었다. 응답 필드(squadVerdict·squadRating)는 계약상 그대로 받는다.
                    if let c = p.clinic { clinic(c, sampleGames: p.sampleGames) }
                    if let picks = p.picks {
                        Panel {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel("내 픽 vs 랭커 픽")
                                HStack(alignment: .lastTextBaseline, spacing: 24) {
                                    VStack(alignment: .leading) { (Text("\(picks.topPickCount)") + Text("명").font(.fcScoreboard(14, typeSize)).foregroundStyle(FC.muted)).font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.win); Text("랭커 대세픽").font(.fcFont(12, typeSize)).foregroundStyle(FC.muted) }
                                    VStack(alignment: .leading) { (Text("\(picks.total - picks.topPickCount)") + Text("명").font(.fcScoreboard(14, typeSize)).foregroundStyle(FC.muted)).font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.ink); Text("TOP10 외").font(.fcFont(12, typeSize)).foregroundStyle(FC.muted) }
                                }
                                Text("내가 쓴 \(picks.total)명 중 랭커 인기 TOP10과 겹치는 카드\(picks.date.map { " · \($0) 스냅샷" } ?? "") · 매일 갱신").fcFont(11).foregroundStyle(FC.muted)
                                ShareCardButton(spec: .pickMatch(nickname: nickname, picks: picks), label: "🔥 랭커 대세픽 카드", compact: true)
                            }
                        }
                    }
                    Text("최근 \(p.sampleGames)경기 · \(p.minGames)경기 이상 출전 선수 · 랭커 평균은 같은 포지션 상위 랭커 기준").fcFont(12).foregroundStyle(FC.muted)
                    ForEach(p.players) { card(_: $0) }
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
                    (Text("\(Int(c.overall))") + Text("/100").font(.fcScoreboard(14, typeSize)).foregroundStyle(FC.muted)).font(.fcScoreboard(34, typeSize)).foregroundStyle(FC.accent)
                    Text(Self.bandLabel(c.band)).fcFont(12, weight: .semibold).foregroundStyle(FC.gold)
                    Spacer()
                    // c.sampleGames 는 선수×경기 출전 수라 "330경기"처럼 부풀어 보였다 — 실제 경기 수로 쓴다.
                    Text("최근 \(sampleGames)경기 · \(c.players)명").fcFont(11).foregroundStyle(FC.muted)
                }
                ForEach(c.lines) { l in
                    HStack {
                        Text(l.label).fcFont(13).foregroundStyle(FC.ink).frame(width: 60, alignment: .leading)
                        GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(FC.surface2); Capsule().fill(l.score >= 60 ? FC.win : l.score >= 40 ? FC.gold : FC.lose).frame(width: g.size.width * CGFloat(l.score) / 100) } }.frame(height: 8)
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
                        if let r = p.ranker {
                            Text("랭커 대비 경기당 골 \(String(format: "%+.2f", p.goalsPerGame - r.goal)) · 패스 \(Int(p.passRate) - r.passRate >= 0 ? "+" : "")\(Int(p.passRate) - r.passRate)%p (n=\(r.matchCount))").fcFont(11).foregroundStyle(FC.muted)
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
    let state: Loadable<PlaystyleResponse>
    var retry: (() -> Void)? = nil
    var body: some View {
        switch state {
        case .idle, .loading: Skeleton(height: 260)
        case .failed(let e): ErrorState(title: "플레이스타일을 불러오지 못했어요", message: e.localizedDescription, error: e, retry: retry)
        case .loaded(let p):
            let r = p.result
            VStack(alignment: .leading, spacing: 12) {
                Panel(highlight: FC.accent.opacity(0.4)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { SectionLabel("플레이스타일 · 베타", color: FC.accent); Spacer(); Chip(text: r.confidence == "ok" ? "신뢰도 보통" : r.confidence == "low" ? "신뢰도 낮음" : "데이터 부족") }
                        Text(r.archetype.name).fcFont(24, weight: .bold).foregroundStyle(FC.ink)
                        Text(r.archetype.tagline).fcFont(14).foregroundStyle(FC.muted)
                        HStack(spacing: 6) { Text("강점").fcFont(12, weight: .bold).foregroundStyle(FC.win); Text(r.archetype.baseStrength).fcFont(13).foregroundStyle(FC.ink) }
                        HStack(spacing: 6) { Text("취약").fcFont(12, weight: .bold).foregroundStyle(FC.lose); Text(r.archetype.baseWeakness).fcFont(13).foregroundStyle(FC.ink) }
                        Text("\(r.games)경기 · \(r.controller) · 성향(주황)≠실력").fcFont(11).foregroundStyle(FC.muted)
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("5축 성향")
                        ForEach(r.axes) { a in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(a.label).fcFont(13, weight: .semibold).foregroundStyle(FC.ink); Spacer(); Text("\(Int(a.value))").fcScoreboard(12).foregroundStyle(a.lowConf ? FC.muted : Color.orange) }
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(FC.surface2)
                                        if a.bipolar { Rectangle().fill(FC.line).frame(width: 1).offset(x: g.size.width / 2) }
                                        Circle().fill(a.lowConf ? FC.muted : Color.orange).frame(width: 12, height: 12).offset(x: g.size.width * CGFloat(a.value) / 100 - 6)
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
                if !p.shots.isEmpty {
                    Panel { VStack(alignment: .leading, spacing: 8) { SectionLabel("누적 슛맵 · 최근 경기 내 슛 \(p.shots.count)개"); ShotMapView(mine: p.shots, theirs: [], myTone: FC.accent, theirTone: FC.lose) } }
                }
            }
        }
    }
}
