import SwiftUI

/**
 스쿼드 공유 카드 (1080×1920) — 서버 `lib/card/squad-card.tsx` 를 앱에서 재현.

 서버 버전은 선수 사진 11장을 각각 fetch 해 data URI 로 인라인한 뒤 satori 로 래스터한다.
 (카드 1장에 넥슨 CDN 왕복 11회 + 대용량 문자열 + resvg 래스터)
 앱은 이미 디스크에 캐시된 이미지를 그대로 쓰므로 네트워크 0, 서버 부하 0.
 */
struct SquadCardView: View {
    let data: SquadCardData

    private var formation: Formation { Formation.get(data.formationId) }
    private var filled: Int { formation.slots.filter { data.slots[$0.id] != nil }.count }
    /// 가장 많이 쓰인 시즌 (서버 topSeason 과 동일 의도)
    private var topSeason: String? {
        let counts = data.slots.values.compactMap { $0.season }.filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text("FC").font(.scoreboard(44)).foregroundStyle(CardPalette.lime)
                Text("SCOPE").font(.scoreboard(44)).foregroundStyle(CardPalette.ink)
                Spacer()
                Text(formation.name).font(.scoreboard(44)).foregroundStyle(CardPalette.gold)
            }
            Text(data.name)
                .font(.pretendard(56, .bold))
                .foregroundStyle(CardPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 18)
            HStack(spacing: 12) {
                Text("\(filled)명 배치").font(.pretendard(30)).foregroundStyle(CardPalette.muted)
                if let s = topSeason {
                    Text(s).font(.pretendard(26, .bold)).foregroundStyle(CardPalette.gold)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(CardPalette.gold.opacity(0.15), in: Capsule())
                }
            }
            .padding(.top, 6)

            pitch.padding(.top, 28)

            Spacer(minLength: 0)
            HStack {
                Text("내 스쿼드도 만들기 →").font(.pretendard(30)).foregroundStyle(CardPalette.muted)
                Spacer()
                Text(AppConfig.shareHost).font(.pretendard(30, .bold)).foregroundStyle(CardPalette.lime)
            }
        }
        .padding(70)
        .frame(width: ShareCardView.width, height: ShareCardView.height, alignment: .topLeading)
        .background(CardPalette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var pitch: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [Color(hex: 0x123322), Color(hex: 0x0d2419)], startPoint: .top, endPoint: .bottom))
                Canvas { ctx, size in
                    var p = Path()
                    p.addRect(CGRect(x: 16, y: 16, width: size.width - 32, height: size.height - 32))
                    p.move(to: CGPoint(x: 16, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width - 16, y: size.height / 2))
                    p.addEllipse(in: CGRect(x: size.width / 2 - 90, y: size.height / 2 - 90, width: 180, height: 180))
                    p.addRect(CGRect(x: size.width * 0.22, y: 16, width: size.width * 0.56, height: size.height * 0.15))
                    p.addRect(CGRect(x: size.width * 0.22, y: size.height - 16 - size.height * 0.15, width: size.width * 0.56, height: size.height * 0.15))
                    ctx.stroke(p, with: .color(.white.opacity(0.14)), lineWidth: 3)
                }
                ForEach(formation.slots) { slot in
                    node(slot: slot)
                        .position(x: w * slot.x / 100, y: h * slot.y / 100)
                }
            }
        }
        .frame(height: 1180)
    }

    @ViewBuilder
    private func node(slot: FormationSlot) -> some View {
        let player = data.slots[slot.id]
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.white.opacity(0.10))
                if let p = player, let img = ImageCache.cached(spid: p.displaySpid) {
                    Image(uiImage: img).resizable().scaledToFill()
                }
                Circle().stroke(player == nil ? Color.white.opacity(0.25) : CardPalette.lime, lineWidth: 4)
            }
            .frame(width: 108, height: 108)
            .clipShape(Circle())

            Text(player.map { short($0.name) } ?? slot.pos)
                .font(.pretendard(26, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.black.opacity(0.5), in: Capsule())
            if let s = player?.season, !s.isEmpty {
                Text(s).font(.pretendard(21, .bold)).foregroundStyle(CardPalette.gold)
            }
        }
        .frame(width: 170)
    }

    private func short(_ name: String, _ n: Int = 6) -> String {
        name.count > n ? String(name.prefix(n)) + "…" : name
    }
}
