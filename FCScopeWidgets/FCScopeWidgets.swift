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
    /// 앱이 이 안에 받아 둔 내 폼이면 네트워크 없이 그린다 — 대부분의 타임라인 요청은 앱의 reloadTimelines 직후라 이미 최신이다.
    static let freshFor: TimeInterval = 30 * 60
    func placeholder(in context: Context) -> FormEntry { FormEntry(date: .now, nickname: "FC Scope", winRate: 62, score: 6.8, streak: 3, form: ["승","승","승","패","무"], tier: "수준급") }
    /// 위젯 갤러리·일시 스냅샷은 즉시 돌려줘야 한다 — 캐시 또는 샘플만 쓴다.
    func getSnapshot(in context: Context, completion: @escaping (FormEntry) -> Void) { completion(cached()?.entry ?? placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FormEntry>) -> Void) {
        let hit = cached()
        if let hit, Date().timeIntervalSince(hit.updatedAt) < Self.freshFor {
            return completion(Timeline(entries: [hit.entry], policy: .after(Date().addingTimeInterval(3 * 3600))))
        }
        Task {
            let entry = await fresh() ?? hit?.entry ?? FormEntry(date: .now, nickname: nickname, winRate: 0, score: 0, streak: 0, form: [], tier: "")
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3 * 3600))))
        }
    }
    private var nickname: String? { Self.suite?.string(forKey: "myNickname") }
    private func cached() -> (entry: FormEntry, updatedAt: Date)? {
        guard let nick = nickname, let data = Self.suite?.data(forKey: "formSnapshots"),
              let map = try? JSONDecoder().decode([String: CachedForm].self, from: data), let s = map[nick.lowercased()] else { return nil }
        return (FormEntry(date: .now, nickname: nick, winRate: s.winRate, score: s.score, streak: s.streak, form: s.form ?? [], tier: tierOf(s.score)), s.updatedAt)
    }
    private func fresh() async -> FormEntry? {
        guard let nick = nickname else { return nil }
        var req = URLRequest(url: AppConfig.absolute("/api/v1/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"))
        req.timeoutInterval = 25
        guard let (data, _) = try? await URLSession.shared.data(for: req), let o = try? JSONDecoder().decode(UserOverview.self, from: data) else { return nil }
        let form = o.matches.prefix(5).map(\.result)
        if var map = (Self.suite?.data(forKey: "formSnapshots")).flatMap({ try? JSONDecoder().decode([String: CachedForm].self, from: $0) }) ?? Optional([:]) {
            let prev = map[nick.lowercased()]
            // 앱 LocalPrefs.recordForm 과 같은 규칙 — 승률이 바뀔 때만 이전 값을 민다.
            map[nick.lowercased()] = CachedForm(winRate: o.summary.winRate, score: o.score, streak: o.perf.currentStreak, updatedAt: Date(),
                                                prevWinRate: prev.flatMap { p -> Int? in p.winRate == o.summary.winRate ? p.prevWinRate : p.winRate }, form: form)
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
                if family == .accessoryRectangular { lockScreen(nick) } else { home(nick) }
            } else {
                VStack(spacing: 4) { Text("FC SCOPE").font(.scoreboard(12)).foregroundStyle(FC.accent); Text("앱에서 내 구단주명을 설정하면 폼이 여기 떠요").font(.system(size: 11)).foregroundStyle(FC.muted).multilineTextAlignment(.center) }
                    .widgetURL(AppConfig.absolute("/me"))
            }
        }
        .containerBackground(for: .widget) { FC.bg }
    }

    /// 텍스트는 전부 11pt 이상 — 그보다 작으면 홈 화면에서 읽히지 않는다.
    private func home(_ nick: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("FC").font(.scoreboard(11)).foregroundStyle(FC.accent) + Text(" SCOPE").font(.scoreboard(11)).foregroundStyle(FC.ink); Spacer(); if entry.streak >= 2 { Text("🔥\(entry.streak)").font(.system(size: 11, weight: .bold)).foregroundStyle(FC.gold) } else if entry.streak <= -2 { Text("🥶\(-entry.streak)").font(.system(size: 11, weight: .bold)).foregroundStyle(FC.lose) } }
            Text(nick).font(.system(size: 13, weight: .bold)).foregroundStyle(FC.ink).lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(entry.winRate)%").font(.scoreboard(family == .systemSmall ? 26 : 30)).foregroundStyle(FC.accent)
                Text("승률").font(.system(size: 11)).foregroundStyle(FC.muted)
                if family != .systemSmall { Text(String(format: "%.1f", entry.score)).font(.scoreboard(22)).foregroundStyle(FC.gold); Text(entry.tier).font(.system(size: 11)).foregroundStyle(FC.muted).lineLimit(1) }
            }
            HStack(spacing: 3) { ForEach(Array(entry.form.enumerated()), id: \.offset) { _, r in Text(r).font(.system(size: 11, weight: .bold)).foregroundStyle(FC.resultColor(r)).frame(width: 20, height: 20).background(FC.resultColor(r).opacity(0.18), in: RoundedRectangle(cornerRadius: 4)) } }
            if family != .systemSmall { Spacer(minLength: 0); Text("최근 30경기 · \(entry.date.formatted(date: .omitted, time: .shortened)) 갱신").font(.system(size: 11)).foregroundStyle(FC.muted).lineLimit(1) }
        }
        .widgetURL(AppConfig.absolute("/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"))
    }

    /// 잠금 화면 직사각형(약 160×72pt)은 홈 위젯 레이아웃이 넘친다 — 세 줄로 줄인다.
    private func lockScreen(_ nick: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(nick).font(.system(size: 13, weight: .bold)).lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(entry.winRate)%").font(.scoreboard(20))
                Text("승률").font(.system(size: 11))
                if entry.streak >= 2 { Text("🔥\(entry.streak)").font(.system(size: 11, weight: .bold)) } else if entry.streak <= -2 { Text("🥶\(-entry.streak)").font(.system(size: 11, weight: .bold)) }
            }
            Text(entry.form.joined(separator: " ")).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(AppConfig.absolute("/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"))
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
    static let suite = UserDefaults(suiteName: "group.xyz.fcscope.app")
    private static let moverKey = "widget.mover", imageKey = "widget.moverImage", imageSpidKey = "widget.moverImageSpid"
    /// 갤러리 미리보기용 샘플 (Mover 는 Decodable 전용이라 JSON 으로 만든다)
    static let sample: Mover? = try? JSONDecoder().decode(Mover.self, from: Data(#"{"spId":0,"position":25,"line":"FW","matchCount":128,"delta":42,"name":"오늘의 급상승 카드","season":"","positionLabel":"ST","imageUrl":"","lineTitle":"공격"}"#.utf8))

    func placeholder(in context: Context) -> MoverEntry { MoverEntry(date: .now, mover: Self.sample, image: nil) }
    /// 갤러리·일시 스냅샷은 네트워크를 기다리지 않는다 — 마지막으로 받은 카드 또는 샘플.
    func getSnapshot(in context: Context, completion: @escaping (MoverEntry) -> Void) { completion(cached() ?? placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoverEntry>) -> Void) {
        Task {
            // 네트워크 실패 시엔 마지막 카드를 유지한다(빈 "준비 중" 으로 떨어지지 않게).
            let entry = await load() ?? cached() ?? MoverEntry(date: .now, mover: nil, image: nil)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600))))
        }
    }
    /// nil = 받지 못함(네트워크·해석 실패). 받았는데 급상승이 없으면 mover 가 nil 인 엔트리.
    private func load() async -> MoverEntry? {
        guard let (data, resp) = try? await URLSession.shared.data(from: AppConfig.absolute("/api/v1/home")),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let h = try? JSONDecoder().decode(HomeResponse.self, from: data) else { return nil }
        guard let m = h.mover else {
            Self.suite?.removeObject(forKey: Self.moverKey)
            return MoverEntry(date: .now, mover: nil, image: nil)
        }
        // 다음 스냅샷용으로 급상승 카드 JSON 만 떼어 App Group 에 둔다(홈 응답 전체는 필요 없다).
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let mv = obj["mover"],
           let md = try? JSONSerialization.data(withJSONObject: mv) { Self.suite?.set(md, forKey: Self.moverKey) }
        // 본체와 동일하게 넥슨 CDN 직접 로드 (서버 프록시 경유 0). 폴백 체인도 동일.
        var img: UIImage?
        for url in NexonCDN.playerImageURLs(spid: m.spId) {
            if let (d, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let ui = UIImage(data: d) {
                img = ui
                Self.suite?.set(d, forKey: Self.imageKey); Self.suite?.set(m.spId, forKey: Self.imageSpidKey)
                break
            }
        }
        return MoverEntry(date: .now, mover: m, image: img)
    }
    private func cached() -> MoverEntry? {
        guard let md = Self.suite?.data(forKey: Self.moverKey), let m = try? JSONDecoder().decode(Mover.self, from: md) else { return nil }
        let img = Self.suite?.integer(forKey: Self.imageSpidKey) == m.spId ? Self.suite?.data(forKey: Self.imageKey).flatMap(UIImage.init(data:)) : nil
        return MoverEntry(date: .now, mover: m, image: img)
    }
}

struct MoverWidgetView: View {
    let entry: MoverEntry
    var body: some View {
        Group {
            if let m = entry.mover {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚡ 오늘의 급상승").font(.scoreboard(11, weight: .semibold)).foregroundStyle(FC.win)
                    HStack(spacing: 8) {
                        if let img = entry.image { Image(uiImage: img).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8)) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(.system(size: 13, weight: .bold)).foregroundStyle(FC.ink).lineLimit(1)
                            Text("\(m.positionLabel) · \(m.lineTitle ?? m.line)").font(.system(size: 11)).foregroundStyle(FC.muted).lineLimit(1)
                        }
                    }
                    Text(m.isNew ? "NEW 진입" : "▲\(m.deltaValue ?? 0) 랭커 사용").font(.scoreboard(13)).foregroundStyle(m.isNew ? FC.gold : FC.win).lineLimit(1)
                }
                .widgetURL(AppConfig.absolute("/player/\(m.spId)"))
            } else {
                VStack(spacing: 4) { Text("RANKER PICKS").font(.scoreboard(11)).foregroundStyle(FC.accent); Text("랭커 픽 랭킹 준비 중").font(.system(size: 11)).foregroundStyle(FC.muted) }.widgetURL(AppConfig.absolute("/meta"))
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
