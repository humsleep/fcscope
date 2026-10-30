import SwiftUI

/// 홈 "오늘의 피온" — 매일 열 이유를 한 화면에(docs/STRATEGY-2026-11.md Phase 1).
/// 내 폼·지난 방문 이후 새 경기·이번 주 성적·즐겨찾기 폼은 디스크 캐시로만 그린다(네트워크 0).
/// 네트워크는 /api/v1/home(급상승·데모)과 커뮤니티 목록 1장(인기 글)뿐이다.
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @State private var vm = HomeViewModel()
    @State private var prefs = LocalPrefs.shared
    /// 내 구단 공식경기 캐시 — 지난 방문 이후 새 경기·이번 주 성적의 재료
    @State private var mine: UserOverview?
    @State private var hot: [Post] = []
    @State private var league: [LeagueEntry] = []
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let nick = prefs.myNickname { myFormCard(nick) } else { registerCard }
                if let w = mine?.week, w.games > 0, let nick = prefs.myNickname { weekCard(w, nick: nick) }
                if league.count >= 2 { leagueCard }
                if !prefs.favorites.isEmpty { favoritesSection }
                if let home = vm.state.value {
                    if let mover = home.mover { MoverCard(m: mover) }
                    AdSlot(placement: "home", reserve: true).padding(.top, 8)
                } else if vm.state.isLoading { Skeleton(height: 60) }
                let visibleHot = hot.filter { !prefs.isBlocked($0.authorId) }
                if !visibleHot.isEmpty {
                    HotBox(posts: Array(visibleHot.prefix(3)), open: { p in
                        CommunityPrefs.shared.markRead(p.id)
                        router.push(.post(p.id))
                    }, more: { router.tab = .community })
                }
            }
            .padding(16)
            // 스냅샷·캐시는 다른 화면(전적)에서 바뀐다 — 화면 밖에서 시작한 전환 애니메이션이 멈춘 채 남지 않게(QA 2R P2-3)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
        .fcScreen()
        .navigationTitle("홈").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    SpotGlyph(height: 22)
                    (Text("FC ").foregroundStyle(FC.brand) + Text("SCOPE").foregroundStyle(FC.ink))
                        .font(.scoreboard(17)).tracking(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("FC Scope")
                .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.me) } label: { Image(systemName: "person.crop.circle") }
                    .accessibilityLabel("내 정보")
            }
        }
        .task { await vm.load() }
        .task { await loadHot() }
        .refreshable { await vm.refresh(); await loadHot(); await loadMine() }
        // 전적을 보고 돌아오면 본 경기 표시가 바뀌므로 나타날 때마다 다시 읽는다(디스크 읽기 1회).
        .onAppear { Task { await loadMine() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("오늘의 피온", color: FC.tint)
            Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR"))))
                .fcFont(22, weight: .bold).foregroundStyle(FC.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadMine() async {
        league = await FriendLeague.cachedRows()
        guard let nick = prefs.myNickname else { mine = nil; return }
        let path = "/api/v1/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"
        let hit: (value: UserOverview, isFresh: Bool)? = await APIClient.shared.cachedValue(path, query: ["type": "50"])
        mine = hit?.value
    }

    /// 인기 글은 전체 탭 1쪽 응답의 hot 에 실려 온다(구 서버는 nil → 섹션을 숨긴다). 실패해도 홈은 그대로.
    private func loadHot() async {
        hot = (try? await CommunityAPI.list(["page": "1"]))?.hot ?? []
    }

    /// 구단주명이 없으면 홈의 절반이 비어 보인다 — 내 구단은 전적 화면의 "내 구단으로"로 정하므로 전적 탭으로 보낸다.
    private var registerCard: some View {
        Button { router.tab = .home } label: {
            Panel(highlight: FC.tint.opacity(0.4)) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("내 구단 고정", color: FC.tint)
                        Text("구단주명을 등록해 보세요").fcFont(17, weight: .bold).foregroundStyle(FC.ink)
                        Text("내 전적을 검색하고 '내 구단으로'를 누르면 매일 여기서 폼·새 경기·이번 주 성적을 봐요.").fcFont(13).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func myFormCard(_ nick: String) -> some View {
        Button { router.openUser(nick) } label: {
            Panel(highlight: FC.tint.opacity(0.5)) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("내 구단")
                        Text(nick).fcFont(18, weight: .bold).foregroundStyle(FC.ink)
                        if let s = prefs.snapshot(for: nick) {
                            HStack(spacing: 8) {
                                Text("승률 \(s.winRate)%").fcScoreboard(14).foregroundStyle(FC.ink)
                                if let p = s.prevWinRate, p != s.winRate {
                                    Text(s.winRate > p ? "▲\(s.winRate - p)%p" : "▼\(p - s.winRate)%p").fcScoreboard(12).foregroundStyle(s.winRate > p ? FC.win : FC.lose)
                                }
                                if s.streak >= 2 { Text("🔥\(s.streak)연승").fcFont(12, weight: .bold).foregroundStyle(FC.gold) }
                                if s.streak <= -2 { Text("🥶\(-s.streak)연패").fcFont(12, weight: .bold).foregroundStyle(FC.lose) }
                            }
                        } else {
                            Text("탭해서 최근 폼 확인").fcFont(13).foregroundStyle(FC.muted)
                        }
                        if let o = mine, let new = prefs.matchesSinceLastSeen(nick: nick, in: o.matches), !new.isEmpty {
                            // 30경기 창 안에서만 셀 수 있다 — 창을 넘으면 "30+"로 정직하게.
                            let count = new.count >= 30 ? "30+" : "\(new.count)"
                            let w = new.filter { $0.result == "승" }.count, d = new.filter { $0.result == "무" }.count, l = new.filter { $0.result == "패" }.count
                            // 무승부가 빠지면 "6개 · 3승 1패"처럼 합이 안 맞아 보인다 — 있을 때만 끼운다.
                            Text("지난 방문 이후 새 경기 \(count)개 · \(w)승\(d > 0 ? " \(d)무" : "") \(l)패").fcFont(12, weight: .semibold).foregroundStyle(FC.ink)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 이번 주 성적 — 주간 카드는 전적 화면에서 만든다(여기선 바로가기만).
    private func weekCard(_ w: WeeklyRecap, nick: String) -> some View {
        Button { router.openUser(nick) } label: {
            Panel(padding: 12) {
                HStack(spacing: 10) {
                    Text("📅").fcFont(22)
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel("이번 주 · \(w.label)")
                        // 한 줄에 몰면 큰 글씨에서 "승률 4…"로 잘렸다 — 기록과 승률을 각자 한 줄로(RecordView 주간 카드와 같은 처리)
                        Text("\(w.win)승 \(w.draw)무 \(w.lose)패")
                            .fcFont(15, weight: .bold).foregroundStyle(w.winRate >= 50 ? FC.win : FC.lose)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("승률 \(w.winRate)%").fcFont(12).foregroundStyle(FC.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize { Text("주간 카드").fcFont(12, weight: .semibold).foregroundStyle(FC.tint) }
                    Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 친구 리그 요약 — 내 순위 + 상위 3명. 캐시만으로 그린다.
    private var leagueCard: some View {
        Button { router.push(.league) } label: {
            Panel(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel("🏆 친구 리그 · 최근 7일")
                        Spacer()
                        let ranked = league.filter(\.qualified)
                        if let i = ranked.firstIndex(where: \.isMe) {
                            Text("내 순위 \(i + 1)위 / \(ranked.count)명").fcFont(12, weight: .bold).foregroundStyle(FC.tint)
                        }
                        Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
                    }
                    let top = league.filter(\.qualified).prefix(3)
                    if top.isEmpty {
                        Text("아직 3경기 이상 뛴 친구가 없어요. 눌러서 최신 기록을 받아 보세요.").fcFont(12).foregroundStyle(FC.muted)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(Array(top.enumerated()), id: \.element.id) { i, r in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(["🥇", "🥈", "🥉"][i]) \(r.nick)").fcFont(13, weight: .semibold).foregroundStyle(r.isMe ? FC.tint : FC.ink).lineLimit(1)
                                    Text("\(r.winRate)%").fcScoreboard(13).foregroundStyle(FC.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("⭐ 즐겨찾기 구단주")
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(prefs.favorites, id: \.self) { n in
                    Button { router.openUser(n) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(n).fcFont(14, weight: .semibold).foregroundStyle(FC.ink).lineLimit(1)
                            if let s = prefs.snapshot(for: n) {
                                HStack(spacing: 4) {
                                    Text("\(s.winRate)%").fcScoreboard(13).foregroundStyle(FC.ink)
                                    if let p = s.prevWinRate, p != s.winRate {
                                        Text(s.winRate > p ? "▲" : "▼").fcScoreboard(11).foregroundStyle(s.winRate > p ? FC.win : FC.lose)
                                    }
                                    if s.streak >= 2 { Text("🔥\(s.streak)").fcFont(11) }
                                }
                            } else { Text("폼 미확인").fcFont(11).foregroundStyle(FC.muted) }
                        }
                        .padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: Radius.control))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
