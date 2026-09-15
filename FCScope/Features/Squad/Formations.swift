import Foundation

/// lib/squad/formations.ts 이식 — 슬롯 좌표(x 0~100, y 0~100; 92=우리 골대)
struct FormationSlot: Identifiable, Hashable { let id: String; let pos: String; let x: Double; let y: Double }
struct Formation: Identifiable, Hashable {
    let id: String; let name: String; let line: String; let slots: [FormationSlot]
    static func build(_ rows: [[String]]) -> [FormationSlot] {
        var out: [FormationSlot] = []; var counts: [String: Int] = [:]
        let outRows = rows.count - 1
        for (ri, row) in rows.enumerated() {
            let y: Double = ri == 0 ? 92 : outRows <= 1 ? 20 : (78 - Double(ri - 1) * (62 / Double(outRows - 1))).rounded()
            for (j, pos) in row.enumerated() {
                let x = min(92, max(8, (Double(j + 1) / Double(row.count + 1) * 100).rounded()))
                let key = pos.lowercased(); counts[key, default: 0] += 1
                out.append(FormationSlot(id: "\(key)\(counts[key]!)", pos: pos, x: x, y: y))
            }
        }
        return out
    }
    static let all: [Formation] = [
        ("433", "4-3-3", "4", [["GK"], ["LB","CB","CB","RB"], ["CM","CM","CM"], ["LW","ST","RW"]]),
        ("442", "4-4-2", "4", [["GK"], ["LB","CB","CB","RB"], ["LM","CM","CM","RM"], ["ST","ST"]]),
        ("4231", "4-2-3-1", "4", [["GK"], ["LB","CB","CB","RB"], ["CDM","CDM"], ["LAM","CAM","RAM"], ["ST"]]),
        ("4141", "4-1-4-1", "4", [["GK"], ["LB","CB","CB","RB"], ["CDM"], ["LM","CM","CM","RM"], ["ST"]]),
        ("4312", "4-3-1-2", "4", [["GK"], ["LB","CB","CB","RB"], ["CM","CM","CM"], ["CAM"], ["ST","ST"]]),
        ("41212", "4-1-2-1-2", "4", [["GK"], ["LB","CB","CB","RB"], ["CDM"], ["LM","RM"], ["CAM"], ["ST","ST"]]),
        ("4222", "4-2-2-2", "4", [["GK"], ["LB","CB","CB","RB"], ["CDM","CDM"], ["LAM","RAM"], ["ST","ST"]]),
        ("4411", "4-4-1-1", "4", [["GK"], ["LB","CB","CB","RB"], ["LM","CM","CM","RM"], ["CF"], ["ST"]]),
        ("451", "4-5-1", "4", [["GK"], ["LB","CB","CB","RB"], ["LM","CM","CM","CM","RM"], ["ST"]]),
        ("4321", "4-3-2-1", "4", [["GK"], ["LB","CB","CB","RB"], ["CM","CM","CM"], ["CF","CF"], ["ST"]]),
        ("424", "4-2-4", "4", [["GK"], ["LB","CB","CB","RB"], ["CM","CM"], ["LW","ST","ST","RW"]]),
        ("352", "3-5-2", "3", [["GK"], ["CB","CB","CB"], ["LWB","CM","CM","CM","RWB"], ["ST","ST"]]),
        ("343", "3-4-3", "3", [["GK"], ["CB","CB","CB"], ["LM","CM","CM","RM"], ["LW","ST","RW"]]),
        ("3412", "3-4-1-2", "3", [["GK"], ["CB","CB","CB"], ["LM","CM","CM","RM"], ["CAM"], ["ST","ST"]]),
        ("3142", "3-1-4-2", "3", [["GK"], ["CB","CB","CB"], ["CDM"], ["LM","CM","CM","RM"], ["ST","ST"]]),
        ("3421", "3-4-2-1", "3", [["GK"], ["CB","CB","CB"], ["LM","CM","CM","RM"], ["CAM","CAM"], ["ST"]]),
        ("532", "5-3-2", "5", [["GK"], ["LWB","CB","CB","CB","RWB"], ["CM","CM","CM"], ["ST","ST"]]),
        ("541", "5-4-1", "5", [["GK"], ["LWB","CB","CB","CB","RWB"], ["LM","CM","CM","RM"], ["ST"]]),
        ("523", "5-2-3", "5", [["GK"], ["LWB","CB","CB","CB","RWB"], ["CM","CM"], ["LW","ST","RW"]]),
    ].map { Formation(id: $0.0, name: $0.1, line: $0.2, slots: build($0.3)) }
    static func get(_ id: String) -> Formation { all.first { $0.id == id } ?? all[0] }

    /// 포지션 라벨 → 라인 (임포트 배치용)
    static func lineOf(_ pos: String) -> String {
        if pos == "GK" { return "GK" }
        if ["CB","LCB","RCB","LB","RB","LWB","RWB","SW"].contains(pos) { return "DEF" }
        if ["ST","CF","LW","RW","LF","RF","LS","RS"].contains(pos) { return "ATT" }
        return "MID"
    }
}

/// 팀 프리셋 목록 (서버 /api/squad/preset?id= 로 spid 해석)
///
/// ⚠️ 서버(웹 lib/squad/presets.ts PRESETS)에 **정의된 팀만** 둔다. 예전엔 18팀을 나열했지만 서버에는 6팀뿐이라
/// 나머지 12팀은 누르면 404 "not found" 가 떴다. 팀을 늘리려면 서버에 먼저 추가할 것.
struct PresetTeam: Identifiable { let id: String; let league: String; let team: String }
let PRESET_TEAMS: [PresetTeam] = [
    ("arsenal", "프리미어리그", "아스날"), ("mancity", "프리미어리그", "맨체스터 시티"), ("liverpool", "프리미어리그", "리버풀"), ("tottenham", "프리미어리그", "토트넘"),
    ("realmadrid", "라리가", "레알 마드리드"), ("barcelona", "라리가", "바르셀로나"),
].map { PresetTeam(id: $0.0, league: $0.1, team: $0.2) }
