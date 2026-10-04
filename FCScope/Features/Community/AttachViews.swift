import SwiftUI

// MARK: - 글 첨부: 내 전적 카드 · VS 카드
//
// 서버에는 구단주명(과 모드)만 저장한다(`PostAttach` — meta.attach_*). 카드는 상세를 열 때마다 최신 전적으로 그린다.
// 같은 전적 응답 캐시(디스크)를 쓰므로 전적·VS 화면을 본 적 있는 구단주는 네트워크 없이 바로 그려진다.

/// 상세 화면의 첨부 카드 — 탭하면 전적(record) / VS 화면(versus)으로.
struct PostAttachCard: View {
    let attach: PostAttach
    @Environment(AppRouter.self) private var router
    @State private var a: UserOverview?
    @State private var b: UserOverview?
    @State private var failed = false

    var body: some View {
        Button {
            switch attach.kind {
            case .record: router.push(.user(attach.me))
            case .versus: router.push(.versus(me: attach.me, type: attach.mode, with: attach.with))
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: attach.kind == .versus ? "person.2.fill" : "chart.bar.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.tint)
                    Text(attach.kind == .versus ? "VS 카드" : "전적 카드").cmText(12.5, .semibold).foregroundStyle(FC.tint)
                    Text("· \(Self.modeName(attach.mode)) 최근 30경기").cmText(12).foregroundStyle(CM.faint)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.muted)
                }
                switch attach.kind {
                case .record: recordBody
                case .versus: versusBody
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(FC.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(attach.kind == .versus ? "VS 화면을 열어요" : "전적을 열어요")
        .task(id: attach) { await load() }
    }

    // 내 전적: 닉 + 폼 티어 / 승률 · 경기당 득실 / 요즘 흐름
    @ViewBuilder private var recordBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(attach.me).cmText(18, .bold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.7)
            if let o = a, o.summary.played > 0 { FormTierBadge(tier: o.formTier, size: .compact) }
        }
        if let o = a {
            if o.summary.played == 0 {
                Text("이 모드는 최근 기록이 없어요").cmText(13).foregroundStyle(FC.muted)
            } else {
                HStack(spacing: 8) {
                    stat("승률", "\(o.summary.winRate)%")
                    stat("경기당 득점", String(format: "%.1f", o.goalsForPerGame))
                    stat("경기당 실점", String(format: "%.1f", o.goalsAgainstPerGame))
                }
                if let t = o.diagnosis.type {
                    (Text("요즘 흐름 ").foregroundStyle(CM.faint) + Text(t.title).foregroundStyle(FC.ink).bold())
                        .cmText(13).lineLimit(1)
                }
            }
        } else if failed {
            Text("전적을 불러오지 못했어요 · 눌러서 열기").cmText(13).foregroundStyle(FC.muted)
        } else {
            Skeleton(height: 54)
        }
    }

    // VS: 닉 vs 닉 + 이긴 항목 수 + 판정
    @ViewBuilder private var versusBody: some View {
        let other = attach.with ?? ""
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(attach.me).cmText(18, .bold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text("vs").cmText(14, .semibold).foregroundStyle(FC.muted)
            Text(other).cmText(18, .bold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.6)
        }
        if let x = a, let y = b {
            if x.summary.played == 0 || y.summary.played == 0 {
                Text("한쪽의 최근 기록이 없어 비교할 수 없어요").cmText(13).foregroundStyle(FC.muted)
            } else {
                let c = VersusComparison(a: x, b: y)
                let (l, r) = c.tally
                HStack(spacing: 10) {
                    (Text("\(l)").foregroundStyle(l >= r ? FC.ink : FC.muted) + Text(" · ").foregroundStyle(FC.muted) + Text("\(r)").foregroundStyle(r >= l ? FC.ink : FC.muted))
                        .fcScoreboard(22)
                    Text("이긴 항목").cmText(12).foregroundStyle(CM.faint)
                    Spacer(minLength: 4)
                    Text(c.verdict).cmText(13, .bold).foregroundStyle(l == r ? FC.tint : FC.gold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(l == r ? FC.tint : FC.gold, lineWidth: 1.2))
                }
                HStack(spacing: 8) {
                    stat("승률", "\(x.summary.winRate)% · \(y.summary.winRate)%")
                    stat("폼 티어", "\(x.formTier.level?.name ?? "배치") · \(y.formTier.level?.name ?? "배치")")
                }
            }
        } else if failed {
            Text("전적을 불러오지 못했어요 · 눌러서 열기").cmText(13).foregroundStyle(FC.muted)
        } else {
            Skeleton(height: 54)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).fcScoreboard(15).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).cmText(11.5).foregroundStyle(CM.faint).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FC.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func load() async {
        let other = attach.with
        async let x = Self.overview(attach.me, mode: attach.mode)
        async let y: UserOverview? = { if let o = other { return await Self.overview(o, mode: attach.mode) }; return nil }()
        let (ra, rb) = await (x, y)
        a = ra; b = rb
        failed = ra == nil || (attach.kind == .versus && rb == nil)
    }

    /// 전적 화면과 같은 경로·쿼리 — 디스크 캐시를 공유한다. 실패하면 nil.
    static func overview(_ nick: String, mode: Int) async -> UserOverview? {
        let enc = nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick
        let path = "/api/v1/user/\(enc)", q = ["type": String(mode)]
        if let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path, query: q), hit.isFresh { return hit.value }
        return try? await APIClient.shared.getAndCache(path, query: q, auth: false)
    }

    static func modeName(_ m: Int) -> String { m == 52 ? "감독모드" : m == 40 ? "클래식 1on1" : "공식경기" }
}

/// 글쓰기 — 첨부 고르기. 내 구단주명(설정)으로 채워 두고, VS 는 상대 구단주명을 받는다.
struct AttachPickerSheet: View {
    var initial: PostAttach?
    let onPick: (PostAttach) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PostAttach.Kind = .record
    @State private var me = ""
    @State private var other = ""
    @State private var mode = 50

    private static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
        guard (1...20).contains(t.count), t.range(of: #"[\s/\\?#%&<>"'`]"#, options: .regularExpression) == nil else { return nil }
        return t
    }
    private var result: PostAttach? {
        guard let m = Self.clean(me) else { return nil }
        if kind == .versus {
            guard let o = Self.clean(other), o.caseInsensitiveCompare(m) != .orderedSame else { return nil }
            return PostAttach(kind: .versus, me: m, with: o, mode: mode)
        }
        return PostAttach(kind: .record, me: m, mode: mode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("종류", selection: $kind) {
                        Text("내 전적 카드").tag(PostAttach.Kind.record)
                        Text("VS 카드").tag(PostAttach.Kind.versus)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("내 구단주명", text: $me)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if kind == .versus {
                        TextField("친구 구단주명", text: $other)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Picker("모드", selection: $mode) {
                        Text("공식경기").tag(50); Text("감독모드").tag(52); Text("클래식 1on1").tag(40)
                    }
                } footer: {
                    Text(kind == .versus
                         ? "두 구단주의 최근 30경기를 붙인 VS 카드가 글에 들어가요. 보는 사람이 열 때마다 최신 전적으로 그려요."
                         : "폼 티어 · 승률 · 경기당 득실 · 요즘 흐름이 담긴 카드가 글에 들어가요. 열 때마다 최신 전적으로 그려요.")
                        .cmText(12).foregroundStyle(CM.faint)
                }
                .listRowBackground(FC.surface)
            }
            .scrollContentBackground(.hidden)
            .background(FC.bg.ignoresSafeArea())
            .navigationTitle("전적 · VS 첨부").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("첨부") { if let r = result { onPick(r); dismiss() } }.disabled(result == nil)
                }
            }
            .onAppear {
                if let i = initial { kind = i.kind; me = i.me; other = i.with ?? ""; mode = i.mode }
                else { me = LocalPrefs.shared.myNickname ?? "" }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 목록 행의 첨부 글리프(스쿼드 방패와 같은 크기·색)
struct PostAttachGlyph: View {
    let attach: PostAttach
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Image(systemName: attach.kind == .versus ? "person.2.fill" : "chart.bar.fill")
            .font(.system(size: 12 * TypeScale.factor(typeSize)))
            .foregroundStyle(CM.faint)
            .accessibilityHidden(true)
    }
}
