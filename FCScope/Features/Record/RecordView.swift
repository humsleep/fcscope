import SwiftUI

@Observable
@MainActor
final class RecordViewModel {
    let nickname: String
    var matchType = 50
    var overview: Loadable<UserOverview> = .idle
    var report: Loadable<ReportResponse> = .idle
    var players: Loadable<PlayersResponse> = .idle
    var playstyle: Loadable<PlaystyleResponse> = .idle
    var section: Section = .matches
    enum Section: String, CaseIterable, Identifiable { case matches = "경기 기록", report = "종합 리포트", players = "선수 성적표", style = "플레이스타일"; var id: String { rawValue } }

    /// 콜드 조회 선행 프로필 — 경기 30건을 기다리는 동안 히어로를 먼저 그린다.
    var quickProfile: UserProfile?
    var loadedFromCache = false

    init(nickname: String) { self.nickname = nickname }
    private var enc: String { nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nickname }
    private var path: String { "/api/v1/user/\(enc)" }
    private var query: [String: String] { ["type": String(matchType)] }

    /**
     최적화 2종.

     1) **stale-while-revalidate** — 디스크에 남은 마지막 응답을 즉시 그린다.
        같은 구단주 재방문 시 서버가 넥슨 36콜 + match_cache 30행 쓰기를 반복하지 않는다.
     2) **2단계 조회** — 진짜 콜드일 때만 프로필(넥슨 2콜)을 선행 조회해 히어로를 먼저 띄운다.
        최대 60초 걸리는 경기 30건을 기다리며 빈 화면을 보는 문제를 없앤다.
     */
    func load(force: Bool = false) async {
        if !force, let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path, query: query) {
            apply(hit.value)
            loadedFromCache = true
            if hit.isFresh { return } // 2분 이내 → 네트워크 생략
        } else if overview.value == nil {
            overview = .loading
            await loadQuickProfile()
        }
        do {
            apply(try await APIClient.shared.getAndCache(path, query: query, auth: false))
            loadedFromCache = false
        } catch {
            if overview.value == nil { overview = .failed(error) }
        }
    }

    /// 프로필·등급만 (경기 팬아웃 없음). 실패해도 본 조회에 영향 없음.
    private func loadQuickProfile() async {
        struct ProfileOnly: Decodable { let profile: UserProfile }
        if let r: ProfileOnly = try? await APIClient.shared.get(path, query: ["stage": "profile"], auth: false) {
            if overview.value == nil { quickProfile = r.profile }
        }
    }

    private func apply(_ o: UserOverview) {
        overview = .loaded(o)
        quickProfile = nil
        LocalPrefs.shared.addRecent(o.profile.nickname)
        LocalPrefs.shared.recordForm(nick: o.profile.nickname, winRate: o.summary.winRate, score: o.score, streak: o.perf.currentStreak, form: o.matches.prefix(5).map(\.result))
        Task { await AdsManager.shared.requestConsentIfNeeded() }
    }
    func changeType(_ t: Int) async {
        guard t != matchType else { return }
        matchType = t
        report = .idle; players = .idle; playstyle = .idle
        await load(force: true)
        await loadSection()
    }
    func loadSection() async {
        switch section {
        case .matches: break
        case .report:
            if report.value != nil { return }
            let p = "/api/v1/user/\(enc)/report"
            if let hit: (value: ReportResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: query) {
                report = .loaded(hit.value)
                if hit.isFresh { return }
            } else { report = .loading }
            do { report = .loaded(try await APIClient.shared.getAndCache(p, query: query, auth: false)) }
            catch { if report.value == nil { report = .failed(error) } }
        case .players:
            if players.value != nil { return }
            let p = "/api/v1/user/\(enc)/players"
            if let hit: (value: PlayersResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: query) {
                players = .loaded(hit.value)
                if hit.isFresh { return }
            } else { players = .loading }
            do { players = .loaded(try await APIClient.shared.getAndCache(p, query: query, auth: false)) }
            catch { if players.value == nil { players = .failed(error) } }
        case .style:
            if playstyle.value != nil { return }
            let p = "/api/v1/user/\(enc)/playstyle"
            if let hit: (value: PlaystyleResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: query) {
                playstyle = .loaded(hit.value)
                if hit.isFresh { return }
            } else { playstyle = .loading }
            do { playstyle = .loaded(try await APIClient.shared.getAndCache(p, query: query, auth: false)) }
            catch { if playstyle.value == nil { playstyle = .failed(error) } }
        }
    }
    func refresh() async {
        _ = try? await APIClient.shared.sendNoContent("/api/refresh/\(enc)", method: "POST")
        report = .idle; players = .idle; playstyle = .idle
        await load(force: true)
        await loadSection()
    }
}

struct RecordView: View {
    let nickname: String
    @State private var vm: RecordViewModel
    @State private var prefs = LocalPrefs.shared
    @Environment(AppRouter.self) private var router

    init(nickname: String) {
        self.nickname = nickname
        _vm = State(initialValue: RecordViewModel(nickname: nickname))
    }

    var body: some View {
        Group {
            switch vm.overview {
            case .idle, .loading:
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let p = vm.quickProfile {
                            // 2단계 조회: 프로필이 먼저 도착 → 히어로부터 표시
                            quickHero(p)
                            Text("최근 30경기를 불러오는 중이에요. 처음 조회하는 구단주는 조금 걸려요.")
                                .font(.system(size: 12)).foregroundStyle(FC.muted)
                        } else {
                            Skeleton(height: 120)
                        }
                        Skeleton(height: 90); Skeleton(height: 200)
                    }.padding(16)
                }
            case .failed(let err):
                errorView(err)
            case .loaded(let o):
                content(o)
            }
        }
        .fcScreen()
        .navigationTitle(vm.overview.value?.profile.nickname ?? nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Button { Haptic.light(); prefs.toggleFavorite(nickname) } label: {
                        Image(systemName: prefs.isFavorite(nickname) ? "star.fill" : "star").foregroundStyle(FC.gold)
                    }
                    if let o = vm.overview.value {
                        ShareLink(item: AppConfig.absolute("/user/\(o.profile.nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nickname)")) { Image(systemName: "link") }
                    }
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
    }

    /// 선행 프로필 히어로 (경기 데이터 도착 전)
    private func quickHero(_ p: UserProfile) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(p.nickname).font(.system(size: 26, weight: .bold)).foregroundStyle(FC.ink)
                    (Text("LV.").foregroundStyle(FC.muted) + Text("\(p.level)").foregroundStyle(FC.accent)).font(.scoreboard(14, weight: .semibold))
                }
                ForEach(p.divisions) { d in
                    HStack(spacing: 6) {
                        Text(d.matchTypeName).font(.system(size: 13)).foregroundStyle(FC.muted)
                        if let icon = d.iconUrl { RemoteImage(url: icon, size: 20) }
                        Text(d.divisionName).font(.system(size: 13, weight: .bold)).foregroundStyle(FC.gold)
                    }
                }
            }
        }
    }

    private func errorView(_ err: Error) -> some View {
        let api = err as? APIError
        return ErrorState(
            title: api?.isUserNotFound == true ? "‘\(nickname)’ 구단주를 찾을 수 없어요" : (api?.code == "maintenance" || api?.code == "paused" || api?.code == "not_configured") ? "잠시 조회를 쉬고 있어요" : "전적을 불러오지 못했어요",
            message: api?.isUserNotFound == true ? "닉네임 철자를 확인해 주세요. 닉네임을 방금 바꿨다면 반영까지 시간이 걸려요." : err.localizedDescription,
            retry: { Task { await vm.load(force: true) } }
        )
    }

    @ViewBuilder
    private func content(_ o: UserOverview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero(o)
                if let mt = o.diagnosis.type { badge("⚽", mt) { vm.section = .report; Task { await vm.loadSection() } } }
                typeTabs(o)
                sectionPicker
                switch vm.section {
                case .matches: MatchesSection(o: o, nickname: o.profile.nickname)
                case .report: ReportSection(state: vm.report)
                case .players: PlayersSection(state: vm.players, nickname: o.profile.nickname)
                case .style: PlaystyleSection(state: vm.playstyle)
                }
                HStack { Spacer(); ShareCardButton(spec: .user(o), label: "전적 카드 저장 · 공유"); Spacer() }.padding(.top, 8)
            }
            .padding(16)
        }
    }

    private func hero(_ o: UserOverview) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(o.profile.nickname).font(.system(size: 26, weight: .bold)).foregroundStyle(FC.ink)
                    (Text("LV.").foregroundStyle(FC.muted) + Text("\(o.profile.level)").foregroundStyle(FC.accent)).font(.scoreboard(14, weight: .semibold))
                    Spacer()
                    if prefs.myNickname?.caseInsensitiveCompare(o.profile.nickname) != .orderedSame {
                        Button("내 구단으로") { prefs.myNickname = o.profile.nickname; Haptic.success() }.font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.accent)
                    } else { Chip(text: "내 구단", color: FC.accentInk, bg: FC.accent) }
                }
                ForEach(o.profile.divisions) { d in
                    HStack(spacing: 6) {
                        Text(d.matchTypeName).font(.system(size: 13)).foregroundStyle(FC.muted)
                        if let icon = d.iconUrl { RemoteImage(url: icon, size: 20) }
                        Text(d.divisionName).font(.system(size: 13, weight: .bold)).foregroundStyle(FC.gold)
                        Text("(\(d.date))").font(.system(size: 12)).foregroundStyle(FC.muted)
                    }
                }
                if let rankSpec = ShareCardSpec.rank(o) { ShareCardButton(spec: rankSpec, label: "🏆 계급 인증 카드", compact: true) }
            }
        }
    }

    private func badge(_ emoji: String, _ r: Rule, action: @escaping () -> Void) -> some View {
        Button(action: action) { Panel(padding: 12) { RuleBadge(rule: r, prefix: "\(emoji) ") } }.buttonStyle(.plain)
    }

    private func typeTabs(_ o: UserOverview) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(o.matchTabs) { t in
                    Button { Task { await vm.changeType(t.type) } } label: {
                        Text(t.label).font(.scoreboard(13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(t.type == vm.matchType ? FC.accent : FC.surface2, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(t.type == vm.matchType ? FC.accentInk : FC.muted)
                    }
                }
            }
        }
    }

    private var sectionPicker: some View {
        Picker("섹션", selection: Binding(get: { vm.section }, set: { vm.section = $0; Task { await vm.loadSection() } })) {
            ForEach(RecordViewModel.Section.allCases) { s in Text(s.rawValue).tag(s) }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - 경기 기록

struct MatchesSection: View {
    let o: UserOverview
    let nickname: String
    @Environment(AppRouter.self) private var router
    private var enc: String { nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nickname }

    var body: some View {
        if o.matches.isEmpty {
            Panel { Text(o.listOk ? "최근 경기 기록이 없습니다." : "넥슨 조회가 일시적으로 원활하지 않아요. 잠시 후 당겨서 새로고침해 주세요.").font(.system(size: 14)).foregroundStyle(FC.muted).frame(maxWidth: .infinity) }
        } else {
            if o.loaded < o.requested {
                Text("⚠️ 최근 \(o.requested)경기 중 \(o.loaded)경기만 불러와 \(o.loaded)경기 기준으로 계산했어요.").font(.system(size: 13)).foregroundStyle(FC.muted)
                    .padding(10).background(FC.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            if o.week.games >= 3 { weekly(o.week) }
            if o.streak.highlight { streakBanner(o.streak) }
            if let n = o.nemesis { revenge(n) }
            scoreboard
            HStack(spacing: 8) {
                StatTile(label: "득점 / 실점", value: "\(o.summary.goalsFor) / \(o.summary.goalsAgainst)")
                StatTile(label: "경기당 득점", value: String(format: "%.1f", Double(o.summary.goalsFor) / Double(max(1, o.summary.played))))
                StatTile(label: "평균 점유율", value: "\(o.summary.avgPossession)%")
            }
            if o.diagnosis.type != nil || !o.diagnosis.notes.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("경기 성향 진단")
                        if let t = o.diagnosis.type { RuleBadge(rule: t) }
                        ForEach(o.diagnosis.notes) { RuleBadge(rule: $0) }
                    }
                }
            }
            if !o.rivals.isEmpty { rivals(o.rivals) }
            LazyVStack(spacing: 6) {
                ForEach(o.matches) { m in
                    Button { router.push(.match(id: m.matchId, me: o.profile.ouid)) } label: { MatchRow(m: m) }.buttonStyle(.plain)
                        .contextMenu {
                            Button { router.push(.match(id: m.matchId, me: o.profile.ouid)) } label: { Label("슛맵 · 매치 리포트", systemImage: "soccerball") }
                            if let opp = m.opponent { Button { router.push(.user(opp.nickname)) } label: { Label("\(opp.nickname) 전적 보기", systemImage: "person") } }
                        }
                }
            }
        }
    }

    private var scoreboard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FC Scope 스코어").font(.system(size: 12)).foregroundStyle(FC.muted)
                        (Text(String(format: "%.1f", o.score)) + Text("/10").font(.scoreboard(14)).foregroundStyle(FC.muted)).font(.scoreboard(34)).foregroundStyle(FC.tone(o.tier.tone))
                        Text(o.tier.label).font(.scoreboard(11)).foregroundStyle(FC.tone(o.tier.tone))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("최근 \(o.summary.played)경기 승률").font(.system(size: 12)).foregroundStyle(FC.muted)
                        Text("\(o.summary.winRate)%").font(.scoreboard(34)).foregroundStyle(FC.accent)
                        Text("\(o.summary.win)승 \(o.summary.draw)무 \(o.summary.lose)패").font(.scoreboard(11)).foregroundStyle(FC.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("최근 10경기 폼").font(.system(size: 12)).foregroundStyle(FC.muted)
                    HStack(spacing: 4) { ForEach(o.matches.prefix(10)) { ResultBadge(result: $0.result, size: 24) } }
                }
                RatingSparkline(values: o.matches.reversed().map { $0.me.rating })
                Text("FC Scope 스코어는 승패·득실차·인게임 평점·점유율을 종합한 퍼포먼스 점수(10점 만점)예요.").font(.system(size: 11)).foregroundStyle(FC.muted)
            }
        }
    }

    private func weekly(_ w: WeeklyRecap) -> some View {
        Panel(padding: 12, highlight: FC.accent.opacity(0.3)) {
            HStack(spacing: 10) {
                Text("📅").font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("이번 주 성적표 · 최근 7일 \(w.games)경기")
                    HStack(spacing: 6) {
                        Text("\(w.win)승 \(w.draw)무 \(w.lose)패").font(.system(size: 16, weight: .bold)).foregroundStyle(w.winRate >= 50 ? FC.win : FC.lose)
                        Text("승률 \(w.winRate)% · 평균 \(String(format: "%.1f", w.avgScore))").font(.system(size: 12)).foregroundStyle(FC.muted)
                        if w.bestStreak >= 2 { Text("🔥\(w.bestStreak)연승").font(.system(size: 12, weight: .bold)).foregroundStyle(FC.win) }
                    }
                }
                Spacer()
                ShareCardButton(spec: .weekly(o), label: "주간 카드", compact: true)
            }
        }
    }

    private func streakBanner(_ s: StreakInfo) -> some View {
        Panel(padding: 12, highlight: (s.color == "lose" ? FC.lose : FC.win).opacity(0.4)) {
            HStack(spacing: 10) {
                Text(s.color == "lose" ? "🥶" : "🔥").font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.text).font(.scoreboard(18)).foregroundStyle(FC.tone(s.color))
                    Text(s.color == "lose" ? "반등을 노려보자" : "이 기세 이어가자 — 폼 카드로 자랑하기").font(.system(size: 12)).foregroundStyle(FC.muted)
                }
                Spacer()
                ShareCardButton(spec: .streak(o), label: "폼 카드", compact: true)
            }
        }
    }

    private func revenge(_ r: Rival) -> some View {
        Button { router.push(.user(r.nickname)) } label: {
            Panel(padding: 12, highlight: FC.lose.opacity(0.4)) {
                HStack(spacing: 10) {
                    Text("🎯").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("천적 복수전", color: FC.lose)
                        Text("\(r.nickname) 에게 \(r.win)승 \(r.lose)패 — 아직 \(r.lose - r.win)점 뒤").font(.system(size: 14, weight: .bold)).foregroundStyle(FC.ink)
                    }
                    Spacer()
                    ShareCardButton(spec: .rival(o, rival: r), label: "저격 카드", compact: true)
                }
            }
        }.buttonStyle(.plain)
    }

    private func rivals(_ rs: [Rival]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("자주 만난 상대 H2H")
                ForEach(rs) { r in
                    Button { router.push(.user(r.nickname)) } label: {
                        HStack {
                            Text(r.nickname).font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.ink).lineLimit(1)
                            Spacer()
                            Text("\(r.win)승 \(r.draw)무 \(r.lose)패").font(.scoreboard(13)).foregroundStyle(r.win > r.lose ? FC.win : r.win < r.lose ? FC.lose : FC.muted)
                            Text("\(r.games)경기").font(.system(size: 12)).foregroundStyle(FC.muted)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct RatingSparkline: View {
    let values: [Double]
    var body: some View {
        let vs = values.filter { $0 > 0 }
        if vs.count >= 3 {
            let lo = (vs.min() ?? 5) - 0.2, hi = (vs.max() ?? 8) + 0.2
            GeometryReader { geo in
                Path { p in
                    for (i, v) in vs.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(max(1, vs.count - 1))
                        let y = geo.size.height * (1 - CGFloat((v - lo) / max(0.1, hi - lo)))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(FC.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .frame(height: 36)
        }
    }
}
