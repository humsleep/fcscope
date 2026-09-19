import SwiftUI
import UIKit

/**
 공유 카드 v2 공통 부품 (1080×1920, ImageRenderer scale 1 → 1pt = 1px).

 v1 은 "킥커 · 거대한 숫자 · 배지 3개" 텍스트 템플릿이라 닉네임이 작고 사진·엠블럼이 없어
 공유할 마음이 들지 않았다(2026-09-20 운영자·유저 패널 평가). v2 원칙:
 - 닉네임이 가장 큰 타이포 중 하나
 - 인스타 스토리 안전영역: 위 250px·아래 340px 는 인스타 UI 에 가려진다 → 콘텐츠는 y 264~1560
 - 부정 문구("분발 필요", "N연패 중")는 카드에 싣지 않는다 — 성적이 나빠도 올릴 수 있게
 - 이미지(선수·시즌 아이콘·계급 엠블럼)는 렌더 전에 CardImages 로 전부 받아 둔다
   (ImageRenderer 는 비동기 로딩을 기다리지 않는다)
 */
enum CardLayout {
    static let width: CGFloat = 1080
    static let height: CGFloat = 1920
    static let padX: CGFloat = 64
    static let contentWidth: CGFloat = 952
    static let safeTop: CGFloat = 264
    static let safeBottom: CGFloat = 1560
    static var contentHeight: CGFloat { safeBottom - safeTop }
}

// MARK: - 이미지

/// 렌더 직전에 받아 둔 이미지 묶음. 없으면 자리만 남긴다(카드 생성은 막지 않음).
struct CardImages {
    var players: [Int: UIImage] = [:]
    var seasons: [Int: UIImage] = [:]
    var urls: [String: UIImage] = [:]

    func player(_ spid: Int) -> UIImage? { players[spid] ?? ImageCache.cached(spid: spid) }
    func season(_ spid: Int) -> UIImage? { seasons[NexonCDN.seasonId(of: spid)] }
    func url(_ s: String?) -> UIImage? { s.flatMap { urls[$0] } }

    @MainActor
    static func load(players spids: [Int], seasonsFor seasonSpids: [Int] = [], urls: [String] = []) async -> CardImages {
        var out = CardImages()
        await SeasonIcons.shared.ensureLoaded()
        let seasonURLs: [(Int, URL)] = Set(seasonSpids.map { NexonCDN.seasonId(of: $0) }).compactMap { sid in
            // seasonId → 그 시즌의 아무 spid 로 URL 을 얻는다
            seasonSpids.first { NexonCDN.seasonId(of: $0) == sid }.flatMap { SeasonIcons.shared.url(forSpid: $0) }.map { (sid, $0) }
        }
        await withTaskGroup(of: (String, Int, UIImage?).self) { group in
            for spid in Set(spids) { group.addTask { ("p", spid, await ImageCache.load(spid: spid)) } }
            for (sid, url) in seasonURLs { group.addTask { ("s", sid, try? await ImageCache.pipeline.image(for: url)) } }
            for (i, u) in urls.enumerated() {
                guard let url = URL(string: u) else { continue }
                group.addTask { ("u", i, try? await ImageCache.pipeline.image(for: url)) }
            }
            for await (kind, key, img) in group {
                guard let img else { continue }
                switch kind {
                case "p": out.players[key] = img
                case "s": out.seasons[key] = img
                default: out.urls[urls[key]] = img
                }
            }
        }
        return out
    }
}

// MARK: - 캔버스

/// 배경(글로우 2개 + 잔디 결) + 안전영역 안 콘텐츠 + 가림 영역의 갤러리용 문구.
struct CardCanvas<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardPalette.bg
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { i in
                    Rectangle().fill(Color.white.opacity(i.isMultiple(of: 2) ? 0.018 : 0)).frame(width: 120)
                }
            }
            EllipticalGradient(colors: [CardPalette.lime.opacity(0.16), .clear],
                               center: .init(x: 0.5, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.55)
            EllipticalGradient(colors: [CardPalette.gold.opacity(0.07), .clear],
                               center: .init(x: 1, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.45)
            // 인스타 답장창에 가려지는 영역 — 갤러리 저장·메신저 공유 때만 보인다
            VStack(spacing: 18) {
                Text("FC온라인 전적 분석 · App Store에서 FC Scope 검색")
                    .font(.pretendard(26, .semibold)).foregroundStyle(CardPalette.muted)
                Text("FC SCOPE").font(.scoreboard(200)).foregroundStyle(Color.white.opacity(0.035)).lineLimit(1)
            }
            .frame(width: CardLayout.width)
            .offset(y: 1640)
            content
                .frame(width: CardLayout.contentWidth, height: CardLayout.contentHeight, alignment: .top)
                .offset(x: CardLayout.padX, y: CardLayout.safeTop)
        }
        .frame(width: CardLayout.width, height: CardLayout.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - 텍스트 부품

struct CardHeader: View {
    let chip: String
    var body: some View {
        HStack(spacing: 10) {
            Text("FC").font(.scoreboard(36)).foregroundStyle(CardPalette.lime)
            Text("SCOPE").font(.scoreboard(36)).foregroundStyle(CardPalette.ink)
            Spacer(minLength: 16)
            Text(chip).font(.pretendard(24, .semibold)).foregroundStyle(CardPalette.muted).lineLimit(1)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .frame(height: 44)
    }
}

/// 닉네임 — 글자 폭 계수로 크기를 직접 계산한다(길이가 달라도 한 줄, 베이스라인 고정).
struct NicknameTitle: View {
    let text: String
    var maxSize: CGFloat = 144
    var minSize: CGFloat = 72
    var boxHeight: CGFloat = 176
    var width: CGFloat = CardLayout.contentWidth
    var color: Color = CardPalette.ink
    var alignment: Alignment = .bottomLeading

    static func size(for s: String, width: CGFloat, max hi: CGFloat, min lo: CGFloat) -> CGFloat {
        var units: CGFloat = 0
        for sc in s.unicodeScalars {
            switch sc.value {
            case 0xAC00...0xD7A3, 0x3130...0x318F, 0x4E00...0x9FFF: units += 0.95
            case 65...90: units += 0.68
            case 97...122, 48...57: units += 0.56
            default: units += 0.5
            }
        }
        return Swift.min(hi, Swift.max(lo, floor(width / Swift.max(units, 1))))
    }

    var body: some View {
        Text(text)
            .font(.pretendard(Self.size(for: text, width: width, max: maxSize, min: minSize), .bold))
            .kerning(-2)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: width, height: boxHeight, alignment: alignment)
    }
}

/// 레벨 · 공식 최고 등급(엠블럼) · 다른 모드 최고 등급. 들어가는 만큼만.
struct IdentityPills: View {
    let level: Int
    let divisions: [DivisionCard]
    let images: CardImages
    var compact = false

    private var primary: DivisionCard? { divisions.first { $0.matchType == 50 } ?? divisions.first }
    private var others: [DivisionCard] { divisions.filter { $0.matchType != primary?.matchType } }
    private var h: CGFloat { compact ? 48 : 56 }
    private var d: CGFloat { compact ? 4 : 0 }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(primary.map { [$0] + others.prefix(1) } ?? [])
            row(primary.map { [$0] } ?? [])
            row([])
        }
        .frame(height: h, alignment: .leading)
    }

    private func row(_ divs: [DivisionCard]) -> some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("LV").font(.scoreboard(22 - d)).foregroundStyle(CardPalette.muted)
                Text("\(level)").font(.scoreboard(32 - d)).foregroundStyle(CardPalette.ink)
            }
            .padding(.horizontal, 22).frame(height: h)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(CardPalette.line, lineWidth: 2))
            ForEach(Array(divs.enumerated()), id: \.element.id) { i, dv in
                HStack(spacing: 10) {
                    if let img = images.url(dv.iconUrl) {
                        Image(uiImage: img).resizable().scaledToFit().frame(width: 40 - d, height: 40 - d)
                    }
                    Text(dv.divisionName).font(.pretendard(30 - d, .bold)).foregroundStyle(CardPalette.gold)
                }
                .fixedSize()
                .padding(.leading, 14).padding(.trailing, 22).frame(height: h)
                .background(CardPalette.gold.opacity(i == 0 ? 0.12 : 0.06), in: Capsule())
                .overlay(Capsule().stroke(CardPalette.gold.opacity(i == 0 ? 0.6 : 0.3), lineWidth: 2))
            }
        }
        .fixedSize()
    }
}

/// 긍정 포인트 칩 (▲ …)
struct HighlightChip: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Text("▲").font(.scoreboard(20)).foregroundStyle(CardPalette.lime)
            Text(text).font(.pretendard(26, .semibold)).foregroundStyle(CardPalette.ink).lineLimit(1)
        }
        .padding(.horizontal, 22).frame(height: 48)
        .background(CardPalette.lime.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(CardPalette.lime.opacity(0.45), lineWidth: 2))
    }
}

struct CardLabel: View {
    let text: String
    var body: some View {
        let ascii = text.unicodeScalars.allSatisfy(\.isASCII)
        Text(text)
            .font(ascii ? .scoreboard(22) : .pretendard(22, .semibold))
            .kerning(ascii ? 4 : 1)
            .foregroundStyle(CardPalette.muted)
            .lineLimit(1)
    }
}

/// 하단 CTA — 구분선 + 문구 + 도메인 필 (y 1488~1560)
struct CardFooter: View {
    var cta: String = "나도 내 전적 카드 만들기 →"
    private var host: String {
        let h = AppConfig.shareHost
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
    var body: some View {
        VStack(spacing: 16) {
            Rectangle().fill(CardPalette.line).frame(height: 1)
            HStack {
                // 설치 안내는 인스타 답장창(1580~)에 가려지지 않도록 CTA 옆에 둔다
                VStack(alignment: .leading, spacing: 4) {
                    Text(cta).font(.pretendard(28, .semibold)).foregroundStyle(CardPalette.ink.opacity(0.85)).lineLimit(1)
                    Text("App Store에서 ‘FC Scope’ 검색").font(.pretendard(24)).foregroundStyle(CardPalette.muted).lineLimit(1)
                }
                Spacer()
                Text(host).font(.scoreboard(30)).foregroundStyle(CardPalette.bg)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(CardPalette.lime, in: Capsule())
            }
            .frame(height: 64)
        }
        .frame(height: 80)
    }
}

// MARK: - 폼 · 선수 · 슛맵

/// 최근 경기 결과 칸 — 왼쪽이 오래된 경기, 오른쪽이 가장 최근. 패 칸은 원색으로 채우지 않는다.
struct FormStrip: View {
    let matches: [MatchSummary]   // 최신순 그대로 넘긴다
    var cell: CGFloat = 46
    var spacing: CGFloat = 12
    var count = 10

    var body: some View {
        let recent = Array(matches.prefix(count).reversed())
        HStack(spacing: spacing) {
            ForEach(Array(recent.enumerated()), id: \.element.id) { i, m in
                let (bg, fg) = Self.colors(m.result)
                Text(m.result).font(.pretendard(cell * 0.48, .bold)).foregroundStyle(fg)
                    .frame(width: cell, height: cell)
                    .background(bg, in: RoundedRectangle(cornerRadius: cell * 0.26))
                    .overlay {
                        if m.forfeit {
                            RoundedRectangle(cornerRadius: cell * 0.26).stroke(CardPalette.muted, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        }
                    }
                    .overlay {
                        if i == recent.count - 1 {
                            RoundedRectangle(cornerRadius: cell * 0.26 + 4).stroke(CardPalette.ink, lineWidth: 3).padding(-5)
                        }
                    }
            }
        }
    }

    static func colors(_ result: String) -> (Color, Color) {
        switch result {
        case "승": return (CardPalette.lime, CardPalette.bg)
        case "패": return (CardPalette.lose.opacity(0.22), CardPalette.lose)
        default: return (CardPalette.muted.opacity(0.3), CardPalette.ink)
        }
    }
}

struct CardPlayer: Identifiable {
    let spId: Int
    let name: String
    let season: String
    let position: String
    let rating: Double
    let goals: Int
    let assists: Int
    let games: Int
    var id: Int { spId }
}

/// 선수 사진 + 시즌 아이콘 + 평점 타일
struct PlayerTile: View {
    let p: CardPlayer
    let images: CardImages
    var width: CGFloat = 304
    var height: CGFloat = 222
    var top = false

    var body: some View {
        if width > 600 { wide } else { compactTile }
    }

    /// 한 명만 크게(계급 카드의 에이스) — 큰 사진 + 이름·기록 + 평점
    private var wide: some View {
        HStack(spacing: 28) {
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    Color.white.opacity(0.08)
                    if let img = images.player(p.spId) { Image(uiImage: img).resizable().scaledToFill() }
                }
                .frame(width: height - 40, height: height - 40)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if let s = images.season(p.spId) {
                    Image(uiImage: s).resizable().scaledToFit().frame(height: 40).offset(x: -6, y: 10)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(p.position).font(.scoreboard(30)).foregroundStyle(CardPalette.muted)
                Text(p.name).font(.pretendard(48, .bold)).foregroundStyle(CardPalette.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(statLine).font(.pretendard(28, .semibold)).foregroundStyle(CardPalette.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("평점").font(.pretendard(24)).foregroundStyle(CardPalette.muted)
                Text(String(format: "%.2f", p.rating)).font(.scoreboard(88)).foregroundStyle(top ? CardPalette.gold : CardPalette.ink)
            }
        }
        .padding(20)
        .frame(width: width, height: height)
        .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(top ? CardPalette.gold : CardPalette.line, lineWidth: top ? 3 : 2))
    }

    private var compactTile: some View {
        let big = width > 400
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        Color.white.opacity(0.08)
                        if let img = images.player(p.spId) { Image(uiImage: img).resizable().scaledToFill() }
                    }
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    if let s = images.season(p.spId) {
                        Image(uiImage: s).resizable().scaledToFit().frame(height: 40).offset(x: -6, y: 12)
                    } else if !p.season.isEmpty {
                        Text(p.season).font(.pretendard(24, .bold)).foregroundStyle(CardPalette.gold)
                            .padding(.horizontal, 6).background(CardPalette.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                            .offset(x: -4, y: 8)
                    }
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.position).font(.scoreboard(24)).foregroundStyle(CardPalette.muted)
                    Spacer(minLength: 0)
                    Text("평점").font(.pretendard(20)).foregroundStyle(CardPalette.muted)
                    Text(String(format: "%.2f", p.rating)).font(.scoreboard(big ? 72 : 52))
                        .foregroundStyle(top ? CardPalette.gold : CardPalette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: 110, alignment: .trailing)
            }
            .frame(height: 112)
            Spacer(minLength: 0)
            Text(p.name).font(.pretendard(28, .bold)).foregroundStyle(CardPalette.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(statLine).font(.pretendard(24, .semibold)).foregroundStyle(CardPalette.muted).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            ZStack {
                CardPalette.surface
                if top { LinearGradient(colors: [CardPalette.gold.opacity(0.10), .clear], startPoint: .top, endPoint: .center) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(top ? CardPalette.gold : CardPalette.line, lineWidth: top ? 3 : 2))
    }

    private var statLine: String {
        p.goals == 0 && p.assists == 0 ? "\(p.games)경기" : "\(p.goals)G · \(p.assists)A · \(p.games)경기"
    }
}

/// 하프 피치를 세로로 세운 누적 슛맵(골대가 위). 플레이스타일 슛은 공격 진영(x 0.5~1)만 온다.
struct HalfShotMap: View {
    let shots: [Shot]
    let height: CGFloat
    var width: CGFloat { height * 1.295 }

    var body: some View {
        let sx = ShotMapView.scale(shots, \.x), sy = ShotMapView.scale(shots, \.y)
        ZStack(alignment: .bottomLeading) {
            Canvas { ctx, s in
                let w = s.width, h = s.height
                ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(CardPalette.surface))
                var l = Path()
                l.addRect(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
                let bw = w * 0.59, bd = h * 0.31
                l.addRect(CGRect(x: (w - bw) / 2, y: 0, width: bw, height: bd))
                let aw = w * 0.27, ad = h * 0.105
                l.addRect(CGRect(x: (w - aw) / 2, y: 0, width: aw, height: ad))
                let r = w * 0.135
                l.addArc(center: CGPoint(x: w / 2, y: h), radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                ctx.stroke(l, with: .color(CardPalette.line), lineWidth: 2)
                let gw = w * 0.11
                ctx.fill(Path(CGRect(x: (w - gw) / 2, y: 0, width: gw, height: 4)), with: .color(CardPalette.ink.opacity(0.6)))
                // 비골 → 골대 → 골 순서로 그려 골이 위에 오게 한다
                let ordered = shots.filter { !$0.isGoal && !$0.hitPost } + shots.filter { $0.hitPost && !$0.isGoal } + shots.filter(\.isGoal)
                for shot in ordered {
                    let x = min(1, max(0.5, shot.x / sx)), y = min(1, max(0, shot.y / sy))
                    let pt = CGPoint(x: min(w - 8, max(8, y * w)), y: min(h - 8, max(10, (1 - x) * 2 * h)))
                    let rad: CGFloat = shot.isGoal ? 5 : 4.5
                    let rect = CGRect(x: pt.x - rad, y: pt.y - rad, width: rad * 2, height: rad * 2)
                    if shot.isGoal {
                        ctx.fill(Path(ellipseIn: rect), with: .color(shot.hitPost ? CardPalette.gold : CardPalette.lime))
                    } else {
                        ctx.stroke(Path(ellipseIn: rect), with: .color(shot.hitPost ? CardPalette.gold : CardPalette.muted.opacity(0.45)), lineWidth: 2)
                    }
                }
            }
            HStack(spacing: 8) { Circle().fill(CardPalette.lime).frame(width: 12, height: 12); Text("골").font(.pretendard(20, .semibold)); Circle().stroke(CardPalette.muted, lineWidth: 2).frame(width: 12, height: 12); Text("슛").font(.pretendard(20, .semibold)) }.foregroundStyle(CardPalette.muted).padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

/// 라벨 + 큰 값 스탯 박스
struct StatBox: View {
    let label: String
    let value: String
    var color: Color = CardPalette.ink
    var width: CGFloat = 304
    var height: CGFloat = 140
    var valueSize: CGFloat = 64

    var body: some View {
        let ascii = value.unicodeScalars.allSatisfy(\.isASCII)
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.pretendard(24)).foregroundStyle(CardPalette.muted).lineLimit(1)
            Text(value).font(ascii ? .scoreboard(valueSize) : .pretendard(valueSize * 0.7, .bold))
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 24)
        .frame(width: width, height: height, alignment: .leading)
        .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(CardPalette.line, lineWidth: 2))
    }
}
