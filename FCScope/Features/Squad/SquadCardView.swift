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
    /// 자리 라벨(pos)·좌표까지 반영한 배치 — 칩과 같은 "커스텀 (≈4-4-2)" 문구를 쓰기 위해
    private var layout: PitchLayout.Layout { PitchLayout.restore(formation: formation, slots: Array(data.slots.values)) }
    private var filled: Int { formation.slots.filter { data.slots[$0.id] != nil }.count }
    /// 가장 많이 쓰인 시즌 (서버 topSeason 과 동일 의도)
    private var topSeason: String? {
        let counts = data.slots.values.compactMap { $0.season }.filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    // 인스타 스토리 안전영역(y 264~1560) 안에 배치 — v1 은 y 70부터 그려 로고·포메이션이 가려졌다.
    var body: some View {
        CardCanvas {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(chip: layout.title)
                Spacer().frame(height: 12)
                NicknameTitle(text: data.name, maxSize: 72, minSize: 44, boxHeight: 88)
                HStack(spacing: 12) {
                    Text("\(filled)명 배치").font(.pretendard(28)).foregroundStyle(CardPalette.muted)
                    if let s = topSeason {
                        Text(s).font(.pretendard(26, .bold)).foregroundStyle(CardPalette.gold)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(CardPalette.gold.opacity(0.15), in: Capsule())
                    }
                }
                .frame(height: 44)
                Spacer().frame(height: 16)
                pitch
                Spacer(minLength: 0)
                CardFooter(cta: "내 스쿼드도 만들기 →")
            }
        }
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
                    p.addEllipse(in: CGRect(x: size.width / 2 - 80, y: size.height / 2 - 80, width: 160, height: 160))
                    p.addRect(CGRect(x: size.width * 0.22, y: 16, width: size.width * 0.56, height: size.height * 0.15))
                    p.addRect(CGRect(x: size.width * 0.22, y: size.height - 16 - size.height * 0.15, width: size.width * 0.56, height: size.height * 0.15))
                    ctx.stroke(p, with: .color(.white.opacity(0.14)), lineWidth: 3)
                }
                ForEach(formation.slots) { slot in
                    // 드래그로 옮긴 자리는 선수 슬롯의 x/y(0~100)를 쓴다 — 빌더·공유 페이지와 같은 배치.
                    let p = data.slots[slot.id]
                    node(slot: slot)
                        .position(x: w * (p?.x ?? slot.x) / 100, y: h * Self.cardY(p?.y ?? slot.y) / 100)
                }
            }
        }
        .frame(height: 1010)
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
            .frame(width: 96, height: 96)
            .clipShape(Circle())

            Text(player.map { short($0.name) } ?? layout.pos(of: slot))
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

    /// 카드 피치는 빌더보다 납작해 수비 라인(78)과 GK(92)가 겹쳤다 — 78 아래만 골라인 쪽으로 늘린다(92 → 93.5).
    static func cardY(_ y: Double) -> Double { y <= 78 ? y : 78 + (y - 78) * (15.5 / 14.0) }

    private func short(_ name: String, _ n: Int = 6) -> String {
        name.count > n ? String(name.prefix(n)) + "…" : name
    }
}
