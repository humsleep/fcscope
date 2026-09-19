#if DEBUG
import SwiftUI

/// 개발용: `-renderCards <구단주명>` 인자로 실행하면 모든 공유 카드를 Documents/cards/*.png 로 저장한다.
/// 시뮬레이터에서 카드 디자인을 한 번에 검수하기 위한 도구(릴리스 빌드에는 포함되지 않음).
enum CardDebugExport {
    @MainActor
    static func runIfRequested() {
        guard let nick = UserDefaults.standard.string(forKey: "renderCards"), !nick.isEmpty else { return }
        Task { @MainActor in
            let enc = nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick
            guard let o: UserOverview = try? await APIClient.shared.getAndCache("/api/v1/user/\(enc)", query: ["type": "50"], auth: false) else {
                print("[cards] overview failed"); return
            }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cards")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var cards: [StoryCard] = [.user(o), .rank(o), .streak(o), .weekly(o)]
            if let r = o.rivals.first { cards.append(.rival(o, r)) }
            if let pl: PlayersResponse = try? await APIClient.shared.getAndCache("/api/v1/user/\(enc)/players", query: ["type": "50"], auth: false),
               let picks = pl.picks { cards.append(.pickMatch(o, picks)) }
            for c in cards {
                if let img = await c.render(), let data = img.pngData() {
                    let name = c.filename.split(separator: "-").dropFirst().first.map(String.init) ?? "card"
                    try? data.write(to: dir.appendingPathComponent("\(name).png"))
                }
            }
            if let m = o.matches.first,
               let detail: MatchDetailResponse = try? await APIClient.shared.get("/api/v1/match/\(m.matchId)", query: ["me": o.profile.ouid], auth: false) {
                if let p = detail.potm { await ImageCache.prefetch(spids: [p.spId]) }
                if let img = ShareCardRenderer.render(view: MatchCardView(m: detail), size: CGSize(width: CardLayout.width, height: CardLayout.height)),
                   let data = img.pngData() { try? data.write(to: dir.appendingPathComponent("match.png")) }
            }
            if let r: PresetResponse = try? await APIClient.shared.get("/api/squad/preset", query: ["id": "korea"], auth: false) {
                let slots = Dictionary(r.slots.map { ($0.slotId, $0) }, uniquingKeysWith: { a, _ in a })
                let data = SquadCardData(name: r.name, formationId: r.formation, slots: slots, shareCode: "sample")
                await ImageCache.prefetch(spids: slots.values.map(\.displaySpid))
                if let img = ShareCardRenderer.render(view: SquadCardView(data: data), size: CGSize(width: CardLayout.width, height: CardLayout.height)),
                   let png = img.pngData() { try? png.write(to: dir.appendingPathComponent("squad.png")) }
            }
            print("[cards] done → \(dir.path)")
        }
    }
}
#endif
