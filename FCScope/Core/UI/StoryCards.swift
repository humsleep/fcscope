import SwiftUI

/**
 공유 카드 v2 — 전적(메인)·계급·폼·주간·라이벌·대세픽. 부품은 CardKit.swift.

 전적 카드는 overview 외에 players·report·playstyle 응답이 필요하다. 전적 화면은 탭을 열 때만
 이들을 받으므로, 카드를 만들 때 없는 것만 받아 온다(응답 캐시가 있으면 즉시). 하나가 실패해도
 해당 섹션만 대체 내용으로 바꾸고 카드는 만든다.
 */
enum StoryCard {
    case user(UserOverview)
    case rank(UserOverview)
    case streak(UserOverview)
    case weekly(UserOverview)
    case rival(UserOverview, Rival)
    case pickMatch(UserOverview, PicksInfo)

    var filename: String {
        switch self {
        case .user(let o): return "fcscope-user-\(o.profile.nickname)"
        case .rank(let o): return "fcscope-rank-\(o.profile.nickname)"
        case .streak(let o): return "fcscope-streak-\(o.profile.nickname)"
        case .weekly(let o): return "fcscope-weekly-\(o.profile.nickname)"
        case .rival(let o, _): return "fcscope-rival-\(o.profile.nickname)"
        case .pickMatch(let o, _): return "fcscope-pick-\(o.profile.nickname)"
        }
    }

    private var overview: UserOverview {
        switch self {
        case .user(let o), .rank(let o), .streak(let o), .weekly(let o), .rival(let o, _), .pickMatch(let o, _): return o
        }
    }

    /// 필요한 부가 응답·이미지를 받은 뒤 1080×1920 이미지로 렌더한다.
    @MainActor
    func render() async -> UIImage? {
        let o = overview
        let enc = o.profile.nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? o.profile.nickname
        let q = ["type": String(o.matchType)]
        let icons = o.profile.divisions.compactMap(\.iconUrl)
        let size = CGSize(width: CardLayout.width, height: CardLayout.height)

        switch self {
        case .user:
            async let pl: PlayersResponse? = try? APIClient.shared.getAndCache("/api/v1/user/\(enc)/players", query: q, auth: false)
            async let rp: ReportResponse? = try? APIClient.shared.getAndCache("/api/v1/user/\(enc)/report", query: q, auth: false)
            async let ps: PlaystyleResponse? = try? APIClient.shared.getAndCache("/api/v1/user/\(enc)/playstyle", query: q, auth: false)
            let data = UserCardData(o: o, players: await pl, report: await rp, playstyle: await ps)
            let best = data.bestPlayers
            let images = await CardImages.load(players: best.map(\.spId), seasonsFor: best.map(\.spId), urls: icons)
            return ShareCardRenderer.render(view: UserCardView(d: data, images: images), size: size)
        case .rank:
            let pl: PlayersResponse? = try? await APIClient.shared.getAndCache("/api/v1/user/\(enc)/players", query: ["type": "50"], auth: false)
            let ace = UserCardData.best(players: pl, limit: 1).first
            let images = await CardImages.load(players: ace.map { [$0.spId] } ?? [], seasonsFor: ace.map { [$0.spId] } ?? [], urls: icons)
            return ShareCardRenderer.render(view: RankCardView(o: o, ace: ace, images: images), size: size)
        case .streak:
            let images = await CardImages.load(players: [], urls: icons)
            return ShareCardRenderer.render(view: StreakCardView(o: o, images: images), size: size)
        case .weekly:
            let images = await CardImages.load(players: [], urls: icons)
            return ShareCardRenderer.render(view: WeeklyCardView(o: o, images: images), size: size)
        case .rival(_, let r):
            let images = await CardImages.load(players: [], urls: icons)
            return ShareCardRenderer.render(view: RivalCardView(o: o, r: r, images: images), size: size)
        case .pickMatch(_, let picks):
            let pl: PlayersResponse? = try? await APIClient.shared.getAndCache("/api/v1/user/\(enc)/players", query: q, auth: false)
            let tops = (pl?.players ?? []).filter(\.topPick)
            let shown = Array((tops.isEmpty ? (pl?.players ?? []).sorted { $0.avgRating > $1.avgRating } : tops).prefix(6))
            let images = await CardImages.load(players: shown.map(\.spId), seasonsFor: shown.map(\.spId), urls: icons)
            return ShareCardRenderer.render(view: PickCardView(o: o, picks: picks, shown: shown, images: images), size: size)
        }
    }
}

// MARK: - 전적 카드 데이터

struct UserCardData {
    let o: UserOverview
    let players: PlayersResponse?
    let report: ReportResponse?
    let playstyle: PlaystyleResponse?

    var bestPlayers: [CardPlayer] { Self.best(players: players, limit: 3) }

    /// 클리닉 강점(이미 평점순) → 부족하면 출전 충분한 선수 평점순.
    static func best(players: PlayersResponse?, limit: Int) -> [CardPlayer] {
        guard let pr = players else { return [] }
        let byId = Dictionary(pr.players.map { ($0.spId, $0) }, uniquingKeysWith: { a, _ in a })
        let byPid = Dictionary(pr.players.map { ($0.spId % 1_000_000, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [PlayerCard] = []
        for s in pr.clinic?.strengths ?? [] {
            if let p = byId[s.spId] ?? byPid[s.spId % 1_000_000], !out.contains(where: { $0.spId == p.spId }) { out.append(p) }
        }
        let minGames = max(pr.minGames, 3)
        for p in pr.players.filter({ $0.games >= minGames }).sorted(by: { $0.avgRating > $1.avgRating }) where out.count < limit {
            if !out.contains(where: { $0.spId == p.spId }) { out.append(p) }
        }
        return out.prefix(limit).map {
            CardPlayer(spId: $0.spId, name: $0.name, season: $0.season, position: $0.positionLabel,
                       rating: $0.avgRating, goals: $0.goals, assists: $0.assists, games: $0.games)
        }
    }

    /// 플레이스타일 이름·강점 한 줄. 표본이 부족하면 서버 진단 유형으로 대체.
    var style: (name: String, line: String?, beta: Bool)? {
        if let r = playstyle?.result, r.confidence == "ok" {
            return (r.archetype.name, r.chips.first { $0.kind == "strength" }?.text ?? r.archetype.tagline, true)
        }
        if let t = o.diagnosis.type {
            return (t.title, t.desc.components(separatedBy: " — ").first, false)
        }
        return nil
    }

    var shotTotals: (goals: Int, tries: Int)? {
        guard let st = report?.report.shotTypes, !st.isEmpty else { return nil }
        let g = st.reduce(0) { $0 + $1.goals }, t = st.reduce(0) { $0 + $1.tries }
        return t > 0 ? (g, t) : nil
    }

    /// 긍정 스탯 후보 — 조건을 만족하는 것만, 우선순위순
    var positives: [(String, String)] {
        let p = o.perf
        var out: [(String, String)] = []
        if let inbox = report?.report.shotTypes.first(where: { $0.key == "inbox" }), inbox.tries > 0 {
            let r = Int((Double(inbox.goals) / Double(inbox.tries) * 100).rounded())
            if r >= 35 { out.append(("박스 안 결정력", "\(r)%")) }
        }
        if p.played > 0 {
            let gpg = Double(o.summary.goalsFor) / Double(max(1, o.summary.played))
            if gpg >= 1.8 { out.append(("경기당 득점", String(format: "%.1f", gpg))) }
        }
        if p.bestWinStreak >= 3 { out.append(("최고 연승", "\(p.bestWinStreak)")) }
        if p.cleanSheets >= 2 { out.append(("클린시트", "\(p.cleanSheets)")) }
        if o.summary.avgPossession >= 55 { out.append(("평균 점유율", "\(o.summary.avgPossession)%")) }
        if p.avgRating >= 6.8 { out.append(("평균 평점", String(format: "%.1f", p.avgRating))) }
        out.append(("총 득점", "\(o.summary.goalsFor)"))
        out.append(("경기 수", "\(o.summary.played)"))
        return out
    }
}

// MARK: - 전적 카드 (메인)

struct UserCardView: View {
    let d: UserCardData
    let images: CardImages
    private var o: UserOverview { d.o }

    var body: some View {
        CardCanvas {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(chip: "\(matchTypeName) · 최근 \(o.summary.played)경기")          // 264–308
                Spacer().frame(height: 16)
                NicknameTitle(text: o.profile.nickname)                                     // 324–500
                Spacer().frame(height: 16)
                IdentityPills(level: o.profile.level, divisions: o.profile.divisions, images: images)   // 516–572
                Spacer().frame(height: 24)
                if o.summary.played == 0 {
                    Text("최근 기록이 없어요").font(.pretendard(32, .semibold)).foregroundStyle(CardPalette.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if let s = d.style { styleBlock(s) } // 596–716
                    Spacer().frame(height: 24)
                    scorePanel.frame(height: d.style == nil ? 352 : 232)                   // 740–972
                    Spacer().frame(height: 24)
                    let best = d.bestPlayers
                    if !best.isEmpty { bestBlock(best) }                                    // 996–1250
                    Spacer().frame(height: best.isEmpty ? 0 : 38)
                    finishing(tall: best.isEmpty)                                           // 1288–1480
                    Spacer(minLength: 0)
                }
                CardFooter()                                                                // 1488–1560
            }
        }
    }

    private var matchTypeName: String {
        o.matchTabs.first { $0.type == o.matchType }?.label ?? (o.matchType == 52 ? "감독모드" : o.matchType == 40 ? "클래식 1on1" : "공식경기")
    }

    private func styleBlock(_ s: (name: String, line: String?, beta: Bool)) -> some View {
        HStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 3).fill(CardPalette.lime).frame(width: 6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    CardLabel(text: "PLAYSTYLE")
                    if s.beta {
                        Text("BETA").font(.scoreboard(16)).foregroundStyle(CardPalette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 2).overlay(Capsule().stroke(CardPalette.line, lineWidth: 2))
                    }
                }
                Text(s.name).font(.pretendard(46, .bold)).foregroundStyle(CardPalette.lime).lineLimit(1).minimumScaleFactor(0.7)
                if let line = s.line {
                    Text("▲ \(line)").font(.pretendard(26, .medium)).foregroundStyle(CardPalette.ink.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 120)
    }

    private var scoreColor: Color {
        switch o.tier.tone { case "gold": return CardPalette.gold; case "win", "lime": return CardPalette.lime; default: return CardPalette.ink }
    }
    private var showTier: Bool { ["gold", "win", "lime"].contains(o.tier.tone) }

    /// 왼쪽 큰 숫자 — 그 유저에게 가장 좋은 지표를 올린다.
    /// 스코어가 좋으면(티어 win/gold) FC SCORE, 아니면 몰수 제외 승률이 더 높을 때 그것, 그것도 아니면 평균 평점.
    private var hero: (label: String, value: String, sub: String?, color: Color, gauge: Bool) {
        if showTier { return ("FC SCORE", String(format: "%.1f", o.score), o.tier.label, scoreColor, true) }
        if let f = o.perf.forfeits, f > 0, realWinRate > o.summary.winRate {
            return ("실경기 승률", "\(realWinRate)%", "몰수 \(f)경기 제외", realWinRate >= 50 ? CardPalette.lime : CardPalette.ink, false)
        }
        return ("평균 평점", String(format: "%.2f", o.perf.avgRating), "최근 \(o.perf.played)경기", CardPalette.ink, false)
    }

    private var scorePanel: some View {
        let h = hero
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CardLabel(text: h.label)
                Text(h.value).font(.scoreboard(96)).foregroundStyle(h.color).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(height: 110, alignment: .leading)
                Spacer(minLength: 0)
                if h.gauge {
                    HStack(spacing: 6) {
                        ForEach(0..<10, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(i < Int(o.score.rounded()) ? scoreColor : CardPalette.line)
                                .frame(width: 18, height: 12)
                        }
                    }
                }
                if let sub = h.sub {
                    Text(sub).font(.pretendard(26, .bold)).foregroundStyle(h.gauge ? scoreColor : CardPalette.muted).padding(.top, 8)
                }
            }
            .frame(width: 272, alignment: .leading)
            Rectangle().fill(CardPalette.line).frame(width: 1).padding(.vertical, 8).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    wdl(o.summary.win, "승"); wdl(o.summary.draw, "무"); wdl(o.summary.lose, "패")
                    Spacer(minLength: 8)
                    Text("\(o.summary.winRate)%").font(.scoreboard(44)).foregroundStyle(o.summary.winRate >= 50 ? CardPalette.lime : CardPalette.ink)
                }
                Spacer(minLength: 8)
                HStack {
                    Text("최근 10경기").font(.pretendard(24, .semibold)).foregroundStyle(CardPalette.muted)
                    Spacer()
                    if o.streak.color != "lose", o.perf.played > 0 {
                        Text(o.streak.text).font(.pretendard(26, .bold)).foregroundStyle(o.streak.color == "gold" ? CardPalette.gold : CardPalette.lime).lineLimit(1)
                    }
                }
                .padding(.bottom, 10)
                FormStrip(matches: o.matches, cell: 46, spacing: 12)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(CardPalette.line, lineWidth: 2))
    }

    private var realWinRate: Int {
        let p = o.perf
        guard let np = p.normalPlayed, np > 0, let nw = p.normalWin else { return o.summary.winRate }
        return Int((Double(nw) / Double(np) * 100).rounded())
    }

    private func wdl(_ n: Int, _ l: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n)").font(.scoreboard(56)).foregroundStyle(CardPalette.ink)
            Text(l).font(.pretendard(28)).foregroundStyle(CardPalette.muted)
        }
        .padding(.trailing, 20)
    }

    private func bestBlock(_ best: [CardPlayer]) -> some View {
        let n = CGFloat(best.count)
        let w = (CardLayout.contentWidth - 20 * (n - 1)) / n
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardLabel(text: "BEST PLAYERS")
                Spacer()
                Text("최근 \(d.players?.sampleGames ?? o.summary.played)경기 평균 평점").font(.pretendard(24)).foregroundStyle(CardPalette.muted)
            }
            .frame(height: 24)
            HStack(spacing: 20) {
                ForEach(Array(best.enumerated()), id: \.element.id) { i, p in
                    PlayerTile(p: p, images: images, width: w, height: 222, top: i == 0)
                }
            }
        }
        .frame(height: 254)
    }

    @ViewBuilder
    private func finishing(tall: Bool) -> some View {
        let shots = d.playstyle?.shots ?? []
        let mapH: CGFloat = tall ? 360 : 176
        let pos = d.positives
        HStack(alignment: .top, spacing: 24) {
            if !shots.isEmpty { HalfShotMap(shots: shots, height: mapH) }
            VStack(alignment: .leading, spacing: 0) {
                CardLabel(text: "FINISHING")
                if let t = d.shotTotals, Double(t.goals) / Double(t.tries) >= 0.25 {
                    HStack(alignment: .center, spacing: 20) {
                        Text("\(Int((Double(t.goals) / Double(t.tries) * 100).rounded()))%").font(.scoreboard(88)).foregroundStyle(CardPalette.lime)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("결정력").font(.pretendard(30, .bold)).foregroundStyle(CardPalette.ink)
                            Text("슛 \(t.tries)개 중 \(t.goals)골").font(.pretendard(26)).foregroundStyle(CardPalette.muted)
                        }
                    }
                    .frame(height: 100)
                    if let first = pos.first {
                        HighlightChip(text: "\(first.0) \(first.1)").padding(.top, 8)
                    }
                } else if let first = pos.first {
                    HStack(alignment: .center, spacing: 20) {
                        Text(first.1).font(.scoreboard(88)).foregroundStyle(CardPalette.lime).lineLimit(1).minimumScaleFactor(0.6)
                        Text(first.0).font(.pretendard(30, .bold)).foregroundStyle(CardPalette.ink)
                    }
                    .frame(height: 100)
                    miniStats(Array(pos.dropFirst().prefix(2)), width: shots.isEmpty ? CardLayout.contentWidth : CardLayout.contentWidth - mapH * 1.295 - 24)
                }
            }
            .padding(.top, 2)
        }
        .frame(height: mapH, alignment: .top)
    }

    private func miniStats(_ items: [(String, String)], width: CGFloat) -> some View {
        let w = (width - 20) / 2
        return HStack(spacing: 20) {
            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0).font(.pretendard(22)).foregroundStyle(CardPalette.muted).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 6)
                    Text(item.1).font(.scoreboard(34)).foregroundStyle(CardPalette.ink).lineLimit(1)
                }
                .padding(.horizontal, 20)
                .frame(width: w, height: 64)
                .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - 공통 템플릿 (나머지 카드)

/// 헤더 → 닉네임(M) → 아이덴티티 → 킥커 → 히어로 → 서브라인 → 바디 → 푸터
struct TemplateCard<Hero: View, Sub: View, Body: View>: View {
    let chip: String
    let o: UserOverview
    let images: CardImages
    let kicker: String
    var cta: String = "나도 내 전적 카드 만들기 →"
    var showNickname = true
    @ViewBuilder var hero: Hero
    @ViewBuilder var sub: Sub
    @ViewBuilder var content: Body

    var body: some View {
        CardCanvas {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(chip: chip)                                                                 // 264–308
                Spacer().frame(height: 16)
                if showNickname {
                    NicknameTitle(text: o.profile.nickname, maxSize: 88, minSize: 56, boxHeight: 112)  // 324–436
                    Spacer().frame(height: 16)
                    IdentityPills(level: o.profile.level, divisions: o.profile.divisions, images: images, compact: true) // 452–500
                    Spacer().frame(height: 32)
                }
                Text(kicker).font(.pretendard(30, .bold)).kerning(2).foregroundStyle(CardPalette.muted).lineLimit(1)
                    .frame(height: 48, alignment: .leading)
                hero.frame(maxWidth: .infinity, alignment: .leading).frame(height: 260)
                Spacer().frame(height: 20)
                sub.frame(maxWidth: .infinity, alignment: .leading).frame(height: 64)
                Spacer().frame(height: 24)
                content.frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
                CardFooter(cta: cta)
            }
        }
    }
}

struct CardStampView: View {
    let text: String
    var color: Color = CardPalette.lime
    var body: some View {
        Text(text).font(.pretendard(34, .bold)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 32).frame(height: 64)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(color, lineWidth: 3))
    }
}

private func statRow(_ items: [(String, String, Color)]) -> some View {
    let items = Array(items.prefix(3))
    let w = (CardLayout.contentWidth - 20 * CGFloat(items.count - 1)) / CGFloat(max(1, items.count))
    return HStack(spacing: 20) {
        ForEach(items, id: \.0) { StatBox(label: $0.0, value: $0.1, color: $0.2, width: w) }
    }
}

// 계급 인증
struct RankCardView: View {
    let o: UserOverview
    let ace: CardPlayer?
    let images: CardImages
    private var d: DivisionCard? { o.profile.divisions.first { $0.matchType == 50 } ?? o.profile.divisions.first }

    var body: some View {
        TemplateCard(chip: "계급 인증", o: o, images: images, kicker: "\(d?.matchTypeName ?? "공식경기") 최고 등급") {
            HStack(spacing: 32) {
                if let img = images.url(d?.iconUrl) {
                    Image(uiImage: img).resizable().scaledToFit().frame(width: 200, height: 200)
                }
                Text(d?.divisionName ?? "-").font(.pretendard(120, .bold)).foregroundStyle(CardPalette.gold)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        } sub: {
            if let d { CardStampView(text: "달성 \(d.date)", color: CardPalette.gold) }
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(o.profile.divisions.filter { $0.matchType != d?.matchType }.prefix(2)) { other in
                    HStack(spacing: 20) {
                        if let img = images.url(other.iconUrl) { Image(uiImage: img).resizable().scaledToFit().frame(width: 56, height: 56) }
                        Text(other.divisionName).font(.pretendard(40, .bold)).foregroundStyle(CardPalette.gold)
                        Text("\(other.matchTypeName) 최고 · \(other.date)").font(.pretendard(24)).foregroundStyle(CardPalette.muted)
                        Spacer()
                    }
                    .padding(.horizontal, 24).frame(height: 96)
                    .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                }
                if let ace {
                    CardLabel(text: "ACE")
                    PlayerTile(p: ace, images: images, width: CardLayout.contentWidth, height: 240, top: true)
                }
            }
        }
    }
}

// 폼
struct StreakCardView: View {
    let o: UserOverview
    let images: CardImages
    var body: some View {
        let good = o.streak.color != "lose" && o.perf.played > 0
        TemplateCard(chip: "이번 폼", o: o, images: images, kicker: "최근 \(min(10, o.matches.count))경기 폼") {
            VStack(alignment: .leading, spacing: 28) {
                Text(good ? o.streak.text : "최근 \(o.perf.played)경기")
                    .font(.pretendard(72, .bold)).foregroundStyle(good ? (o.streak.color == "gold" ? CardPalette.gold : CardPalette.lime) : CardPalette.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                FormStrip(matches: o.matches, cell: 80, spacing: 11)
            }
        } sub: {
            Text("평균 평점 \(String(format: "%.1f", o.perf.avgRating)) · 최근 \(o.perf.played)경기")
                .font(.pretendard(34, .semibold)).foregroundStyle(CardPalette.muted)
        } content: {
            let base: [(String, String, Color)] = [
                ("최고 연승", "\(o.perf.bestWinStreak)", CardPalette.lime),
                ("클린시트", "\(o.perf.cleanSheets)", CardPalette.ink),
                ("대승", "\(o.perf.bigWins)", CardPalette.ink),
            ]
            let filled = base.filter { $0.1 != "0" }
            let extra = UserCardData(o: o, players: nil, report: nil, playstyle: nil).positives
                .filter { e in !filled.contains { $0.0 == e.0 } }.map { ($0.0, $0.1, CardPalette.ink) }
            VStack(alignment: .leading, spacing: 20) {
                statRow(filled + extra)
                CardLabel(text: "RECENT MATCHES")
                VStack(spacing: 12) {
                    ForEach(o.matches.prefix(3)) { m in recentRow(m) }
                }
            }
        }
    }

    /// 최근 경기 한 줄 — 결과 · 스코어 · 점유율 · 평점 (상대 구단주명은 싣지 않는다)
    private func recentRow(_ m: MatchSummary) -> some View {
        let (bg, fg) = FormStrip.colors(m.result)
        return HStack(spacing: 24) {
            Text(m.result).font(.pretendard(30, .bold)).foregroundStyle(fg)
                .frame(width: 60, height: 60).background(bg, in: RoundedRectangle(cornerRadius: 14))
            Text("\(m.me.goals) : \(m.opponent?.goals ?? 0)").font(.scoreboard(48)).foregroundStyle(CardPalette.ink)
            if m.forfeit { Text("몰수").font(.pretendard(24, .semibold)).foregroundStyle(CardPalette.muted) }
            Spacer()
            Text("점유 \(m.me.possession)%").font(.pretendard(26)).foregroundStyle(CardPalette.muted)
            Text(m.me.rating > 0 ? String(format: "%.1f", m.me.rating) : "-").font(.scoreboard(40))
                .foregroundStyle(m.me.rating >= 7 ? CardPalette.gold : CardPalette.ink).frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 20).frame(height: 84)
        .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

// 주간
struct WeeklyCardView: View {
    let o: UserOverview
    let images: CardImages
    var body: some View {
        let w = o.week
        TemplateCard(chip: "주간 리포트", o: o, images: images, kicker: w.games >= o.summary.played && o.summary.played >= 30 ? "최근 7일 · 최근 \(w.games)경기 기준" : "최근 7일 · \(w.games)경기") {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                big(w.win, "승"); big(w.draw, "무"); big(w.lose, "패")
            }
        } sub: {
            if w.games == 0 {
                CardStampView(text: "이번 주 공식경기 없음", color: CardPalette.muted)
            } else if w.bestStreak >= 3 {
                CardStampView(text: "이번 주 \(w.bestStreak)연승", color: CardPalette.gold)
            } else if w.winRate >= 45 {
                CardStampView(text: "승률 \(w.winRate)%", color: CardPalette.lime)
            } else {
                CardStampView(text: "이번 주 \(w.games)경기 출전", color: CardPalette.lime)
            }
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                if let best = w.best, let m = o.matches.first(where: { $0.matchId == best.matchId }) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            CardLabel(text: "BEST MATCH")
                            Text("\(m.me.goals) : \(m.opponent?.goals ?? 0)").font(.scoreboard(72)).foregroundStyle(CardPalette.ink)
                            Text("vs \(m.opponent?.nickname ?? "상대")").font(.pretendard(28, .semibold)).foregroundStyle(CardPalette.muted).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("경기 스코어").font(.pretendard(22)).foregroundStyle(CardPalette.muted)
                            Text(String(format: "%.1f", best.score)).font(.scoreboard(96)).foregroundStyle(CardPalette.gold)
                        }
                    }
                    .padding(.horizontal, 28).frame(height: 200)
                    .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(CardPalette.gold.opacity(0.6), lineWidth: 2))
                }
                FormStrip(matches: o.matches, cell: 80, spacing: 11)
                statRow(cells(w))
            }
        }
    }
    /// 득실은 득점이 실점 이상일 때만 싣는다
    private func cells(_ w: WeeklyRecap) -> [(String, String, Color)] {
        var c: [(String, String, Color)] = [("최고 연승", "\(w.bestStreak)", CardPalette.lime), ("한 경기 최다 득점", "\(o.matches.map(\.me.goals).max() ?? 0)", CardPalette.ink)]
        if w.goalsFor >= w.goalsAgainst { c.append(("득실", "\(w.goalsFor):\(w.goalsAgainst)", CardPalette.ink)) }
        return c
    }
    private func big(_ n: Int, _ l: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.scoreboard(150)).foregroundStyle(CardPalette.ink)
            Text(l).font(.pretendard(56, .bold)).foregroundStyle(CardPalette.muted)
        }
    }
}

// 라이벌
struct RivalCardView: View {
    let o: UserOverview
    let r: Rival
    let images: CardImages
    var body: some View {
        let gap = r.win - r.lose
        let label: (String, Color) = gap <= -2 ? ("다음 판은 설욕전", CardPalette.muted) : gap >= 2 ? ("이 상대에겐 강해요", CardPalette.gold) : ("팽팽한 접전", CardPalette.lime)
        TemplateCard(chip: "라이벌 H2H", o: o, images: images, kicker: "맞대결 \(r.games)경기", cta: "우리 전적도 확인하기 →", showNickname: false) {
            VStack(spacing: 24) {
                HStack(spacing: 0) {
                    NicknameTitle(text: o.profile.nickname, maxSize: 64, minSize: 36, boxHeight: 80, width: 428, color: CardPalette.lime, alignment: .leading)
                    Text("VS").font(.scoreboard(40)).foregroundStyle(CardPalette.muted).frame(width: 96)
                    NicknameTitle(text: r.nickname, maxSize: 64, minSize: 36, boxHeight: 80, width: 428, color: CardPalette.ink, alignment: .trailing)
                }
                HStack(spacing: 24) {
                    Text("\(r.win)").font(.scoreboard(150)).foregroundStyle(CardPalette.lime)
                    Text(":").font(.scoreboard(120)).foregroundStyle(CardPalette.muted)
                    Text("\(r.lose)").font(.scoreboard(150)).foregroundStyle(CardPalette.ink)
                }
                .frame(maxWidth: .infinity)
            }
        } sub: {
            CardStampView(text: label.0, color: label.1).frame(maxWidth: .infinity)
        } content: {
            statRow([("무승부", "\(r.draw)", CardPalette.ink), ("득실", "\(r.goalsFor):\(r.goalsAgainst)", CardPalette.ink), ("맞대결", "\(r.games)", CardPalette.ink)])
        }
    }
}

// 대세픽
struct PickCardView: View {
    let o: UserOverview
    let picks: PicksInfo
    let shown: [PlayerCard]
    let images: CardImages
    var body: some View {
        let hit = picks.topPickCount > 0
        TemplateCard(chip: "대세픽 체크", o: o, images: images, kicker: hit ? "내 스쿼드 vs 포지션별 인기 TOP10" : "인기 픽과 다른 나만의 스쿼드") {
            if hit {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(picks.topPickCount)").font(.scoreboard(200)).foregroundStyle(CardPalette.lime)
                    Text("/ \(picks.total)명").font(.scoreboard(72)).foregroundStyle(CardPalette.muted)
                }
            } else {
                Text("나만의 스쿼드").font(.pretendard(110, .bold)).foregroundStyle(CardPalette.lime).lineLimit(1).minimumScaleFactor(0.6)
            }
        } sub: {
            Text(hit ? "포지션별 인기 TOP10에 든 내 카드" : "평점 상위 \(shown.count)명").font(.pretendard(32, .semibold)).foregroundStyle(CardPalette.muted)
        } content: {
            let cols = [GridItem(.fixed(296), spacing: 32), GridItem(.fixed(296), spacing: 32), GridItem(.fixed(296))]
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 20) {
                    ForEach(shown) { p in
                        PlayerTile(p: CardPlayer(spId: p.spId, name: p.name, season: p.season, position: p.positionLabel,
                                                 rating: p.avgRating, goals: p.goals, assists: p.assists, games: p.games),
                                   images: images, width: 296, height: 222)
                    }
                }
                HighlightChip(text: "너는 몇 명?")
            }
        }
    }
}
