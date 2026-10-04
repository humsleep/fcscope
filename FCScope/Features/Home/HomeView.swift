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
    /// 히어로 검색 필드 — 홈의 유일한 검색 입력. 내비 바 `.searchable`은 같은 일을 하는 두 번째 검색창이라
    /// 첫 화면의 40% 가 검색창 둘이었다(QA P1-1 · 디자인 M11 · 유저 패널 A). 최근 검색 제안은 이 필드 아래 드롭다운으로.
    @State private var heroQuery = ""
    @FocusState private var heroFocused: Bool
    /// 내 구단 "지난 방문 이후 새 경기" — 디스크 캐시에 남은 전적(백그라운드 갱신·이전 조회)으로만 계산한다. 홈에서 네트워크 0.
    @State private var sinceLastSeen: [MatchSummary]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                homeSections
            }
            .padding(16)
            // 히어로 드롭다운이 닫히는 애니메이션도 화면 밖(전적으로 이동 중)에서 멈추면 아래 섹션 위치가 어긋난 채 남는다 — 홈 전체를 즉시 배치
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
        .scrollDismissesKeyboard(.interactively)
        .fcScreen()
        .navigationTitle("전적").navigationBarTitleDisplayMode(.inline)
        .toolbar { brandToolbar }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        // 전적을 보고 돌아오면 본 경기 표시가 바뀌므로 나타날 때마다 다시 센다(디스크 읽기 1회).
        .onAppear { Task { await loadSinceLastSeen() } }
    }

    /// 히어로 아래 섹션들. 최근 검색·내 구단 스냅샷은 **다른 화면(전적)에서** 바뀐다 — 그 변경이 애니메이션 트랜잭션에
    /// 실려 오면 홈이 화면 밖일 때 시작한 삽입·이동 애니메이션이 멈춘 채 남아, 처음 돌아왔을 때 "최근 검색" 칩이
    /// "이런 것도 돼요" 위에 겹쳤다(QA 3R P2-2, 2R P2-3 과 같은 계열). 이 묶음의 레이아웃 변경은 애니메이션 없이 즉시.
    @ViewBuilder private var homeSections: some View {
        VStack(alignment: .leading, spacing: 14) {
                if let mine = prefs.myNickname { myFormCard(mine) }
                else if let demo = vm.state.value?.demoNickname { demoCard(demo) }
                if !prefs.favorites.isEmpty { favoritesSection }
                if let home = vm.state.value {
                    if let mover = home.mover { MoverCard(m: mover) }
                    if !home.liveSearches.isEmpty { liveChips(home.liveSearches) }
                } else if vm.state.isLoading { Skeleton(height: 60) }
                // 광고는 "첫 3초" 영역 밖 — 내 폼·급상승·검색 칩을 먼저 보여 준 뒤 한 장(화면당 1개 유지).
                // 예전엔 슬로건 바로 아래라 첫 화면 두 번째 블록이 광고였다(UX-AUDIT-GENZ #1).
                AdSlot()
                if let home = vm.state.value, !home.posts.isEmpty { latestPosts(home.posts) }
                if !prefs.recentSearches.isEmpty { recentSection }
                featureGrid
        }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    @ToolbarContentBuilder private var brandToolbar: some ToolbarContent {
            // 앱 안에서 아이콘 마크가 한 번도 안 나오던 문제 — 홈 내비에 S 마크 + 워드마크(디자인 M11)
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
        Task {
            let gated = SearchGate.shouldShowAd()
            Analytics.shared.track(.search, ["gated": gated])
            if gated { await AdsManager.shared.showInterstitialIfReady() }
            router.push(.user(nick))
        }
    }

    /// 검색 히어로(UX-AUDIT-GENZ #6) — 내비게이션 바의 회색 검색 필드는 눈에 안 띄었다. 첫 화면 주인공을 검색 하나로.
    /// 기능 나열 대신 유저의 질문을 카피로 쓴다. 포커스되면 최근 검색이 필드 바로 아래에 뜬다.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("FC온라인 비공식 데이터 랩", color: FC.tint)
            (Text("나 요즘 왜 지는지,\n") + Text("30경기").foregroundStyle(FC.brand) + Text("로 바로 진단"))
                .fcFont(26, weight: .bold).foregroundStyle(FC.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(FC.muted)  // AX5 에서 약 50pt 로 커져 입력칸을 밀어냈다(디자인 2R N-6) — 아이콘은 고정
                TextField("구단주명 입력", text: $heroQuery)
                    .fcFont(16).foregroundStyle(FC.ink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).focused($heroFocused)
                    .onSubmit { submitHero() }
                Button(action: submitHero) {
                    HStack(spacing: 4) { Text("진단"); Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)) }
                }
                .buttonStyle(BrandButtonStyle(compact: true))
                .disabled(heroQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 52)
            .background(FC.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(FC.brand, lineWidth: 1.5))
            if heroFocused, !heroSuggestions.isEmpty { suggestionList }
            else { Text("전적·슛맵·선수 성적표·플레이스타일 · 로그인 없이").fcText(.meta).foregroundStyle(FC.muted) }
        }
    }

    /// 최근 검색 중 입력과 맞는 것(최대 5개)
    private var heroSuggestions: [String] {
        let q = heroQuery.trimmingCharacters(in: .whitespaces)
        return Array(prefs.recentSearches.filter { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }.prefix(5))
    }

    /// 최근 검색 드롭다운 — 칩과 같은 "탐색"이라 검색 광고 카운트(SearchGate)를 태우지 않고 바로 이동한다.
    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(heroSuggestions.enumerated()), id: \.element) { i, n in
                if i > 0 { Rectangle().fill(FC.line).frame(height: 1).padding(.leading, 40) }
                Button {
                    heroFocused = false
                    heroQuery = ""
                    router.push(.user(n))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .medium)).foregroundStyle(FC.muted).frame(width: 18)
                        Text(n).fcText(.callout, weight: .medium).foregroundStyle(FC.ink).lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(FC.muted)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).stroke(FC.line, lineWidth: 1))
        .transition(.opacity)
    }

    private func submitHero() {
        heroFocused = false
        let q = heroQuery
        heroQuery = ""
        search(q)
    }

    /// 구단주명이 없는 첫 방문자용 — 서버가 내려주는 데모 계정으로 결과 화면을 먼저 보여준다.
    /// (웹의 "예시 리포트" 버튼과 동일 목적. Vercel `NEXT_PUBLIC_DEMO_NICKNAME` 미설정 시 자동 숨김)
    private func demoCard(_ nick: String) -> some View {
        Button { router.push(.user(nick)) } label: {
            Panel(highlight: FC.tint.opacity(0.4)) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("일단 구경부터 👀", color: FC.tint)
                        Text("예시 리포트 먼저 보기").fcFont(17, weight: .bold).foregroundStyle(FC.ink)
                        Text("구단주 \(nick)의 실제 전적·슛맵·진단이에요. 로그인 없이 바로 봐요.").fcFont(13).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func myFormCard(_ nick: String) -> some View {
        Button { router.push(.user(nick)) } label: {
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
                            .transition(.identity)
                        } else {
                            Text("탭해서 최근 폼 확인").fcFont(13).foregroundStyle(FC.muted).transition(.identity)
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
                    Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
                }
            }
        }
        .buttonStyle(.plain)
        // 스냅샷은 전적 화면(다른 탭·푸시된 화면)에서 저장된다. 그 변경이 애니메이션 트랜잭션에 실려 오면
        // 홈이 화면 밖일 때 시작한 opacity 전환이 끝나지 않고 남아, "탭해서 / 최근 폼 / 확인" 잔상이
        // 아래 "커뮤니티 최신" 위에 겹쳐 보였다(QA 2R P2-3). 이 카드의 내용 교체는 애니메이션 없이 즉시.
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
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


    private func liveChips(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("지금 검색되는 구단주")
            // 3~4줄로 접히던 칩 묶음을 한 줄 가로 스크롤로(디자인 N8 · UX-AUDIT #6 미완료분)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(names, id: \.self) { n in
                        Button { router.push(.user(n)) } label: { Chip(text: n, color: FC.ink, size: .large).tapTarget() }.buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
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
                    .padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: Radius.control))
                }.buttonStyle(.plain)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("최근 검색")
            FlowLayout(spacing: 6, lineSpacing: 0) {
                ForEach(prefs.recentSearches, id: \.self) { n in
                    Button { router.push(.user(n)) } label: { Chip(text: n, color: FC.ink, size: .large).tapTarget() }.buttonStyle(.plain)
                        .contextMenu { Button("삭제", role: .destructive) { prefs.recentSearches.removeAll { $0 == n } } }
                }
            }
        }
    }

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("이런 것도 돼요")
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
        else { heroFocused = true }
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
    /// check 가 어떤 입력에 대한 결과인가 — 입력이 바뀐 뒤 옛 결과를 저장하면 남의 구단이 "내 구단"이 됐다(E2E 2026-09-20)
    @State private var checkedFor = ""
    @FocusState private var nickFocused: Bool

    /// 구단주명 확인 상태. 네트워크 실패는 막지 않는다(확인 못 한 채로 저장 → 전적 화면이 최종 판정).
    enum NickCheck: Equatable { case idle, checking, ok(String), notFound, unknown }

    /// NFC 로 합친다 — 입력 경로에 따라 한글이 자모 분리(NFD)로 들어오면 화면엔 "보엠"인데 서버는 없는 구단주로 답했다.
    private var trimmed: String { nick.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping }

    var body: some View {
        VStack {
            TabView(selection: $page) {
                onboardPage(icon: "chart.xyaxis.line", title: "감이 아니라, 데이터로.", desc: "구단주명 하나로 최근 30경기 승률·슛맵·선수 성적표·플레이스타일을 진단해요. 로그인 없이 바로.").tag(0)
                VStack(spacing: 16) {
                    Image(systemName: "person.text.rectangle").fcFont(56).foregroundStyle(FC.tint)
                    Text("내 구단주명을 알려주세요").fcFont(22, weight: .bold).foregroundStyle(FC.ink)
                    // 다른 페이지와 같은 좌우 여백 — 없으면 이 페이지만 설명이 화면 끝까지 붙는다.
                    Text("홈에 내 폼 카드가 고정되고, 위젯·주간 성적표에 쓰여요. 나중에 바꿀 수 있어요.").fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
                    TextField("FC온라인 구단주명", text: $nick).textFieldStyle(.roundedBorder).padding(.horizontal, 32).autocorrectionDisabled()
                        .focused($nickFocused)
                        .textInputAutocapitalization(.never).submitLabel(.done)
                    checkLine.frame(minHeight: 20)
                }.tag(1)
                onboardPage(icon: "sportscourt", title: "마지막 경기부터 바로", desc: "방금 끝난 경기의 슛맵·POTM·선수 평점을 한눈에. 카드 한 장으로 공유도 돼요.").tag(2)
            }
            .tabViewStyle(.page)
            // 2쪽에서 키보드를 띄운 채 넘기면 3쪽에 키보드가 남았다(QA P2-5)
            .onChange(of: page) { _, p in if p != 1 { nickFocused = false } }
            // 기본 페이지 점은 흰색이라 라이트 모드 배경(거의 흰색)에서 보이지 않았다 — 반투명 배경 캡슐을 깐다.
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                nickFocused = false
                if page < 2 { withAnimation { page += 1 } } else { finish() }
            } label: { Text(primaryLabel) }
            .buttonStyle(BrandButtonStyle(fullWidth: true))
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
        // 입력이 바뀌면 옛 결과를 즉시 지운다(디바운스 동안 "✓ 확인됐어요 · 이전값"이 남아 있었다)
        check = .idle; checkedFor = n
        guard !n.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        check = .checking
        struct ProfileOnly: Decodable { let profile: UserProfile }
        let enc = n.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? n
        do {
            let r: ProfileOnly = try await APIClient.shared.get("/api/v1/user/\(enc)", query: ["stage": "profile"], auth: false)
            guard !Task.isCancelled, checkedFor == n else { return }
            check = .ok(r.profile.nickname)
        } catch {
            guard !Task.isCancelled, checkedFor == n else { return }
            check = (error as? APIError)?.isUserNotFound == true ? .notFound : .unknown
        }
    }

    private func onboardPage(icon: String, title: String, desc: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).fcFont(56).foregroundStyle(FC.tint)
            Text(title).fcFont(22, weight: .bold).foregroundStyle(FC.ink)
            Text(desc).fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
        }
    }

    /// 확인된 구단주명(넥슨 표기)으로 저장하고 바로 그 전적으로 보낸다 — 홈에 남겨 두면 "이제 뭘 하지"가 된다.
    /// 없는 구단주로 판정된 이름은 저장하지 않는다(홈 카드·위젯·주간 리캡이 빈 이름을 붙잡는다).
    private func finish() {
        // 결과가 지금 입력에 대한 것일 때만 믿는다. 넥슨 표기(대소문자 등)를 쓰되, 이름 자체가 다르면 입력값을 쓴다.
        let current = checkedFor == trimmed ? check : .idle
        let saved: String? = switch current {
        case .ok(let n) where n.caseInsensitiveCompare(trimmed) == .orderedSame: n
        case .notFound: nil
        default: trimmed.isEmpty ? nil : trimmed
        }
        if let saved { prefs.myNickname = saved }
        prefs.onboardingDone = true
        if let saved { router.tab = .home; router.homePath.append(Route.user(saved)) }
    }
}
