import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var state: Loadable<HomeResponse> = .idle
    /// 캐시 우선 렌더 후 백그라운드 갱신 — 앱 재실행 시 홈이 즉시 채워진다.
    func load() async {
        if case .loaded = state { return }
        if let hit: (value: HomeResponse, isFresh: Bool) = await APIClient.shared.cachedValue("/api/v1/home") {
            state = .loaded(hit.value)
            if hit.isFresh { return }
        } else { state = .loading }
        await refresh()
    }
    func refresh() async {
        do { state = .loaded(try await APIClient.shared.getAndCache("/api/v1/home", auth: false)) }
        catch { if state.value == nil { state = .failed(error) } }
    }
}

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @State private var vm = HomeViewModel()
    @State private var prefs = LocalPrefs.shared
    @State private var query = ""
    /// 검색창 활성 상태 — 제안 탭 후 닫고, "전적 · 분석 리포트" 카드에서 열 때 쓴다.
    @State private var searchPresented = false
    /// 내 구단 "지난 방문 이후 새 경기" — 디스크 캐시에 남은 전적(백그라운드 갱신·이전 조회)으로만 계산한다. 홈에서 네트워크 0.
    @State private var sinceLastSeen: [MatchSummary]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if let mine = prefs.myNickname { myFormCard(mine) }
                else if let demo = vm.state.value?.demoNickname { demoCard(demo) }
                if !prefs.favorites.isEmpty { favoritesSection }
                if let home = vm.state.value {
                    if let mover = home.mover { moverCard(mover) }
                    if !home.liveSearches.isEmpty { liveChips(home.liveSearches) }
                    if !home.posts.isEmpty { latestPosts(home.posts) }
                } else if vm.state.isLoading { Skeleton(height: 60) }
                if !prefs.recentSearches.isEmpty { recentSection }
                featureGrid
                // 맨 아래 — 칩·카드 사이에 두면 잘못 누르기 쉽다(AdMob 오클릭 정책)
                AdSlot().padding(.top, 8)
            }
            .padding(16)
        }
        .fcScreen()
        .navigationTitle("전적").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $searchPresented, prompt: "구단주명 검색")
        .onSubmit(of: .search) { search(query) }
        .searchSuggestions {
            // .searchCompletion 은 onSubmit(of: .search) 를 태워 직접 입력 검색으로 셌다(SearchGate 광고 카운트).
            // 최근 검색 제안은 칩과 같은 탐색이라 바로 이동한다.
            ForEach(prefs.recentSearches.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { n in
                Button {
                    query = ""
                    searchPresented = false
                    router.push(.user(n))
                } label: { Text(n) }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        // 전적을 보고 돌아오면 본 경기 표시가 바뀌므로 나타날 때마다 다시 센다(디스크 읽기 1회).
        .onAppear { Task { await loadSinceLastSeen() } }
    }

    private func loadSinceLastSeen() async {
        guard let mine = prefs.myNickname else { sinceLastSeen = nil; return }
        let path = "/api/v1/user/\(mine.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? mine)"
        guard let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path, query: ["type": "50"]) else { sinceLastSeen = nil; return }
        sinceLastSeen = prefs.matchesSinceLastSeen(nick: mine, in: hit.value.matches)
    }

    private func search(_ raw: String) {
        let nick = raw.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else { return }
        Haptic.light()
        query = ""
        Task {
            let gated = SearchGate.shouldShowAd()
            Analytics.shared.track(.search, ["gated": gated])
            if gated { await AdsManager.shared.showInterstitialIfReady() }
            router.push(.user(nick))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("FC온라인 비공식 데이터 랩", color: FC.accent)
            (Text("감이 아니라, ") + Text("데이터").foregroundStyle(FC.accent) + Text("로."))
                .fcFont(28, weight: .bold).foregroundStyle(FC.ink)
            Text("전적·슛맵·선수 성적표·플레이스타일을 구단주명 하나로.").fcFont(14).foregroundStyle(FC.muted)
        }
    }

    /// 구단주명이 없는 첫 방문자용 — 서버가 내려주는 데모 계정으로 결과 화면을 먼저 보여준다.
    /// (웹의 "예시 리포트" 버튼과 동일 목적. Vercel `NEXT_PUBLIC_DEMO_NICKNAME` 미설정 시 자동 숨김)
    private func demoCard(_ nick: String) -> some View {
        Button { router.push(.user(nick)) } label: {
            Panel(highlight: FC.gold.opacity(0.4)) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("처음이신가요?", color: FC.gold)
                        Text("예시 리포트 먼저 보기").fcFont(17, weight: .bold).foregroundStyle(FC.ink)
                        Text("실제 구단주 \(nick)의 전적·슛맵·진단을 그대로 볼 수 있어요.").fcFont(13).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(FC.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func myFormCard(_ nick: String) -> some View {
        Button { router.push(.user(nick)) } label: {
            Panel(highlight: FC.accent.opacity(0.5)) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("내 구단")
                        Text(nick).fcFont(18, weight: .bold).foregroundStyle(FC.ink)
                        if let s = prefs.snapshot(for: nick) {
                            HStack(spacing: 8) {
                                Text("승률 \(s.winRate)%").fcScoreboard(14).foregroundStyle(FC.accent)
                                if let p = s.prevWinRate, p != s.winRate {
                                    Text(s.winRate > p ? "▲\(s.winRate - p)%p" : "▼\(p - s.winRate)%p").fcScoreboard(12).foregroundStyle(s.winRate > p ? FC.win : FC.lose)
                                }
                                if s.streak >= 2 { Text("🔥\(s.streak)연승").fcFont(12, weight: .bold).foregroundStyle(FC.gold) }
                                if s.streak <= -2 { Text("🥶\(-s.streak)연패").fcFont(12, weight: .bold).foregroundStyle(FC.lose) }
                            }
                        } else {
                            Text("탭해서 최근 폼 확인").fcFont(13).foregroundStyle(FC.muted)
                        }
                        if let new = sinceLastSeen, !new.isEmpty {
                            // 30경기 창 안에서만 셀 수 있다 — 창을 넘으면 "30+"로 정직하게.
                            let count = new.count >= 30 ? "30+" : "\(new.count)"
                            let w = new.filter { $0.result == "승" }.count, d = new.filter { $0.result == "무" }.count, l = new.filter { $0.result == "패" }.count
                            // 무승부가 빠지면 "6개 · 3승 1패"처럼 합이 안 맞아 보인다 — 있을 때만 끼운다.
                            Text("지난 방문 이후 새 경기 \(count)개 · \(w)승\(d > 0 ? " \(d)무" : "") \(l)패").fcFont(12, weight: .semibold).foregroundStyle(FC.ink)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(FC.muted)
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
                        Button { router.push(.user(n)) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(n).fcFont(14, weight: .semibold).foregroundStyle(FC.ink).lineLimit(1)
                                if let s = prefs.snapshot(for: n) {
                                    HStack(spacing: 4) {
                                        Text("\(s.winRate)%").fcScoreboard(13).foregroundStyle(FC.accent)
                                        if let p = s.prevWinRate, p != s.winRate {
                                            Text(s.winRate > p ? "▲" : "▼").fcScoreboard(11).foregroundStyle(s.winRate > p ? FC.win : FC.lose)
                                        }
                                        if s.streak >= 2 { Text("🔥\(s.streak)").fcFont(11) }
                                    }
                                } else { Text("폼 미확인").fcFont(11).foregroundStyle(FC.muted) }
                            }
                            .padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
            }
        }
    }

    private func moverCard(_ m: Mover) -> some View {
        Button { router.push(.player(m.spId)) } label: {
            Panel(padding: 12, highlight: FC.win.opacity(0.4)) {
                HStack(spacing: 10) {
                    PlayerImage(spid: m.spId, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("⚡ 오늘의 급상승", color: FC.win)
                        Text(m.name).fcFont(15, weight: .bold).foregroundStyle(FC.ink)
                        Text("\(m.positionLabel) · \(m.lineTitle ?? m.line)").fcFont(12).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    Text(m.isNew ? "NEW" : "▲\(m.deltaValue ?? 0)").fcScoreboard(14).foregroundStyle(m.isNew ? FC.gold : FC.win)
                        .padding(.horizontal, 8).padding(.vertical, 5).background((m.isNew ? FC.gold : FC.win).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.buttonStyle(.plain)
    }

    private func liveChips(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("지금 검색되는 구단주")
            FlowLayout(spacing: 6) {
                ForEach(names, id: \.self) { n in
                    Button { router.push(.user(n)) } label: { Chip(text: n, color: FC.ink) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func latestPosts(_ posts: [HomePost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("커뮤니티 최신")
            ForEach(posts) { p in
                Button { router.push(.post(p.id)) } label: {
                    HStack {
                        Text(p.title).fcFont(14, weight: .medium).foregroundStyle(FC.ink).lineLimit(1)
                        Spacer()
                        if let c = p.commentCount, c > 0 { Text("💬\(c)").fcFont(12).foregroundStyle(FC.muted) }
                        Text(DateFmt.relative(p.createdAt)).fcFont(12).foregroundStyle(FC.muted)
                    }
                    .padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("최근 검색")
            FlowLayout(spacing: 6) {
                ForEach(prefs.recentSearches, id: \.self) { n in
                    Button { router.push(.user(n)) } label: { Chip(text: n, color: FC.ink) }.buttonStyle(.plain)
                        .contextMenu { Button("삭제", role: .destructive) { prefs.recentSearches.removeAll { $0 == n } } }
                }
            }
        }
    }

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("여기서 할 수 있는 것")
            feature("전적 · 분석 리포트", "슛맵부터 스쿼드 진단까지", "경기별 슛맵, 선수 성적표, 플레이스타일을 한 번에.") { openReportFeature() }
            feature("스쿼드 빌더", "스쿼드 만들고 공유", "포메이션에 선수 배치, 팀 프리셋, 최근 경기 선발 그대로 불러오기.") { router.tab = .squad }
            feature("픽 랭킹 · 선수 도감", "지금 가장 많이 쓰는 카드", "포지션별 인기 카드와 랭커 성적을 매일 갱신.") { router.tab = .meta }
            feature("커뮤니티 · 배틀", "자랑하고, 모으고, 겨룬다", "스쿼드 자랑과 평가, 클럽원 모집, 투표로 겨루는 스쿼드 배틀.") { router.tab = .community }
        }
    }
    /// 누르면 아무 일도 없던 카드 — 내 구단 → 예시(데모) 리포트 → 검색창 순으로 연다.
    private func openReportFeature() {
        if let mine = prefs.myNickname { router.push(.user(mine)) }
        else if let demo = vm.state.value?.demoNickname { router.push(.user(demo)) }
        else { searchPresented = true }
    }
    private func feature(_ tag: String, _ title: String, _ desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag).fcFont(12, weight: .bold).foregroundStyle(FC.gold)
                    Text(title).fcFont(16, weight: .bold).foregroundStyle(FC.ink)
                    Text(desc).fcFont(13).foregroundStyle(FC.muted)
                }
            }
        }.buttonStyle(.plain)
    }
}

/// 온보딩 3화면 — 로그인 강요 없음, 구단주명 입력은 건너뛰기 가능.
/// 시스템 권한 팝업은 여기서 띄우지 않는다 — 가치를 보기 전에 묻던 푸시 요청은 전적 화면의 소프트 카드로 옮겼다.
struct OnboardingView: View {
    @Environment(AppRouter.self) private var router
    @State private var prefs = LocalPrefs.shared
    @State private var page = 0
    @State private var nick = ""
    @State private var check: NickCheck = .idle

    /// 구단주명 확인 상태. 네트워크 실패는 막지 않는다(확인 못 한 채로 저장 → 전적 화면이 최종 판정).
    enum NickCheck: Equatable { case idle, checking, ok(String), notFound, unknown }

    /// NFC 로 합친다 — 입력 경로에 따라 한글이 자모 분리(NFD)로 들어오면 화면엔 "보엠"인데 서버는 없는 구단주로 답했다.
    private var trimmed: String { nick.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping }

    var body: some View {
        VStack {
            TabView(selection: $page) {
                onboardPage(icon: "chart.xyaxis.line", title: "감이 아니라, 데이터로.", desc: "구단주명 하나로 최근 30경기 승률·슛맵·선수 성적표·플레이스타일을 진단해요. 로그인 없이 바로.").tag(0)
                VStack(spacing: 16) {
                    Image(systemName: "person.text.rectangle").fcFont(56).foregroundStyle(FC.accent)
                    Text("내 구단주명을 알려주세요").fcFont(22, weight: .bold).foregroundStyle(FC.ink)
                    // 다른 페이지와 같은 좌우 여백 — 없으면 이 페이지만 설명이 화면 끝까지 붙는다.
                    Text("홈에 내 폼 카드가 고정되고, 위젯·주간 성적표에 쓰여요. 나중에 바꿀 수 있어요.").fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
                    TextField("FC온라인 구단주명", text: $nick).textFieldStyle(.roundedBorder).padding(.horizontal, 32).autocorrectionDisabled()
                        .textInputAutocapitalization(.never).submitLabel(.done)
                    checkLine.frame(minHeight: 20)
                }.tag(1)
                onboardPage(icon: "sportscourt", title: "마지막 경기부터 바로", desc: "방금 끝난 경기의 슛맵·POTM·선수 평점을 한눈에. 카드 한 장으로 공유도 돼요.").tag(2)
            }
            .tabViewStyle(.page)
            // 기본 페이지 점은 흰색이라 라이트 모드 배경(거의 흰색)에서 보이지 않았다 — 반투명 배경 캡슐을 깐다.
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if page < 2 { withAnimation { page += 1 } } else { finish() }
            } label: { Text(primaryLabel).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk)
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .background(FC.bg.ignoresSafeArea())
        // 입력이 멈춘 뒤 0.6초에 확인 — 글자마다 넥슨을 치지 않게(프로필 단계는 넥슨 2콜).
        .task(id: trimmed) { await validate(trimmed) }
    }

    private var primaryLabel: String {
        guard page == 1 else { return page < 2 ? "다음" : "시작하기" }
        if trimmed.isEmpty { return "나중에 입력할게요" }
        return check == .notFound ? "구단주명 없이 계속" : "다음"
    }

    @ViewBuilder private var checkLine: some View {
        switch check {
        case .idle: EmptyView()
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("확인 중…").fcFont(13).foregroundStyle(FC.muted) }
        case .ok(let n): Text("✓ 확인됐어요 · \(n)").fcFont(13, weight: .semibold).foregroundStyle(FC.win)
        case .notFound: Text("그런 구단주명을 찾지 못했어요").fcFont(13, weight: .semibold).foregroundStyle(FC.lose)
        case .unknown: Text("지금은 확인할 수 없어요 · 그대로 저장돼요").fcFont(13).foregroundStyle(FC.muted)
        }
    }

    private func validate(_ n: String) async {
        guard !n.isEmpty else { check = .idle; return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        check = .checking
        struct ProfileOnly: Decodable { let profile: UserProfile }
        let enc = n.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? n
        do {
            let r: ProfileOnly = try await APIClient.shared.get("/api/v1/user/\(enc)", query: ["stage": "profile"], auth: false)
            guard !Task.isCancelled else { return }
            check = .ok(r.profile.nickname)
        } catch {
            guard !Task.isCancelled else { return }
            check = (error as? APIError)?.isUserNotFound == true ? .notFound : .unknown
        }
    }

    private func onboardPage(icon: String, title: String, desc: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).fcFont(56).foregroundStyle(FC.accent)
            Text(title).fcFont(22, weight: .bold).foregroundStyle(FC.ink)
            Text(desc).fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
        }
    }

    /// 확인된 구단주명(넥슨 표기)으로 저장하고 바로 그 전적으로 보낸다 — 홈에 남겨 두면 "이제 뭘 하지"가 된다.
    /// 없는 구단주로 판정된 이름은 저장하지 않는다(홈 카드·위젯·주간 리캡이 빈 이름을 붙잡는다).
    private func finish() {
        let saved: String? = switch check {
        case .ok(let n): n
        case .notFound: nil
        default: trimmed.isEmpty ? nil : trimmed
        }
        if let saved { prefs.myNickname = saved }
        prefs.onboardingDone = true
        if let saved { router.tab = .home; router.homePath.append(Route.user(saved)) }
    }
}
