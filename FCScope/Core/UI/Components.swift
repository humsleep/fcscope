import SwiftUI
import Nuke
import NukeUI
import UIKit

/**
 선수 이미지 — 넥슨 CDN 직접 로드.

 최적화 전에는 `/api/player-image/:spid` 서버 프록시를 거쳐 전적 화면 1회당
 0.9~1.3MB 가 Vercel 대역폭을 소모했다. 네이티브는 CORS 제약이 없으므로 CDN 을 직접 부른다.
 폴백 체인(액션샷 → 기본 이미지 → 실루엣)은 서버 프록시와 동일하다.
 */
struct PlayerImage: View {
    let spid: Int
    var size: CGFloat = 40
    var radius: CGFloat = 10

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            FC.surface2
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                PlayerSilhouette()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: spid) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        if let cached = ImageCache.cached(spid: spid) {
            image = cached
            return
        }
        if let loaded = await ImageCache.load(spid: spid) {
            image = loaded
        } else {
            failed = true
        }
    }
}

/// 선수 실루엣 폴백 (서버 프록시의 SVG 와 동일 형태)
struct PlayerSilhouette: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(Color(hex: 0x223042)).frame(width: s * 0.33, height: s * 0.33).offset(y: -s * 0.15)
                Capsule().fill(Color(hex: 0x223042)).frame(width: s * 0.66, height: s * 0.42).offset(y: s * 0.28)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// 절대 URL 이미지 (등급 아이콘 등 넥슨 정적 자산)
struct RemoteImage: View {
    let url: String
    var size: CGFloat = 20
    var body: some View {
        LazyImage(url: URL(string: url)) { state in
            if let image = state.image { image.resizable().scaledToFit() } else { Color.clear }
        }
        .frame(width: size, height: size)
    }
}

/// 선수 이미지 로딩·캐시 — Nuke 파이프라인(디스크 캐시 적극 사용) 위의 얇은 래퍼.
enum ImageCache {
    /// 넥슨 CDN 은 Cache-Control 헤더가 없어 URLCache 가 잘 안 듣는다 →
    /// Nuke DataCache(원본 바이트 디스크 캐시)를 쓰는 전용 파이프라인.
    static let pipeline: ImagePipeline = {
        var config = ImagePipeline.Configuration.withDataCache(name: "xyz.fcscope.images", sizeLimit: 256 << 20)
        config.dataLoadingQueue.maxConcurrentOperationCount = 6
        return ImagePipeline(configuration: config)
    }()

    static func cached(spid: Int) -> UIImage? {
        for url in NexonCDN.playerImageURLs(spid: spid) {
            if let container = pipeline.cache[ImageRequest(url: url)] { return container.image }
        }
        return nil
    }

    /// 폴백 체인을 순서대로 시도. 전부 실패하면 nil.
    static func load(spid: Int) async -> UIImage? {
        for url in NexonCDN.playerImageURLs(spid: spid) {
            if let image = try? await pipeline.image(for: url) { return image }
        }
        return nil
    }

    /// 카드 렌더 등 동기 렌더 직전에 여러 장을 미리 채운다.
    static func prefetch(spids: [Int]) async {
        await withTaskGroup(of: Void.self) { group in
            for spid in spids {
                group.addTask { _ = await load(spid: spid) }
            }
        }
    }
}

/// 심판 도장 (웹 VerdictStamp)
struct VerdictStamp: View {
    let verdict: Verdict
    var large = false
    var showLiner = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verdict.icon).fcScoreboard(large ? 18 : 13)
                Text(verdict.grade).fcScoreboard(large ? 22 : 14).kerning(1)
                // 등급과 라벨이 같은 경기는 "승리 승리" 로 중복돼 보였다 — 다를 때만 붙인다
                if verdict.label != verdict.grade {
                    Text(verdict.label).fcFont(large ? 13 : 11, weight: .semibold).foregroundStyle(FC.muted)
                }
            }
            .foregroundStyle(FC.tone(verdict.color))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(FC.tone(verdict.color), lineWidth: 2))
            .rotationEffect(.degrees(-3))
            if showLiner { Text(verdict.oneLiner).fcFont(13).foregroundStyle(FC.muted) }
        }
    }
}

/// 결과 배지 (승/무/패)
struct ResultBadge: View {
    let result: String
    var size: CGFloat = 26
    var body: some View {
        Text(result).fcScoreboard(size * 0.5).foregroundStyle(FC.resultColor(result))
            .frame(width: size, height: size)
            .background(FC.resultColor(result).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// 공유 카드 소스 — 전부 앱에서 렌더한다(서버 next/og 호출 없음).
enum ShareCardSource {
    case spec(ShareCardSpec)
    case squad(SquadCardData)
    case match(MatchDetailResponse)
}

struct SquadCardData {
    let name: String
    let formationId: String
    /// slotId → (spid, 이름, 시즌)
    let slots: [String: SquadSlotModel]
    let shareCode: String?
}

/// 공유 카드 버튼 — 앱에서 PNG 를 만들어 시스템 시트/인스타 스토리로 보낸다.
struct ShareCardButton: View {
    let source: ShareCardSource
    var label: String = "카드 저장 · 공유"
    var compact = false

    @State private var busy = false
    @State private var image: UIImage?
    @State private var showSheet = false
    @State private var error: String?

    init(spec: ShareCardSpec, label: String = "카드 저장 · 공유", compact: Bool = false) {
        self.source = .spec(spec)
        self.label = label
        self.compact = compact
    }
    init(squad: SquadCardData, label: String = "스쿼드 카드", compact: Bool = false) {
        self.source = .squad(squad)
        self.label = label
        self.compact = compact
    }
    init(match: MatchDetailResponse, label: String = "매치 카드", compact: Bool = false) {
        self.source = .match(match)
        self.label = label
        self.compact = compact
    }

    var body: some View {
        Button {
            Task { await make() }
        } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small) } else { Image(systemName: "square.and.arrow.up") }
                Text(busy ? "만드는 중…" : label).fcFont(compact ? 12 : 14, weight: .bold)
            }
            .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 7 : 10)
            .background(FC.surface2, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(FC.ink)
        }
        .disabled(busy)
        .sheet(isPresented: $showSheet) { if let image { ShareCardSheet(image: image, filename: filename) } }
        .alert("카드를 만들지 못했어요", isPresented: Binding(get: { error != nil }, set: { _ in error = nil })) { Button("확인") {} } message: { Text(error ?? "") }
    }

    private var filename: String {
        switch source {
        case .spec(let s): return s.filename
        case .squad(let s): return "fcscope-squad-\(s.shareCode ?? s.formationId)"
        case .match(let m): return "fcscope-match-\(m.matchId)"
        }
    }

    @MainActor
    private func make() async {
        busy = true
        defer { busy = false }
        switch source {
        case .spec(let spec):
            image = ShareCardRenderer.render(spec)
        case .squad(let data):
            // 동기 렌더 전에 선수 이미지를 미리 채운다(ImageRenderer 는 비동기 로딩을 기다리지 않음)
            await ImageCache.prefetch(spids: data.slots.values.map(\.spid))
            image = ShareCardRenderer.render(
                view: SquadCardView(data: data),
                size: CGSize(width: ShareCardView.width, height: ShareCardView.height)
            )
        case .match(let m):
            if let p = m.potm { await ImageCache.prefetch(spids: [p.spId]) }
            image = ShareCardRenderer.render(
                view: MatchCardView(m: m),
                size: CGSize(width: ShareCardView.width, height: ShareCardView.height)
            )
        }
        if image == nil {
            error = "이미지 생성에 실패했어요. 잠시 후 다시 시도해 주세요."
        } else {
            Haptic.success()
            showSheet = true
        }
    }
}

struct ShareCardSheet: View {
    let image: UIImage
    var filename: String = "fcscope-card"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if InstagramShare.available {
                Button { InstagramShare.shareStory(image); dismiss() } label: {
                    Label("인스타그램 스토리에 올리기", systemImage: "camera.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk)
            }
            ShareLink(item: Image(uiImage: image), preview: SharePreview("FC Scope 카드", image: Image(uiImage: image))) {
                Label("공유 · 저장", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("앱에서 직접 만든 이미지예요. 서버를 거치지 않아 즉시 생성됩니다.")
                .fcFont(11).foregroundStyle(FC.muted)
        }
        .padding(20)
        .presentationDetents([.large])
        .presentationBackground(FC.bg)
    }
}

/// 인스타그램 스토리 직결 (LSApplicationQueriesSchemes: instagram-stories)
enum InstagramShare {
    static var available: Bool { UIApplication.shared.canOpenURL(URL(string: "instagram-stories://share")!) }
    static func shareStory(_ image: UIImage) {
        guard let data = image.pngData() else { return }
        UIPasteboard.general.setItems([["com.instagram.sharedSticker.backgroundImage": data]], options: [.expirationDate: Date().addingTimeInterval(300)])
        UIApplication.shared.open(URL(string: "instagram-stories://share?source_application=\(AppConfig.bundleId)")!)
    }
}

/// 경기 행
struct MatchRow: View {
    let m: MatchSummary
    var body: some View {
        HStack(spacing: 10) {
            ResultBadge(result: m.result, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(m.me.goals)").fcScoreboard(16).foregroundStyle(FC.ink)
                    Text(":").foregroundStyle(FC.muted)
                    Text(m.opponent.map { "\($0.goals)" } ?? "-").fcScoreboard(16).foregroundStyle(FC.muted)
                    Text("vs \(m.opponent?.nickname ?? "상대 없음")").fcFont(14, weight: .semibold).foregroundStyle(FC.ink).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(DateFmt.short(m.matchDate)).fcFont(12).foregroundStyle(FC.muted)
                    if m.forfeit { Chip(text: "몰수", color: FC.lose, bg: FC.lose.opacity(0.15)) }
                    Text("점유 \(m.me.possession)%").fcFont(12).foregroundStyle(FC.muted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", m.score)).fcScoreboard(16).foregroundStyle(m.score >= 6.5 ? FC.accent : m.score < 5 ? FC.lose : FC.ink)
                Text("평점 \(String(format: "%.1f", m.me.rating))").fcFont(11).foregroundStyle(FC.muted)
            }
            Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
        }
        .padding(12)
        .background(FC.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
    }
}

enum DateFmt {
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let iso2: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let plain: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC"); return f }()
    static func parse(_ raw: String) -> Date? {
        iso.date(from: raw) ?? iso2.date(from: raw) ?? plain.date(from: raw) ?? plain.date(from: String(raw.prefix(19)))
    }
    static func short(_ raw: String) -> String {
        guard let d = parse(raw) else { return raw }
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.timeZone = TimeZone(identifier: "Asia/Seoul"); f.dateFormat = "M.d HH:mm"
        return f.string(from: d)
    }
    static func relative(_ raw: String) -> String {
        guard let d = parse(raw) else { return raw }
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "방금" }
        if s < 3600 { return "\(Int(s / 60))분 전" }
        if s < 86_400 { return "\(Int(s / 3600))시간 전" }
        if s < 86_400 * 7 { return "\(Int(s / 86_400))일 전" }
        let f = DateFormatter(); f.dateFormat = "M.d"; return f.string(from: d)
    }
}

/// 톤 배지 (진단 룰)
struct RuleBadge: View {
    let rule: Rule
    var prefix: String = ""
    /// 글자를 키우면 제목 칩(fixedSize)이 폭을 다 먹어 설명이 한 글자씩 흐르는 기둥이 된다.
    /// 접근성 크기에서는 가로 배치를 포기하고 세로로 쌓는다.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            Text("\(prefix)\(rule.title)").fcScoreboard(12, weight: .semibold).foregroundStyle(FC.tone(rule.tone))
                .padding(.horizontal, 8).padding(.vertical, 4).background(FC.tone(rule.tone).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .fixedSize()
            Text(rule.desc).fcFont(13).foregroundStyle(FC.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 비동기 로드 상태 공용
enum Loadable<T> {
    case idle, loading, loaded(T), failed(Error)
    var value: T? { if case .loaded(let v) = self { return v }; return nil }
    var isLoading: Bool { if case .loading = self { return true }; return false }
}
