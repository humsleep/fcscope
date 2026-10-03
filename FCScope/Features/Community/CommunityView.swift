import SwiftUI

/// 1차 탭 — 7개 유형 칩 더미 대신 그룹 4개(SPEC 4절)
enum CommunityTab: String, CaseIterable, Identifiable {
    case all, hot, squad, club
    var id: String { rawValue }
    var label: String {
        switch self { case .all: return "전체"; case .hot: return "인기"; case .squad: return "스쿼드"; case .club: return "클럽·대회" }
    }
    /// 그룹 안 2차 칩(유형) — 순서는 목업 기준
    var types: [String] {
        switch self {
        case .squad: return ["squad_show", "squad_rate", "squad_make", "squad_battle"]
        case .club: return ["club_recruit", "club_match", "tournament"]
        default: return []
        }
    }
}

@Observable
@MainActor
final class CommunityModel {
    var state: Loadable<PostListResponse> = .idle
    var types: [PostTypeInfo] = []
    var tab: CommunityTab = .all
    /// 그룹 탭의 2차 칩(유형). nil = 그룹 전체
    var chip: String?
    /// "new" | "comments"
    var sort = "new"

    /// 지금까지 이어붙인 글. 아래로 스크롤하면 다음 장을 붙인다(iOS 표준).
    var posts: [Post] = []
    var hot: [Post] = []
    private(set) var page = 1
    private(set) var totalPages = 1
    private(set) var loadingMore = false
    /// 다음 장 실패 — 목록 끝에 "불러오지 못했어요 · 다시 시도" 한 줄
    var moreFailed = false
    var hasMore: Bool { page < totalPages }
    private let prefs = CommunityPrefs.shared
    /// 늦게 도착한 이전 탭 응답이 현재 목록을 덮지 않게
    private var generation = 0

    /// 서버가 sort·types 를 지원하는가(응답 `sort` 키). 모르면 그룹 "전체" 칩을 숨기고 첫 유형으로 동작한다
    /// (SPEC 14-2: types 쿼리 전엔 클라이언트에서 병합하지 않는다).
    var groupFilter: Bool { prefs.groupFilterSupported }

    func load(reset: Bool = false) async {
        if reset { page = 1; moreFailed = false }
        if state.value == nil || reset { state = .loading }
        await fetch(page: 1, append: false)
    }

    func loadMore() async {
        guard !loadingMore, hasMore, state.value != nil, !moreFailed else { return }
        loadingMore = true
        await fetch(page: page + 1, append: true)
        loadingMore = false
    }

    func retryMore() async {
        moreFailed = false
        await loadMore()
    }

    /// 탭 상태만 바꾼다(애니메이션 트랜잭션 안에서 호출). 바뀌었으면 true — 호출부가 load 한다.
    func switchTab(_ t: CommunityTab) -> Bool {
        guard t != tab else { return false }
        tab = t
        chip = (t.types.isEmpty || groupFilter) ? nil : t.types.first
        posts = []; hot = []
        return true
    }

    func switchChip(_ c: String?) -> Bool {
        guard c != chip else { return false }
        chip = c
        posts = []
        return true
    }

    private func query(page target: Int) -> [String: String] {
        var q = ["page": String(target)]
        switch tab {
        case .all: if sort != "new" { q["sort"] = sort }
        case .hot: q["sort"] = "hot"
        case .squad, .club:
            if let c = chip { q["type"] = c } else { q["types"] = tab.types.joined(separator: ",") }
            if sort != "new" { q["sort"] = sort }
        }
        return q
    }

    private func fetch(page target: Int, append: Bool) async {
        generation += 1
        let gen = generation
        let q = query(page: target)
        do {
            let r = try await CommunityAPI.list(q)
            guard gen == generation else { return }
            types = r.types
            // 서버 기능 감지 — 구 서버에서는 새 기능을 조용히 숨긴다
            prefs.groupFilterSupported = r.sort != nil
            prefs.capabilityChecked = true
            if target == 1, tab == .all, sort == "new" { prefs.hotSupported = r.hot != nil }
            if tab == .hot, r.sort != "hot" {
                // 인기 정렬 미지원(0023 전) — 탭을 숨기고 전체로 되돌린다
                prefs.hotSupported = false
                tab = .all
                await load(reset: true)
                return
            }
            if r.sort == nil, q["types"] != nil {
                // types 쿼리를 모르는 서버 — 그룹 전체를 합쳐 그리지 않고 첫 유형으로
                chip = tab.types.first
                await load(reset: true)
                return
            }
            page = r.page
            totalPages = r.totalPages
            if append {
                let known = Set(posts.map(\.id))
                posts += r.posts.filter { !known.contains($0.id) }
            } else {
                posts = r.posts
                if target == 1 { hot = Array((r.hot ?? []).prefix(3)) }
            }
            state = .loaded(r)
        } catch {
            guard gen == generation else { return }
            if append { moreFailed = true } else { state = .failed(error) }
        }
    }
}

struct CommunityView: View {
    @State private var model = CommunityModel()
    @State private var prefs = LocalPrefs.shared
    @State private var cprefs = CommunityPrefs.shared
    @State private var composeReq: ComposeRequest?
    @State private var showLogin = false
    @State private var needNickname = false
    @State private var reportTarget: ReportTarget?
    @State private var toast: String?
    @State private var showNotifications = false
    @State private var fabCollapsed = false
    @State private var lastOffset: CGFloat = 0
    @State private var highlightId: String?
    @SceneStorage("community.tab") private var savedTab = CommunityTab.all.rawValue
    @SceneStorage("community.chip") private var savedChip = ""
    @Namespace private var tabNS
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    struct ComposeRequest: Identifiable { let type: String?; var id: String { type ?? "_" } }

    private var visibleTabs: [CommunityTab] {
        CommunityTab.allCases.filter { $0 != .hot || cprefs.hotSupported }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { g in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("cmScroll")).minY)
                        }
                        .frame(height: 0).id("top")
                        content
                    }
                    .padding(.bottom, 90)   // FAB 가 마지막 행을 가리지 않게
                }
                .coordinateSpace(name: "cmScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { y in trackScroll(y) }
                .refreshable {
                    await model.load(reset: true)
                    CMHaptic.selection()
                }
                .onChange(of: model.tab) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
        }
        .background(FC.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(FC.bg, for: .tabBar)
        // 빈 상태에는 화면 가운데 CTA 가 있다 — 그라디언트 버튼 두 개(CTA + FAB)를 동시에 두지 않는다(QA P2-11)
        .overlay(alignment: .bottomTrailing) { if !showsEmptyState { fab } }
        .overlay(alignment: .top) { CMToast(text: toast) }
        .sheet(item: $composeReq) { req in
            ComposeView(types: model.types, initialType: req.type) { newId in
                Task {
                    await model.load(reset: true)
                    flash(newId)
                }
            }
        }
        .sheet(isPresented: $showLogin) { LoginView(reason: "로그인이 필요해요") }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet { id in showNotifications = false; router.push(.post(id)) }
        }
        .alert("닉네임을 먼저 등록해 주세요", isPresented: $needNickname) {
            Button("내 정보로 이동") { router.tab = .me }
            Button("취소", role: .cancel) {}
        } message: { Text("커뮤니티에 글을 쓰려면 내 정보 탭에서 닉네임을 등록해야 해요.") }
        .reportDialog(target: $reportTarget) { msg in showToast(msg) } needLogin: { showLogin = true }
        .task {
            guard model.state.value == nil else { return }
            let t = CommunityTab(rawValue: savedTab) ?? .all
            model.tab = (t == .hot && !cprefs.hotSupported) ? .all : t
            model.chip = model.tab.types.contains(savedChip) ? savedChip : nil
            if !model.tab.types.isEmpty, model.chip == nil, !model.groupFilter { model.chip = model.tab.types.first }
            #if DEBUG
            CommunityDebugLaunch.runOnce(router: router, model: model) { composeReq = ComposeRequest(type: $0) }
            #endif
            await model.load()
        }
        .onChange(of: model.tab) { _, t in savedTab = t.rawValue }
        .onChange(of: model.chip) { _, c in savedChip = c ?? "" }
    }

    // MARK: 머리 — 큰 제목 + 🔔 + 1차 탭

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("커뮤니티").cmText(24, .bold).kerning(-0.6).foregroundStyle(FC.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // 🔍 은 백엔드 검색(q) 전까지 두지 않는다(SPEC 4절)
                if CommunityAPI.isLoggedIn {
                    Button { showNotifications = true } label: {
                        Image(systemName: "bell").font(.system(size: 20, weight: .medium)).foregroundStyle(FC.ink)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("내 글 새 댓글 알림")
                }
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.top, 4).frame(minHeight: 52)

            HStack(spacing: 22) {
                ForEach(visibleTabs) { t in tabButton(t) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            Rectangle().fill(CM.hair).frame(height: 1)
        }
        .background(FC.bg)
    }

    private func tabButton(_ t: CommunityTab) -> some View {
        let on = model.tab == t
        return Button { selectTab(t) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    Text(t.label).cmText(15, on ? .bold : .semibold).foregroundStyle(on ? FC.ink : FC.muted)
                    if t == .hot { Text("HOT").cmScore(11, .bold).foregroundStyle(CM.coral) }
                }
                .frame(minHeight: 40)
                ZStack {
                    Color.clear.frame(height: 2.5)
                    if on {
                        Capsule().fill(FC.ink).frame(height: 2.5)
                            .matchedGeometryEffect(id: "tabUnderline", in: tabNS)
                    }
                }
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func selectTab(_ t: CommunityTab) {
        let changed = withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { model.switchTab(t) }
        guard changed else { return }
        CMHaptic.selection()
        Task { await model.load(reset: true) }
    }

    // MARK: 본문

    @ViewBuilder private var content: some View {
        if !model.tab.types.isEmpty { chips }
        switch model.state {
        case .idle, .loading:
            if model.posts.isEmpty { skeletonRows } else { list }
        case .failed(let e):
            ErrorState(title: "커뮤니티를 불러오지 못했어요", message: e.localizedDescription, error: e, retry: { Task { await model.load(reset: true) } })
        case .loaded:
            list
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 8, lineSpacing: 0) {
                if model.groupFilter { chipButton(nil, "전체") }
                ForEach(model.tab.types, id: \.self) { t in chipButton(t, PostTypeNames.short(t, types: model.types)) }
            }
            .padding(.horizontal, 16).padding(.top, 6)
            HStack {
                let n = todayCount
                if n > 0 {
                    (Text("새 글 ") + Text("\(n)").font(.cm(13, typeSize, .bold)).foregroundColor(FC.ink) + Text("개 · 오늘"))
                        .cmText(13).foregroundStyle(FC.muted)
                }
                Spacer()
                if model.groupFilter {
                    Menu {
                        Picker("정렬", selection: Binding(get: { model.sort }, set: { v in model.sort = v; Task { await model.load(reset: true) } })) {
                            Text("최신순").tag("new")
                            Text("댓글순").tag("comments")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.sort == "comments" ? "댓글순" : "최신순").cmText(13, .semibold)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(FC.ink).frame(minHeight: 36).contentShape(Rectangle())
                    }
                    .accessibilityLabel("정렬: \(model.sort == "comments" ? "댓글순" : "최신순")")
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 34)
        }
    }

    private var todayCount: Int {
        let cal = Calendar.current
        return model.posts.filter { DateFmt.parse($0.createdAt).map { cal.isDateInToday($0) } ?? false }.count
    }

    private func chipButton(_ t: String?, _ label: String) -> some View {
        let on = model.chip == t
        return Button {
            guard model.switchChip(t) else { return }
            CMHaptic.selection()
            Task { await model.load(reset: true) }
        } label: {
            Text(label).cmText(13, .semibold)
                .foregroundStyle(on ? FC.tint : FC.muted)
                .padding(.horizontal, 14).frame(height: 32)
                .background(on ? FC.tint.opacity(0.12) : FC.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? FC.tint : .clear, lineWidth: 1.5))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var visiblePosts: [Post] { model.posts.filter { !prefs.isBlocked($0.authorId) } }
    private var showsEmptyState: Bool {
        if case .loaded = model.state { return visiblePosts.isEmpty }
        return false
    }
    /// 글은 있는데 전부 차단한 작성자의 글 — "아직 글이 없어요"는 틀린 말이다(QA P2-7)
    private var allHiddenByBlock: Bool { !model.posts.isEmpty && visiblePosts.isEmpty }

    @ViewBuilder private var list: some View {
        let visible = visiblePosts
        let hot = model.hot.filter { !prefs.isBlocked($0.authorId) }
        if model.tab == .all, !hot.isEmpty {
            HotBox(posts: hot, open: { open($0) }, more: { selectTab(.hot) })
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
        }
        if visible.isEmpty, model.state.value != nil {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, p in
                    row(p)
                        .onAppear { if p.id == visible.last?.id { Task { await model.loadMore() } } }
                    // 광고 — 3번째 행 뒤(행이 3개 미만이면 마지막 행 뒤). 크기는 기존 AdSlot 그대로(운영자 결정).
                    if i == min(2, visible.count - 1) {
                        AdSlot().padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
            footer(count: visible.count)
        }
    }

    private func row(_ p: Post) -> some View {
        Button { open(p) } label: {
            PostListRow(post: p, types: model.types, read: cprefs.isRead(p.id))
                .background(highlightId == p.id ? FC.tint.opacity(0.12) : Color.clear)
        }
        .buttonStyle(PressRowStyle())
        .contextMenu {
            ShareLink(item: AppConfig.absolute("/community/\(p.id)")) { Label("공유", systemImage: "square.and.arrow.up") }
            Button { reportTarget = ReportTarget(type: "post", id: p.id) } label: { Label("신고", systemImage: "exclamationmark.bubble") }
            Button(role: .destructive) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { prefs.block(p.authorId) }
                Haptic.warning()
                showToast("\(p.author.nickname)님의 글을 숨겼어요")
            } label: { Label("작성자 차단", systemImage: "hand.raised") }
        } preview: {
            PostPreviewCard(post: p, types: model.types)
        }
    }

    private func open(_ p: Post) {
        cprefs.markRead(p.id)
        router.push(.post(p.id))
    }

    @ViewBuilder private func footer(count: Int) -> some View {
        if model.moreFailed {
            Button { Task { await model.retryMore() } } label: {
                Text("불러오지 못했어요 · 다시 시도").cmText(13, .semibold).foregroundStyle(FC.tint)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.vertical, 8)
        } else if model.hasMore {
            HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 16)
        } else if count > 8 {
            Text("다 봤어요 👀").cmText(13).foregroundStyle(CM.faint)
                .frame(maxWidth: .infinity).padding(.vertical, 20)
        }
    }

    private var skeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                GeometryReader { g in
                    VStack(alignment: .leading, spacing: 10) {
                        ShimmerBar(width: g.size.width * [0.78, 0.58, 0.85, 0.66, 0.74, 0.6, 0.82, 0.7][i], height: 14)
                        ShimmerBar(width: g.size.width * 0.46, height: 10)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 64)
                .padding(.horizontal, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(CM.hair).frame(height: 1) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("글 목록을 불러오는 중")
    }

    private var emptyCopy: (emoji: String, title: String, desc: String, cta: String, type: String?) {
        switch model.tab {
        case .all: return ("📝", "아직 글이 없어요", "첫 글의 주인공이 돼 보세요", "첫 글 쓰기", nil)
        case .hot: return ("🔥", "아직 뜨는 글이 없어요", "추천과 댓글이 쌓이면 여기에 떠요", "글쓰기", nil)
        case .squad, .club:
            if model.chip == "tournament" { return ("🏆", "아직 대회 글이 없어요", "첫 대회를 열면 여기 맨 위에 떠요.\n규칙·일정만 적으면 끝!", "대회 열기", "tournament") }
            let name = model.chip.map { PostTypeNames.short($0, types: model.types) } ?? model.tab.label
            let emoji = model.tab == .club ? "🤝" : "🛡️"
            return (emoji, "아직 \(name) 글이 없어요", "첫 글의 주인공이 돼 보세요", "글쓰기", model.chip ?? model.tab.types.first)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if allHiddenByBlock {
            VStack(spacing: 8) {
                Text("🙈").font(.system(size: 44)).padding(.bottom, 6).accessibilityHidden(true)
                Text("차단한 사용자의 글만 있어요").cmText(17, .bold).foregroundStyle(FC.ink)
                Text("내 정보 → 설정 · 약관 · 계정에서 차단을 풀 수 있어요").cmText(14).foregroundStyle(FC.muted).multilineTextAlignment(.center)
                Button("새로고침") { Task { await model.load(reset: true) } }
                    .cmText(15, .semibold).foregroundStyle(FC.tint).frame(minHeight: 44).padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 70).padding(.horizontal, 24)
        } else {
            emptyCreate
        }
    }

    private var emptyCreate: some View {
        let c = emptyCopy
        return VStack(spacing: 8) {
            Text(c.emoji).font(.system(size: 44)).padding(.bottom, 6).accessibilityHidden(true)
            Text(c.title).cmText(17, .bold).foregroundStyle(FC.ink)
            Text(c.desc).cmText(14).foregroundStyle(FC.muted).multilineTextAlignment(.center).lineSpacing(4)
            Button(c.cta) { Task { await openCompose(c.type) } }
                .buttonStyle(BrandButtonStyle())
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70).padding(.horizontal, 24)
    }

    // MARK: 글쓰기 FAB

    private var fab: some View {
        Button { Task { await openCompose(model.chip) } } label: {
            HStack(spacing: 8) {
                Image(systemName: "pencil").font(.system(size: 19, weight: .bold))
                if !fabCollapsed { Text("글쓰기").cmText(17, .bold).fixedSize().transition(.opacity) }
            }
            .foregroundStyle(FC.brandInk)
            .padding(.horizontal, fabCollapsed ? 0 : 22)
            .frame(width: fabCollapsed ? 52 : nil, height: 52)
            .background(FC.brand, in: Capsule())
            // 컬러 글로우를 줄였다 — 큰 번짐은 "AI 랜딩" 느낌이었다(디자인 N2)
            .shadow(color: FC.brandEnd.opacity(0.18), radius: 6, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.trailing, 16).padding(.bottom, 18)
        .accessibilityLabel("글쓰기")
    }

    private func trackScroll(_ y: CGFloat) {
        let delta = y - lastOffset
        lastOffset = y
        let anim: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.2)
        if y > -20 { if fabCollapsed { withAnimation(anim) { fabCollapsed = false } }; return }
        if delta < -6, !fabCollapsed { withAnimation(anim) { fabCollapsed = true } }
        else if delta > 6, fabCollapsed { withAnimation(anim) { fabCollapsed = false } }
    }

    // MARK: 토스트·하이라이트

    private func showToast(_ s: String) {
        withAnimation { toast = s }
        Task { try? await Task.sleep(for: .seconds(2.2)); withAnimation { if toast == s { toast = nil } } }
    }
    private func flash(_ id: String) {
        highlightId = id
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { highlightId = nil }
        }
    }

    /// 글을 다 쓴 뒤 서버가 403(닉네임 없음)으로 거절하지 않도록, 작성 화면을 열기 전에 닉네임부터 확인한다.
    private func openCompose(_ type: String?) async {
        guard CommunityAPI.isLoggedIn else { showLogin = true; return }
        if let r = try? await CommunityAPI.profile(),
           (r.profile?.nickname ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            needNickname = true
            return
        }
        composeReq = ComposeRequest(type: type)   // 확인 실패(네트워크)면 막지 않는다 — 서버가 최종 판단
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 행 누름 피드백 — 배경만 살짝
struct PressRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? FC.surface2.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// 상단 토스트(신고 접수·차단 등)
struct CMToast: View {
    let text: String?
    var edge: Edge = .top
    var body: some View {
        if let text {
            Text(text).cmText(14, .semibold).foregroundStyle(FC.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(FC.surface2, in: Capsule())
                .overlay(Capsule().stroke(FC.line, lineWidth: 1))
                .padding(edge == .top ? .top : .bottom, 8)
                .transition(.move(edge: edge).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

enum CMHaptic {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - 신고 다이얼로그(목록·상세 공용)

private struct ReportDialog: ViewModifier {
    @Binding var target: ReportTarget?
    let done: (String) -> Void
    let needLogin: () -> Void
    /// 로그인하러 간 사이 기다리는 신고 — 로그인되면 사유 선택을 이어서 띄운다
    @State private var pending: ReportTarget?
    @State private var auth = AuthManager.shared

    func body(content: Content) -> some View {
        content.confirmationDialog("신고 사유", isPresented: Binding(get: { target != nil && CommunityAPI.isLoggedIn }, set: { if !$0 { target = nil } }), titleVisibility: .visible, presenting: target) { t in
            ForEach(ReportReason.allCases) { r in
                Button(r.label) { Task { await send(t, r) } }
            }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("운영자가 확인하고 조치해요. 신고가 쌓인 글은 자동으로 숨겨져요.")
        }
        // 비로그인이면 사유를 고르기 **전에** 로그인부터 — 예전엔 사유를 고른 뒤 로그인 시트가 떠 사유가 사라졌다(QA P2-6)
        .onChange(of: target) { _, t in
            guard let t, !CommunityAPI.isLoggedIn else { return }
            pending = t
            target = nil
            needLogin()
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            guard loggedIn, let p = pending else { return }
            pending = nil
            Task { try? await Task.sleep(for: .milliseconds(500)); target = p }
        }
    }
    @MainActor private func send(_ t: ReportTarget, _ r: ReportReason) async {
        do {
            try await CommunityAPI.report(type: t.type, id: t.id, reason: r.rawValue)
            Haptic.success()
            done("신고 접수됐어요. 확인하고 조치할게요")
        } catch APIError.unauthorized {
            pending = t
            needLogin()
        } catch {
            done(error.localizedDescription)
        }
    }
}

extension View {
    func reportDialog(target: Binding<ReportTarget?>, done: @escaping (String) -> Void, needLogin: @escaping () -> Void) -> some View {
        modifier(ReportDialog(target: target, done: done, needLogin: needLogin))
    }
}

// MARK: - 알림(내 글 새 댓글)

struct NotificationsSheet: View {
    let open: (String) -> Void
    @State private var state: Loadable<NotificationsResponse> = .idle
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let e): ErrorState(title: "알림을 불러오지 못했어요", message: e.localizedDescription, error: e) { Task { await load() } }
                case .loaded(let r):
                    if r.items.isEmpty {
                        VStack(spacing: 8) {
                            Text("🔔").font(.system(size: 40))
                            Text("새 댓글이 없어요").cmText(16, .bold).foregroundStyle(FC.ink)
                            Text("최근 7일 동안 내 글에 달린 댓글을 모아 보여 줘요").cmText(13).foregroundStyle(FC.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(r.items) { it in
                            Button { open(it.postId) } label: {
                                HStack {
                                    Text(it.title).cmText(15, .medium).foregroundStyle(FC.ink).lineLimit(1)
                                    Spacer()
                                    Text("새 댓글 \(it.count)").cmText(12, .semibold).foregroundStyle(FC.tint)
                                }
                                .frame(minHeight: 44)
                            }
                            .listRowBackground(FC.surface)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .background(FC.bg.ignoresSafeArea())
            .navigationTitle("알림").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }
    private func load() async {
        state = .loading
        do { state = .loaded(try await CommunityAPI.notifications()) } catch { state = .failed(error) }
    }
}
