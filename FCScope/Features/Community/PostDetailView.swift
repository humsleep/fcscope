import SwiftUI

@Observable
@MainActor
final class PostDetailModel {
    let postId: String
    var state: Loadable<PostDetailResponse> = .idle
    /// 낙관적 추천 상태(글)
    var postLike: LikeState?
    /// 낙관적 하트 상태(댓글 id → 상태)
    var commentLikes: [String: LikeState] = [:]
    /// 서버가 좋아요를 "아직 준비 중"(0023 전)으로 거절 — 하트 UI 를 숨긴다
    var likesDisabled = false

    init(postId: String) { self.postId = postId }

    var detail: PostDetailResponse? { state.value }
    /// v2 **코드**가 배포된 서버인가(목록 응답의 `sort` 키 — CommunityPrefs.serverV2). DB 필드(`like_count`)로
    /// 판단하면 "스키마 v2 + 코드 v1" 혼합 서버에서 추천 404·답글 parent_id 유실이 났다(QA 1라운드 P0-1).
    var serverV2: Bool { CommunityPrefs.shared.serverV2 }
    /// 답글(parent_id) 전송 — v2 확인됐을 때만. 아니면 "@닉 " 접두로 대신한다.
    var repliesEnabled: Bool { serverV2 }
    /// 추천 UI — v2 확인 + 서버가 404/503 으로 거절한 적 없음 + 값이 실제로 옴
    var likesEnabled: Bool { serverV2 && !likesDisabled && detail?.post.likeCount != nil }

    func load() async {
        // 댓글 작성·삭제 후 재로드 때 화면(과 광고)을 통째로 갈아 끼우지 않는다 — 이미 있으면 그 위에서 갱신
        if state.value == nil { state = .loading }
        // 딥링크로 상세부터 열었으면 서버 v2 여부를 먼저 확인한다(실행당 1회 · 목록 1장)
        async let cap: Void = CommunityAPI.ensureCapability()
        do {
            let d = try await CommunityAPI.detail(postId)
            await cap
            state = .loaded(d)
            if let n = d.post.likeCount { postLike = LikeState(liked: d.post.viewerLiked ?? false, count: n) } else { postLike = nil }
            var m: [String: LikeState] = [:]
            for c in d.comments { if let n = c.likeCount { m[c.id] = LikeState(liked: c.viewerLiked ?? false, count: n) } }
            commentLikes = m
            // 목록 [N] 은 서버 comment_count(숨김 댓글 포함 · 트리거) — 상세에서 실제로 받은 댓글 수와의 차이를 기억해
            // 목록으로 돌아갔을 때 같은 숫자를 보이게 한다(유저 패널 C "12 vs 11").
            // 차단한 작성자의 댓글도 상세에선 안 보이므로 같이 뺀다 — 상세 "댓글 N" 과 목록 [N] 이 같은 기준.
            let visible = d.comments.filter { !LocalPrefs.shared.isBlocked($0.authorId) }.count
            if let listed = d.post.commentCount { CommunityPrefs.shared.noteCommentGap(postId, listed: listed, gap: listed - visible) }
        } catch {
            await cap
            if state.value == nil { state = .failed(error) }
        }
    }

    /// 결과: nil = 성공, .login = 로그인 필요
    enum LikeOutcome { case ok, login, failed(String) }

    func togglePostLike() async -> LikeOutcome {
        guard var s = postLike else { return .ok }
        let target = !s.liked
        s.liked = target; s.count = max(0, s.count + (target ? 1 : -1))
        let before = postLike
        postLike = s
        do {
            let r = try await CommunityAPI.like(.post, postId, on: target)
            postLike = LikeState(liked: r.liked, count: r.likeCount ?? s.count)
            return .ok
        } catch {
            postLike = before
            return outcome(error)
        }
    }

    func toggleCommentLike(_ id: String) async -> LikeOutcome {
        guard var s = commentLikes[id] else { return .ok }
        let before = s
        s.liked.toggle(); s.count = max(0, s.count + (s.liked ? 1 : -1))
        commentLikes[id] = s
        do {
            let r = try await CommunityAPI.like(.comment, id, on: s.liked)
            commentLikes[id] = LikeState(liked: r.liked, count: r.likeCount ?? s.count)
            return .ok
        } catch {
            commentLikes[id] = before
            return outcome(error)
        }
    }

    private func outcome(_ error: Error) -> LikeOutcome {
        if case APIError.unauthorized = error { return .login }
        if CommunityAPI.isNotReady(error) { likesDisabled = true; return .failed("추천은 곧 열려요") }
        return .failed(error.localizedDescription)
    }
}

// MARK: - 상세

struct PostDetailView: View {
    let postId: String
    @State private var model: PostDetailModel
    @State private var prefs = LocalPrefs.shared
    @State private var cprefs = CommunityPrefs.shared
    @State private var reportTarget: ReportTarget?
    @State private var showLogin = false
    @State private var confirmDeletePost = false
    @State private var confirmDeleteComment: String?
    @State private var confirmBlockAuthor = false
    @State private var toast: String?
    @State private var commentSort = "asc"
    @State private var expanded: Set<String> = []
    @State private var highlightComment: String?
    /// 원래 자리에서 펼친 BEST 댓글(기본은 한 줄로 접힘)
    @State private var expandedBest: Set<String> = []
    /// 제목이 스크롤로 사라졌는가 — 그때만 내비 제목에 글 제목을 띄운다(디자인 M5)
    @State private var showNavTitle = false
    // 입력창
    @State private var text = ""
    @State private var replyTo: Comment?
    @State private var attach: (id: String, name: String)?
    @State private var showSquadPicker = false
    @State private var sending = false
    @FocusState private var composerFocused: Bool
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(postId: String) {
        self.postId = postId
        _model = State(initialValue: PostDetailModel(postId: postId))
    }

    private var post: Post? { model.detail?.post }
    private var blocked: Bool { post.map { prefs.isBlocked($0.authorId) } ?? false }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                switch model.state {
                case .idle, .loading: skeleton
                case .failed(let e): failed(e)
                case .loaded(let d): content(d, proxy: proxy)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let d = model.detail, !blocked {
                    composer(d, proxy: proxy)
                }
            }
            #if DEBUG
            .onChange(of: model.detail != nil) { _, loaded in
                guard loaded, let target = CommunityDebugLaunch.scrollTarget else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(target, anchor: .top)
                    if let rid = UserDefaults.standard.string(forKey: "communityReply"), let c = model.detail?.comments.first(where: { $0.id == rid }) {
                        startReply(c)
                        text += "풀백부터 바꿔볼게요"   // startReply 가 넣은 "@닉 " 접두(구 서버)를 지우지 않게
                    }
                }
            }
            #endif
        }
        .background(FC.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // 말머리가 내비 제목과 태그에 두 번 나오던 것을 없앴다 — 제목이 화면 밖으로 나간 뒤에만 글 제목을 띄운다.
                if showNavTitle, let p = post {
                    Text(p.title).cmText(15, .semibold).foregroundStyle(FC.ink).lineLimit(1)
                        .transition(.opacity)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { if let d = model.detail { moreMenu(d) } }
        }
        .toolbarBackground(FC.bg, for: .navigationBar)
        // 상세에선 탭 바를 숨긴다 — 바닥 입력창 자리(SPEC 6절)
        .toolbar(.hidden, for: .tabBar)
        // 토스트는 아래쪽 — 위에 두면 차단 직후 "차단한 사용자의 글이에요" 배너와 겹쳤다(QA 2R P2-9)
        .overlay(alignment: .bottom) { CMToast(text: toast, edge: .bottom).padding(.bottom, model.detail != nil && !blocked ? 72 : 16) }
        .task { if model.state.value == nil { await model.load(); cprefs.markRead(postId) } }
        .sheet(isPresented: $showLogin) { LoginView(reason: "로그인이 필요해요") }
        .sheet(isPresented: $showSquadPicker) { SquadPickerSheet { id, name in attach = (id, name) } }
        .alert("글을 삭제할까요?", isPresented: $confirmDeletePost) {
            Button("삭제", role: .destructive) { Task { await deletePost() } }
            Button("취소", role: .cancel) {}
        } message: { Text("댓글까지 같이 지워지고 되돌릴 수 없어요") }
        .alert("댓글을 삭제할까요?", isPresented: Binding(get: { confirmDeleteComment != nil }, set: { if !$0 { confirmDeleteComment = nil } })) {
            Button("삭제", role: .destructive) { if let id = confirmDeleteComment { Task { await deleteComment(id) } } }
            Button("취소", role: .cancel) {}
        } message: { Text("되돌릴 수 없어요") }
        .reportDialog(target: $reportTarget) { showToast($0) } needLogin: { showLogin = true }
    }

    // MARK: 상태

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShimmerBar(width: 70, height: 18)
            ShimmerBar(height: 22)
            ShimmerBar(width: 220, height: 22)
            HStack(spacing: 10) {
                Circle().fill(FC.surface2).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) { ShimmerBar(width: 90, height: 12); ShimmerBar(width: 130, height: 10) }
            }
            .padding(.vertical, 8)
            ForEach(0..<5, id: \.self) { i in ShimmerBar(height: 14).padding(.trailing, i == 4 ? 120 : 0) }
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("글을 불러오는 중")
    }

    private func failed(_ e: Error) -> some View {
        let notFound: Bool = {
            if case .server(_, _, let status, _)? = e as? APIError { return status == 404 }
            return false
        }()
        return VStack(spacing: 0) {
            ErrorState(title: notFound ? "삭제됐거나 숨겨진 글이에요" : "글을 불러오지 못했어요", message: e.localizedDescription, error: e,
                       retry: notFound ? nil : { Task { await model.load() } })
            if notFound {
                Button("목록으로") { dismiss() }.buttonStyle(BrandButtonStyle())
            }
        }
    }

    // MARK: 본문

    private func content(_ d: PostDetailResponse, proxy: ScrollViewProxy) -> some View {
        let p = d.post
        return VStack(alignment: .leading, spacing: 0) {
            if blocked {
                HStack {
                    Text("차단한 사용자의 글이에요").cmText(15).foregroundStyle(FC.muted)
                    Spacer()
                    Button("차단 해제") { prefs.unblock(p.authorId) }.cmText(14, .semibold).foregroundStyle(FC.tint)
                }
                .padding(16)
                .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card))
                .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    head(p)
                    authorRow(p)
                    metaTable(p)
                    LinkedBody(text: p.body)
                    if p.type == "squad_battle", let a = p.squadId, let b = p.squadB {
                        BattleCard(postId: p.id, squadA: a, squadB: b) { focusComposer(proxy) }
                    } else if let s = p.squadId {
                        AttachedSquadCard(squadId: s)
                    }
                    if let a = p.attach { PostAttachCard(attach: a) }
                    if let c = p.contact { contactRow(c) }
                    actionRow(d, proxy: proxy)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 18)

                // 광고 — 본문 액션 줄(추천·댓글·공유) 뒤 · "댓글 N" 헤더 앞(AD-PLACEMENT 1-7).
                // 정렬 버튼 바로 밑에 있던 자리는 오탭 위험이 커서 옮겼다. 위는 본문 여백 18pt, 아래는 띠 + 헤더 여백.
                adBlock("community_detail").padding(.bottom, 8)

                // 8pt 띠 — 위아래 hair 를 붙이면 "이중선"으로 보였다(디자인 리뷰). 채움만 둔다.
                Rectangle().fill(FC.surface).frame(height: 8)

                comments(d, proxy: proxy).id("comments")
            }
        }
    }

    private func head(_ p: Post) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 목록과 같은 짧은 이름("평가") — 긴 이름("스쿼드 평가 요청")은 목록 태그와 달라 보였다.
            PostTag(text: PostTypeNames.short(p.type, types: [], label: p.typeLabel), color: PostFamily(type: p.type).color, closed: p.status == "closed")
            Text(p.title).cmText(20, .bold).kerning(-0.5).lineSpacing(5)
                .foregroundStyle(FC.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
                .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 0 } action: { gone in
                    guard gone != showNavTitle else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showNavTitle = gone }
                }
        }
    }

    private func authorRow(_ p: Post) -> some View {
        HStack(spacing: 10) {
            NickAvatar(nickname: p.author.nickname, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(p.author.nickname).cmText(14, .semibold).foregroundStyle(FC.ink).lineLimit(1)
                    if p.author.verifiedNickname != nil {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(FC.tint).accessibilityLabel("인증 구단주")
                    }
                    if p.author.isOperator == true { OperatorBadge() }
                }
                // 조회수는 v2 서버에서만 센다 — 혼합 서버(코드 v1)는 늘 0 이라 "조회 0"만 박혔다.
                Text([DateFmt.relative(p.createdAt), p.viewCount.flatMap { v in (model.serverV2 || v > 0) ? "조회 \(CMFormat.count(v))" : nil }].compactMap { $0 }.joined(separator: " · "))
                    .cmText(12).foregroundStyle(CM.faint)
            }
            Spacer(minLength: 8)
            if let v = p.author.verifiedNickname {
                Button { router.push(.user(v)) } label: {
                    HStack(spacing: 3) {
                        Text("전적 보기").cmText(13.5, .semibold)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(FC.tint)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(FC.tint.opacity(0.13), in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(v) 전적 보기")
            }
        }
    }

    /// 메타 표 — metaRows + 지역 + 포지션을 2열 그리드 카드로
    @ViewBuilder private func metaTable(_ p: Post) -> some View {
        let rows: [(String, AnyView)] = {
            var out: [(String, AnyView)] = (p.metaRows ?? []).map { r in
                (r.label, AnyView(Text(r.value).cmText(14, .semibold).foregroundStyle(FC.ink).fixedSize(horizontal: false, vertical: true)))
            }
            if let r = p.region { out.append(("지역", AnyView(Text(r).cmText(14, .semibold).foregroundStyle(FC.ink)))) }
            if !p.positions.isEmpty {
                out.append(("구하는 포지션", AnyView(FlowLayout(spacing: 4) {
                    ForEach(p.positions, id: \.self) { pos in
                        Text(pos).cmScore(12, .bold).foregroundStyle(CM.teal)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(CM.teal.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
                    }
                })))
            }
            return out
        }()
        if !rows.isEmpty {
            let pairs = stride(from: 0, to: rows.count, by: 2).map { Array(rows[$0..<min($0 + 2, rows.count)]) }
            VStack(spacing: 0) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
                    if i > 0 { Rectangle().fill(FC.line).frame(height: 1) }
                    HStack(spacing: 0) {
                        ForEach(Array(pair.enumerated()), id: \.offset) { j, cell in
                            if j > 0 { Rectangle().fill(FC.line).frame(width: 1) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cell.0).cmText(11.5).foregroundStyle(CM.faint)
                                cell.1
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        if pair.count == 1 && rows.count > 1 {
                            Rectangle().fill(FC.line).frame(width: 1)
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(FC.line, lineWidth: 1))
        }
    }

    private func contactRow(_ c: String) -> some View {
        HStack(spacing: 10) {
            Text("연락").cmText(12, .semibold).foregroundStyle(CM.faint)
            Text(c).cmText(14.5, .medium).foregroundStyle(FC.ink).textSelection(.enabled).lineLimit(2)
            Spacer()
            Button {
                UIPasteboard.general.string = c
                Haptic.light()
                showToast("연락처를 복사했어요")
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 14)).foregroundStyle(FC.tint)
                    .frame(width: 44, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("연락처 복사")
        }
        .padding(.leading, 14).padding(.vertical, 4)
        .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).stroke(FC.line, lineWidth: 1))
    }

    private func actionRow(_ d: PostDetailResponse, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            if let like = model.postLike, model.likesEnabled {
                Button { Task { await likePost() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: like.liked ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .symbolEffect(.bounce, value: like.liked)
                        Text("추천 \(like.count)").cmText(14.5, .semibold).contentTransition(.numericText())
                    }
                    .foregroundStyle(like.liked ? CM.coral : FC.ink)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(like.liked ? CM.coral.opacity(0.12) : Color.clear, in: Capsule())
                    .overlay(Capsule().stroke(like.liked ? CM.coral : FC.line, lineWidth: 1.2))
                }
                .buttonStyle(PressScaleStyle())
                .sensoryFeedback(.impact(weight: .light), trigger: like.liked)
                .accessibilityLabel(like.liked ? "추천함, \(like.count)" : "추천 \(like.count)")
            }
            Button { focusComposer(proxy) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left").font(.system(size: 15, weight: .medium))
                    Text("댓글 \(visibleComments(d).count)").cmText(14.5, .semibold)
                }
                .foregroundStyle(FC.ink)
                .padding(.horizontal, 16).frame(height: 38)
                .overlay(Capsule().stroke(FC.line, lineWidth: 1.2))
            }
            .buttonStyle(PressScaleStyle())
            Spacer()
            ShareLink(item: AppConfig.absolute("/community/\(d.post.id)")) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .offset(y: -1)
                    .frame(width: 38, height: 38)
                    .background(FC.brand, in: Circle())
            }
            .accessibilityLabel("글 공유")
        }
        .padding(.top, 4)
    }

    private func moreMenu(_ d: PostDetailResponse) -> some View {
        Menu {
            Button {
                UIPasteboard.general.string = AppConfig.absolute("/community/\(d.post.id)").absoluteString
                showToast("링크를 복사했어요")
            } label: { Label("링크 복사", systemImage: "link") }
            if d.viewer.isOwner {
                Button(role: .destructive) { confirmDeletePost = true } label: { Label("삭제", systemImage: "trash") }
            } else {
                Button { reportTarget = ReportTarget(type: "post", id: d.post.id) } label: { Label("신고", systemImage: "exclamationmark.bubble") }
                // 차단은 확인 후 실행 — 메뉴 한 번 탭에 바로 글이 가려졌다(QA 2R P2-9)
                Button(role: .destructive) { confirmBlockAuthor = true } label: { Label("작성자 차단", systemImage: "hand.raised") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(FC.ink)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("더보기")
        // 다이얼로그는 메뉴 자신에 건다 — 본문 뷰에는 alert 2개·신고 다이얼로그가 이미 걸려 있어 함께 두면 뜨지 않았다
        .confirmationDialog(post.map { "\($0.author.nickname)님을 차단할까요?" } ?? "작성자를 차단할까요?", isPresented: $confirmBlockAuthor, titleVisibility: .visible) {
            Button("차단", role: .destructive) {
                guard let p = post else { return }
                prefs.block(p.authorId); Haptic.warning()
                showToast("\(p.author.nickname)님을 차단했어요")
            }
            Button("취소", role: .cancel) {}
        } message: { Text("이 사람의 글과 댓글이 보이지 않아요. 설정에서 해제할 수 있어요.") }
    }

    // MARK: 댓글

    private func visibleComments(_ d: PostDetailResponse) -> [Comment] {
        d.comments.filter { !prefs.isBlocked($0.authorId) }
    }

    private func comments(_ d: PostDetailResponse, proxy: ScrollViewProxy) -> some View {
        let list = visibleComments(d)
        let threads = CommentThread.build(list, newestFirst: commentSort == "desc")
        let best = model.likesEnabled ? CommentThread.best(list) { model.commentLikes[$0.id]?.count } : []
        let bestIds = Set(best.map(\.id))
        let byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        // 광고 자리(하나): BEST 묶음 뒤. BEST 가 없으면 댓글 머리 바로 아래.
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                (Text("댓글 ").font(.cm(16, typeSize, .bold)).foregroundColor(FC.ink)
                 + Text("\(list.count)").font(.cmScore(16, typeSize, .bold)).foregroundColor(FC.tint))
                Spacer()
                if list.count > 1 {
                    HStack(spacing: 0) {
                        sortButton("asc", "등록순")
                        sortButton("desc", "최신순")
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)

            if list.isEmpty {
                VStack(spacing: 4) {
                    Text("아직 댓글이 없어요").cmText(15, .semibold).foregroundStyle(FC.ink)
                    Text("첫 댓글을 남겨 보세요").cmText(13).foregroundStyle(FC.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            }

            // BEST 복제본은 별도 id — ForEach 의 기본 id(c.id)를 쓰면 scrollTo(새 댓글)가 BEST 쪽으로 간다
            ForEach(best.map { ("best-\($0.id)", $0) }, id: \.0) { item in
                commentRow(item.1, d: d, best: true, parentNick: item.1.parentId.flatMap { byId[$0]?.author.nickname })
            }
            ForEach(Array(threads.enumerated()), id: \.element.id) { ti, t in
                // 루트 댓글 15개마다 1개(깊은 자리 — 받은 뒤 편다)
                if ti > 0, ti % 15 == 0 { CompactAdRow(placement: "community_detail_more", instance: "\(ti)").padding(.vertical, 8) }
                rootOrCollapsed(t.root, d: d, isBest: bestIds.contains(t.root.id))
                let showAll = t.replies.count <= 3 || expanded.contains(t.id)
                let shown = showAll ? t.replies : Array(t.replies.prefix(2))
                ForEach(shown) { r in
                    if bestIds.contains(r.id) && !expandedBest.contains(r.id) {
                        bestPlaceholder(r, reply: true)
                    } else {
                        // 마지막 답글이 아니거나 "더 보기"가 아래에 있으면 세로선을 잇는다
                        commentRow(r, d: d, reply: true, parentNick: t.root.author.nickname,
                                   continuesBelow: r.id != shown.last?.id || !showAll).id(r.id)
                    }
                }
                if !showAll {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { _ = expanded.insert(t.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Rectangle().fill(FC.line).frame(width: 26, height: 1)
                            Text("답글 \(t.replies.count - 2)개 더 보기").cmText(13, .semibold).foregroundStyle(FC.muted)
                        }
                        .padding(.leading, 58).frame(minHeight: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 24)
    }

    /// 상세 광고 — 목록과 같은 행형 배너(320×50, 컨테이너 B). 깊은 자리라 받은 뒤 편다(R4).
    private func adBlock(_ placement: String) -> some View {
        CompactAdRow(placement: placement)
    }

    /// 원래 자리 — BEST 로 올라간 댓글은 한 줄로 접는다(같은 글이 한 화면에 두 번 보이면 버그처럼 읽혔다 · 디자인 M4).
    @ViewBuilder private func rootOrCollapsed(_ c: Comment, d: PostDetailResponse, isBest: Bool) -> some View {
        if isBest && !expandedBest.contains(c.id) {
            bestPlaceholder(c, reply: false)
        } else {
            commentRow(c, d: d).id(c.id)
        }
    }

    /// 접힌 줄에도 **주인**(22pt 아바타 + 닉)을 밝힌다. 주인이 없으면 아래 답글들이 바로 위 다른 사람 댓글의 답글처럼
    /// 읽혔다(디자인 2R R2-1). 아바타는 원래 댓글 아바타 열(루트 30pt · 답글 24pt)의 가운데에 맞춰 답글 들여쓰기와 이어진다.
    private func bestPlaceholder(_ c: Comment, reply: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { _ = expandedBest.insert(c.id) }
        } label: {
            HStack(spacing: reply ? 10 : 12) {
                NickAvatar(nickname: c.author.nickname, size: 22).frame(width: reply ? 24 : 30)
                HStack(spacing: 4) {
                    Text(c.author.nickname).cmText(13, .semibold).foregroundStyle(FC.ink.opacity(0.75)).lineLimit(1)
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold))
                    Text("BEST로 올라간 댓글 · 펼치기").cmText(13).lineLimit(1).minimumScaleFactor(0.85)
                }
                .foregroundStyle(CM.faint)
                Spacer(minLength: 0)
            }
            .padding(.leading, reply ? 54 : 16).padding(.trailing, 16)
            .frame(minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(c.id)
        .accessibilityLabel("\(c.author.nickname)님의 댓글, 베스트 댓글로 올라감. 펼치기")
    }

    private func sortButton(_ key: String, _ label: String) -> some View {
        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { commentSort = key } } label: {
            Text(label).cmText(13, commentSort == key ? .semibold : .regular)
                .foregroundStyle(commentSort == key ? FC.ink : CM.faint)
                .padding(.horizontal, 7).frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(commentSort == key ? .isSelected : [])
    }

    private func commentRow(_ c: Comment, d: PostDetailResponse, best: Bool = false, reply: Bool = false, parentNick: String? = nil, continuesBelow: Bool = false) -> some View {
        CommentRow(
            comment: c, isReply: reply && !best, continuesBelow: continuesBelow, isBest: best,
            isPostAuthor: c.authorId == d.post.authorId,
            parentNick: parentNick,
            like: model.likesEnabled ? model.commentLikes[c.id] : nil,
            highlighted: highlightComment == c.id,
            onLike: { Task { await likeComment(c.id) } },
            onReply: { startReply(c) },
            onDelete: { confirmDeleteComment = c.id },
            onReport: { reportTarget = ReportTarget(type: "comment", id: c.id) },
            onBlock: { prefs.block(c.authorId); Haptic.warning(); showToast("\(c.author.nickname)님을 차단했어요") },
            onCopy: { UIPasteboard.general.string = c.body; showToast("댓글을 복사했어요") }
        )
    }

    // MARK: 입력창

    private func composer(_ d: PostDetailResponse, proxy: ScrollViewProxy) -> some View {
        let gate: CommentComposer.Gate = d.viewer.canComment ? .ready : (d.viewer.loggedIn || CommunityAPI.isLoggedIn) ? .nickname : .login
        return CommentComposer(
            gate: gate, text: $text,
            replyNick: model.repliesEnabled ? replyTo?.author.nickname : nil,
            squadName: attach?.name, sending: sending, focus: $composerFocused,
            onLogin: { showLogin = true },
            onNickname: { router.tab = .me },
            onCancelReply: { replyTo = nil },
            onAttach: { showSquadPicker = true },
            onRemoveSquad: { attach = nil },
            onSend: { Task { await submit(proxy) } }
        )
    }

    private func focusComposer(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo("comments", anchor: .top) }
        if model.detail?.viewer.canComment == true { composerFocused = true }
    }

    private func startReply(_ c: Comment) {
        guard model.detail?.viewer.canComment == true else {
            if model.detail?.viewer.loggedIn == true { router.tab = .me } else { showLogin = true }
            return
        }
        if model.repliesEnabled {
            replyTo = c
        } else {
            // parent_id 를 모르는 서버 — @닉 을 미리 채우는 것으로 대신한다(SPEC 7절)
            let tag = "@\(c.author.nickname) "
            if !text.hasPrefix(tag) { text = tag + text }
        }
        composerFocused = true
    }

    private func submit(_ proxy: ScrollViewProxy) async {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        var parentId: String?
        if let r = replyTo, model.repliesEnabled {
            // 1단 평면화 — 답글의 답글은 원 댓글에 붙이고, 대상은 @멘션으로 남긴다
            parentId = r.parentId ?? r.id
            if r.parentId != nil, !body.hasPrefix("@") { body = "@\(r.author.nickname) " + body }
        }
        sending = true
        defer { sending = false }
        do {
            let newId = try await CommunityAPI.addComment(postId: postId, body: body, squadId: attach?.id, parentId: parentId)
            text = ""; replyTo = nil; attach = nil
            composerFocused = false
            Haptic.success()
            await model.load()
            if let newId {
                if let p = parentId { expanded.insert(p) }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo(newId, anchor: .center) }
                highlightComment = newId
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { highlightComment = nil }
            }
        } catch APIError.unauthorized {
            showLogin = true
        } catch {
            showToast(error.localizedDescription)
            Haptic.warning()
        }
    }

    // MARK: 동작

    private func likePost() async {
        guard model.detail?.viewer.loggedIn == true || CommunityAPI.isLoggedIn else { showLogin = true; return }
        handle(await model.togglePostLike())
    }
    private func likeComment(_ id: String) async {
        guard model.detail?.viewer.loggedIn == true || CommunityAPI.isLoggedIn else { showLogin = true; return }
        handle(await model.toggleCommentLike(id))
    }
    private func handle(_ o: PostDetailModel.LikeOutcome) {
        switch o {
        case .ok: break
        case .login: showLogin = true
        case .failed(let m): showToast(m)
        }
    }

    private func deleteComment(_ id: String) async {
        do { try await CommunityAPI.deleteComment(postId: postId, commentId: id); await model.load() }
        catch { showToast(error.localizedDescription) }
    }
    private func deletePost() async {
        do { try await CommunityAPI.deletePost(postId); dismiss() }
        catch { showToast(error.localizedDescription) }
    }

    private func showToast(_ s: String) {
        withAnimation { toast = s }
        Task { try? await Task.sleep(for: .seconds(2.2)); withAnimation { if toast == s { toast = nil } } }
    }
}

// MARK: - 본문(링크 자동 인식)

struct LinkedBody: View {
    let text: String
    /// 빈 줄로 나눈 문단 — 빈 줄을 그대로 두면 26pt 줄 높이가 통째로 벌어졌다. 문단 사이는 10pt(디자인 M5).
    private var paragraphs: [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return parts.isEmpty ? [text] : parts
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                Text(Self.attributed(para))
                    .cmText(16)
                    .lineSpacing(7)
                    .kerning(-0.3)
                    .foregroundStyle(CM.ink2)
                    .tint(FC.tint)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    static func attributed(_ text: String) -> AttributedString {
        var a = AttributedString(text)
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
        let ns = text as NSString
        for m in det.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = m.url, let r = Range(m.range, in: text), let ar = Range(r, in: a) else { continue }
            a[ar].link = url
            a[ar].foregroundColor = FC.tint
        }
        return a
    }
}

// MARK: - 첨부 스쿼드 카드(미니 피치)

struct AttachedSquadCard: View {
    let squadId: String
    @State private var squad: Squad?
    @State private var failed = false
    @Environment(AppRouter.self) private var router
    var body: some View {
        Button { router.push(.squad(squadId)) } label: {
            HStack(spacing: 14) {
                MiniPitch(squad: squad).frame(width: 52, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("첨부 스쿼드").cmText(12).foregroundStyle(CM.faint)
                    Text(squad?.name ?? (failed ? "첨부 스쿼드 보기" : " ")).cmText(15, .semibold).foregroundStyle(FC.ink).lineLimit(1)
                    if let s = squad {
                        Text("\(Formation.get(s.formation).name) · \(s.slots.count)명").cmText(13).foregroundStyle(CM.faint)
                        // 썸네일은 점뿐이라 들어가 보기 전엔 정보가 없었다(유저 패널 C) — 앞선 3명 이름을 붙인다.
                        if !Self.keyPlayers(s).isEmpty {
                            Text(Self.keyPlayers(s).joined(separator: " · ")).cmText(12.5, .medium).foregroundStyle(FC.ink).lineLimit(1)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.muted)
            }
            .padding(12)
            .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(FC.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("첨부 스쿼드 \(squad?.name ?? ""). 열기")
        .task {
            do { squad = try await CommunityAPI.squad(squadId) } catch { failed = true }
        }
    }

    /// 공격 쪽(포메이션 좌표 y 가 작은 쪽)부터 3명 — 스쿼드 얼굴이 되는 선수들
    static func keyPlayers(_ s: Squad) -> [String] {
        let def = Dictionary(Formation.get(s.formation).slots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return s.slots
            .filter { !$0.name.isEmpty }
            .sorted { ($0.y ?? def[$0.slotId]?.y ?? 50) < ($1.y ?? def[$1.slotId]?.y ?? 50) }
            .prefix(3).map(\.name)
    }
}

/// 52×64 썸네일 — 슬롯 좌표(없으면 포메이션 기본 좌표)에 점
struct MiniPitch: View {
    let squad: Squad?
    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    // 스쿼드 빌더 피치와 같은 잔디색 — 채도 높은 #1E6B35 는 팔레트 밖이었다(디자인 M5)
                    .fill(LinearGradient(colors: [FC.pitchTop, FC.pitchBottom], startPoint: .top, endPoint: .bottom))
                if let s = squad {
                    let f = Formation.get(s.formation)
                    let def = Dictionary(f.slots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    ForEach(s.slots) { slot in
                        let x = slot.x ?? def[slot.slotId]?.x ?? 50
                        let y = slot.y ?? def[slot.slotId]?.y ?? 50
                        Circle().fill(Color.white.opacity(0.85)).frame(width: 6, height: 6)
                            .position(x: g.size.width * x / 100, y: g.size.height * (y * 0.88 + 6) / 100)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
