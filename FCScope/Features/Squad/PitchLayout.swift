import Foundation

/// 피치 좌표(x 0~100 왼→오, y 0~100 위=공격 · 92=우리 골대)
struct PitchPoint: Hashable, Codable {
    var x: Double
    var y: Double
}

/// 스쿼드 피치 드래그의 순수 로직 — UI·네트워크 의존 없음(스크립트로 검증 가능하게 분리).
///
/// FC온라인처럼 **자리마다 제 포지션 라벨**을 가진다(`Layout.labels`, 없으면 포메이션 기본 라벨).
///
/// 불변식(스크립트로 검증):
/// - 한 번의 이동은 **그 자리 하나의 좌표·라벨만** 바꾼다. 다른 자리는 선수·라벨·위치 모두 그대로.
/// - 자기 기본 위치(또는 같은 구역 안)로 옮기면 아무것도 바뀌지 않는다.
/// - 라벨 11개가 어떤 포메이션과 정확히 일치하면 포메이션 id 가 그쪽으로 바뀐다(화면 변화 없음).
///   아니면 id 는 그대로, 이름은 "커스텀 (≈가장 가까운 포메이션)".
/// - 선수는 사라지지 않는다(포메이션을 직접 바꿔도 11명 모두 새 자리로 재배치).
enum PitchLayout {
    // MARK: - 구역

    /// GK 구역 경계 — 이보다 아래(y 가 큼)는 골키퍼만.
    static let gkZoneTop: Double = 88
    /// 필드 선수가 내려올 수 있는 한계 — GK(92)·수비 라인(78)과 겹치지 않게.
    static let fieldMaxY: Double = 80
    /// 피치 안쪽 여백 — x 는 포메이션 기본 좌표와 같은 8~92(64pt 이름표가 피치 밖으로 나가지 않게)
    static let minX: Double = 8, maxX: Double = 92
    static let minY: Double = 6, maxY: Double = 96

    /// 드래그 위치를 피치 안으로 가두고 GK 규칙을 적용한다.
    /// 골키퍼는 GK 구역을 벗어날 수 없고, 필드 선수는 GK 구역에 들어갈 수 없다(골키퍼는 항상 정확히 1명).
    static func clamp(_ p: PitchPoint, isGK: Bool) -> PitchPoint {
        let x = min(maxX, max(minX, p.x))
        let y = isGK ? min(maxY, max(gkZoneTop, p.y)) : min(fieldMaxY, max(minY, p.y))
        return PitchPoint(x: x.rounded(), y: y.rounded())
    }

    /// 좌표 → FC온라인 포지션 구역 라벨(앱 포메이션이 쓰는 라벨 집합 안에서).
    ///
    /// 세로(y) 구간으로 라인을, 가로(x)로 좌/중/우를 정한다. 측면 경계는 공격 쪽(y<42)은 30/70
    /// (LW 25 는 측면, 투톱 ST 33 은 중앙), 수비·미드 쪽은 22/78 — 기본 좌표 CM 25·75 가 LM/RM 으로 읽히지 않게.
    /// 포메이션마다 같은 좌표에 다른 라벨을 쓰기도 해(4-1-4-1 CM y37 vs 4-2-3-1 CAM y36) 완전한 역함수는 불가능하다 —
    /// 그래서 `move` 는 "옛 위치와 같은 구역이면 라벨 유지" 규칙으로 기본 위치 근처의 흔들림을 흡수한다.
    static func label(at p: PitchPoint) -> String {
        let y = p.y, x = p.x
        if y >= gkZoneTop { return "GK" }
        let wideL: Double = y < 42 ? 30 : 22
        let wideR: Double = 100 - wideL
        let side = x < wideL ? -1 : x > wideR ? 1 : 0
        func pick(_ l: String, _ c: String, _ r: String) -> String { side < 0 ? l : side > 0 ? r : c }
        switch y {
        case ..<24: return pick("LW", "ST", "RW")
        case ..<30: return pick("LW", "CF", "RW")
        case ..<42: return pick("LAM", "CAM", "RAM")
        case ..<54: return pick("LM", "CM", "RM")
        case ..<64: return pick("LM", "CDM", "RM")
        case ..<72: return pick("LWB", "CDM", "RWB")
        default: return pick("LB", "CB", "RB")
        }
    }

    // MARK: - 라인

    enum Line: String { case gk = "GK", def = "DEF", mid = "MID", att = "ATT" }

    /// 웹 `posLineOf` 와 같은 표 — 모르는 라벨은 MID.
    static func line(of pos: String) -> Line {
        switch pos {
        case "GK": return .gk
        case "LB", "RB", "CB", "LWB", "RWB": return .def
        case "CF", "ST", "LW", "RW": return .att
        default: return .mid
        }
    }

    // MARK: - 포메이션 추정

    /// 웹 bestFormationId 의 점수: 정확 포지션 일치 ×2 + 잔여 인원의 같은 라인 일치. 11명 전원 일치면 22.
    static func score(_ labels: [String], _ f: Formation) -> Int {
        var playerCounts: [String: Int] = [:]
        for l in labels { playerCounts[l, default: 0] += 1 }
        var slotCounts: [String: Int] = [:]
        for s in f.slots { slotCounts[s.pos, default: 0] += 1 }
        var exact = 0
        var restByLine: [Line: Int] = [:]
        for label in playerCounts.keys.sorted() {
            let n = playerCounts[label]!
            let m = min(n, slotCounts[label] ?? 0)
            exact += m
            if m > 0 { slotCounts[label]! -= m }
            if n - m > 0 { restByLine[line(of: label), default: 0] += n - m }
        }
        var slotRestByLine: [Line: Int] = [:]
        for (pos, n) in slotCounts where n > 0 { slotRestByLine[line(of: pos), default: 0] += n }
        var lineScore = 0
        for (l, n) in restByLine { lineScore += min(n, slotRestByLine[l] ?? 0) }
        return exact * 2 + lineScore
    }

    /// 라벨 구성이 정확히 같은 포메이션들(예: 3-5-2 와 5-3-2 는 라벨 구성이 같다).
    static func exactFormations(labels: [String]) -> [Formation] {
        Formation.all.filter { $0.slots.count == labels.count && score(labels, $0) == labels.count * 2 }
    }

    // MARK: - 재매핑

    struct Source: Hashable {
        let id: String
        let label: String
        let point: PitchPoint
    }

    /// 슬롯(라벨·현재 위치)을 새 포메이션 슬롯 id 에 1:1 매핑한다(헝가리안 최소 비용 배정).
    ///
    /// - `strict`(드래그 이동): 라벨이 다른 슬롯으로는 사실상 못 간다. 같은 id 를 유지하면 비용 0 —
    ///   옮기지 않은 선수의 라벨·자리가 흔들리지 않게.
    /// - 기본(포메이션 직접 선택): 거리 + 라벨 벌점(정확 0 · 같은 라인 25 · 다른 라인 60). GK↔필드는 사실상 금지.
    static func rekey(_ sources: [Source], to f: Formation, strict: Bool = false) -> [String: String] {
        rekeyWithCost(sources, to: f, strict: strict).map
    }

    static func rekeyWithCost(_ sources: [Source], to f: Formation, strict: Bool) -> (map: [String: String], cost: Double) {
        let targets = f.slots
        let n = max(sources.count, targets.count)
        guard n > 0 else { return ([:], 0) }
        func cost(_ i: Int, _ j: Int) -> Double {
            guard i < sources.count, j < targets.count else { return 0 }   // 더미 행/열
            let s = sources[i], t = targets[j]
            let d = hypot(s.point.x - t.x, s.point.y - t.y)
            if strict {
                if s.label != t.pos { return 10_000 }
                return s.id == t.id ? 0 : d + 1
            }
            if (s.label == "GK") != (t.pos == "GK") { return 10_000 }
            let penalty: Double = s.label == t.pos ? 0 : line(of: s.label) == line(of: t.pos) ? 25 : 60
            return d + penalty
        }
        var out: [String: String] = [:]
        var total: Double = 0
        for (i, j) in hungarian(n: n, cost: cost) where i < sources.count && j < targets.count {
            out[sources[i].id] = targets[j].id
            total += cost(i, j)
        }
        return (out, total)
    }

    /// n×n 최소 비용 배정(포텐셜 헝가리안, O(n³)). 반환: (행, 열) 쌍.
    static func hungarian(n: Int, cost: (Int, Int) -> Double) -> [(Int, Int)] {
        let inf = Double.greatestFiniteMagnitude
        var u = [Double](repeating: 0, count: n + 1), v = u
        var p = [Int](repeating: 0, count: n + 1), way = p
        for i in 1...n {
            p[0] = i
            var j0 = 0
            var minv = [Double](repeating: inf, count: n + 1)
            var used = [Bool](repeating: false, count: n + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = inf, j1 = 0
                for j in 1...n where !used[j] {
                    let cur = cost(i0 - 1, j - 1) - u[i0] - v[j]
                    if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                    if minv[j] < delta { delta = minv[j]; j1 = j }
                }
                for j in 0...n {
                    if used[j] { u[p[j]] += delta; v[j] -= delta } else { minv[j] -= delta }
                }
                j0 = j1
            } while p[j0] != 0
            repeat { let j1 = way[j0]; p[j0] = p[j1]; j0 = j1 } while j0 != 0
        }
        return (1...n).map { (p[$0] - 1, $0 - 1) }
    }

    // MARK: - 배치 상태

    struct Layout {
        var formation: Formation
        var slots: [String: SquadSlotModel]
        var coords: [String: PitchPoint]
        /// 자리별 포지션 라벨(FC온라인처럼 자리마다 제 라벨). 포메이션 기본 라벨과 같으면 두지 않는다.
        var labels: [String: String] = [:]
        /// 옮긴 자리의 (포메이션 전환 후) 슬롯 id
        var movedId: String = ""

        func point(of s: FormationSlot) -> PitchPoint { coords[s.id] ?? PitchLayout.defaultPoint(s) }
        func pos(of s: FormationSlot) -> String { labels[s.id] ?? s.pos }
        /// 11자리의 실제 라벨
        var effectiveLabels: [String] { formation.slots.map { pos(of: $0) } }
        /// 옮긴 자리의 결과 라벨
        var movedLabel: String? { formation.slots.first { $0.id == movedId }.map { pos(of: $0) } }
        /// 라벨 11개가 현재 포메이션과 정확히 일치하는지(아니면 "커스텀")
        var isExact: Bool { score(effectiveLabels, formation) == formation.slots.count * 2 }
        /// 포메이션 칩 문구 — 정확 일치면 "4-4-2", 아니면 "커스텀 (≈4-4-2)"
        var title: String { isExact ? formation.name : "커스텀 (≈\(nearestFormation(labels: effectiveLabels, prefer: labels.keys.sorted().compactMap { labels[$0] }, current: formation.id).name))" }
    }

    static func defaultPoint(_ s: FormationSlot) -> PitchPoint { PitchPoint(x: s.x, y: s.y) }
    /// 이보다 적게(피치 %) 옮기면 라벨을 다시 정하지 않는다.
    static let relabelMinDistance: Double = 6

    /// 웹 bestFormationId — 점수가 가장 높은 포메이션.
    /// 동점이면 ① 자리 라벨(`prefer`, 사용자가 옮겨 만든 라벨)을 더 많이 가진 포메이션 ② 현재 포메이션 ③ 목록 순서.
    /// (4-3-3 에서 LW 를 LM 으로 내리면 4-3-3 과 4-4-2 가 동점인데, 사용자의 의도는 4-4-2 쪽이다)
    static func nearestFormation(labels: [String], prefer: [String] = [], current: String? = nil) -> Formation {
        var best = Formation.all[0]
        var bestKey = (-1, -1, -1)
        for f in Formation.all {
            var avail: [String: Int] = [:]
            for s in f.slots { avail[s.pos, default: 0] += 1 }
            var satisfied = 0
            for p in prefer where (avail[p] ?? 0) > 0 { avail[p]! -= 1; satisfied += 1 }
            let key = (score(labels, f), satisfied, f.id == current ? 1 : 0)
            if key > bestKey { bestKey = key; best = f }
        }
        return best
    }

    // MARK: - 자리 옮기기(빈 잔디에 놓기)

    /// 슬롯 `id` 를 `point` 로 옮긴다. **그 자리의 좌표·라벨만** 바뀌고 다른 자리는 절대 바뀌지 않는다.
    ///
    /// 1. 좌표 저장(GK 규칙 clamp). 기본 위치로 돌아오면 좌표를 지운다.
    /// 2. 라벨: 놓은 곳의 구역 라벨. 단 현재 라벨과 같거나, 옛 위치와 같은 구역이거나, 6% 미만 이동이면 그대로
    ///    (기본 좌표와 구역표가 어긋나는 포메이션에서 제자리 근처 흔들림이 라벨을 바꾸지 않게). GK 자리는 항상 GK.
    /// 3. 라벨 11개가 어떤 포메이션과 정확히 일치하면 그 포메이션 id 로 옮겨 탄다(`normalize` — 화면 변화 없음).
    ///    일치하는 게 없으면 포메이션 id 는 그대로 두고 "커스텀 (≈가장 가까운 포메이션)" 으로 보인다.
    static func move(_ l: Layout, id: String, to point: PitchPoint) -> Layout {
        guard let slot = l.formation.slots.first(where: { $0.id == id }) else { return l }
        let cur = l.pos(of: slot)
        let p = clamp(point, isGK: cur == "GK")
        let old = l.point(of: slot)
        var out = l
        out.movedId = id
        out.coords[id] = p == defaultPoint(slot) ? nil : p
        if cur == "GK" { return out }   // 골키퍼는 구역 안에서만 → 라벨 불변

        let zone = label(at: p)
        if zone == cur || zone == label(at: old) || hypot(p.x - old.x, p.y - old.y) < relabelMinDistance { return out }
        out.labels[id] = zone == slot.pos ? nil : zone
        return normalize(out)
    }

    /// 라벨 11개가 정확히 일치하는 포메이션으로 id 를 맞춘다(현재가 이미 일치하면 그대로).
    /// 같은 라벨끼리만 옮겨 태우므로 선수·라벨·화면 위치는 하나도 바뀌지 않는다.
    static func normalize(_ l: Layout) -> Layout {
        if l.isExact { return l }
        let sources = l.formation.slots.map { Source(id: $0.id, label: l.pos(of: $0), point: l.point(of: $0)) }
        guard let best = exactFormations(labels: sources.map(\.label))
            .map({ f in (f, rekeyWithCost(sources, to: f, strict: true)) })
            .min(by: { $0.1.cost < $1.1.cost })
        else { return l }
        let f = best.0, map = best.1.map
        var out = Layout(formation: f, slots: [:], coords: [:], labels: [:], movedId: map[l.movedId] ?? l.movedId)
        for s in sources {
            guard let nid = map[s.id], let t = f.slots.first(where: { $0.id == nid }) else { return l }
            if let player = l.slots[s.id] { out.slots[nid] = player.moved(to: nid) }
            if s.point != defaultPoint(t) { out.coords[nid] = s.point }
            if s.label != t.pos { out.labels[nid] = s.label }   // 정확 일치라 실제로는 비어 있다
        }
        return out
    }

    /// 포메이션을 직접 고를 때 — 선수를 한 명도 버리지 않고 새 포메이션 자리로 재배치한다(좌표·자리 라벨 초기화).
    static func changeFormation(_ l: Layout, to f: Formation) -> Layout {
        let sources = l.formation.slots.map { Source(id: $0.id, label: l.pos(of: $0), point: l.point(of: $0)) }
        let map = rekey(sources, to: f)
        var slots: [String: SquadSlotModel] = [:]
        for (old, player) in l.slots { if let nid = map[old] { slots[nid] = player.moved(to: nid) } }
        return Layout(formation: f, slots: slots, coords: [:], labels: [:])
    }

    // MARK: - 저장·불러오기

    /// POST /api/squad 의 slots — 옮긴 자리는 x/y, 라벨이 기본과 다른 자리는 pos 를 함께 보낸다.
    static func saveSlots(_ l: Layout) -> [[String: Any]] {
        l.formation.slots.compactMap { fs in
            guard let s = l.slots[fs.id] else { return nil }
            var d: [String: Any] = ["slotId": fs.id, "spid": s.spid, "name": s.name]
            if let img = s.imageSpid { d["imageSpid"] = img }
            if let season = s.season, !season.isEmpty { d["season"] = season }   // 불러온 스쿼드·웹에서 시즌 배지가 빠지지 않게
            if let p = l.coords[fs.id] { d["x"] = p.x; d["y"] = p.y }
            if let pos = l.labels[fs.id], pos != fs.pos { d["pos"] = pos }
            return d
        }
    }

    /// 서버 슬롯(선택적 x/y/pos) → 배치 상태. 포메이션에 없는 slotId 는 버린다.
    static func restore(formation f: Formation, slots list: [SquadSlotModel]) -> Layout {
        var out = Layout(formation: f, slots: [:], coords: [:], labels: [:])
        for sl in list {
            guard let fs = f.slots.first(where: { $0.id == sl.slotId }) else { continue }
            var clean = sl.moved(to: sl.slotId)
            clean.pos = nil
            out.slots[fs.id] = clean
            if let x = sl.x, let y = sl.y { out.coords[fs.id] = PitchPoint(x: x, y: y) }
            if let pos = sl.pos, !pos.isEmpty, pos != fs.pos { out.labels[fs.id] = pos }
        }
        return out
    }

    // MARK: - 겹침

    /// 슬롯 하나가 차지하는 영역(반폭·반높이, pt). 원(44pt)이 겹치지 않을 간격보다 조금 넓게.
    /// 5인 라인의 기본 간격(16% ≈ 59pt)보다 작아야 제자리 근처에서 살짝 옮길 때 옆 선수와 교환되지 않는다.
    static let occupyHalfWidth: Double = 48, occupyHalfHeight: Double = 40

    /// `p`(pt)가 차지 영역 안에 들어가는 가장 가까운 다른 자리. 드래그를 여기서 놓으면 교환한다(겹쳐 놓기 금지).
    static func occupant(near p: (x: Double, y: Double), in l: Layout, excluding id: String, size: (w: Double, h: Double)) -> FormationSlot? {
        var best: (FormationSlot, Double)?
        for s in l.formation.slots where s.id != id {
            let q = l.point(of: s)
            let dx = abs(q.x / 100 * size.w - p.x), dy = abs(q.y / 100 * size.h - p.y)
            guard dx < occupyHalfWidth, dy < occupyHalfHeight else { continue }
            let d = hypot(dx, dy)
            if d < (best?.1 ?? .infinity) { best = (s, d) }
        }
        return best?.0
    }

    // MARK: - 교환

    /// 두 슬롯의 점유자(선수·시즌·사진)만 맞바꾼다. 빈 자리로 놓으면 이동. 자리(좌표·라벨)는 그대로.
    static func swap(_ slots: [String: SquadSlotModel], _ a: String, _ b: String) -> [String: SquadSlotModel] {
        guard a != b else { return slots }
        var out = slots
        out[a] = slots[b].map { $0.moved(to: a) }
        out[b] = slots[a].map { $0.moved(to: b) }
        return out
    }
}

extension SquadSlotModel {
    /// 같은 선수를 다른 슬롯 id 로 옮긴 사본(좌표는 모델의 coords 가 관리하므로 비운다).
    func moved(to slotId: String) -> SquadSlotModel {
        SquadSlotModel(slotId: slotId, spid: spid, name: name, season: season, x: nil, y: nil, imageSpid: imageSpid)
    }
}
