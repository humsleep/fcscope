import SwiftUI

@Observable
@MainActor
final class CommunityModel {
    var state: Loadable<PostListResponse> = .idle
    var type: String? = nil
    var page = 1
    var types: [PostTypeInfo] = []
    func load(reset: Bool = false) async {
        if reset { page = 1 }
        if state.value == nil || reset { state = .loading }
        var q = ["page": String(page)]; if let t = type { q["type"] = t }
        do {
            let r: PostListResponse = try await APIClient.shared.get("/api/v1/community/posts", query: q, auth: false)
            types = r.types; state = .loaded(r)
        } catch { state = .failed(error) }
    }
}

struct CommunityView: View {
    @State private var model = CommunityModel()
    @State private var prefs = LocalPrefs.shared
    @State private var auth = AuthManager.shared
    @State private var showCompose = false
    @State private var showLogin = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tab(nil, "전체")
                        ForEach(model.types) { t in tab(t.type, "\(t.emoji) \(t.label)") }
                    }
                }
                switch model.state {
                case .idle, .loading: Skeleton(height: 300)
                case .failed(let e): ErrorState(title: "커뮤니티를 불러오지 못했어요", message: e.localizedDescription, retry: { Task { await model.load(reset: true) } })
                case .loaded(let r):
                    let visible = r.posts.filter { !prefs.isBlocked($0.authorId) }
                    if visible.isEmpty { Panel { Text("아직 글이 없어요. 첫 글을 남겨보세요!").font(.system(size: 14)).foregroundStyle(FC.muted).frame(maxWidth: .infinity) } }
                    ForEach(visible) { p in
                        Button { router.push(.post(p.id)) } label: { PostRow(post: p) }.buttonStyle(.plain)
                    }
                    if r.totalPages > 1 {
                        HStack {
                            Button("← 이전") { model.page = max(1, model.page - 1); Task { await model.load() } }.disabled(model.page <= 1)
                            Spacer(); Text("\(model.page) / \(r.totalPages)").font(.scoreboard(13)).foregroundStyle(FC.muted); Spacer()
                            Button("다음 →") { model.page += 1; Task { await model.load() } }.disabled(model.page >= r.totalPages)
                        }.font(.system(size: 13, weight: .semibold))
                    }
                }
                AdSlot()
            }.padding(16)
        }
        .fcScreen().navigationTitle("커뮤니티")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { if auth.isLoggedIn { showCompose = true } else { showLogin = true } } label: { Image(systemName: "square.and.pencil") } } }
        .sheet(isPresented: $showCompose) { ComposeView(types: model.types, initialType: model.type) { Task { await model.load(reset: true) } } }
        .sheet(isPresented: $showLogin) { LoginView(reason: "글을 쓰려면 로그인이 필요해요") }
        .task { await model.load() }
        .refreshable { await model.load(reset: true) }
    }
    private func tab(_ t: String?, _ label: String) -> some View {
        Button { model.type = t; Task { await model.load(reset: true) } } label: {
            Text(label).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7)
                .background(model.type == t ? FC.accent : FC.surface2, in: Capsule()).foregroundStyle(model.type == t ? FC.accentInk : FC.muted)
        }
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
                    Text(DateFmt.relative(post.createdAt)).font(.system(size: 11)).foregroundStyle(FC.muted)
                }
                Text(post.title).font(.system(size: 15, weight: .bold)).foregroundStyle(FC.ink).lineLimit(2)
                if let pv = post.preview, !pv.isEmpty { Text(pv).font(.system(size: 13)).foregroundStyle(FC.muted).lineLimit(2) }
                HStack(spacing: 8) {
                    Text(post.author.nickname).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.ink)
                    if let v = post.author.verifiedNickname { Text("✓ \(v)").font(.system(size: 11)).foregroundStyle(FC.accent) }
                    Spacer()
                    if post.squadId != nil { Text("🧩 스쿼드").font(.system(size: 11)).foregroundStyle(FC.muted) }
                    Text("💬 \(post.commentCount ?? 0)").font(.system(size: 11)).foregroundStyle(FC.muted)
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
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            switch state {
            case .idle, .loading: VStack(spacing: 10) { Skeleton(height: 200); Skeleton(height: 120) }.padding(16)
            case .failed(let e): ErrorState(title: "글을 찾을 수 없어요", message: e.localizedDescription)
            case .loaded(let d): content(d)
            }
        }
        .fcScreen().navigationTitle(state.value?.post.typeLabel ?? "커뮤니티").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("알림", isPresented: Binding(get: { msg != nil }, set: { _ in msg = nil })) { Button("확인") {} } message: { Text(msg ?? "") }
        .sheet(isPresented: $showLogin) { LoginView(reason: "댓글을 쓰려면 로그인이 필요해요") }
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
            if prefs.isBlocked(p.authorId) {
                Panel { HStack { Text("차단한 사용자의 글이에요.").foregroundStyle(FC.muted); Spacer(); Button("차단 해제") { prefs.unblock(p.authorId) } } }
            } else {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) { Chip(text: "\(p.typeEmoji) \(p.typeLabel)", color: FC.ink); if p.status == "closed" { Chip(text: "마감") }; if let r = p.region { Chip(text: "📍\(r)", color: FC.accent, bg: FC.accent.opacity(0.12)) } }
                        Text(p.title).font(.system(size: 22, weight: .bold)).foregroundStyle(FC.ink)
                        Text(DateFmt.relative(p.createdAt)).font(.system(size: 12)).foregroundStyle(FC.muted)
                        if !p.positions.isEmpty { FlowLayout(spacing: 4) { ForEach(p.positions, id: \.self) { Chip(text: $0, color: FC.ink) } } }
                        if let rows = p.metaRows, !rows.isEmpty {
                            ForEach(rows) { r in HStack { Text(r.label).font(.system(size: 12)).foregroundStyle(FC.muted).frame(width: 70, alignment: .leading); Text(r.value).font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.ink) }.padding(8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 8)) }
                        }
                        Text(p.body).font(.system(size: 15)).foregroundStyle(FC.ink).textSelection(.enabled)
                        if p.type == "squad_battle", let a = p.squadId, let b = p.squadB { BattleBlock(postId: p.id, squadA: a, squadB: b) }
                        else if let s = p.squadId { squadLink(s) }
                        if let c = p.contact { HStack { Text("연락").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted); Text(c).font(.system(size: 14)).foregroundStyle(FC.ink).textSelection(.enabled) } }
                        Divider().background(FC.line)
                        HStack(spacing: 12) {
                            if d.viewer.isOwner {
                                Button(role: .destructive) { Task { await deletePost() } } label: { Text("삭제").font(.system(size: 13)) }
                            } else {
                                Button { showReport = ("post", p.id) } label: { Text("신고").font(.system(size: 13)).foregroundStyle(FC.muted) }
                                Button { prefs.block(p.authorId); Haptic.warning() } label: { Text("차단").font(.system(size: 13)).foregroundStyle(FC.muted) }
                            }
                            Spacer()
                            ShareLink(item: AppConfig.absolute("/community/\(p.id)")) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                }
                comments(d)
                Panel(padding: 12) {
                    HStack {
                        VStack(alignment: .leading) { SectionLabel("작성자"); Text(p.author.nickname).font(.system(size: 16, weight: .bold)).foregroundStyle(FC.ink); if let v = p.author.verifiedNickname { Text("✓ FC Online: \(v)").font(.system(size: 12)).foregroundStyle(FC.accent) } }
                        Spacer()
                        if let v = p.author.verifiedNickname { Button("전적·진단") { router.push(.user(v)) }.buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk) }
                    }
                }
            }
        }.padding(16)
    }

    private func squadLink(_ id: String) -> some View {
        Button { router.push(.squad(id)) } label: { HStack { Text("🧩 첨부 스쿼드 보기").font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.accent); Spacer(); Image(systemName: "chevron.right").foregroundStyle(FC.muted) }.padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
    }

    private func comments(_ d: PostDetailResponse) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("댓글 \(d.comments.count)")
                ForEach(d.comments.filter { !prefs.isBlocked($0.authorId) }) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(c.author.nickname).font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.ink)
                            Text(DateFmt.relative(c.createdAt)).font(.system(size: 11)).foregroundStyle(FC.muted)
                            Spacer()
                            if c.isOwn { Button("삭제") { Task { await deleteComment(c.id) } }.font(.system(size: 12)).foregroundStyle(FC.lose) }
                            else { Button("신고") { showReport = ("comment", c.id) }.font(.system(size: 12)).foregroundStyle(FC.muted); Button("차단") { prefs.block(c.authorId) }.font(.system(size: 12)).foregroundStyle(FC.muted) }
                        }
                        Text(c.body).font(.system(size: 14)).foregroundStyle(FC.ink).padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
                        if let s = c.squadId { Button("🧩 제안 스쿼드 보기 →") { router.push(.squad(s)) }.font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.accent) }
                    }
                }
                if d.viewer.canComment {
                    HStack(alignment: .bottom) {
                        TextField("의견을 남겨보세요", text: $comment, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                        Button { Task { await submitComment() } } label: { Text(busy ? "…" : "등록") }.buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk).disabled(busy || comment.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else if d.viewer.loggedIn {
                    Button("댓글을 쓰려면 닉네임 등록이 필요해요 →") { router.tab = .me }.font(.system(size: 13)).foregroundStyle(FC.accent)
                } else {
                    Button("로그인하고 의견 남기기") { showLogin = true }.font(.system(size: 13)).foregroundStyle(FC.accent)
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
    @Environment(AppRouter.self) private var router
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                side("🅰️ A팀", squadA, FC.accent); side("🅱️ B팀", squadB, FC.lose)
            }
            let a = votes?.a ?? 0, b = votes?.b ?? 0, total = max(1, a + b)
            GeometryReader { g in HStack(spacing: 2) { Rectangle().fill(FC.accent).frame(width: g.size.width * CGFloat(a) / CGFloat(total)); Rectangle().fill(FC.lose) } }.frame(height: 10).clipShape(Capsule())
            HStack { Text("A \(a)표").font(.scoreboard(12)).foregroundStyle(FC.accent); Spacer(); Text("B \(b)표").font(.scoreboard(12)).foregroundStyle(FC.lose) }
            HStack(spacing: 8) {
                Button("A에 투표") { Task { await vote("A") } }.buttonStyle(.bordered).tint(FC.accent).disabled(votes?.mine != nil)
                Button("B에 투표") { Task { await vote("B") } }.buttonStyle(.bordered).tint(FC.lose).disabled(votes?.mine != nil)
            }
        }
        .task { votes = try? await APIClient.shared.get("/api/community/battle", query: ["postId": postId]) }
    }
    private func side(_ t: String, _ id: String, _ c: Color) -> some View {
        Button { router.push(.squad(id)) } label: { VStack { Text(t).font(.scoreboard(13)).foregroundStyle(c); Text("스쿼드 보기").font(.system(size: 12)).foregroundStyle(FC.muted) }.frame(maxWidth: .infinity).padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
    }
    private func vote(_ pick: String) async {
        let device = UIDevice.current.identifierForVendor?.uuidString ?? "anon"
        votes = try? await APIClient.shared.send("/api/community/battle", method: "POST", json: ["postId": postId, "pick": pick, "voter": device])
        Haptic.success()
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
                    if let t = type { Text(t.blurb).font(.system(size: 12)).foregroundStyle(FC.muted) }
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
                Section { Text("욕설·비하·도배·거래 유도 글은 신고 누적 시 숨김 처리되며 반복 시 이용이 제한돼요.").font(.system(size: 12)).foregroundStyle(FC.muted) }
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
