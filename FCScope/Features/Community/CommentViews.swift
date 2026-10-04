import SwiftUI

// MARK: - 스레드 구성

/// 평면 댓글 + 1단 답글(SPEC 7절). `parentId` 가 없는 서버면 전부 최상위로 그린다.
struct CommentThread: Identifiable {
    let root: Comment
    var replies: [Comment]
    var id: String { root.id }

    static func build(_ comments: [Comment], newestFirst: Bool) -> [CommentThread] {
        let asc = comments.sorted { $0.createdAt < $1.createdAt }
        let ids = Set(asc.map(\.id))
        var roots: [Comment] = []
        var replies: [String: [Comment]] = [:]
        for c in asc {
            if let p = c.parentId, ids.contains(p) { replies[p, default: []].append(c) } else { roots.append(c) }
        }
        if newestFirst { roots.reverse() }
        return roots.map { CommentThread(root: $0, replies: replies[$0.id] ?? []) }
    }

    /// BEST — 댓글 8개 이상인 글에서 추천 5 이상 상위 2개(디자인 리뷰 M4: 5개·3추천은 너무 흔하게 떴다).
    /// 원래 자리는 한 줄("BEST로 올라간 댓글 · 펼치기")로 접는다 — 같은 글이 한 화면에 두 번 보이면 버그처럼 읽혔다.
    static let minComments = 8
    static let minLikes = 5
    static func best(_ comments: [Comment], likes: (Comment) -> Int?) -> [Comment] {
        guard comments.count >= minComments else { return [] }
        var scored: [(c: Comment, n: Int)] = []
        for c in comments { if let n = likes(c), n >= minLikes { scored.append((c, n)) } }
        scored.sort { a, b in a.n != b.n ? a.n > b.n : a.c.createdAt < b.c.createdAt }
        return scored.prefix(2).map { $0.c }
    }
}

/// 댓글 하트 상태(낙관적 업데이트 오버레이)
struct LikeState: Equatable { var liked: Bool; var count: Int }

// MARK: - 댓글 행

struct CommentRow: View {
    let comment: Comment
    var isReply = false
    /// 아래에 형제 답글이 더 있다 — 세로선을 행 끝까지 이어 답글끼리 한 줄로 잇는다(디자인 3R 4-3: 답글마다 ㄴ 이 끊겼다)
    var continuesBelow = false
    var isBest = false
    /// 글쓴이가 단 댓글 — `작성자` 배지
    var isPostAuthor = false
    /// 답글일 때 원 댓글 닉 — 본문 앞 @멘션
    var parentNick: String?
    var like: LikeState?
    var highlighted = false
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onCopy: () -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: isReply ? 10 : 12) {
            NickAvatar(nickname: comment.author.nickname, size: isReply ? 24 : 30)
                .padding(.top, isReply ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                header
                bodyText
                if let s = comment.squadId {
                    Button { router.push(.squad(s)) } label: {
                        Label { Text("제안 스쿼드 보기").cmText(13, .semibold) } icon: { Image(systemName: "shield.fill").font(.system(size: 12)) }
                            .foregroundStyle(FC.tint)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(FC.tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
                actions
            }
        }
        // 좌우 16 하나로 — 행 trailing 6 + 본문 trailing 10 조합이 빌드·경로마다 6pt 로 붙던 버그(디자인 M3)
        .padding(.leading, isReply ? 54 : 16).padding(.trailing, 16)
        .padding(.top, 10).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            if highlighted { FC.tint.opacity(0.12) }
        }
        // BEST — 채움 없이 왼쪽 2pt 골드 바만(인디고 위 골드 12% 채움이 탁한 갈색·살구색이 됐다 · 디자인 M4)
        .overlay(alignment: .leading) {
            if isBest { Rectangle().fill(Self.bestGold).frame(width: 2).padding(.vertical, 6) }
        }
        .overlay(alignment: .topLeading) {
            if isReply && continuesBelow {
                Rectangle().fill(FC.line).frame(width: 1.5).frame(maxHeight: .infinity).padding(.leading, 30.25)
            }
        }
        .overlay(alignment: .topLeading) {
            if isReply { ReplyConnector().stroke(FC.line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 20, height: 23).padding(.leading, 31) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityAction(named: "답글 달기", onReply)
        .accessibilityAction(named: like?.liked == true ? "추천 취소" : "추천") { if like != nil { onLike() } }
        .accessibilityAction(named: comment.isOwn ? "삭제" : "신고") { comment.isOwn ? onDelete() : onReport() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if isBest {
                // 다크·라이트 공통 #F7C948 채움 + #3A2A00 글자(대비 9:1) — 두 모드에서 같은 배지
                Text("BEST").cmScore(11, .bold).foregroundStyle(Self.bestInk)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Self.bestGold, in: RoundedRectangle(cornerRadius: 4))
            }
            Text(comment.author.nickname).cmText(13, .semibold).foregroundStyle(FC.ink).lineLimit(1)
            if comment.author.verifiedNickname != nil {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(FC.tint).accessibilityLabel("인증")
            }
            if isPostAuthor {
                Text("작성자").cmText(11, .semibold).foregroundStyle(FC.tint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(FC.tint, lineWidth: 1))
                    .fixedSize()
            }
            if comment.author.isOperator == true { OperatorBadge() }
            Text(DateFmt.relative(comment.createdAt)).cmText(12).foregroundStyle(CM.faint).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            menu
        }
        .frame(minHeight: 20)
    }

    private var menu: some View {
        Menu {
            Button(action: onCopy) { Label("복사", systemImage: "doc.on.doc") }
            if comment.isOwn {
                Button(role: .destructive, action: onDelete) { Label("삭제", systemImage: "trash") }
            } else {
                Button(action: onReport) { Label("신고", systemImage: "exclamationmark.bubble") }
                Button(role: .destructive, action: onBlock) { Label("작성자 차단", systemImage: "hand.raised") }
            }
        } label: {
            // 탭 영역 44×44(HIG) — 레이아웃 높이는 머리 줄(20)만 차지하게 음수 패딩, 점 아이콘은 본문 오른쪽 끝과 맞춘다
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(CM.faint)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .padding(.vertical, -12).padding(.trailing, -14)
        .accessibilityLabel("\(comment.author.nickname) 댓글 더보기")
    }

    /// `@닉` 으로 시작하면 그 부분을 tint SemiBold. 답글인데 멘션이 없으면 원 댓글 닉을 앞에 붙인다.
    private var bodyText: some View {
        var mention: String?
        var rest = comment.body
        if comment.body.hasPrefix("@"), let sp = comment.body.firstIndex(where: { $0 == " " || $0 == "\n" }) {
            mention = String(comment.body[..<sp])
            rest = String(comment.body[sp...])
        } else if isReply, let p = parentNick {
            mention = "@\(p)"
            rest = " " + comment.body
        }
        let t = (mention.map { Text($0).font(.cm(15, typeSize, .semibold)).foregroundColor(FC.tint) } ?? Text(""))
            + Text(rest).font(.cm(15, typeSize)).foregroundColor(CM.ink2)
        return t.lineSpacing(4).kerning(-0.2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    /// 행동 줄 — 보이는 높이 26, 탭 영역은 위아래로 넓혀 44(디자인 M2: 한 줄 댓글 105 → 약 80pt)
    private var actions: some View {
        HStack(spacing: 18) {
            if let like {
                Button(action: onLike) {
                    HStack(spacing: 5) {
                        Image(systemName: like.liked ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .symbolEffect(.bounce, value: like.liked)
                        // 0 이면 숫자를 숨긴다 — "♡ 0" 이 줄마다 깔리면 회색 숫자만 늘었다
                        if like.count > 0 {
                            Text("\(like.count)").cmText(13, .medium).contentTransition(.numericText())
                        }
                    }
                    .foregroundStyle(like.liked ? CM.coral : CM.faint)
                    .frame(minWidth: 28, minHeight: 26, alignment: .leading)
                    .contentShape(Rectangle().inset(by: -9))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: like.liked)
                .accessibilityLabel(like.liked ? "추천함, \(like.count)" : "추천 \(like.count)")
            }
            Button(action: onReply) {
                Text("답글 달기").cmText(12.5, .medium).foregroundStyle(CM.faint)
                    .frame(minHeight: 26).contentShape(Rectangle().inset(by: -9))
            }
            .buttonStyle(.plain)
        }
    }

    static let bestGold = Color(UIColor(hex: 0xF7C948))
    static let bestInk = Color(UIColor(hex: 0x3A2A00))

    private var a11yLabel: String {
        var s = comment.author.nickname
        if isBest { s += ", 베스트 댓글" }
        if isPostAuthor { s += ", 작성자" }
        if comment.author.isOperator == true { s += ", 운영자" }
        s += ", \(DateFmt.relative(comment.createdAt)). \(comment.body)"
        if let like { s += ". 추천 \(like.count)" }
        return s
    }
}

/// 답글 왼쪽 `ㄴ` 연결선
struct ReplyConnector: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: r.height - 8))
        p.addQuadCurve(to: CGPoint(x: 8, y: r.height), control: CGPoint(x: 0, y: r.height))
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        return p
    }
}

// MARK: - 바닥 고정 입력창

struct CommentComposer: View {
    enum Gate { case login, nickname, ready }
    let gate: Gate
    @Binding var text: String
    var replyNick: String?
    var squadName: String?
    var sending: Bool
    var focus: FocusState<Bool>.Binding
    let onLogin: () -> Void
    let onNickname: () -> Void
    let onCancelReply: () -> Void
    let onAttach: () -> Void
    let onRemoveSquad: () -> Void
    let onSend: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private let maxLen = 1000

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(CM.hair).frame(height: 1)
            switch gate {
            case .login:
                gateButton("로그인하고 댓글 달기", action: onLogin)
            case .nickname:
                gateButton("닉네임 등록하고 댓글 달기 →", action: onNickname)
            case .ready:
                ready
            }
        }
        .background(.bar)
    }

    private func gateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).cmText(15, .semibold).foregroundStyle(FC.tint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(FC.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyNick {
                HStack {
                    (Text("@\(replyNick)").font(.cm(13, typeSize, .semibold)).foregroundColor(FC.tint)
                     + Text("님에게 답글").font(.cm(13, typeSize)).foregroundColor(FC.muted))
                    Spacer()
                    Button(action: onCancelReply) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.muted)
                            .frame(width: 36, height: 28).contentShape(Rectangle())
                    }
                    .accessibilityLabel("답글 취소")
                }
                .padding(.horizontal, 16).padding(.top, 6)
            }
            if let squadName {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill").font(.system(size: 11))
                    Text(squadName).cmText(12.5, .semibold).lineLimit(1)
                    Button(action: onRemoveSquad) { Image(systemName: "xmark.circle.fill").font(.system(size: 13)) }
                        .accessibilityLabel("첨부 스쿼드 빼기")
                }
                .foregroundStyle(FC.tint)
                .padding(.horizontal, 10).frame(height: 26)
                .background(FC.tint.opacity(0.12), in: Capsule())
                .padding(.horizontal, 16).padding(.top, replyNick == nil ? 6 : 0)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    Image(systemName: "shield.fill").font(.system(size: 19))
                        .foregroundStyle(squadName != nil ? FC.tint : CM.faint)
                        .frame(width: 36, height: 40).contentShape(Rectangle())
                }
                .accessibilityLabel("내 스쿼드 첨부")
                ZStack(alignment: .bottomTrailing) {
                    TextField("댓글 달기…", text: $text, axis: .vertical)
                        .cmText(15)
                        .lineLimit(1...5)
                        .focused(focus)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .padding(.trailing, text.count > 300 ? 40 : 0)
                        .frame(minHeight: 40)
                        .background(FC.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onChange(of: text) { _, v in if v.count > maxLen { text = String(v.prefix(maxLen)) } }
                    if text.count > 300 {
                        Text("\(maxLen - text.count)").cmScore(11).foregroundStyle(text.count > 950 ? CM.coral : CM.faint)
                            .padding(.trailing, 12).padding(.bottom, 11)
                    }
                }
                Button(action: onSend) {
                    ZStack {
                        if trimmed.isEmpty { Circle().fill(FC.surface2) } else { Circle().fill(FC.brand) }
                        if sending { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(trimmed.isEmpty ? CM.faint : .white) }
                    }
                    .frame(width: 40, height: 40)
                }
                .disabled(trimmed.isEmpty || sending)
                .accessibilityLabel("댓글 등록")
            }
            .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 8)
        }
    }
}

// MARK: - 내 스쿼드 고르기(댓글·글쓰기 공용)

struct SquadPickerSheet: View {
    let onPick: (_ id: String, _ name: String) -> Void
    @State private var state: Loadable<[ProfileResponse.MySquad]> = .idle
    @State private var code = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    switch state {
                    case .idle, .loading: HStack { Spacer(); ProgressView(); Spacer() }
                    case .failed: Text("내 스쿼드를 불러오지 못했어요").cmText(14).foregroundStyle(FC.muted)
                    case .loaded(let squads):
                        if squads.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("저장한 스쿼드가 없어요").cmText(15, .semibold).foregroundStyle(FC.ink)
                                Text("스쿼드 탭에서 만들고 저장하면 여기서 고를 수 있어요").cmText(13).foregroundStyle(FC.muted)
                            }
                        }
                        ForEach(squads) { s in
                            Button { onPick(s.id, s.name); dismiss() } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "shield.fill").foregroundStyle(FC.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name).cmText(15, .semibold).foregroundStyle(FC.ink)
                                        Text(Formation.get(s.formation).name).cmText(12.5).foregroundStyle(CM.faint)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CM.faint)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                } header: { Text("내 스쿼드").cmText(13, .semibold) }
                .listRowBackground(FC.surface)

                Section {
                    HStack {
                        TextField("공유코드 붙여넣기", text: $code)
                            .cmText(15)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("첨부") {
                            let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
                            onPick(c, "공유코드 \(c)"); dismiss()
                        }
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^[A-Za-z0-9]{1,32}$", options: .regularExpression) == nil)
                    }
                } header: { Text("다른 스쿼드").cmText(13, .semibold) } footer: {
                    Text("스쿼드 빌더의 공유 링크 끝 코드를 붙여 넣어요").cmText(12).foregroundStyle(CM.faint)
                }
                .listRowBackground(FC.surface)
            }
            .scrollContentBackground(.hidden)
            .background(FC.bg.ignoresSafeArea())
            .navigationTitle("스쿼드 첨부").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .task {
                state = .loading
                do { state = .loaded(try await CommunityAPI.profile().squads) } catch { state = .failed(error) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
