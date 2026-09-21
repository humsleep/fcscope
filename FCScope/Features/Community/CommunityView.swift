import SwiftUI

@Observable
@MainActor
final class CommunityModel {
    var state: Loadable<PostListResponse> = .idle
    var type: String? = nil
    var types: [PostTypeInfo] = []

    /// 지금까지 이어붙인 글. 페이지 버튼 대신 **아래로 스크롤하면 다음 장을 붙인다**(iOS 표준).
    var posts: [Post] = []
    private(set) var page = 1
    private(set) var totalPages = 1
    private(set) var loadingMore = false
    var hasMore: Bool { page < totalPages }

    func load(reset: Bool = false) async {
        if reset { page = 1; posts = [] }
        if state.value == nil || reset { state = .loading }
        await fetch(page: 1, append: false)
    }

    /// 목록 바닥이 보이면 호출된다. 중복 호출·마지막 장에서는 아무 것도 하지 않는다.
    func loadMore() async {
        guard !loadingMore, hasMore, state.value != nil else { return }
        loadingMore = true
        await fetch(page: page + 1, append: true)
        loadingMore = false
    }

    private func fetch(page target: Int, append: Bool) async {
        var q = ["page": String(target)]; if let t = type { q["type"] = t }
        do {
            let r: PostListResponse = try await APIClient.shared.get("/api/v1/community/posts", query: q, auth: false)
            types = r.types
            page = r.page
            totalPages = r.totalPages
            // 같은 글이 두 번 들어오지 않게(글이 새로 올라오면 페이지 경계가 밀린다)
            if append {
                let known = Set(posts.map(\.id))
                posts += r.posts.filter { !known.contains($0.id) }
            } else {
                posts = r.posts
            }
            state = .loaded(r)
        } catch {
            if !append { state = .failed(error) }
        }
    }
}

struct CommunityView: View {
    @State private var model = CommunityModel()
    @State private var prefs = LocalPrefs.shared
    @State private var auth = AuthManager.shared
    @State private var showCompose = false
    @State private var showLogin = false
    @State private var needNickname = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 글 종류는 전체를 한눈에 봐야 고를 수 있다 — 가로 스크롤 금지, 줄바꿈.
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    tab(nil, "전체")
                    ForEach(model.types) { t in tab(t.type, "\(t.emoji) \(t.label)") }
                }
                // 카카오톡 채팅 목록처럼 글 종류 탭 바로 아래·목록 맨 위에 카드 하나(2026-09-21 운영자 결정)
                if case .loaded = model.state { AdSlot() }
                switch model.state {
                case .idle, .loading: Skeleton(height: 300)
                case .failed(let e): ErrorState(title: "커뮤니티를 불러오지 못했어요", message: e.localizedDescription, error: e, retry: { Task { await model.load(reset: true) } })
                case .loaded:
                    let visible = model.posts.filter { !prefs.isBlocked($0.authorId) }
                    if visible.isEmpty {
                        // 한 줄 문구 + 광고만 남아 고장난 화면처럼 보였다 — 시스템 빈 상태 + 바로 쓰기 동작.
                        ContentUnavailableView {
                            Label("아직 글이 없어요", systemImage: "text.bubble")
                        } description: {
                            Text("첫 글을 남겨 이야기를 시작해 보세요.")
                        } actions: {
                            Button("첫 글 쓰기") { Task { await openCompose() } }
                                .buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk)
                        }
                        .padding(.top, 24)
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(visible) { p in
                            Button { router.push(.post(p.id)) } label: { PostRow(post: p) }.buttonStyle(.plain)
                                // 마지막 글이 보이면 다음 장을 미리 붙인다 — 버튼을 누를 필요가 없다.
                                .onAppear { if p.id == visible.last?.id { Task { await model.loadMore() } } }
                        }
                    }
                    if model.hasMore {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 12)
                    } else if visible.count > 8 {
                        Text("마지막 글이에요").fcFont(12).foregroundStyle(FC.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
            }.padding(16)
        }
        .fcScreen().navigationTitle("커뮤니티").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await openCompose() } } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("글쓰기") } }
        .sheet(isPresented: $showCompose) { ComposeView(types: model.types, initialType: model.type) { Task { await model.load(reset: true) } } }
        .sheet(isPresented: $showLogin) { LoginView(reason: "글을 쓰려면 로그인이 필요해요") }
        .alert("닉네임을 먼저 등록해 주세요", isPresented: $needNickname) {
            Button("내 정보로 이동") { router.tab = .me }
            Button("취소", role: .cancel) {}
        } message: { Text("커뮤니티에 글을 쓰려면 내 정보 탭에서 닉네임을 등록해야 해요.") }
        .task { await model.load() }
        .refreshable { await model.load(reset: true) }
    }

    /// 글을 다 쓴 뒤 서버가 403(닉네임 없음)으로 거절하지 않도록, 작성 화면을 열기 전에 닉네임부터 확인한다.
    private func openCompose() async {
        guard auth.isLoggedIn else { showLogin = true; return }
        if let r: ProfileResponse = try? await APIClient.shared.get("/api/profile"),
           (r.profile?.nickname ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            needNickname = true
            return
        }
        showCompose = true   // 확인 실패(네트워크)면 막지 않는다 — 서버가 최종 판단
    }
    private func tab(_ t: String?, _ label: String) -> some View {
        Button { model.type = t; Task { await model.load(reset: true) } } label: {
            Text(label).fcFont(13, weight: .semibold).padding(.horizontal, 10).padding(.vertical, 7)
                .background(model.type == t ? FC.accent : FC.surface2, in: Capsule()).foregroundStyle(model.type == t ? FC.accentInk : FC.muted)
        }
        // 선택 여부가 색으로만 표현돼 VoiceOver 는 어떤 필터가 켜졌는지 알 수 없었다.
        .accessibilityAddTraits(model.type == t ? .isSelected : [])
    }
}

struct PostRow: View {
    let post: Post
    var body: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Chip(text: "\(post.typeEmoji) \(post.typeLabel)", color: FC.ink)
                    if post.status == "closed" { Chip(text: "마감") }
                    if let r = post.region { Chip(text: "📍\(r)", color: FC.accent, bg: FC.accent.opacity(0.12)) }
                    Spacer()
                    Text(DateFmt.relative(post.createdAt)).fcFont(11).foregroundStyle(FC.muted)
                }
                Text(post.title).fcFont(15, weight: .bold).foregroundStyle(FC.ink).lineLimit(2)
                if let pv = post.preview, !pv.isEmpty { Text(pv).fcFont(13).lineSpacing(4).foregroundStyle(FC.muted).lineLimit(2) }
                HStack(spacing: 8) {
                    Text(post.author.nickname).fcFont(12, weight: .semibold).foregroundStyle(FC.ink)
                    if let v = post.author.verifiedNickname { Text("✓ \(v)").fcFont(11).foregroundStyle(FC.accent) }
                    Spacer()
                    if post.squadId != nil { Text("🧩 스쿼드").fcFont(11).foregroundStyle(FC.muted) }
                    Text("💬 \(post.commentCount ?? 0)").fcFont(11).foregroundStyle(FC.muted)
                }
            }
        }
    }
}

// MARK: - 상세

struct PostDetailView: View {
    let postId: String
    @State private var state: Loadable<PostDetailResponse> = .idle
    @State private var prefs = LocalPrefs.shared
    @State private var comment = ""
    @State private var busy = false
    @State private var msg: String?
    @State private var showReport: (String, String)? = nil
    @State private var showLogin = false
    @State private var confirmDeletePost = false
    @State private var confirmDeleteComment: String?
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            switch state {
            case .idle, .loading: VStack(spacing: 10) { Skeleton(height: 200); Skeleton(height: 120) }.padding(16)
            case .failed(let e): ErrorState(title: "글을 불러오지 못했어요", message: e.localizedDescription, error: e, retry: { Task { await load() } })
            case .loaded(let d): content(d)
            }
        }
        .fcScreen().navigationTitle(state.value?.post.typeLabel ?? "커뮤니티").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("알림", isPresented: Binding(get: { msg != nil }, set: { _ in msg = nil })) { Button("확인") {} } message: { Text(msg ?? "") }
        .sheet(isPresented: $showLogin) { LoginView(reason: "댓글을 쓰려면 로그인이 필요해요") }
        .alert("글을 삭제할까요?", isPresented: $confirmDeletePost) {
            Button("삭제", role: .destructive) { Task { await deletePost() } }
            Button("취소", role: .cancel) {}
        } message: { Text("댓글까지 함께 삭제되며 되돌릴 수 없어요.") }
        .alert("댓글을 삭제할까요?", isPresented: Binding(get: { confirmDeleteComment != nil }, set: { if !$0 { confirmDeleteComment = nil } })) {
            Button("삭제", role: .destructive) { if let id = confirmDeleteComment { Task { await deleteComment(id) } } }
            Button("취소", role: .cancel) {}
        } message: { Text("되돌릴 수 없어요.") }
        .confirmationDialog("신고 사유", isPresented: Binding(get: { showReport != nil }, set: { if !$0 { showReport = nil } }), titleVisibility: .visible) {
            ForEach([("spam", "스팸·도배·광고"), ("abuse", "욕설·비하·혐오"), ("illegal", "불법·음란·거래 유도"), ("other", "기타")], id: \.0) { r in
                Button(r.1) { if let t = showReport { Task { await report(type: t.0, id: t.1, reason: r.0) } } }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await APIClient.shared.get("/api/v1/community/posts/\(postId)")) } catch { state = .failed(error) }
    }

    private func content(_ d: PostDetailResponse) -> some View {
        let p = d.post
        return VStack(alignment: .leading, spacing: 12) {
            // 다른 화면과 같은 상단 카드 광고(화면당 1개) — 본문 중간에 끼우지 않는다
            AdSlot()
            if prefs.isBlocked(p.authorId) {
                Panel { HStack { Text("차단한 사용자의 글이에요.").foregroundStyle(FC.muted); Spacer(); Button("차단 해제") { prefs.unblock(p.authorId) } } }
            } else {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) { Chip(text: "\(p.typeEmoji) \(p.typeLabel)", color: FC.ink); if p.status == "closed" { Chip(text: "마감") }; if let r = p.region { Chip(text: "📍\(r)", color: FC.accent, bg: FC.accent.opacity(0.12)) } }
                        Text(p.title).fcFont(22, weight: .bold).foregroundStyle(FC.ink)
                        Text(DateFmt.relative(p.createdAt)).fcFont(12).foregroundStyle(FC.muted)
                        if !p.positions.isEmpty { FlowLayout(spacing: 4) { ForEach(p.positions, id: \.self) { Chip(text: $0, color: FC.ink) } } }
                        if let rows = p.metaRows, !rows.isEmpty {
                            ForEach(rows) { r in HStack { Text(r.label).fcFont(12).foregroundStyle(FC.muted).frame(width: 70, alignment: .leading); Text(r.value).fcFont(14, weight: .semibold).foregroundStyle(FC.ink) }.padding(8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 8)) }
                        }
                        // 기본 행간은 한글 본문이 빽빽해 읽기 어려웠다 — 줄 사이를 넉넉히(15pt 글자에 +8)
                        Text(p.body).fcFont(16).lineSpacing(8).foregroundStyle(FC.ink).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if p.type == "squad_battle", let a = p.squadId, let b = p.squadB { BattleBlock(postId: p.id, squadA: a, squadB: b) }
                        else if let s = p.squadId { squadLink(s) }
                        if let c = p.contact { HStack { Text("연락").fcFont(12, weight: .semibold).foregroundStyle(FC.muted); Text(c).fcFont(14).foregroundStyle(FC.ink).textSelection(.enabled) } }
                        Divider().background(FC.line)
                        HStack(spacing: 12) {
                            if d.viewer.isOwner {
                                Button(role: .destructive) { confirmDeletePost = true } label: { Text("삭제").fcFont(13) }
                            } else {
                                Button { showReport = ("post", p.id) } label: { Text("신고").fcFont(13).foregroundStyle(FC.muted) }
                                Button { prefs.block(p.authorId); Haptic.warning() } label: { Text("차단").fcFont(13).foregroundStyle(FC.muted) }
                            }
                            Spacer()
                            ShareLink(item: AppConfig.absolute("/community/\(p.id)")) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("글 공유")
                        }
                    }
                }
                comments(d)
                Panel(padding: 12) {
                    HStack {
                        VStack(alignment: .leading) { SectionLabel("작성자"); Text(p.author.nickname).fcFont(16, weight: .bold).foregroundStyle(FC.ink); if let v = p.author.verifiedNickname { Text("✓ FC Online: \(v)").fcFont(12).foregroundStyle(FC.accent) } }
                        Spacer()
                        if let v = p.author.verifiedNickname { Button("전적·진단") { router.push(.user(v)) }.buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk) }
                    }
                }
            }
        }.padding(16)
    }

    private func squadLink(_ id: String) -> some View {
        Button { router.push(.squad(id)) } label: { HStack { Text("🧩 첨부 스쿼드 보기").fcFont(14, weight: .semibold).foregroundStyle(FC.accent); Spacer(); Image(systemName: "chevron.right").foregroundStyle(FC.muted) }.padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
    }

    private func comments(_ d: PostDetailResponse) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("댓글 \(d.comments.count)")
                ForEach(d.comments.filter { !prefs.isBlocked($0.authorId) }) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(c.author.nickname).fcFont(13, weight: .semibold).foregroundStyle(FC.ink)
                            Text(DateFmt.relative(c.createdAt)).fcFont(11).foregroundStyle(FC.muted)
                            Spacer()
                            // 12pt 텍스트 버튼(신고·차단)이 붙어 있어 탭 영역이 44pt 에 한참 못 미쳤고 오탭이 잦았다.
                            // 삭제는 확인 알림이 있으니 그대로 두되 탭 영역만 넓히고, 신고·차단은 메뉴 하나로 모은다.
                            if c.isOwn {
                                Button("삭제") { confirmDeleteComment = c.id }.fcFont(12).foregroundStyle(FC.lose)
                                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            } else {
                                Menu {
                                    Button { showReport = ("comment", c.id) } label: { Label("신고", systemImage: "exclamationmark.bubble") }
                                    Button(role: .destructive) { prefs.block(c.authorId); Haptic.warning() } label: { Label("작성자 차단", systemImage: "hand.raised") }
                                } label: {
                                    Image(systemName: "ellipsis").fcFont(14, weight: .semibold).foregroundStyle(FC.muted)
                                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel("\(c.author.nickname) 댓글 더보기")
                            }
                        }
                        Text(c.body).fcFont(15).lineSpacing(6).foregroundStyle(FC.ink).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
                        if let s = c.squadId { Button("🧩 제안 스쿼드 보기 →") { router.push(.squad(s)) }.fcFont(12, weight: .semibold).foregroundStyle(FC.accent) }
                    }
                }
                if d.viewer.canComment {
                    HStack(alignment: .bottom) {
                        TextField("의견을 남겨보세요", text: $comment, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                        Button { Task { await submitComment() } } label: { Text(busy ? "…" : "등록") }.buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk).disabled(busy || comment.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else if d.viewer.loggedIn {
                    Button("댓글을 쓰려면 닉네임 등록이 필요해요 →") { router.tab = .me }.fcFont(13).foregroundStyle(FC.accent)
                } else {
                    Button("로그인하고 의견 남기기") { showLogin = true }.fcFont(13).foregroundStyle(FC.accent)
                }
            }
        }
    }

    private func submitComment() async {
        busy = true; defer { busy = false }
        do { try await APIClient.shared.sendNoContent("/api/community/posts/\(postId)/comments", method: "POST", json: ["body": comment.trimmingCharacters(in: .whitespaces)]); comment = ""; Haptic.success(); await load() } catch { msg = error.localizedDescription }
    }
    private func deleteComment(_ id: String) async {
        do { try await APIClient.shared.sendNoContent("/api/community/posts/\(postId)/comments", method: "DELETE", json: ["comment_id": id]); await load() } catch { msg = error.localizedDescription }
    }
    private func deletePost() async {
        do { try await APIClient.shared.sendNoContent("/api/community/posts/\(postId)", method: "DELETE"); router.communityPath = NavigationPath() } catch { msg = error.localizedDescription }
    }
    private func report(type: String, id: String, reason: String) async {
        do { try await APIClient.shared.sendNoContent("/api/community/report", method: "POST", json: ["target_type": type, "target_id": id, "reason": reason]); msg = "신고가 접수됐어요. 확인 후 조치할게요." }
        catch let e as APIError where e.code == nil && "\(e)".contains("unauthorized") { showLogin = true }
        catch { msg = (error as? APIError) == nil ? error.localizedDescription : ((error as? APIError).map { if case .unauthorized = $0 { return "신고하려면 로그인이 필요해요." } else { return $0.localizedDescription } } ?? "") }
    }
}

struct BattleBlock: View {
    let postId: String; let squadA: String; let squadB: String
    @State private var votes: BattleVotes?
    /// 서버가 "내 투표"를 돌려주지 않으므로 이 화면에서만 기억한다(중복 투표는 서버가 upsert 로 막는다).
    @State private var myPick: String?
    @State private var voteError: String?
    @Environment(AppRouter.self) private var router
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                side("🅰️ A팀", squadA, FC.accent); side("🅱️ B팀", squadB, FC.lose)
            }
            let a = votes?.a ?? 0, b = votes?.b ?? 0, total = max(1, a + b)
            GeometryReader { g in HStack(spacing: 2) { Rectangle().fill(FC.accent).frame(width: g.size.width * CGFloat(a) / CGFloat(total)); Rectangle().fill(FC.lose) } }.frame(height: 10).clipShape(Capsule())
            HStack { Text("A \(a)표").fcScoreboard(12).foregroundStyle(FC.accent); Spacer(); Text("B \(b)표").fcScoreboard(12).foregroundStyle(FC.lose) }
            HStack(spacing: 8) {
                Button("A에 투표") { Task { await vote("A") } }.buttonStyle(.bordered).tint(FC.accent).disabled(myPick != nil)
                Button("B에 투표") { Task { await vote("B") } }.buttonStyle(.bordered).tint(FC.lose).disabled(myPick != nil)
            }
            if let e = voteError { Text(e).fcFont(12).foregroundStyle(FC.lose) }
        }
        .task { votes = try? await APIClient.shared.get("/api/community/battle", query: ["postId": postId]) }
    }
    private func side(_ t: String, _ id: String, _ c: Color) -> some View {
        Button { router.push(.squad(id)) } label: { VStack { Text(t).fcScoreboard(13).foregroundStyle(c); Text("스쿼드 보기").fcFont(12).foregroundStyle(FC.muted) }.frame(maxWidth: .infinity).padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
    }
    private func vote(_ pick: String) async {
        let device = UIDevice.current.identifierForVendor?.uuidString ?? "anon"
        do {
            let v: BattleVotes = try await APIClient.shared.send("/api/community/battle", method: "POST", json: ["postId": postId, "pick": pick, "voter": device])
            votes = v
            myPick = pick
            voteError = nil
            Haptic.success()
        } catch {
            voteError = "투표를 반영하지 못했어요. 잠시 후 다시 시도해 주세요."
            Haptic.warning()
        }
    }
}

// MARK: - 글쓰기

struct ComposeView: View {
    let types: [PostTypeInfo]
    var initialType: String?
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type: PostTypeInfo?
    @State private var title = ""
    @State private var body_ = ""
    @State private var squad = ""
    @State private var squadB = ""
    @State private var region = "전국(온라인)"
    @State private var contact = ""
    @State private var extras: [String: String] = [:]
    @State private var busy = false
    @State private var msg: String?
    private let regions = ["전국(온라인)", "서울", "경기", "인천", "강원", "대전", "세종", "충북", "충남", "대구", "경북", "부산", "울산", "경남", "광주", "전북", "전남", "제주"]

    var body: some View {
        NavigationStack {
            Form {
                Section("유형") {
                    Picker("유형", selection: Binding(get: { type?.type ?? "" }, set: { v in type = types.first { $0.type == v }; if body_.isEmpty { body_ = type?.template ?? "" } })) {
                        ForEach(types) { t in Text("\(t.emoji) \(t.label)").tag(t.type) }
                    }
                    if let t = type { Text(t.blurb).fcFont(12).foregroundStyle(FC.muted) }
                }
                Section("제목 · 내용") {
                    TextField("제목 (60자)", text: $title)
                    TextEditor(text: $body_).frame(minHeight: 140)
                }
                if let t = type {
                    Section("추가 정보") {
                        if t.fields.contains("squad") { TextField(t.type == "squad_battle" ? "A팀 스쿼드 공유코드" : "스쿼드 공유코드 (선택)", text: $squad) }
                        if t.fields.contains("squad_b") { TextField("B팀 스쿼드 공유코드", text: $squadB) }
                        if t.fields.contains("region") { Picker("지역", selection: $region) { ForEach(regions, id: \.self) { Text($0) } } }
                        if t.fields.contains("contact") { TextField("연락 방법 (선택)", text: $contact) }
                        ForEach(t.fields.filter { ["budget", "schedule", "date", "format", "entry"].contains($0) }, id: \.self) { f in
                            TextField(["budget": "예산", "schedule": "가능 시간", "date": "일정", "format": "형식", "entry": "참가 방법"][f] ?? f, text: Binding(get: { extras[f] ?? "" }, set: { extras[f] = $0 }))
                        }
                    }
                }
                Section { Text("욕설·비하·도배·거래 유도 글은 신고 누적 시 숨김 처리되며 반복 시 이용이 제한돼요.").fcFont(12).foregroundStyle(FC.muted) }
            }
            .navigationTitle("글쓰기").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "등록 중…" : "등록") { Task { await submit() } }.disabled(busy || type == nil || title.isEmpty || body_.isEmpty) }
            }
            .alert("알림", isPresented: Binding(get: { msg != nil }, set: { _ in msg = nil })) { Button("확인") {} } message: { Text(msg ?? "") }
            .onAppear { type = types.first { $0.type == initialType } ?? types.first; if body_.isEmpty { body_ = type?.template ?? "" } }
        }
    }
    private func submit() async {
        guard let t = type else { return }
        busy = true; defer { busy = false }
        var json: [String: Any] = ["type": t.type, "title": title, "body": body_]
        if !squad.isEmpty { json["squad_id"] = squad }
        if !squadB.isEmpty { json["squad_b"] = squadB }
        if t.fields.contains("region") { json["region"] = region }
        if !contact.isEmpty { json["contact"] = contact }
        for (k, v) in extras where !v.isEmpty { json[k] = v }
        do { let _: IdBody = try await APIClient.shared.send("/api/community/posts", method: "POST", json: json); Haptic.success(); onDone(); dismiss() }
        catch { msg = error.localizedDescription }
    }
}
