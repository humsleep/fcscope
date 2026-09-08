import WidgetKit
import SwiftUI

@main
struct FCScopeWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyFormWidget()
        MoverWidget()
    }
}

// MARK: - 내 폼 위젯 (회의 결정 #2: 웹이 못 하는 유일한 것)

struct FormEntry: TimelineEntry {
    let date: Date
    let nickname: String?
    let winRate: Int
    let score: Double
    let streak: Int
    let form: [String]      // 최근 5경기 승/무/패
    let tier: String
}

struct FormProvider: TimelineProvider {
    static let suite = UserDefaults(suiteName: "group.xyz.fcscope.app")
    func placeholder(in context: Context) -> FormEntry { FormEntry(date: .now, nickname: "FC Scope", winRate: 62, score: 6.8, streak: 3, form: ["승","승","승","패","무"], tier: "수준급") }
    func getSnapshot(in context: Context, completion: @escaping (FormEntry) -> Void) { completion(cached() ?? placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FormEntry>) -> Void) {
        Task {
            let entry = await fresh() ?? cached() ?? FormEntry(date: .now, nickname: nil, winRate: 0, score: 0, streak: 0, form: [], tier: "")
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3 * 3600))))
        }
    }
    private var nickname: String? { Self.suite?.string(forKey: "myNickname") }
    private func cached() -> FormEntry? {
        guard let nick = nickname, let data = Self.suite?.data(forKey: "formSnapshots"),
              let map = try? JSONDecoder().decode([String: CachedForm].self, from: data), let s = map[nick.lowercased()] else { return nil }
        return FormEntry(date: .now, nickname: nick, winRate: s.winRate, score: s.score, streak: s.streak, form: s.form ?? [], tier: tierOf(s.score))
    }
    private func fresh() async -> FormEntry? {
        guard let nick = nickname else { return nil }
        var req = URLRequest(url: AppConfig.absolute("/api/v1/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"))
        req.timeoutInterval = 25
        guard let (data, _) = try? await URLSession.shared.data(for: req), let o = try? JSONDecoder().decode(UserOverview.self, from: data) else { return nil }
        let form = o.matches.prefix(5).map(\.result)
        if var map = (Self.suite?.data(forKey: "formSnapshots")).flatMap({ try? JSONDecoder().decode([String: CachedForm].self, from: $0) }) ?? Optional([:]) {
            let prev = map[nick.lowercased()]
            map[nick.lowercased()] = CachedForm(winRate: o.summary.winRate, score: o.score, streak: o.perf.currentStreak, updatedAt: Date(), prevWinRate: prev?.winRate, form: form)
            if let d = try? JSONEncoder().encode(map) { Self.suite?.set(d, forKey: "formSnapshots") }
        }
        return FormEntry(date: .now, nickname: o.profile.nickname, winRate: o.summary.winRate, score: o.score, streak: o.perf.currentStreak, form: form, tier: o.tier.label)
    }
    private func tierOf(_ s: Double) -> String { s >= 8 ? "월드클래스" : s >= 6.5 ? "수준급" : s >= 5 ? "평범" : "분발 필요" }
    struct CachedForm: Codable { var winRate: Int; var score: Double; var streak: Int; var updatedAt: Date; var prevWinRate: Int?; var form: [String]? }
}

struct MyFormWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FormEntry
    var body: some View {
        Group {
            if let nick = entry.nickname {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("FC").font(.scoreboard(11)).foregroundStyle(FC.accent) + Text(" SCOPE").font(.scoreboard(11)).foregroundStyle(FC.ink); Spacer(); if entry.streak >= 2 { Text("🔥\(entry.streak)").font(.system(size: 11, weight: .bold)).foregroundStyle(FC.gold) } else if entry.streak <= -2 { Text("🥶\(-entry.streak)").font(.system(size: 11, weight: .bold)).foregroundStyle(FC.lose) } }
                    Text(nick).font(.system(size: 13, weight: .bold)).foregroundStyle(FC.ink).lineLimit(1)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(entry.winRate)%").font(.scoreboard(family == .systemSmall ? 26 : 30)).foregroundStyle(FC.accent)
                        Text("승률").font(.system(size: 10)).foregroundStyle(FC.muted)
                        if family != .systemSmall { Text(String(format: "%.1f", entry.score)).font(.scoreboard(22)).foregroundStyle(FC.gold); Text(entry.tier).font(.system(size: 10)).foregroundStyle(FC.muted) }
                    }
                    HStack(spacing: 3) { ForEach(Array(entry.form.enumerated()), id: \.offset) { _, r in Text(r).font(.scoreboard(10)).foregroundStyle(FC.resultColor(r)).frame(width: 18, height: 18).background(FC.resultColor(r).opacity(0.18), in: RoundedRectangle(cornerRadius: 4)) } }
                    if family != .systemSmall { Spacer(minLength: 0); Text("최근 30경기 · \(entry.date.formatted(date: .omitted, time: .shortened)) 갱신").font(.system(size: 9)).foregroundStyle(FC.muted) }
                }
                .widgetURL(AppConfig.absolute("/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"))
            } else {
                VStack(spacing: 4) { Text("FC SCOPE").font(.scoreboard(12)).foregroundStyle(FC.accent); Text("앱에서 내 구단주명을 설정하면 폼이 여기 떠요").font(.system(size: 11)).foregroundStyle(FC.muted).multilineTextAlignment(.center) }
                    .widgetURL(AppConfig.absolute("/me"))
            }
        }
        .containerBackground(for: .widget) { FC.bg }
    }
}

struct MyFormWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyFormWidget", provider: FormProvider()) { MyFormWidgetView(entry: $0) }
            .configurationDisplayName("내 폼")
            .description("최근 30경기 승률·FC 스코어·연승을 홈 화면에서.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - 오늘의 급상승 위젯

struct MoverEntry: TimelineEntry { let date: Date; let mover: Mover?; let image: UIImage? }

struct MoverProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoverEntry { MoverEntry(date: .now, mover: nil, image: nil) }
    func getSnapshot(in context: Context, completion: @escaping (MoverEntry) -> Void) { Task { completion(await load()) } }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoverEntry>) -> Void) {
        Task { completion(Timeline(entries: [await load()], policy: .after(Date().addingTimeInterval(6 * 3600)))) }
    }
    private func load() async -> MoverEntry {
        guard let (data, _) = try? await URLSession.shared.data(from: AppConfig.absolute("/api/v1/home")), let h = try? JSONDecoder().decode(HomeResponse.self, from: data), let m = h.mover else { return MoverEntry(date: .now, mover: nil, image: nil) }
        // 본체와 동일하게 넥슨 CDN 직접 로드 (서버 프록시 경유 0). 폴백 체인도 동일.
        var img: UIImage?
        for url in NexonCDN.playerImageURLs(spid: m.spId) {
            if let (d, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let ui = UIImage(data: d) {
                img = ui
                break
            }
        }
        return MoverEntry(date: .now, mover: m, image: img)
    }
}

struct MoverWidgetView: View {
    let entry: MoverEntry
    var body: some View {
        Group {
            if let m = entry.mover {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚡ 오늘의 급상승").font(.scoreboard(10, weight: .semibold)).foregroundStyle(FC.win)
                    HStack(spacing: 8) {
                        if let img = entry.image { Image(uiImage: img).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8)) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(.system(size: 13, weight: .bold)).foregroundStyle(FC.ink).lineLimit(1)
                            Text("\(m.positionLabel) · \(m.lineTitle ?? m.line)").font(.system(size: 10)).foregroundStyle(FC.muted)
                        }
                    }
                    Text(m.isNew ? "NEW 진입" : "▲\(m.deltaValue ?? 0) 랭커 사용").font(.scoreboard(13)).foregroundStyle(m.isNew ? FC.gold : FC.win)
                }
                .widgetURL(AppConfig.absolute("/player/\(m.spId)"))
            } else {
                VStack(spacing: 4) { Text("RANKER PICKS").font(.scoreboard(10)).foregroundStyle(FC.accent); Text("랭커 픽 랭킹 준비 중").font(.system(size: 11)).foregroundStyle(FC.muted) }.widgetURL(AppConfig.absolute("/meta"))
            }
        }
        .containerBackground(for: .widget) { FC.bg }
    }
}

struct MoverWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoverWidget", provider: MoverProvider()) { MoverWidgetView(entry: $0) }
            .configurationDisplayName("오늘의 급상승")
            .description("랭커 사용량이 가장 많이 오른 카드를 매일.")
            .supportedFamilies([.systemSmall])
    }
}
