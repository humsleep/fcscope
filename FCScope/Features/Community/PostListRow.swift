import SwiftUI

/// 목록 행 — "제목 한 줄 + 메타 한 줄"(SPEC 5절, mockups 01-list-a/b)
///
/// ```
/// [평가] 도르트문트 팀컬러 4-2-3-1 평가 부탁드려요 🛡 [12]
/// 보엠✓ · 3분 전 · 추천 9
/// ```
/// 조회수는 목록에서 뺐다(유저 패널 합의: 회색 숫자가 많아진다) — 상세 작성자 줄에만 둔다.
struct PostListRow: View {
    let post: Post
    let types: [PostTypeInfo]
    var read = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var cprefs = CommunityPrefs.shared

    private var family: PostFamily { PostFamily(type: post.type) }
    /// 상세에서 확인한 실제 댓글 수 기준(서버 카운터는 숨김 댓글까지 센다)
    private var commentCount: Int? { cprefs.displayCommentCount(post) }
    private var shortName: String { PostTypeNames.short(post.type, types: types, label: post.typeLabel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 7) {
                PostTag(text: shortName, color: family.color, closed: post.status == "closed")
                Text(post.title)
                    .cmText(15, .medium)
                    .foregroundStyle(read ? FC.muted : FC.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if post.squadId != nil {
                    Image(systemName: "shield.fill").font(.system(size: 13 * TypeScale.factor(typeSize)))
                        .foregroundStyle(CM.faint).accessibilityHidden(true)
                }
                if let n = commentCount, n > 0 {
                    Text("[\(n)]").cmScore(13).foregroundStyle(FC.tint).fixedSize()
                }
                Spacer(minLength: 0)
            }
            meta
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(CM.hair).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint("글 열기. 길게 누르면 공유·신고·차단")
    }

    private var meta: some View {
        HStack(spacing: 4) {
            PostMetaLine(post: post, showNick: true)
        }
    }

    private var a11yLabel: String {
        var parts = ["\(post.typeLabel). \(post.title)"]
        if post.status == "closed" { parts.append("마감") }
        if post.squadId != nil { parts.append("스쿼드 첨부") }
        if let n = commentCount, n > 0 { parts.append("댓글 \(n)개") }
        parts.append("\(post.author.nickname), \(DateFmt.relative(post.createdAt))")
        if cprefs.serverV2, let l = post.likeCount, l > 0 { parts.append("추천 \(l)") }
        if read { parts.append("읽음") }
        return parts.joined(separator: ". ")
    }
}

/// 메타 한 줄 — 닉 ✓ 운영자 · 시간 · 추천 N · 지역 (추천은 v2 서버에서만)
struct PostMetaLine: View {
    let post: Post
    var showNick = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var cprefs = CommunityPrefs.shared

    var body: some View {
        HStack(spacing: 0) {
            if showNick {
                (Text(post.author.nickname).font(.cm(12, typeSize, .medium)).foregroundColor(FC.muted)
                 + Text(post.author.verifiedNickname != nil ? " ✓" : "").font(.cm(11, typeSize, .bold)).foregroundColor(FC.tint))
                    .lineLimit(1)
                if post.author.isOperator == true { OperatorBadge().padding(.leading, 4) }
            }
            rest.lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    private var rest: Text {
        let dot = Text(" · ").font(.cm(12, typeSize)).foregroundColor(CM.faint)
        var t = (showNick ? dot : Text("")) + Text(DateFmt.relative(post.createdAt)).font(.cm(12, typeSize)).foregroundColor(CM.faint)
        if cprefs.serverV2, let l = post.likeCount, l > 0 {
            let hot = l >= 50
            t = t + (hot ? Text(" · ").font(.cm(12, typeSize)).foregroundColor(CM.coral) : dot)
                + Text("추천 \(CMFormat.count(l))").font(.cm(12, typeSize, hot ? .bold : .regular)).foregroundColor(hot ? CM.coral : CM.faint)
        }
        if let r = post.region {
            t = t + dot + Text(r).font(.cm(12, typeSize)).foregroundColor(CM.faint)
        }
        return t
    }
}

/// "🔥 지금 뜨는 글" 3줄 상자 — 전체 탭 상단(서버 hot 이 없으면 그리지 않는다)
struct HotBox: View {
    let posts: [Post]
    let open: (Post) -> Void
    let more: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label { Text("지금 뜨는 글").cmText(13, .bold) } icon: { Image(systemName: "flame.fill").font(.system(size: 12, weight: .bold)) }
                    .foregroundStyle(CM.coral)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: more) {
                    Text("더보기").cmText(12.5, .medium).foregroundStyle(CM.faint).frame(minHeight: 32).contentShape(Rectangle())
                }
                .accessibilityLabel("인기 글 더보기")
            }
            ForEach(Array(posts.prefix(3).enumerated()), id: \.element.id) { i, p in
                Button { open(p) } label: {
                    HStack(spacing: 12) {
                        Text("\(i + 1)").cmScore(15, .bold).foregroundStyle(CM.coral).frame(width: 14)
                        Text(p.title).cmText(14, .medium).foregroundStyle(FC.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        if let n = CommunityPrefs.shared.displayCommentCount(p), n > 0 { Text("[\(n)]").cmScore(13).foregroundStyle(FC.tint).fixedSize() }
                    }
                    .frame(minHeight: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i + 1)위. \(p.title). 댓글 \(p.commentCount ?? 0)개")
            }
        }
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 10)
        .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(FC.line, lineWidth: 1))
    }
}

/// 길게 누르기 미리보기 — 제목 + 본문 3줄
struct PostPreviewCard: View {
    let post: Post
    let types: [PostTypeInfo]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostTag(text: PostTypeNames.short(post.type, types: types, label: post.typeLabel), color: PostFamily(type: post.type).color, closed: post.status == "closed")
            Text(post.title).cmText(18, .bold).foregroundStyle(FC.ink).fixedSize(horizontal: false, vertical: true)
            Text(post.preview ?? post.body).cmText(15).lineSpacing(5).foregroundStyle(CM.ink2).lineLimit(3)
            PostMetaLine(post: post)
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(FC.surface)
    }
}
