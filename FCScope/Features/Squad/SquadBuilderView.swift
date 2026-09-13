import SwiftUI

@Observable
@MainActor
final class SquadBuilderModel {
    var formation: Formation = Formation.get("433")
    var slots: [String: SquadSlotModel] = [:]
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
    }
    func assign(_ hit: PlayerHit, to slot: FormationSlot) {
        // 같은 실선수(pid) 중복 배치 방지
        for (k, v) in slots where v.spid % 1_000_000 == hit.pid { slots[k] = nil }
        slots[slot.id] = SquadSlotModel(slotId: slot.id, spid: hit.spid, name: hit.name, season: hit.season, x: nil, y: nil)
        Haptic.light()
    }
    func remove(_ slot: FormationSlot) { slots[slot.id] = nil }
    func clear() { slots = [:]; savedId = nil; teamTag = nil }

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
            formation = Formation.get(r.formation); slots = [:]
            for s in r.slots { slots[s.slotId] = s }
            name = r.name; teamTag = r.teamTag; savedId = nil
            Haptic.success()
        } catch { message = error.localizedDescription }
    }
    func importFromUser(_ nick: String) async {
        busy = true; defer { busy = false }
        do {
            let r: FromUserResponse = try await APIClient.shared.get("/api/squad/from-user", query: ["nickname": nick], auth: false)
            formation = Formation.get(r.formation); slots = [:]
            place(players: r.players.map { ($0.spid, $0.name, $0.pos, $0.season) })
            name = "\(r.nickname)의 스쿼드"; teamTag = nil; savedId = nil
            Haptic.success()
        } catch { message = error.localizedDescription }
    }
    func load(id: String) async {
        busy = true; defer { busy = false }
        do {
            let s: Squad = try await APIClient.shared.get("/api/squad/\(id)", auth: false)
            formation = Formation.get(s.formation); slots = [:]
            for sl in s.slots { slots[sl.slotId] = sl }
            name = s.name; teamTag = s.teamTag; savedId = s.id
        } catch { message = error.localizedDescription }
    }
    func save() async {
        guard filled > 0 else { message = "선수를 먼저 배치해 주세요."; return }
        busy = true; defer { busy = false }
        do {
            var body: [String: Any] = ["name": name, "formation": formation.id, "slots": slots.values.map { ["slotId": $0.slotId, "spid": $0.spid, "name": $0.name] }]
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
                TextField("스쿼드 이름", text: Binding(get: { model.name }, set: { model.name = $0 })).textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button { Task { await model.save(); if model.savedId != nil { showSaved = true } } } label: { Text(model.busy ? "저장 중…" : "저장 · 공유 링크").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk).disabled(model.busy || model.filled == 0)
                    Button(role: .destructive) { model.clear() } label: { Text("비우기") }.buttonStyle(.bordered)
                }
                if let id = model.savedId {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("저장됨 · 공유 코드 \(id)", color: FC.accent)
                            HStack {
                                ShareLink(item: AppConfig.absolute("/squad/\(id)")) { Label("링크 공유", systemImage: "link") }.buttonStyle(.bordered)
                                ShareCardButton(squad: SquadCardData(name: model.name, formationId: model.formation.id, slots: model.slots, shareCode: id), label: "스쿼드 카드")
                                Button { router.push(.squad(id)) } label: { Text("보기 →").fcScoreboard(13).foregroundStyle(FC.accent) }
                            }
                        }
                    }
                }
                Text("슬롯을 탭해 선수를 검색·배치하고, 배치된 선수를 탭하면 교체·제거할 수 있어요. 같은 선수는 시즌이 달라도 한 명만.").fcFont(12).foregroundStyle(FC.muted)
            }.padding(16)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .squadAddPlayer)) { n in
            guard let hit = n.object as? PlayerHit else { return }
            if let slot = model.formation.slots.first(where: { model.slots[$0.id] == nil && Formation.lineOf($0.pos) == guessLine(hit) }) ?? model.formation.slots.first(where: { model.slots[$0.id] == nil }) {
                model.assign(hit, to: slot); model.message = "\(hit.name) 을(를) \(slot.pos) 에 배치했어요."
            }
        }
    }
    private func guessLine(_ hit: PlayerHit) -> String { "ATT" }
    private func handlePending() {
        guard let p = router.pendingSquadImport else { return }
        router.pendingSquadImport = nil
        switch p {
        case .owner(let nick): Task { await model.importFromUser(nick) }
        case .load(let id): Task { await model.load(id: id) }
        }
    }
    private func chipButton(_ t: String) -> some View {
        Text(t).fcFont(13, weight: .semibold).foregroundStyle(FC.ink).padding(.horizontal, 10).padding(.vertical, 8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 피치 + 슬롯 (탭-배치)
struct PitchView: View {
    @Bindable var model: SquadBuilderModel
    var readOnly = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
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
                ForEach(model.formation.slots) { s in
                    let filled = model.slots[s.id]
                    Button { if !readOnly { Haptic.light(); model.selectedSlot = s } } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                if let f = filled { PlayerImage(spid: f.spid, size: 44, radius: 22) }
                                else { Circle().fill(Color.white.opacity(0.12)).frame(width: 44, height: 44).overlay(Text("+").fcFont(18, weight: .bold).foregroundStyle(.white.opacity(0.7))) }
                                Circle().stroke(filled == nil ? Color.white.opacity(0.3) : FC.accent, lineWidth: 2).frame(width: 44, height: 44)
                            }
                            Text(filled?.name ?? s.pos).fcFont(10, weight: .bold).foregroundStyle(.white).lineLimit(1).frame(width: 64)
                                .padding(.horizontal, 2).background(Color.black.opacity(0.45), in: Capsule())
                            if let f = filled, let season = f.season, !season.isEmpty { Text(season).fcFont(8, weight: .semibold).foregroundStyle(FC.gold) }
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: w * s.x / 100, y: h * s.y / 100)
                    .contextMenu { if !readOnly, filled != nil { Button("교체") { model.selectedSlot = s }; Button("제거", role: .destructive) { model.remove(s) } } }
                }
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
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
                        Section { Button(role: .destructive) { model.remove(slot); dismiss() } label: { Label("\(current.name) 제거", systemImage: "trash") } }
                    }
                    ForEach(hits) { h in
                        Button { if h.seasons.count > 1 { pick = h } else { model.assign(h, to: slot); dismiss() } } label: {
                            HStack { PlayerImage(spid: h.spid, size: 36, radius: 8); VStack(alignment: .leading) { Text(h.name).foregroundStyle(FC.ink); Text("\(h.season) 외 \(max(0, h.seasons.count - 1))개 시즌").fcFont(11).foregroundStyle(FC.muted) } }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("\(slot.pos) 선수 선택").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $pick) { h in
                NavigationStack {
                    List(h.seasons) { s in
                        Button { model.assign(PlayerHit(spid: s.spid, pid: h.pid, name: h.name, season: s.season, seasons: h.seasons), to: slot); pick = nil; dismiss() } label: { HStack { PlayerImage(spid: s.spid, size: 36, radius: 8); Text(h.name).foregroundStyle(FC.ink); Chip(text: s.season, color: FC.gold, bg: FC.gold.opacity(0.15)) } }
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
                        ShareCardButton(squad: SquadCardData(name: model.name, formationId: model.formation.id, slots: model.slots, shareCode: squadId), label: "카드")
                        ShareLink(item: AppConfig.absolute("/squad/\(squadId)")) { Image(systemName: "link") }.buttonStyle(.bordered).accessibilityLabel("스쿼드 링크 공유")
                    }
                } else if let m = model.message { ErrorState(title: "스쿼드를 찾을 수 없어요", message: m) } else { Skeleton(height: 400) }
            }.padding(16)
        }
        .fcScreen().navigationTitle("스쿼드").navigationBarTitleDisplayMode(.inline)
        .task { await model.load(id: squadId); loaded = model.message == nil }
    }
}
