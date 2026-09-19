import SwiftUI
import UIKit

/**
 최적화: 공유 카드를 앱에서 직접 렌더.

 서버는 `next/og`(satori + resvg)로 1080×1920 PNG 를 굽는데, 개발 기록상 이것이
 Vercel 함수 **CPU 소모 1위**다. 카드 1장마다 한국어 폰트 서브셋 fetch + 래스터가 일어난다.

 카드에 필요한 데이터는 이미 앱이 받은 API 응답 안에 전부 있으므로,
 SwiftUI `ImageRenderer` 로 로컬 생성하면 **서버 CPU·대역폭·넥슨 재조회가 모두 0** 이 된다.
 (웹 공유용 OG 이미지는 서버에 그대로 남는다 — 크롤러는 앱을 실행할 수 없으므로)

 레이아웃·색·폰트 크기는 `lib/card/render.tsx` 와 1:1로 맞춘다.
 */

struct CardBadge: Identifiable {
    let label: String
    let value: String
    var color: Color = CardPalette.ink
    var id: String { label + value }
}

struct CardStamp {
    let text: String
    var color: Color = CardPalette.lime
}

/// 서버 renderCard(CardData) 와 동일한 스펙
struct ShareCardSpec {
    let kicker: String
    let title: String
    var subtitle: String? = nil
    var stamp: CardStamp? = nil
    var badges: [CardBadge] = []
    /// 파일명에 쓰이는 짧은 이름
    var filename: String = "fcscope-card"
}

/// 카드 전용 팔레트 — 카드는 항상 다크(공유 이미지라 뷰어 테마와 무관)
enum CardPalette {
    static let bg = Color(hex: 0x0a1119)
    static let surface = Color(hex: 0x101a26)
    static let line = Color(hex: 0x22334a)
    static let ink = Color(hex: 0xe9eef6)
    static let muted = Color(hex: 0x8fa0b5)
    static let lime = Color(hex: 0xc8f542)
    static let gold = Color(hex: 0xf2c14e)
    static let lose = Color(hex: 0xfb7185)

    /// 서버 VerdictColor 문자열 → 카드 색
    static func verdict(_ name: String) -> Color {
        switch name {
        case "gold": return gold
        case "lime", "win": return lime
        case "lose": return lose
        case "muted", "draw": return muted
        default: return ink
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

/// Chakra Petch 에는 한글 글리프가 없다 → ASCII·숫자일 때만 전광판 폰트, 아니면 시스템 볼드.
private func cardFont(_ text: String, size: CGFloat) -> Font {
    let asciiOnly = text.unicodeScalars.allSatisfy { $0.isASCII }
    return asciiOnly ? .scoreboard(size) : .pretendard(size, .bold)
}

struct ShareCardView: View {
    let spec: ShareCardSpec
    static let width: CGFloat = 1080
    static let height: CGFloat = 1920

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            hero
            Spacer(minLength: 0)
            footer
        }
        .padding(96)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(
            ZStack {
                CardPalette.bg
                // radial-gradient(900px 500px at 50% 0%, rgba(200,245,66,0.16), transparent)
                EllipticalGradient(
                    colors: [CardPalette.lime.opacity(0.16), .clear],
                    center: .init(x: 0.5, y: 0),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.55
                )
            }
        )
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text("FC").font(.scoreboard(44)).foregroundStyle(CardPalette.lime)
                Text("SCOPE").font(.scoreboard(44)).foregroundStyle(CardPalette.ink)
            }
            Text(spec.kicker)
                .font(.pretendard(34, .bold))
                .kerning(6)
                .foregroundStyle(CardPalette.muted)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(spec.title)
                .font(cardFont(spec.title, size: 200))
                .foregroundStyle(CardPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
            if let subtitle = spec.subtitle {
                Text(subtitle)
                    .font(.pretendard(48, .bold))
                    .foregroundStyle(CardPalette.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            if let stamp = spec.stamp {
                Text(stamp.text)
                    .font(.pretendard(52, .bold))
                    .foregroundStyle(stamp.color)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(stamp.color, lineWidth: 3))
                    .padding(.top, 8)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 40) {
            if !spec.badges.isEmpty {
                HStack(spacing: 20) {
                    ForEach(spec.badges.prefix(3)) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(b.label).font(.pretendard(28)).foregroundStyle(CardPalette.muted).lineLimit(1)
                            Text(b.value)
                                .font(cardFont(b.value, size: 56))
                                .foregroundStyle(b.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .background(CardPalette.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CardPalette.line, lineWidth: 1))
                    }
                }
            }
            HStack {
                Text("내 전적도 검색 →").font(.pretendard(30)).foregroundStyle(CardPalette.muted)
                Spacer()
                Text(AppConfig.shareHost).font(.pretendard(30, .bold)).foregroundStyle(CardPalette.lime)
            }
        }
    }
}

enum ShareCardRenderer {
    /// SwiftUI 뷰 → 1080×1920 PNG. 메인 액터에서만 호출.
    @MainActor
    static func render(_ spec: ShareCardSpec) -> UIImage? {
        render(view: ShareCardView(spec: spec), size: CGSize(width: ShareCardView.width, height: ShareCardView.height))
    }

    @MainActor
    static func render<V: View>(view: V, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1 // 뷰 크기가 이미 픽셀 크기(1080×1920)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// MARK: - API 응답 → 카드 스펙 (서버 app/api/card/* 의 renderCard 인자와 동일)

extension ShareCardSpec {
    /// 전적 카드 (서버 card/user)
    static func user(_ o: UserOverview) -> ShareCardSpec {
        let r = o.summary
        let division = o.profile.divisions.first { $0.matchType == 50 } ?? o.profile.divisions.first
        var badges: [CardBadge] = []
        if r.played > 0 {
            badges.append(CardBadge(label: "FC 스코어", value: String(format: "%.1f", o.score), color: CardPalette.verdict(o.tier.tone == "win" ? "lime" : o.tier.tone)))
        }
        badges.append(CardBadge(label: "최근 경기", value: "\(r.played)"))
        badges.append(CardBadge(label: "득실", value: "\(r.goalsFor):\(r.goalsAgainst)"))
        return ShareCardSpec(
            kicker: "전적 카드",
            title: "\(r.winRate)%",
            subtitle: "\(o.profile.nickname) · Lv.\(o.profile.level)" + (division.map { " · \($0.divisionName)" } ?? ""),
            stamp: r.played > 0 ? CardStamp(text: "\(r.win)승 \(r.draw)무 \(r.lose)패", color: CardPalette.lime) : nil,
            badges: badges,
            filename: "fcscope-\(o.profile.nickname)"
        )
    }

    /// 계급 인증 카드 (서버 card/rank)
    static func rank(_ o: UserOverview) -> ShareCardSpec? {
        guard let d = o.profile.divisions.first(where: { $0.matchType == 50 }) ?? o.profile.divisions.first else { return nil }
        let others = o.profile.divisions.filter { $0.matchType != d.matchType }.prefix(2)
        return ShareCardSpec(
            kicker: "\(d.matchTypeName) 최고 등급",
            title: d.divisionName,
            subtitle: o.profile.nickname,
            stamp: CardStamp(text: "달성 \(d.date)", color: CardPalette.gold),
            badges: [CardBadge(label: "레벨", value: "Lv.\(o.profile.level)")]
                + others.map { CardBadge(label: "\($0.matchTypeName) 최고", value: $0.divisionName, color: CardPalette.gold) },
            filename: "fcscope-rank-\(o.profile.nickname)"
        )
    }

    /// 폼 카드 (서버 card/streak)
    static func streak(_ o: UserOverview) -> ShareCardSpec {
        let color = CardPalette.verdict(o.streak.color)
        return ShareCardSpec(
            kicker: "이번 폼",
            title: o.perf.played > 0 ? o.streak.text : "—",
            subtitle: "\(o.profile.nickname) · 최근 \(o.perf.played)경기",
            stamp: o.perf.played > 0 ? CardStamp(text: "FC스코어 \(String(format: "%.1f", o.score))", color: color) : nil,
            badges: o.perf.played > 0 ? [
                CardBadge(label: "승률", value: "\(o.perf.winRate)%", color: color),
                CardBadge(label: "최고 연승", value: "\(o.perf.bestWinStreak)"),
                CardBadge(label: "최근 경기", value: "\(o.perf.played)"),
            ] : [],
            filename: "fcscope-streak-\(o.profile.nickname)"
        )
    }

    /// 주간 리포트 카드 (서버 card/weekly)
    static func weekly(_ o: UserOverview) -> ShareCardSpec {
        let w = o.week
        guard w.games > 0 else {
            return ShareCardSpec(kicker: "주간 리포트", title: "—", subtitle: "\(o.profile.nickname) · 최근 7일 공식경기 없음", filename: "fcscope-weekly")
        }
        let color: Color = w.winRate >= 60 ? CardPalette.gold : w.winRate >= 45 ? CardPalette.lime : CardPalette.lose
        return ShareCardSpec(
            kicker: "주간 리포트",
            title: "\(w.win)승 \(w.draw)무 \(w.lose)패",
            subtitle: "\(o.profile.nickname) · 최근 7일 \(w.games)경기",
            stamp: CardStamp(text: w.bestStreak >= 2 ? "이번 주 \(w.bestStreak)연승" : "승률 \(w.winRate)%", color: color),
            badges: [
                CardBadge(label: "승률", value: "\(w.winRate)%", color: color),
                // 서버 주간 avgScore 는 전적 화면의 FC Scope 스코어와 척도가 달라 빼고, 같은 주의 최고 연승을 싣는다.
                CardBadge(label: "최고 연승", value: "\(w.bestStreak)"),
                CardBadge(label: "득실", value: "\(w.goalsFor):\(w.goalsAgainst)"),
            ],
            filename: "fcscope-weekly-\(o.profile.nickname)"
        )
    }

    /// 라이벌 H2H 카드 (서버 card/rival)
    ///
    /// 카드에는 실제 다른 유저의 구단주명이 찍힌다. 상대를 깎아내리는 라벨("호구" 등)은 쓰지 않는다
    /// (서버 lib/verdict.ts 의 otherUser 톤 게이트와 같은 원칙) — 내 입장에서 본 중립 문구만.
    static func rival(_ o: UserOverview, rival r: Rival) -> ShareCardSpec {
        let gap = r.win - r.lose
        let label: (String, Color) = gap <= -2 ? ("이 상대에겐 고전 중", CardPalette.lose) : gap >= 2 ? ("이 상대에겐 강해요", CardPalette.gold) : ("팽팽한 접전", CardPalette.lime)
        return ShareCardSpec(
            kicker: "라이벌 H2H",
            title: "\(r.win) : \(r.lose)",
            subtitle: "\(o.profile.nickname) vs \(r.nickname)",
            stamp: CardStamp(text: label.0, color: label.1),
            badges: [
                CardBadge(label: "무", value: "\(r.draw)"),
                CardBadge(label: "득실", value: "\(r.goalsFor):\(r.goalsAgainst)"),
                CardBadge(label: "맞대결", value: "\(r.games)경기"),
            ],
            filename: "fcscope-rival-\(o.profile.nickname)"
        )
    }

    /// 랭커 대세픽 카드 (서버 card/pickmatch)
    static func pickMatch(nickname: String, picks: PicksInfo) -> ShareCardSpec {
        ShareCardSpec(
            kicker: "내 스쿼드 vs 대세픽",
            title: "\(picks.topPickCount)명",
            subtitle: "포지션별 인기 TOP10 기준 · \(nickname)",
            stamp: CardStamp(text: "너는 몇 명?", color: CardPalette.lime),
            badges: [
                CardBadge(label: "내가 쓴 카드", value: "\(picks.total)명"),
                CardBadge(label: "TOP10 외", value: "\(picks.total - picks.topPickCount)명", color: CardPalette.muted),
                CardBadge(label: "기준일", value: picks.date ?? "최신"),
            ],
            filename: "fcscope-pick-\(nickname)"
        )
    }

    /// 매치 리포트 카드 (서버 card/match)
    static func match(_ m: MatchDetailResponse) -> ShareCardSpec {
        let color = CardPalette.verdict(m.verdict.color)
        return ShareCardSpec(
            kicker: "\(m.matchTypeName) 리포트",
            title: "\(m.me.goals) : \(m.opponent?.goals ?? 0)",
            subtitle: "\(m.me.nickname) · \(m.verdict.label)",
            stamp: CardStamp(text: m.verdict.oneLiner, color: color),
            badges: [
                CardBadge(label: "점유율", value: "\(m.me.possession)%"),
                CardBadge(label: "유효슛", value: "\(m.me.stats.effectiveShots)"),
                CardBadge(label: "경기 평점", value: String(format: "%.1f", m.me.rating), color: color),
            ],
            filename: "fcscope-match-\(m.matchId)"
        )
    }
}
