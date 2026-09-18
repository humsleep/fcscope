import Foundation

/// 피치 좌표(x 0~100 왼→오, y 0~100 위=공격 · 92=우리 골대)
struct PitchPoint: Hashable, Codable {
    var x: Double
    var y: Double
}

/// 스쿼드 피치 드래그의 순수 로직 — UI·네트워크 의존 없음(스크립트로 검증 가능하게 분리).
///
/// - 좌표 → 포지션 라벨(FC온라인 포지션 구역)
/// - 라벨 11개 → 가장 가까운 포메이션(웹 `lib/squad/assign.ts` bestFormationId 이식)
/// - 포메이션이 바뀔 때 슬롯 id 재매핑(라벨 벌점 + 거리 최소 비용 배정)
/// - 두 슬롯 점유자 교환
enum PitchLayout {
    // MARK: - 구역

    /// GK 구역 경계 — 이보다 아래(y 가 큼)는 골키퍼만.
    static let gkZoneTop: Double = 86
    /// 피치 안쪽 여백 — x 는 포메이션 기본 좌표와 같은 8~92(64pt 이름표가 피치 밖으로 나가지 않게)
    static let minX: Double = 8, maxX: Double = 92
    static let minY: Double = 6, maxY: Double = 96

    /// 드래그 위치를 피치 안으로 가두고 GK 규칙을 적용한다.
    /// 골키퍼는 GK 구역을 벗어날 수 없고, 필드 선수는 GK 구역에 들어갈 수 없다(골키퍼는 항상 정확히 1명).
    static func clamp(_ p: PitchPoint, isGK: Bool) -> PitchPoint {
        let x = min(maxX, max(minX, p.x))
        let y = isGK ? min(maxY, max(gkZoneTop, p.y)) : min(gkZoneTop - 2, max(minY, p.y))
        return PitchPoint(x: x.rounded(), y: y.rounded())
    }

    /// 좌표 → FC온라인 포지션 라벨(앱 포메이션이 쓰는 라벨 집합 안에서).
    ///
    /// 세로(y) 구간으로 라인을, 가로(x)로 좌/중/우를 정한다. 측면 경계는 공격 쪽(y<42)은 30/70
    /// (LW 25 는 측면, 투톱 ST 33 은 중앙), 수비·미드 쪽은 22/78 — 기본 좌표 CM 25·75 가 LM/RM 으로 읽히지 않게.
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

    /// 웹 bestFormationId 이식: 점수 = 정확 포지션 일치 ×2 + 잔여 인원의 같은 라인 일치.
    static func score(_ labels: [String], _ f: Formation) -> Int {
        var playerCounts: [String: Int] = [:]
        for l in labels { playerCounts[l, default: 0] += 1 }
        var slotCounts: [String: Int] = [:]
        for s in f.slots { slotCounts[s.pos, default: 0] += 1 }
        var exact = 0
        var restByLine: [Line: Int] = [:]
        // 딕셔너리 순회 순서와 무관한 결과를 위해 키 정렬
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

    /// 라벨 11개에 가장 가까운 포메이션.
    /// 동점이면 ① 방금 옮긴 자리의 새 라벨을 가진 포메이션(재라벨이 살아남게) ② 현재 포메이션(불필요한 전환 방지)
    /// ③ 목록 앞 순서.
    static func bestFormation(labels: [String], preferLabel: String? = nil, current: String? = nil) -> Formation {
        var best = Formation.all[0]
        var bestKey = (-1, -1, -1)
        for f in Formation.all {
            let key = (score(labels, f),
                       preferLabel.map { l in f.slots.contains { $0.pos == l } ? 1 : 0 } ?? 0,
                       f.id == current ? 1 : 0)
            if key > bestKey { bestKey = key; best = f }
        }
        return best
    }

    // MARK: - 재매핑

    struct Source: Hashable {
        let id: String
        let label: String
        let point: PitchPoint
    }

    /// 기존 슬롯(라벨·현재 위치)을 새 포메이션 슬롯 id 에 1:1 매핑한다.
    ///
    /// 비용 = (현재 위치 ↔ 새 슬롯 기본 위치) 거리 + 라벨 벌점(정확 0 · 같은 라인 25 · 다른 라인 60)의
    /// 총합이 최소인 배정(헝가리안). 단계별 탐욕 매칭은 왼쪽 CM 이 오른쪽 RM 슬롯으로 가는 식의 어색한 결과를 냈다.
    /// `pinned`(방금 옮긴 자리)는 라벨이 다르면 큰 벌점 — 새 라벨을 확실히 받게. GK↔필드는 사실상 금지.
    static func rekey(_ sources: [Source], to f: Formation, pinned: String? = nil) -> [String: String] {
        let targets = f.slots
        let n = max(sources.count, targets.count)
        guard n > 0 else { return [:] }
        func cost(_ i: Int, _ j: Int) -> Double {
            guard i < sources.count, j < targets.count else { return 0 }   // 더미 행/열
            let s = sources[i], t = targets[j]
            if (s.label == "GK") != (t.pos == "GK") { return 10_000 }
            let d = hypot(s.point.x - t.x, s.point.y - t.y)
            let penalty: Double = s.label == t.pos ? 0 : line(of: s.label) == line(of: t.pos) ? 25 : 60
            return d + penalty * (s.id == pinned ? 8 : 1)
        }
        var out: [String: String] = [:]
        for (i, j) in hungarian(n: n, cost: cost) where i < sources.count && j < targets.count {
            out[sources[i].id] = targets[j].id
        }
        return out
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

    // MARK: - 자리 옮기기(빈 잔디에 놓기)

    struct Layout {
        var formation: Formation
        var slots: [String: SquadSlotModel]
        var coords: [String: PitchPoint]
        /// 옮긴 자리의 (재매핑 후) 슬롯 id
        var movedId: String
    }

    static func defaultPoint(_ s: FormationSlot) -> PitchPoint { PitchPoint(x: s.x, y: s.y) }

    /// 슬롯 `id` 를 `point` 로 옮기고, 그 자리의 라벨을 좌표로 다시 정한 뒤 포메이션을 11개 라벨에 맞춰 갱신한다.
    /// 선수·사진은 유지하고, 모든 자리의 현재 위치를 보존한다(새 포메이션 기본 위치와 다를 때만 좌표를 고정 — 피치가 튀지 않게).
    static func move(_ l: Layout, id: String, to point: PitchPoint) -> Layout {
        guard let slot = l.formation.slots.first(where: { $0.id == id }) else { return l }
        let isGK = slot.pos == "GK"
        let p = clamp(point, isGK: isGK)
        var out = l
        out.movedId = id
        // 골키퍼는 구역 안에서만 움직이므로 라벨·포메이션이 바뀌지 않는다.
        if isGK {
            out.coords[id] = p == defaultPoint(slot) ? nil : p
            return out
        }
        let newLabel = label(at: p)
        let sources = l.formation.slots.map { s in
            Source(id: s.id, label: s.id == id ? newLabel : s.pos, point: s.id == id ? p : (l.coords[s.id] ?? defaultPoint(s)))
        }
        let f = bestFormation(labels: sources.map(\.label), preferLabel: newLabel, current: l.formation.id)
        let map = rekey(sources, to: f, pinned: id)
        var slots: [String: SquadSlotModel] = [:]
        var coords: [String: PitchPoint] = [:]
        for s in sources {
            guard let nid = map[s.id], let target = f.slots.first(where: { $0.id == nid }) else { continue }
            if let player = l.slots[s.id] { slots[nid] = player.moved(to: nid) }
            if s.point != defaultPoint(target) { coords[nid] = s.point }
        }
        out.formation = f
        out.slots = slots
        out.coords = coords
        out.movedId = map[id] ?? id
        return out
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
