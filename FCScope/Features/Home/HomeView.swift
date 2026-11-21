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
    /// 내 최근 30경기 상대(소문자) — "상대 저격" 검색은 전면광고에서 뺀다.
    @State private var myOpponents: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                // 쿠팡 파트너스 — 입력창 바로 아래. 입력을 시작하면(최근 검색 드롭다운·키보드) 접어 검색을 가리지 않는다.
                // 계층에서 빼면 웹뷰가 새로 만들어져 쿠팡·분석 노출이 포커스마다 다시 잡힌다 — 붙여 둔 채 높이만 접는다.
                if AdsManager.shared.canShowPartnerBanner {
                    let show = !heroFocused && heroQuery.isEmpty
                    CoupangBanner(placement: "search")
                        .frame(height: show ? nil : 0, alignment: .top).clipped().opacity(show ? 1 : 0)
                        .allowsHitTesting(show).accessibilityHidden(!show)
                }
                homeSections
            }
            .padding(16)
            // 히어로 드롭다운이 닫히는 애니메이션도 화면 밖(전적으로 이동 중)에서 멈추면 아래 섹션 위치가 어긋난 채 남는다 — 홈 전체를 즉시 배치
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
        .scrollDismissesKeyboard(.interactively)
        .fcScreen()
        .fcTabHeader("전적")
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        .onAppear { Task { await loadOpponents() } }
        .onChange(of: prefs.myNickname) { _, _ in Task { await loadOpponents() } }
    }

    /// 히어로 아래 섹션들. 최근 검색·내 구단 스냅샷은 **다른 화면(전적)에서** 바뀐다 — 그 변경이 애니메이션 트랜잭션에
    /// 실려 오면 홈이 화면 밖일 때 시작한 삽입·이동 애니메이션이 멈춘 채 남아, 처음 돌아왔을 때 "최근 검색" 칩이
    /// "이런 것도 돼요" 위에 겹쳤다(QA 3R P2-2, 2R P2-3 과 같은 계열). 이 묶음의 레이아웃 변경은 애니메이션 없이 즉시.
    @ViewBuilder private var homeSections: some View {
        VStack(alignment: .leading, spacing: 14) {
                // 내 폼·즐겨찾기·급상승·배너는 홈("오늘의 피온", TodayView)으로 옮겼다(2026-11 탭 재편). 이 탭은 검색 전용.
                if prefs.myNickname == nil, let demo = vm.state.value?.demoNickname { demoCard(demo) }
                if !prefs.recentSearches.isEmpty { recentSection }
                if let home = vm.state.value {
                    if !home.liveSearches.isEmpty { liveChips(home.liveSearches) }
                } else if vm.state.isLoading { Skeleton(height: 60) }
        }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private func loadOpponents() async {
        guard let mine = prefs.myNickname else { myOpponents = []; return }
        let path = "/api/v1/user/\(mine.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? mine)"
        guard let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path, query: ["type": "50"]) else { return }
        myOpponents = Set(hit.value.matches.compactMap { $0.opponent?.nickname.lowercased() })
    }

    private func search(_ raw: String) {
        let nick = raw.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else { return }
        Haptic.light()
        Task {
            // 내 구단주·즐겨찾기·내 최근 상대는 "찾아보기"가 아니라 늘 보는 대상 — 광고를 띄우지 않고 무료 횟수도 쓰지 않는다.
            let exempt = prefs.myNickname?.caseInsensitiveCompare(nick) == .orderedSame
                || prefs.isFavorite(nick) || myOpponents.contains(nick.lowercased())
            let gated = SearchGate.shouldShowAd(exempt: exempt)
            Analytics.shared.track(.search, ["gated": gated, "exempt": exempt])
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
                        SectionLabel("일단 구경부터", color: FC.tint)
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
            // 로고 워드마크 — 시스템 아이콘만 있어 템플릿 같았다(UX 패널 2026-11 R1·R3)
            HStack(spacing: 8) {
                SpotGlyph(height: 26)
                (Text("FC ").foregroundStyle(FC.brandSolid) + Text("SCOPE").foregroundStyle(FC.ink)).font(.scoreboard(20)).tracking(1)
            }
            .padding(.top, 24)
            .accessibilityElement().accessibilityLabel("FC SCOPE")
            // 페이지 TabView(.page)는 실행 직후 "다음"을 누르면 점·버튼은 2쪽인데 내용은 1쪽에 남는 일이 있었다
            // (UX 패널 2026-11 R2 캡처) — 구단주명 칸을 못 보고 지나간다. 직접 전환해 어긋날 수 없게 한다. 좌우 스와이프도 받는다.
            ZStack {
                switch page {
                case 0:
                    // 1·2쪽도 3쪽처럼 실제 화면 모양 미리보기 — 시스템 아이콘이 템플릿 같았다(UX 패널 R6)
                    VStack(spacing: 16) {
                        OnboardingRecordPreview()
                        Text("감이 아니라, 데이터로.").fcFont(22, weight: .bold).foregroundStyle(FC.ink)
                        Text("구단주명 하나로 최근 30경기 승률·슛맵·선수 성적표·플레이스타일을 진단해요. 로그인 없이 바로.").fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case 1:
                    VStack(spacing: 16) {
                        OnboardingHomePreview()
                        Text("내 구단주명을 알려주세요").fcFont(22, weight: .bold).foregroundStyle(FC.ink)
                        // 다른 페이지와 같은 좌우 여백 — 없으면 이 페이지만 설명이 화면 끝까지 붙는다.
                        Text("홈에 내 폼 카드가 고정되고, 위젯·주간 성적표에 쓰여요. 나중에 바꿀 수 있어요.").fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
                        TextField("FC온라인 구단주명", text: $nick).textFieldStyle(.roundedBorder).padding(.horizontal, 32).autocorrectionDisabled()
                            .focused($nickFocused)
                            .textInputAutocapitalization(.never).submitLabel(.done)
                        checkLine.frame(minHeight: 20)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                default:
                    // 아이콘 대신 실제 경기 카드 모양 미리보기 — 시스템 아이콘만 있어 무엇을 얻는지 안 보였다(UX 패널 R5)
                    VStack(spacing: 16) {
                        OnboardingMatchPreview()
                        Text("마지막 경기부터 바로").fcFont(22, weight: .bold).foregroundStyle(FC.ink)
                        Text("방금 끝난 경기의 슛맵·최우수 선수·선수 평점을 한눈에. 카드 한 장으로 공유도 돼요.").fcFont(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                }
            }
            .padding(.bottom, 90)  // 화면 정중앙보다 조금 위(시선이 먼저 닿는 곳)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -50, page < 2 { withAnimation { page += 1 } }
                else if v.translation.width > 50, page > 0 { withAnimation { page -= 1 } }
            })
            .onChange(of: page) { _, p in if p != 1 { nickFocused = false } }
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i == page ? FC.brandSolid : FC.line).frame(width: i == page ? 20 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 16)
            .accessibilityElement().accessibilityLabel("\(page + 1) / 3쪽")
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


/// 온보딩 1쪽 미리보기 — 전적 헤더 모양(예시 데이터): 3칸 타일 + 최근 10경기 폼.
private struct OnboardingRecordPreview: View {
    private let form = Array("승승패승무승패승승패")
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                tile("승률", "56%", FC.ink)
                tile("경기력", "6.8", FC.win)
                tile("경기당 득점", "2.1", FC.ink)
            }
            HStack(spacing: 4) {
                ForEach(form.indices, id: \.self) { i in
                    let c: Color = form[i] == "승" ? FC.win : form[i] == "패" ? FC.lose : FC.muted
                    Text(String(form[i])).fcFont(11, weight: .bold).foregroundStyle(c)
                        .frame(maxWidth: .infinity, minHeight: 22).background(c.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .modifier(OnboardingPreviewCard())
        .accessibilityElement().accessibilityLabel("예시 전적: 승률 56%, 경기력 6.8, 최근 10경기 폼")
    }
    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).fcScoreboard(20).foregroundStyle(color)
            Text(label).fcFont(10.5).foregroundStyle(FC.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(FC.surface2, in: RoundedRectangle(cornerRadius: Radius.chip))
    }
}

/// 온보딩 2쪽 미리보기 — 구단주명을 넣으면 홈에 고정되는 "내 구단" 카드(예시 데이터).
private struct OnboardingHomePreview: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("내 구단")
                Text("내 구단주명").fcFont(17, weight: .bold).foregroundStyle(FC.ink)
                HStack(spacing: 8) {
                    Text("승률 56%").fcScoreboard(14).foregroundStyle(FC.ink)
                    Text("▲3%p").fcScoreboard(12).foregroundStyle(FC.win)
                    Text("3연승").fcFont(12, weight: .bold).foregroundStyle(FC.gold)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
        }
        .modifier(OnboardingPreviewCard())
        .accessibilityElement().accessibilityLabel("예시 홈 카드: 내 구단 승률 56%, 3연승")
    }
}

/// 온보딩 미리보기 카드 공통 겉모양(3쪽 경기 카드와 같은 폭·테두리)
private struct OnboardingPreviewCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(width: 260)
            .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(FC.line))
    }
}

/// 온보딩 3쪽 미리보기 — 실제 마지막 경기 카드와 같은 모양(예시 데이터, 화면 낭독에는 "예시"로 읽힌다).
private struct OnboardingMatchPreview: View {
    /// 예시 슛 위치(0~1, 왼쪽 골대를 공격) — (x, y, 골인가)
    private let mine: [(CGFloat, CGFloat, Bool)] = [(0.06, 0.45, true), (0.09, 0.55, true), (0.12, 0.38, false), (0.16, 0.6, false), (0.08, 0.5, true)]
    private let theirs: [(CGFloat, CGFloat, Bool)] = [(0.9, 0.42, true), (0.86, 0.6, false), (0.93, 0.55, true)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("승").fcFont(15, weight: .bold).foregroundStyle(FC.win)
                    .frame(width: 32, height: 32).background(FC.win.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Text("5 : 3").fcScoreboard(22).foregroundStyle(FC.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("7.6").fcScoreboard(17).foregroundStyle(FC.win)
                    Text("경기력").fcFont(11).foregroundStyle(FC.muted)
                }
            }
            Canvas { ctx, size in
                ShotMapView.drawPitch(ctx, size, ground: FC.turf, line: .white, lineWidth: 1.5, stripe: FC.turfStripe)
                for (shots, tone) in [(theirs, FC.muted), (mine, FC.tint)] {
                    for (x, y, goal) in shots {
                        let r: CGFloat = goal ? 5 : 4
                        let rect = CGRect(x: x * size.width - r, y: y * size.height - r, width: 2 * r, height: 2 * r)
                        if goal { ctx.fill(Path(ellipseIn: rect), with: .color(tone)) }
                        ctx.stroke(Path(ellipseIn: rect), with: .color(tone), lineWidth: 1.5)
                    }
                }
            }
            .aspectRatio(ShotMapView.pitchRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.chip))
        }
        .modifier(OnboardingPreviewCard())
        .accessibilityElement().accessibilityLabel("예시 경기 카드: 5 대 3 승리, 경기력 7.6, 슛맵")
    }
}
