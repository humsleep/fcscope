import SwiftUI

@Observable
@MainActor
final class SquadBuilderModel {
    var formation: Formation = Formation.get("433")
    var slots: [String: SquadSlotModel] = [:]
    /// 드래그로 옮긴 자리의 좌표(slotId → 0~100). 없으면 포메이션 기본 위치.
    /// 빈 자리도 옮길 수 있어 선수(slots)와 따로 둔다 — 저장할 때 선수 슬롯에 x/y 로 합친다.
    var coords: [String: PitchPoint] = [:]
    /// 슬롯을 들어 올린 동안 true — 바깥 ScrollView 스크롤을 막는다.
    var isDraggingSlot = false
    var name = "내 스쿼드"
    var teamTag: String? = nil
    var selectedSlot: FormationSlot?
    var busy = false
    var message: String?
    var savedId: String?

    var filled: Int { formation.slots.filter { slots[$0.id] != nil }.count }

    func changeFormation(_ f: Formation) {
        let valid = Set(f.slots.map(\.id))
        slots = slots.filter { valid.contains($0.key) }
        formation = f
        coords = [:]   // 포메이션을 직접 고르면 그 포메이션의 기본 배치로
    }

    /// 화면에 그릴 위치(옮긴 좌표 또는 포메이션 기본 위치)
    func point(of s: FormationSlot) -> PitchPoint { coords[s.id] ?? PitchLayout.defaultPoint(s) }

    /// 드래그를 다른 자리 위에서 놓음 — 두 자리의 선수만 맞바꾼다(빈 자리면 이동). 자리(좌표·라벨)는 그대로.
    func swapSlots(_ a: String, _ b: String) {
        guard a != b, slots[a] != nil || slots[b] != nil else { return }
        slots = PitchLayout.swap(slots, a, b)
        Haptic.medium()
    }

    /// 드래그를 빈 잔디에서 놓음 — 자리를 옮기고 라벨·포메이션을 다시 정한다.
    func moveSlot(_ id: String, to p: PitchPoint) {
        let before = formation.id
        let r = PitchLayout.move(.init(formation: formation, slots: slots, coords: coords, movedId: id), id: id, to: p)
        formation = r.formation
        slots = r.slots
        coords = r.coords
        if r.formation.id != before { Haptic.medium() } else { Haptic.light() }
    }

    /// 옮긴 좌표를 모두 지우고 현재 포메이션의 기본 배치로
    func resetPositions() {
        guard !coords.isEmpty else { return }
        coords = [:]
        Haptic.light()
    }

    /// 저장·공유 카드용 — 옮긴 자리의 좌표를 선수 슬롯의 x/y 로 합친다.
    var exportSlots: [String: SquadSlotModel] {
        var out = slots
        for (id, s0) in slots {
            var s = s0
            let p = coords[id]
            s.x = p?.x; s.y = p?.y
            out[id] = s
        }
        return out
    }
    /// 서버에서 받은 슬롯(선택적 x/y 포함)으로 선수·좌표를 채운다.
    private func apply(_ list: [SquadSlotModel]) {
        slots = [:]; coords = [:]
        let valid = Set(formation.slots.map(\.id))
        for sl in list where valid.contains(sl.slotId) {
            slots[sl.slotId] = sl
            if let x = sl.x, let y = sl.y { coords[sl.slotId] = PitchPoint(x: x, y: y) }
        }
    }
    func assign(_ hit: PlayerHit, to slot: FormationSlot) {
        // 같은 실선수(pid) 중복 배치 방지
        for (k, v) in slots where v.spid % 1_000_000 == hit.pid { slots[k] = nil }
        slots[slot.id] = SquadSlotModel(slotId: slot.id, spid: hit.spid, name: hit.name, season: hit.season, x: nil, y: nil)
        Haptic.light()
    }
    func remove(_ slot: FormationSlot) { slots[slot.id] = nil }
    /// 사진만 바꾼다(카드·능력치는 그대로). 다른 선수의 사진은 받지 않는다 — pid 가 같아야 한다.
    func setImage(_ imageSpid: Int?, for slotId: String) {
        guard var s = slots[slotId] else { return }
        if let imageSpid, imageSpid % 1_000_000 != s.spid % 1_000_000 { return }
        s.imageSpid = imageSpid == s.spid ? nil : imageSpid
        slots[slotId] = s
        Haptic.light()
    }
    func clear() { slots = [:]; coords = [:]; savedId = nil; teamTag = nil }

    /// 라인별로 빈 슬롯에 순서대로 배치 (프리셋/임포트)
    func place(players: [(spid: Int, name: String, pos: String, season: String)]) {
        var rest = players
        var used = Set<String>()
        // 1) 정확한 포지션 매칭
        for s in formation.slots {
            if let i = rest.firstIndex(where: { $0.pos == s.pos }) {
                let p = rest.remove(at: i); slots[s.id] = SquadSlotModel(slotId: s.id, spid: p.spid, name: p.name, season: p.season, x: nil, y: nil); used.insert(s.id)
            }
        }
        // 2) 같은 라인
        for s in formation.slots where !used.contains(s.id) {
            if let i = rest.firstIndex(where: { Formation.lineOf($0.pos) == Formation.lineOf(s.pos) }) {
                let p = rest.remove(at: i); slots[s.id] = SquadSlotModel(slotId: s.id, spid: p.spid, name: p.name, season: p.season, x: nil, y: nil); used.insert(s.id)
            }
        }
        // 3) 남은 자리
        for s in formation.slots where !used.contains(s.id) && !rest.isEmpty {
            let p = rest.removeFirst(); slots[s.id] = SquadSlotModel(slotId: s.id, spid: p.spid, name: p.name, season: p.season, x: nil, y: nil)
        }
    }

    func loadPreset(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            let r: PresetResponse = try await APIClient.shared.get("/api/squad/preset", query: ["id": id], auth: false)
            formation = Formation.get(r.formation)
            apply(r.slots)
            name = r.name; teamTag = r.teamTag; savedId = nil
            Haptic.success()
        } catch { message = error.localizedDescription }
    }
    func importFromUser(_ nick: String) async {
        busy = true; defer { busy = false }
        do {
            let r: FromUserResponse = try await APIClient.shared.get("/api/squad/from-user", query: ["nickname": nick], auth: false)
            formation = Formation.get(r.formation); slots = [:]; coords = [:]
            place(players: r.players.map { ($0.spid, $0.name, $0.pos, $0.season) })
            name = "\(r.nickname)의 스쿼드"; teamTag = nil; savedId = nil
            Haptic.success()
        } catch { message = error.localizedDescription }
    }
    func load(id: String) async {
        busy = true; defer { busy = false }
        do {
            let s: Squad = try await APIClient.shared.get("/api/squad/\(id)", auth: false)
            formation = Formation.get(s.formation)
            apply(s.slots)
            name = s.name; teamTag = s.teamTag; savedId = s.id
        } catch { message = error.localizedDescription }
    }
    func save() async {
        guard filled > 0 else { message = "선수를 먼저 배치해 주세요."; return }
        busy = true; defer { busy = false }
        do {
            var body: [String: Any] = ["name": name, "formation": formation.id, "slots": exportSlots.values.map { s -> [String: Any] in
                var d: [String: Any] = ["slotId": s.slotId, "spid": s.spid, "name": s.name]
                if let img = s.imageSpid { d["imageSpid"] = img }
                // 옮긴 자리만 좌표를 보낸다(서버는 0~100 만 받는다 — clamp 로 이미 x 8~92 · y 6~96).
                if let x = s.x, let y = s.y { d["x"] = x; d["y"] = y }
                return d
            }]
            if let t = teamTag { body["teamTag"] = t }
            let r: IdBody = try await APIClient.shared.send("/api/squad", method: "POST", json: body)
            savedId = r.id
            Haptic.success()
        } catch { message = error.localizedDescription }
    }
}

struct SquadBuilderView: View {
    @State private var model = SquadBuilderModel()
    @Environment(AppRouter.self) private var router
    @State private var showFormations = false
    @State private var showPresets = false
    @State private var showImport = false
    @State private var importNick = ""
    @State private var showSaved = false
    @State private var showClear = false
    /// 포지션을 몰라 자리를 직접 골라야 하는 선수
    @State private var placing: PlayerHit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button { showFormations = true } label: { chipButton("⚙️ \(model.formation.name)") }
                    Button { showPresets = true } label: { chipButton("🏟 팀 프리셋") }
                    Button { importNick = LocalPrefs.shared.myNickname ?? ""; showImport = true } label: { chipButton("⬇️ 최근 선발") }
                    Spacer()
                    Text("\(model.filled)/11").fcScoreboard(14).foregroundStyle(model.filled == 11 ? FC.accent : FC.muted)
                }
                PitchView(model: model)
                HStack(spacing: 8) {
                    Text("길게 눌러 끌면 자리를 옮겨요").fcFont(12).foregroundStyle(FC.muted)
                    Spacer()
                    // 드래그로 옮긴 좌표만 지운다(선수·포메이션은 그대로). 옮긴 자리가 없으면 비활성.
                    Button { model.resetPositions() } label: {
                        Label("위치 초기화", systemImage: "arrow.counterclockwise").fcFont(12, weight: .semibold)
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(model.coords.isEmpty)
                }
                // .roundedBorder 는 다크 모드에서 새까만 상자로 떠 앱 표면색과 어긋났다 — 앱 표면색으로 직접 그린다.
                TextField("스쿼드 이름", text: Binding(get: { model.name }, set: { model.name = $0 }))
                    .textFieldStyle(.plain).fcFont(15).foregroundStyle(FC.ink)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 8) {
                    let canSave = !(model.busy || model.filled == 0)
                    // 잉크색을 항상 덮어쓰면 비활성 상태의 회색 배경 위에서 흰 글자가 사라졌다 — 활성일 때만 적용.
                    Button { Task { await model.save(); if model.savedId != nil { showSaved = true } } } label: { Text(model.busy ? "저장 중…" : "저장 · 공유 링크").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(canSave ? FC.accentInk : Color.secondary).disabled(!canSave)
                    // 앱 전체 tint(라임)가 destructive 역할보다 우선해 "비우기"가 긍정 버튼처럼 보였다.
                    Button(role: .destructive) { showClear = true } label: { Text("비우기") }.buttonStyle(.bordered).tint(FC.lose).disabled(model.filled == 0)
                }
                if let id = model.savedId {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("저장됨 · 공유 코드 \(id)", color: FC.accent)
                            HStack {
                                ShareLink(item: AppConfig.absolute("/squad/\(id)")) { Label("링크 공유", systemImage: "link") }.buttonStyle(.bordered)
                                ShareCardButton(squad: SquadCardData(name: model.name, formationId: model.formation.id, slots: model.exportSlots, shareCode: id), label: "스쿼드 카드")
                                Button { router.push(.squad(id)) } label: { Text("보기 →").fcScoreboard(13).foregroundStyle(FC.accent) }
                            }
                        }
                    }
                }
                Text("슬롯을 탭해 선수를 검색·배치하고, 배치된 선수를 탭하면 교체·제거할 수 있어요. 선수를 길게 눌러 다른 자리에 놓으면 서로 바뀌고, 빈 잔디에 놓으면 포지션과 포메이션이 자동으로 바뀌어요. 같은 선수는 시즌이 달라도 한 명만.").fcFont(12).foregroundStyle(FC.muted)
            }.padding(16)
        }
        .scrollDisabled(model.isDraggingSlot)
        .fcScreen().navigationTitle("스쿼드 빌더").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFormations) { FormationPicker(model: model) }
        .sheet(isPresented: $showPresets) { PresetPicker(model: model) }
        .sheet(item: Binding(get: { model.selectedSlot }, set: { model.selectedSlot = $0 })) { slot in PlayerSearchSheet(model: model, slot: slot) }
        .alert("최근 공식경기 선발 불러오기", isPresented: $showImport) {
            TextField("구단주명", text: $importNick)
            Button("불러오기") { Task { await model.importFromUser(importNick) } }
            Button("취소", role: .cancel) {}
        } message: { Text("가장 최근 공식경기에서 실제로 사용한 선발 11명을 그대로 배치해요.") }
        .alert("알림", isPresented: Binding(get: { model.message != nil }, set: { _ in model.message = nil })) { Button("확인") {} } message: { Text(model.message ?? "") }
        .onAppear { handlePending() }
        .onChange(of: router.pendingSquadImport) { _, _ in handlePending() }
        .confirmationDialog("배치한 선수를 모두 비울까요?", isPresented: $showClear, titleVisibility: .visible) {
            Button("비우기", role: .destructive) { model.clear() }
            Button("취소", role: .cancel) {}
        } message: { Text("되돌릴 수 없어요.") }
        .confirmationDialog("\(placing?.name ?? "선수")을(를) 어느 자리에 둘까요?", isPresented: Binding(get: { placing != nil }, set: { if !$0 { placing = nil } }), titleVisibility: .visible) {
            if let hit = placing {
                ForEach(model.formation.slots.filter { model.slots[$0.id] == nil }) { slot in
                    Button(slot.pos) { model.assign(hit, to: slot); placing = nil }
                }
            }
            Button("취소", role: .cancel) { placing = nil }
        }
    }
    private func handlePending() {
        guard let p = router.pendingSquadImport else { return }
        router.pendingSquadImport = nil
        switch p {
        case .owner(let nick): Task { await model.importFromUser(nick) }
        case .load(let id): Task { await model.load(id: id) }
        case .add(let hit, let line): place(hit, line: line)
        }
    }
    /// 선수 상세의 "스쿼드 빌더에 배치" — 주 포지션 라인의 빈 슬롯에 넣는다.
    /// 포지션을 모르거나(랭커 기록 없음) 그 라인이 꽉 찼으면 추측하지 않고 자리를 고르게 한다 — 골키퍼가 공격수 자리에 들어가면 안 된다.
    private func place(_ hit: PlayerHit, line: String?) {
        let empty = model.formation.slots.filter { model.slots[$0.id] == nil }
        guard !empty.isEmpty else {
            model.message = "빈 자리가 없어요. 바꿀 선수를 탭해서 교체해 주세요."
            return
        }
        guard let line, let slot = empty.first(where: { Formation.lineOf($0.pos) == line }) else {
            placing = hit
            return
        }
        model.assign(hit, to: slot)
        model.message = "\(hit.name)을(를) \(slot.pos)에 배치했어요."
    }
    private func chipButton(_ t: String) -> some View {
        Text(t).fcFont(13, weight: .semibold).foregroundStyle(FC.ink).padding(.horizontal, 10).padding(.vertical, 8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 피치 + 슬롯
///
/// 편집 모드: 탭 = 선수 검색·교체 시트. 길게 눌러 끌기(FC온라인 방식) —
/// 다른 자리 위에 놓으면 두 선수 교환(빈 자리면 이동), 빈 잔디에 놓으면 자리를 옮기고
/// 좌표로 포지션 라벨을 다시 정한 뒤 포메이션을 자동 갱신한다(`PitchLayout`).
/// 읽기 전용 모드는 드래그·탭이 없다.
struct PitchView: View {
    @Bindable var model: SquadBuilderModel
    var readOnly = false

    /// 드래그 중인 자리와 (슬롯 중심 + 손가락 이동량) 위치(피치 좌표계, pt). 끝나거나 취소되면 nil.
    @State private var drag: PitchDrag?
    struct PitchDrag: Equatable { let id: String; var location: CGPoint; var moved: Bool }

    /// 이 거리(pt) 안에서 놓으면 그 자리와 교환
    private static let swapRadius: CGFloat = 32
    /// 길게 누른 뒤 이만큼도 안 움직이고 놓으면 아무 일도 없다(라벨 재계산 방지)
    private static let moveThreshold: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            let size = g.size
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(red: 0.07, green: 0.2, blue: 0.13), Color(red: 0.05, green: 0.14, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                Canvas { ctx, size in
                    var p = Path()
                    p.addRect(CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16))
                    p.move(to: CGPoint(x: 8, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width - 8, y: size.height / 2))
                    p.addEllipse(in: CGRect(x: size.width / 2 - 36, y: size.height / 2 - 36, width: 72, height: 72))
                    p.addRect(CGRect(x: size.width * 0.22, y: size.height - 8 - size.height * 0.16, width: size.width * 0.56, height: size.height * 0.16))
                    p.addRect(CGRect(x: size.width * 0.22, y: 8, width: size.width * 0.56, height: size.height * 0.16))
                    ctx.stroke(p, with: .color(.white.opacity(0.25)), lineWidth: 1)
                }
                let target = drag.flatMap { swapTarget(for: $0, size: size) }
                ForEach(model.formation.slots) { s in
                    let lifted = drag?.id == s.id
                    slotNode(s, highlighted: target?.id == s.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(s))
                        .scaleEffect(lifted ? 1.15 : target?.id == s.id ? 1.08 : 1)
                        .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 8, y: 4)
                        .opacity(lifted && target != nil ? 0.8 : 1)   // 교체 대상의 금색 테두리가 비쳐 보이게
                        .animation(.easeOut(duration: 0.15), value: target?.id == s.id)
                        .overlay(alignment: .top) { if lifted, let d = drag { liveLabel(d, target: target, size: size) } }
                        .modifier(SlotInteraction(
                            enabled: !readOnly,
                            onTap: { Haptic.light(); model.selectedSlot = s },
                            onDrag: { t in drag = pitchDrag(s, translation: t, size: size) },
                            onDrop: { t in drop(s, translation: t, size: size) },
                            onCancel: { drag = nil }))
                        .position(lifted ? liftedPosition(drag!, target: target, size: size) : screen(model.point(of: s), size))
                        .zIndex(lifted ? 10 : 0)
                }
            }
            .coordinateSpace(name: "pitch")
            .animation(.spring(duration: 0.3), value: model.coords)
        }
        .aspectRatio(0.72, contentMode: .fit)
        // 슬롯 좌표는 피치 비율 기준으로 고정이라 라벨이 커지면 옆 슬롯과 겹친다(AX5 에서 전부 겹침).
        // 피치 안 글자는 xLarge 에서 멈춘다 — 이름 전체는 교체 시트·카드에서 볼 수 있다.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .onChange(of: drag?.id) { old, new in
            if old == nil, new != nil { Haptic.light() }
            model.isDraggingSlot = new != nil
        }
    }

    @ViewBuilder
    private func slotNode(_ s: FormationSlot, highlighted: Bool) -> some View {
        let filled = model.slots[s.id]
        VStack(spacing: 2) {
            ZStack {
                if let f = filled { PlayerImage(spid: f.displaySpid, size: 44, radius: 22) }
                else { Circle().fill(Color.white.opacity(0.12)).frame(width: 44, height: 44).overlay(Text("+").fcFont(18, weight: .bold).foregroundStyle(.white.opacity(0.7))) }
                Circle().stroke(highlighted ? FC.gold : filled == nil ? Color.white.opacity(0.3) : FC.accent, lineWidth: highlighted ? 3 : 2).frame(width: 44, height: 44)
            }
            // 선수가 있는 자리도 포지션을 보인다 — 드래그로 라벨·포메이션이 바뀐 걸 알 수 있게(FC온라인 스쿼드 화면처럼).
            .overlay(alignment: .topLeading) {
                if filled != nil {
                    Text(s.pos).font(.system(size: 8, weight: .heavy)).foregroundStyle(FC.accentInk)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(FC.accent, in: Capsule())
                        .fixedSize()
                        .offset(x: -8, y: -3)
                }
            }
            // 64pt 폭에 전체 이름을 넣으면 "그레고르..." 처럼 잘려 누군지 몰랐다 — 마지막 단어(대개 성)만.
            Text(filled.map { Self.shortName($0.name) } ?? s.pos).fcFont(10, weight: .bold).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7).frame(width: 64)
                .padding(.horizontal, 2).background(Color.black.opacity(0.45), in: Capsule())
            if let f = filled, let season = f.season, !season.isEmpty { SeasonBadge(spid: f.spid, season: season, height: 12) }
        }
        .contentShape(Rectangle())
    }

    /// 드래그 중 위에 뜨는 라벨 — 교환 대상 위면 "교체", 아니면 놓았을 때 받을 포지션(예: CDM).
    private func liveLabel(_ d: PitchDrag, target: FormationSlot?, size: CGSize) -> some View {
        let text: String
        if let t = target { text = "↔ \(t.pos) 교체" }
        else { text = PitchLayout.label(at: clamped(d, size: size)) }
        return Text(text).fcScoreboard(13).foregroundStyle(FC.accentInk)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(target == nil ? FC.accent : FC.gold, in: Capsule())
            .fixedSize()
            .offset(y: -26)
    }

    /// 놓기 — 다른 자리 위면 교환, 빈 잔디면 자리 이동(+라벨·포메이션 갱신). 거의 안 움직였으면 무시.
    private func drop(_ s: FormationSlot, translation: CGSize, size: CGSize) {
        let pd = pitchDrag(s, translation: translation, size: size)
        drag = nil
        guard pd.moved else { return }
        if let t = swapTarget(for: pd, size: size) { model.swapSlots(s.id, t.id) }
        else { model.moveSlot(s.id, to: pct(pd.location, size)) }
    }

    /// 슬롯 중심 + 손가락 이동량 — 손가락 위치를 그대로 쓰면 슬롯 중심이 아닌 곳을 잡았을 때 그만큼 튀었다
    /// (길게 누르고 안 움직여도 "옮김"으로 처리됨).
    private func pitchDrag(_ s: FormationSlot, translation t: CGSize, size: CGSize) -> PitchDrag {
        let o = screen(model.point(of: s), size)
        return PitchDrag(id: s.id, location: CGPoint(x: o.x + t.width, y: o.y + t.height), moved: hypot(t.width, t.height) >= Self.moveThreshold)
    }

    /// 드래그 중인 슬롯 중심에서 swapRadius 안의 가장 가까운 다른 자리
    private func swapTarget(for d: PitchDrag, size: CGSize) -> FormationSlot? {
        guard d.moved else { return nil }
        var best: (FormationSlot, CGFloat)?
        for s in model.formation.slots where s.id != d.id {
            let p = screen(model.point(of: s), size)
            let dist = hypot(p.x - d.location.x, p.y - d.location.y)
            if dist <= Self.swapRadius, dist < (best?.1 ?? .infinity) { best = (s, dist) }
        }
        return best?.0
    }

    private func isGK(_ id: String) -> Bool { model.formation.slots.first { $0.id == id }?.pos == "GK" }
    private func clamped(_ d: PitchDrag, size: CGSize) -> PitchPoint { PitchLayout.clamp(pct(d.location, size), isGK: isGK(d.id)) }
    /// 교환 대상 위에선 손가락을 따라가고, 빈 잔디에선 놓일 자리(GK 규칙 적용)를 보여 준다.
    private func liftedPosition(_ d: PitchDrag, target: FormationSlot?, size: CGSize) -> CGPoint {
        target != nil || !d.moved ? d.location : screen(clamped(d, size: size), size)
    }
    private func screen(_ p: PitchPoint, _ size: CGSize) -> CGPoint { CGPoint(x: size.width * p.x / 100, y: size.height * p.y / 100) }
    private func pct(_ p: CGPoint, _ size: CGSize) -> PitchPoint {
        PitchPoint(x: Double(p.x / max(size.width, 1) * 100), y: Double(p.y / max(size.height, 1) * 100))
    }
    private func accessibilityText(_ s: FormationSlot) -> String {
        if let f = model.slots[s.id] { return "\(s.pos), \(f.name)" }
        return "\(s.pos), 빈 자리"
    }

    static func shortName(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }
}

/// 편집 모드에서만 탭·드래그를 붙인다. 읽기 전용은 제스처 없이 그림만.
private struct SlotInteraction: ViewModifier {
    let enabled: Bool
    let onTap: () -> Void
    let onDrag: (CGSize) -> Void
    let onDrop: (CGSize) -> Void
    let onCancel: () -> Void
    func body(content: Content) -> some View {
        if enabled {
            content
                .overlay(SlotGestureView(onTap: onTap, onDrag: onDrag, onDrop: onDrop, onCancel: onCancel))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("탭하면 선수를 고르고, 길게 눌러 끌면 자리를 옮기거나 교체해요.")
                .accessibilityAction { onTap() }
        } else {
            content
        }
    }
}

/// 탭 + 길게 눌러 끌기를 UIKit 제스처로 받는다.
///
/// SwiftUI `LongPressGesture.sequenced(before: DragGesture)` 는 `.gesture`·`.simultaneousGesture` 어느 쪽이든
/// 슬롯에서 시작한 스와이프가 바깥 ScrollView 스크롤을 막았다(실측). UIKit 길게 누르기는 0.25초 전에 손가락이 움직이면
/// 실패하고 스크롤 팬이 이기며, 0.25초를 버티면 길게 누르기가 이겨 드래그가 된다 — 표준 동작 그대로.
/// 이동량은 윈도 좌표로 잰다(슬롯이 손가락을 따라 움직여도 기준이 흔들리지 않게).
private struct SlotGestureView: UIViewRepresentable {
    let onTap: () -> Void
    let onDrag: (CGSize) -> Void
    let onDrop: (CGSize) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isAccessibilityElement = false   // VoiceOver 는 SwiftUI 요소(라벨·기본 동작)를 쓴다
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.25
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: press)   // 길게 누른 뒤 손을 떼도 탭(시트)이 열리지 않게
        v.addGestureRecognizer(press)
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject {
        var parent: SlotGestureView?
        private var start: CGPoint = .zero

        @objc func tap(_ g: UITapGestureRecognizer) { if g.state == .ended { parent?.onTap() } }

        @objc func press(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: nil)
            let t = CGSize(width: p.x - start.x, height: p.y - start.y)
            switch g.state {
            case .began: start = p; parent?.onDrag(.zero)
            case .changed: parent?.onDrag(t)
            case .ended: parent?.onDrop(t)
            default: parent?.onCancel()
            }
        }
    }
}

struct FormationPicker: View {
    @Bindable var model: SquadBuilderModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(["4", "3", "5"], id: \.self) { line in
                    Section("\(line)백") {
                        ForEach(Formation.all.filter { $0.line == line }) { f in
                            Button { model.changeFormation(f); dismiss() } label: { HStack { Text(f.name).foregroundStyle(FC.ink); Spacer(); if f.id == model.formation.id { Image(systemName: "checkmark").foregroundStyle(FC.accent) } } }
                        }
                    }
                }
            }
            .navigationTitle("포메이션").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

struct PresetPicker: View {
    @Bindable var model: SquadBuilderModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(Dictionary(grouping: PRESET_TEAMS, by: \.league).sorted { $0.key < $1.key }), id: \.key) { league, teams in
                    Section(league) { ForEach(teams) { t in Button(t.team) { dismiss(); Task { await model.loadPreset(t.id) } }.foregroundStyle(FC.ink) } }
                }
            }
            .navigationTitle("팀 프리셋").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

struct PlayerSearchSheet: View {
    @Bindable var model: SquadBuilderModel
    let slot: FormationSlot
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var hits: [PlayerHit] = []
    @State private var pick: PlayerHit?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("선수 이름 (2자 이상)", text: $q).textFieldStyle(.roundedBorder).padding().autocorrectionDisabled()
                    .task(id: q) { await search(q) }
                    .task { await PlayerIndex.shared.load() }
                if q.trimmingCharacters(in: .whitespaces).count >= 2 && hits.isEmpty && !searching {
                    Text("검색 결과가 없어요. 한글 이름으로 검색해 보세요.").fcFont(13).foregroundStyle(FC.muted).padding(.horizontal)
                }
                List {
                    if let current = model.slots[slot.id] {
                        Section {
                            NavigationLink { PlayerPhotoPicker(model: model, slotId: slot.id) } label: {
                                HStack(spacing: 10) { PlayerImage(spid: current.displaySpid, size: 36, radius: 8); Label("\(current.name) 사진 바꾸기", systemImage: "photo.on.rectangle") }
                            }
                            Button(role: .destructive) { model.remove(slot); dismiss() } label: { Label("\(current.name) 제거", systemImage: "trash") }
                        }
                    }
                    ForEach(hits) { h in
                        Button { if h.seasons.count > 1 { pick = h } else { model.assign(h, to: slot); dismiss() } } label: {
                            HStack { PlayerImage(spid: h.spid, size: 36, radius: 8); VStack(alignment: .leading) { Text(h.name).foregroundStyle(FC.ink); Text(h.seasons.count > 1 ? "\(h.season) 외 \(h.seasons.count - 1)개 시즌" : h.season).fcFont(11).foregroundStyle(FC.muted) } }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("\(slot.pos) 선수 선택").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $pick) { h in
                NavigationStack {
                    List(h.seasons) { s in
                        Button { model.assign(PlayerHit(spid: s.spid, pid: h.pid, name: h.name, season: s.season, seasons: h.seasons), to: slot); pick = nil; dismiss() } label: { HStack { PlayerImage(spid: s.spid, size: 36, radius: 8); Text(h.name).foregroundStyle(FC.ink); SeasonBadge(spid: s.spid, season: s.season) } }
                    }.navigationTitle("시즌 선택").navigationBarTitleDisplayMode(.inline)
                }.presentationDetents([.medium])
            }
        }
        .presentationDetents([.large])
    }
    @State private var searching = false
    /// 번들 인덱스 로컬 검색 — 서버 왕복 0, 오프라인 동작, 디바운스 불필요.
    /// 인덱스가 없는 예외 상황에서만 서버로 폴백한다.
    private func search(_ v: String) async {
        let t = v.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { hits = []; return }
        if PlayerIndex.shared.isReady {
            hits = await PlayerIndex.shared.search(t)
            return
        }
        searching = true; defer { searching = false }
        let r: PlayerSearchResponse? = try? await APIClient.shared.get("/api/players/search", query: ["q": t], auth: false)
        if Task.isCancelled || t != q.trimmingCharacters(in: .whitespaces) { return }
        hits = r?.players ?? []
    }
}

/// 공유된 스쿼드 보기 (읽기 전용 피치 + 빌더로 열기)
struct SquadDetailView: View {
    let squadId: String
    @State private var model = SquadBuilderModel()
    @State private var loaded = false
    @Environment(AppRouter.self) private var router
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loaded {
                    Text(model.name).fcFont(20, weight: .bold).foregroundStyle(FC.ink)
                    Text("\(model.formation.name) · \(model.filled)명").fcFont(13).foregroundStyle(FC.muted)
                    PitchView(model: model, readOnly: true)
                    HStack {
                        Button { router.pendingSquadImport = .load(squadId); router.tab = .squad } label: { Text("빌더에서 수정").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                        ShareCardButton(squad: SquadCardData(name: model.name, formationId: model.formation.id, slots: model.exportSlots, shareCode: squadId), label: "카드")
                        ShareLink(item: AppConfig.absolute("/squad/\(squadId)")) { Image(systemName: "link") }.buttonStyle(.bordered).accessibilityLabel("스쿼드 링크 공유")
                    }
                } else if let m = model.message { ErrorState(title: "스쿼드를 찾을 수 없어요", message: m) } else { Skeleton(height: 400) }
            }.padding(16)
        }
        .fcScreen().navigationTitle("스쿼드").navigationBarTitleDisplayMode(.inline)
        .task { await model.load(id: squadId); loaded = model.message == nil }
    }
}

/// 사진 바꾸기 — 같은 선수(pid)의 시즌 카드 사진과 기본 사진만 후보로 보여 준다.
/// 카드(spid)·능력치는 그대로 두고 표시 사진만 바꾼다. 넥슨 CDN 에 사진이 없는 시즌은 숨긴다.
struct PlayerPhotoPicker: View {
    @Bindable var model: SquadBuilderModel
    let slotId: String
    @Environment(\.dismiss) private var dismiss
    @State private var options: [PhotoCandidate] = []
    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    struct PhotoCandidate: Identifiable, Hashable { let spid: Int; let season: String; var id: Int { spid } }

    var body: some View {
        ScrollView {
            if let slot = model.slots[slotId] {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(slot.name)의 다른 시즌 사진만 고를 수 있어요. 시즌 카드와 능력치는 바뀌지 않아요.")
                        .fcFont(13).foregroundStyle(FC.muted)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(options) { o in
                            PhotoOption(candidate: o, selected: slot.displaySpid == o.spid) {
                                model.setImage(o.spid, for: slotId)
                                dismiss()
                            }
                        }
                    }
                }.padding(16)
            }
        }
        .fcScreen().navigationTitle("사진 바꾸기").navigationBarTitleDisplayMode(.inline)
        .task { await loadOptions() }
    }

    private func loadOptions() async {
        guard let slot = model.slots[slotId] else { return }
        await PlayerIndex.shared.load()
        let pid = slot.spid % 1_000_000
        var list: [PhotoCandidate]
        if let hit = await PlayerIndex.shared.player(spid: slot.spid) {
            list = hit.seasons.map { PhotoCandidate(spid: $0.spid, season: $0.season) }
        } else {
            list = [PhotoCandidate(spid: slot.spid, season: slot.season ?? "")]
        }
        // pid 자체 = 시즌 구분 없는 기본 사진(NexonCDN 폴백 체인이 players/p{pid}.png 로 간다)
        list.append(PhotoCandidate(spid: pid, season: "기본"))
        options = list
    }
}

private struct PhotoOption: View {
    let candidate: PlayerPhotoPicker.PhotoCandidate
    let selected: Bool
    let action: () -> Void
    @State private var image: UIImage?
    @State private var missing = false

    private var isBase: Bool { candidate.spid < 1_000_000 }

    var body: some View {
        if !missing {
            Button(action: action) {
                VStack(spacing: 6) {
                    ZStack {
                        FC.surface2
                        if let image { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView() }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? FC.accent : .clear, lineWidth: 3))
                    if isBase { Text("기본").fcFont(12, weight: .semibold).foregroundStyle(FC.muted) }
                    else { SeasonBadge(spid: candidate.spid, season: candidate.season, height: 16) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(candidate.season) 사진\(selected ? ", 선택됨" : "")")
            .task { await load() }
        }
    }

    /// 폴백 없이 그 시즌 사진만 본다 — 없는 시즌이 기본 사진으로 대체돼 같은 사진이 여러 칸에 보이지 않게.
    private func load() async {
        let pid = candidate.spid % 1_000_000
        let path = isBase ? "players/p\(pid).png" : "playersAction/p\(candidate.spid).png"
        guard let url = URL(string: "\(NexonCDN.base)/\(path)") else { missing = true; return }
        if let img = try? await ImageCache.pipeline.image(for: url) { image = img } else { missing = true }
    }
}
