import SwiftUI

/// 글쓰기 — Form 대신 노트형 편집기(SPEC 9절, mockups 03-compose-a/b)
struct ComposeView: View {
    let types: [PostTypeInfo]
    var initialType: String?
    var onDone: (_ newId: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft = CommunityPrefs.Draft()
    @State private var restorable: CommunityPrefs.Draft?
    @State private var busy = false
    @State private var msg: String?
    @State private var savedAt: Date?
    @State private var saveTask: Task<Void, Never>?
    @State private var squadPickerFor: SquadSlot?
    @State private var showPositions = false
    @State private var confirmLeave = false
    @State private var titleLimitHit = 0
    @FocusState private var focus: Field?
    private let cprefs = CommunityPrefs.shared

    enum Field: Hashable { case title, body, extra(String) }
    enum SquadSlot: String, Identifiable { case a, b; var id: String { rawValue } }

    static let regions = ["전국(온라인)", "서울", "경기", "인천", "강원", "대전", "세종", "충북", "충남", "대구", "경북", "부산", "울산", "경남", "광주", "전북", "전남", "제주"]
    static let positionOptions = ["ST", "CF", "LW", "RW", "CAM", "CM", "CDM", "LM", "RM", "LB", "RB", "CB", "GK"]
    private let titleMax = 60
    private let bodyMax = 2000

    private var type: PostTypeInfo? { types.first { $0.type == draft.type } }
    private var hasContent: Bool { !draft.isEmpty }
    private var canSubmit: Bool {
        guard let t = type, !busy else { return false }
        let ok = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if t.type == "squad_battle" { return ok && !draft.squad.isEmpty && !draft.squadB.isEmpty }
        return ok
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let r = restorable { restoreBanner(r) }
                    typeChips
                    titleField
                    Rectangle().fill(CM.hair).frame(height: 1).padding(.top, 10)
                    bodyField
                    if let t = type, !t.template.isEmpty { templateButton(t) }
                    if let t = type { extraCard(t) }
                    Text("욕설·비하·도배·거래 유도 글은 신고가 쌓이면 숨겨져요.")
                        .cmText(12.5).foregroundStyle(CM.faint)
                        .padding(.top, 12).padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(FC.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { accessoryBar }
        .interactiveDismissDisabled(hasContent)
        .presentationDetents([.large])
        .sensoryFeedback(.warning, trigger: titleLimitHit)
        .alert("알림", isPresented: Binding(get: { msg != nil }, set: { _ in msg = nil })) { Button("확인") {} } message: { Text(msg ?? "") }
        .confirmationDialog("작성 중인 글이 있어요", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("임시저장하고 나가기") { flushDraft(); dismiss() }
            Button("지우고 나가기", role: .destructive) { cprefs.clearDraft(); dismiss() }
            Button("계속 쓰기", role: .cancel) {}
        } message: { Text("임시저장하면 다음에 글쓰기를 열 때 이어 쓸 수 있어요.") }
        .sheet(item: $squadPickerFor) { slot in
            SquadPickerSheet { id, name in
                if slot == .a { draft.squad = id; draft.squadName = name } else { draft.squadB = id; draft.squadBName = name }
            }
        }
        .sheet(isPresented: $showPositions) { positionsSheet }
        .onAppear {
            draft.type = (types.first { $0.type == initialType } ?? types.first)?.type
            if let d = cprefs.loadDraft() { restorable = d }
            focus = .title
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
    }

    // MARK: 내비

    private var navBar: some View {
        HStack {
            Button("취소") { if hasContent { confirmLeave = true } else { dismiss() } }
                .cmText(16).foregroundStyle(FC.ink).frame(minWidth: 44, minHeight: 44)
            Spacer()
            Text("새 글").cmText(17, .bold).foregroundStyle(FC.ink)
            Spacer()
            Button { Task { await submit() } } label: {
                Group {
                    if busy { ProgressView().tint(FC.tintInk) } else { Text("등록").cmText(15, .bold) }
                }
                // 그라디언트 아님 — 15pt 흰 글자는 그라디언트 위 AA 미달(디자인 회의 c)
                .foregroundStyle(canSubmit ? FC.tintInk : CM.faint)
                .padding(.horizontal, 16).frame(minWidth: 58, minHeight: 36)
                .background(canSubmit ? FC.tint : FC.surface2, in: Capsule())
            }
            .disabled(!canSubmit)
            .accessibilityLabel(busy ? "등록 중" : "등록")
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    private func restoreBanner(_ r: CommunityPrefs.Draft) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(FC.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("작성 중이던 글이 있어요").cmText(13.5, .semibold).foregroundStyle(FC.ink)
                Text(r.title.isEmpty ? String(r.body.prefix(24)) : r.title).cmText(12).foregroundStyle(CM.faint).lineLimit(1)
            }
            Spacer()
            Button("버리기") { cprefs.clearDraft(); restorable = nil }.cmText(13).foregroundStyle(CM.faint)
            Button("불러오기") { draft = r; restorable = nil; savedAt = r.savedAt }.cmText(13, .semibold).foregroundStyle(FC.tint)
        }
        .padding(12)
        .background(FC.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .padding(.top, 6)
    }

    // MARK: 말머리

    private var typeChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("말머리").cmText(13, .semibold).foregroundStyle(CM.faint).padding(.top, 10)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(types) { t in
                    let on = draft.type == t.type
                    Button {
                        CMHaptic.selection()
                        draft.type = t.type   // 본문은 덮어쓰지 않는다 — 양식은 "＋ 양식 넣기"로만
                    } label: {
                        Text(Self.chipLabels[t.type] ?? t.label).cmText(14, .semibold)
                            .foregroundStyle(on ? FC.tint : FC.muted)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(on ? FC.tint.opacity(0.12) : FC.surface2, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? FC.tint : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if let t = type {
                Text(t.blurb).cmText(12.5).foregroundStyle(CM.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 제목·본문

    private var titleField: some View {
        // 카운터는 제목 첫 줄 기준선에 — lastTextBaseline 이면 6pt 내려가 보였다(디자인 N4)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("제목", text: Binding(get: { draft.title }, set: { v in
                let clean = v.replacingOccurrences(of: "\n", with: " ")
                if clean.count > titleMax { draft.title = String(clean.prefix(titleMax)); titleLimitHit += 1 } else { draft.title = clean }
            }), axis: .vertical)
            .cmText(20, .bold)
            .foregroundStyle(FC.ink)
            .lineLimit(1...3)
            .focused($focus, equals: .title)
            .submitLabel(.next)
            .onSubmit { focus = .body }
            Text("\(draft.title.count)/\(titleMax)").cmScore(12, .medium)
                .foregroundStyle(draft.title.count >= titleMax ? CM.coral : CM.faint)
                .accessibilityLabel("제목 \(draft.title.count)자, 최대 \(titleMax)자")
        }
        .padding(.top, 18)
    }

    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if draft.body.isEmpty {
                Text(type?.bodyPlaceholder ?? "내용을 적어 주세요.")
                    .cmText(16).lineSpacing(7).foregroundStyle(CM.faint)
                    .padding(.top, 8).padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: Binding(get: { draft.body }, set: { draft.body = String($0.prefix(bodyMax)) }))
                .cmText(16)
                .lineSpacing(7)
                .foregroundStyle(CM.ink2)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($focus, equals: .body)
                .frame(minHeight: 200)
        }
        // TextEditor 기본 안쪽 여백(5pt)만큼 당겨 본문 첫 글자를 제목 x 에 맞춘다(디자인 N4)
        .padding(.leading, -5)
        .padding(.top, 8)
        .accessibilityLabel(type?.bodyLabel ?? "내용")
    }

    private func templateButton(_ t: PostTypeInfo) -> some View {
        Button {
            draft.body = draft.body.isEmpty ? t.template : draft.body + (draft.body.hasSuffix("\n") ? "" : "\n") + t.template
            focus = .body
            CMHaptic.selection()
        } label: {
            Text("＋ 양식 넣기").cmText(13, .semibold).foregroundStyle(FC.muted)
                .padding(.horizontal, 14).frame(height: 32)
                .overlay(Capsule().strokeBorder(FC.line, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: 추가 정보

    /// 말머리 칩 이름 — 2줄 안에 들어가게 "스쿼드" 접두를 뺀 이름(목업 03-compose)
    private static let chipLabels = ["squad_show": "자랑", "squad_rate": "평가 요청", "squad_make": "만들어줘", "squad_battle": "배틀",
                                     "club_recruit": "클럽원 모집", "club_match": "클럽전 상대", "tournament": "대회"]
    private static let extraLabels = ["budget": "예산", "schedule": "가능 시간", "date": "일정", "format": "형식", "entry": "참가 방법"]

    @ViewBuilder private func extraCard(_ t: PostTypeInfo) -> some View {
        let fields = t.fields
        if !fields.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.offset) { i, f in
                    if i > 0 { Rectangle().fill(FC.line).frame(height: 1) }
                    extraRow(f, t)
                }
            }
            .background(FC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(FC.line, lineWidth: 1))
            .padding(.top, 14)
        }
    }

    @ViewBuilder private func extraRow(_ f: String, _ t: PostTypeInfo) -> some View {
        switch f {
        case "squad", "squad_b":
            let isB = f == "squad_b"
            let name = isB ? draft.squadBName ?? (draft.squadB.isEmpty ? nil : draft.squadB) : draft.squadName ?? (draft.squad.isEmpty ? nil : draft.squad)
            let label = t.type == "squad_battle" ? (isB ? "B팀 스쿼드" : "A팀 스쿼드") : "스쿼드 첨부"
            Button { squadPickerFor = isB ? .b : .a } label: {
                rowLabel(icon: "shield.fill", iconColor: isB ? CM.coral : FC.tint, label) {
                    HStack(spacing: 6) {
                        Text(name ?? (t.type == "squad_battle" ? "필수 · 고르기" : "선택")).cmText(15, name == nil ? .regular : .semibold)
                            .foregroundStyle(name == nil ? CM.faint : FC.tint).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CM.faint)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                if name != nil { Button("첨부 빼기", role: .destructive) { if isB { draft.squadB = ""; draft.squadBName = nil } else { draft.squad = ""; draft.squadName = nil } } }
            }
        case "region":
            Menu {
                Picker("지역", selection: $draft.region) { ForEach(Self.regions, id: \.self) { Text($0).tag($0) } }
            } label: {
                rowLabel(icon: "mappin.circle.fill", iconColor: CM.teal, "지역") {
                    HStack(spacing: 6) {
                        Text(draft.region).cmText(15).foregroundStyle(FC.muted)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(CM.faint)
                    }
                }
            }
            .buttonStyle(.plain)
        case "positions":
            Button { showPositions = true } label: {
                rowLabel(icon: nil, "구하는 포지션") {
                    HStack(spacing: 6) {
                        Text(draft.positions.isEmpty ? "선택" : draft.positions.joined(separator: " · ")).cmText(15)
                            .foregroundStyle(draft.positions.isEmpty ? CM.faint : FC.ink).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CM.faint)
                    }
                }
            }
            .buttonStyle(.plain)
        case "contact":
            rowLabel(icon: nil, "연락 방법") {
                TextField("선택 사항", text: $draft.contact).cmText(15).multilineTextAlignment(.trailing)
                    .foregroundStyle(FC.ink).focused($focus, equals: .extra("contact"))
            }
        default:
            let label = Self.extraLabels[f] ?? f
            rowLabel(icon: nil, label) {
                TextField("선택 사항", text: Binding(get: { draft.extras[f] ?? "" }, set: { draft.extras[f] = String($0.prefix(80)) }))
                    .cmText(15).multilineTextAlignment(.trailing).foregroundStyle(FC.ink)
                    .focused($focus, equals: .extra(f))
            }
        }
    }

    private func rowLabel<Trailing: View>(icon: String?, iconColor: Color = FC.tint, _ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 17)).foregroundStyle(iconColor) } else { Color.clear }
            }
            .frame(width: 22)
            Text(label).cmText(15.5, .medium).foregroundStyle(FC.ink).fixedSize()
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private var positionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("최대 6개까지 고를 수 있어요").cmText(13).foregroundStyle(CM.faint)
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Self.positionOptions, id: \.self) { p in
                            let on = draft.positions.contains(p)
                            Button {
                                if on { draft.positions.removeAll { $0 == p } } else if draft.positions.count < 6 { draft.positions.append(p) }
                                CMHaptic.selection()
                            } label: {
                                Text(p).cmScore(14, .bold)
                                    .foregroundStyle(on ? CM.teal : FC.muted)
                                    .frame(minWidth: 52, minHeight: 36)
                                    .background(on ? CM.teal.opacity(0.14) : FC.surface2, in: Capsule())
                                    .overlay(Capsule().strokeBorder(on ? CM.teal : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                .padding(16)
            }
            .background(FC.bg.ignoresSafeArea())
            .navigationTitle("구하는 포지션").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showPositions = false } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: 키보드 위 액세서리 바

    private var accessoryBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(CM.hair).frame(height: 1)
            HStack(spacing: 18) {
                if let t = type, t.fields.contains("squad") {
                    Button { squadPickerFor = .a } label: {
                        Label { Text("스쿼드").cmText(14, .semibold) } icon: { Image(systemName: "shield.fill").font(.system(size: 16)) }
                            .foregroundStyle(FC.muted).frame(minHeight: 44)
                    }
                }
                if let t = type, !t.template.isEmpty {
                    Button { draft.body = draft.body.isEmpty ? t.template : draft.body + "\n" + t.template; focus = .body } label: {
                        Text("양식").cmText(14, .semibold).foregroundStyle(FC.muted).frame(minHeight: 44)
                    }
                }
                Spacer()
                if let savedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text("임시저장됨 · \(relative(savedAt, now: ctx.date))").cmText(12.5).foregroundStyle(CM.faint)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .background(.bar)
    }

    private func relative(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "방금" }
        return "\(Int(s / 60))분 전"
    }

    // MARK: 저장·등록

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            flushDraft()
        }
    }
    private func flushDraft() {
        guard hasContent else { return }
        var d = draft; d.savedAt = Date()
        cprefs.saveDraft(d)
        savedAt = d.savedAt
        if restorable != nil { restorable = nil }
    }

    private func submit() async {
        guard let t = type, canSubmit else { return }
        busy = true; defer { busy = false }
        var json: [String: Any] = ["type": t.type, "title": draft.title.trimmingCharacters(in: .whitespacesAndNewlines), "body": draft.body.trimmingCharacters(in: .whitespacesAndNewlines)]
        if t.fields.contains("squad"), !draft.squad.isEmpty { json["squad_id"] = draft.squad }
        if t.fields.contains("squad_b"), !draft.squadB.isEmpty { json["squad_b"] = draft.squadB }
        if t.fields.contains("region") { json["region"] = draft.region }
        if t.fields.contains("positions"), !draft.positions.isEmpty { json["positions"] = draft.positions }
        if t.fields.contains("contact"), !draft.contact.isEmpty { json["contact"] = draft.contact }
        for (k, v) in draft.extras where t.fields.contains(k) && !v.isEmpty { json[k] = v }
        do {
            let id = try await CommunityAPI.createPost(json)
            saveTask?.cancel()
            cprefs.clearDraft()
            Haptic.success()
            onDone(id)
            dismiss()
        } catch {
            msg = error.localizedDescription
            Haptic.warning()
        }
    }
}
