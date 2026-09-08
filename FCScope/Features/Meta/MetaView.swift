import SwiftUI

struct MetaView: View {
    @State private var state: Loadable<MetaResponse> = .idle
    @State private var matchType = 50
    @State private var query = ""
    @State private var hits: [PlayerHit] = []
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("RANKER PICKS", color: FC.accent)
                Text("상위 랭커가 실제 경기에서 가장 많이 쓴 카드.\(state.value?.date.map { " (\($0) 스냅샷)" } ?? "")").font(.system(size: 13)).foregroundStyle(FC.muted)
                Picker("", selection: $matchType) { Text("공식경기").tag(50); Text("감독모드").tag(52) }.pickerStyle(.segmented)
                    .onChange(of: matchType) { _, _ in Task { await load() } }
                if !hits.isEmpty {
                    Panel(padding: 8) {
                        VStack(spacing: 0) {
                            ForEach(hits.prefix(8)) { h in
                                Button { router.push(.player(h.spid)); query = ""; hits = [] } label: {
                                    HStack { PlayerImage(spid: h.spid, size: 32, radius: 8); Text(h.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.ink); Chip(text: h.season, color: FC.gold, bg: FC.gold.opacity(0.15)); Spacer(); Text("\(h.seasons.count)시즌").font(.system(size: 11)).foregroundStyle(FC.muted) }.padding(8)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                switch state {
                case .idle, .loading: Skeleton(height: 300)
                case .failed(let e): ErrorState(title: "픽 랭킹을 불러오지 못했어요", message: e.localizedDescription, retry: { Task { await load() } })
                case .loaded(let m):
                    if m.lines.isEmpty {
                        Panel { VStack(spacing: 6) { Text("오늘의 랭킹을 준비하고 있어요 ⚽").font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink); Text("전적 검색이 쌓일수록 랭커 픽 랭킹이 빨리 채워져요.").font(.system(size: 13)).foregroundStyle(FC.muted) }.frame(maxWidth: .infinity) }
                    } else {
                        if let mv = m.mover { moverCard(mv) }
                        ForEach(m.lines) { line in lineBlock(line) }
                        Text("표본: 각 카드의 n = 랭커 경기 수. n이 작으면 신뢰도가 낮아요.").font(.system(size: 11)).foregroundStyle(FC.muted)
                    }
                }
                AdSlot()
            }.padding(16)
        }
        .fcScreen().navigationTitle("픽 랭킹")
        .searchable(text: $query, prompt: "선수 이름으로 도감 검색")
        .task(id: query) { await search(query) }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let q = ["type": String(matchType)]
        if let hit: (value: MetaResponse, isFresh: Bool) = await APIClient.shared.cachedValue("/api/v1/meta", query: q) {
            state = .loaded(hit.value)
            if hit.isFresh { return }
        } else if state.value == nil { state = .loading }
        do { state = .loaded(try await APIClient.shared.getAndCache("/api/v1/meta", query: q, auth: false)) }
        catch { if state.value == nil { state = .failed(error) } }
    }
    /// 번들 인덱스 로컬 검색 (서버 왕복 0). 인덱스 미탑재 시에만 서버 폴백.
    private func search(_ q: String) async {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { hits = []; return }
        if PlayerIndex.shared.isReady {
            hits = PlayerIndex.shared.search(t)
            return
        }
        let r: PlayerSearchResponse? = try? await APIClient.shared.get("/api/players/search", query: ["q": t], auth: false)
        if Task.isCancelled || t != query.trimmingCharacters(in: .whitespaces) { return }
        hits = r?.players ?? []
    }

    private func moverCard(_ m: Mover) -> some View {
        Button { router.push(.player(m.spId)) } label: {
            Panel(padding: 12, highlight: FC.win.opacity(0.4)) {
                HStack(spacing: 10) {
                    PlayerImage(spid: m.spId, size: 44)
                    VStack(alignment: .leading, spacing: 2) { SectionLabel("⚡ 오늘의 급상승", color: FC.win); Text(m.name).font(.system(size: 15, weight: .bold)).foregroundStyle(FC.ink); Text("\(m.positionLabel) · \(m.lineTitle ?? m.line) · n=\(m.matchCount)").font(.system(size: 12)).foregroundStyle(FC.muted) }
                    Spacer()
                    Text(m.isNew ? "NEW 진입" : "▲\(m.deltaValue ?? 0)").font(.scoreboard(14)).foregroundStyle(m.isNew ? FC.gold : FC.win).padding(.horizontal, 8).padding(.vertical, 5).background((m.isNew ? FC.gold : FC.win).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.buttonStyle(.plain)
    }

    private func lineBlock(_ line: MetaLine) -> some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(line.title)
                let maxCount = max(1, line.rows.first?.matchCount ?? 1)
                ForEach(Array(line.rows.enumerated()), id: \.element.id) { i, r in
                    Button { router.push(.player(r.spId)) } label: {
                        HStack(spacing: 8) {
                            Text("\(i + 1)").font(.scoreboard(13)).foregroundStyle(i < 3 ? FC.gold : FC.muted).frame(width: 20)
                            PlayerImage(spid: r.spId, size: 34, radius: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) { Text(r.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.ink).lineLimit(1); if !r.season.isEmpty { Chip(text: r.season, color: FC.gold, bg: FC.gold.opacity(0.15)) } }
                                GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(FC.surface2); Capsule().fill(FC.accent).frame(width: g.size.width * CGFloat(r.matchCount) / CGFloat(maxCount)) } }.frame(height: 4)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("n=\(r.matchCount)").font(.scoreboard(11)).foregroundStyle(FC.muted)
                                if r.isNew { Text("NEW").font(.scoreboard(11)).foregroundStyle(FC.gold) }
                                else if let d = r.deltaValue, d != 0 { Text(d > 0 ? "▲\(d)" : "▼\(-d)").font(.scoreboard(11)).foregroundStyle(d > 0 ? FC.win : FC.lose) }
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct PlayerDetailView: View {
    let spid: Int
    @State private var state: Loadable<PlayerDetail> = .idle
    @Environment(AppRouter.self) private var router
    var body: some View {
        ScrollView {
            switch state {
            case .idle, .loading: VStack(spacing: 10) { Skeleton(height: 120); Skeleton(height: 200) }.padding(16)
            case .failed(let e): ErrorState(title: "선수 정보를 불러오지 못했어요", message: e.localizedDescription, retry: { Task { await load() } })
            case .loaded(let p):
                VStack(alignment: .leading, spacing: 12) {
                    Panel {
                        HStack(spacing: 12) {
                            PlayerImage(spid: p.spid, size: 72, radius: 16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.system(size: 22, weight: .bold)).foregroundStyle(FC.ink)
                                if !p.season.isEmpty { Chip(text: p.season, color: FC.gold, bg: FC.gold.opacity(0.15)) }
                                Text("랭커 실사용 \(p.ranker.totalMatches)경기\(p.ranker.date.map { " · \($0)" } ?? "")").font(.system(size: 12)).foregroundStyle(FC.muted)
                            }
                        }
                    }
                    if p.ranker.positions.isEmpty {
                        Panel { Text("아직 랭커 실사용 데이터가 없어요. 스냅샷이 쌓이면 표시돼요.").font(.system(size: 13)).foregroundStyle(FC.muted) }
                    }
                    ForEach(p.ranker.positions) { ps in
                        Panel(padding: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(ps.positionLabel).font(.scoreboard(16)).foregroundStyle(FC.accent); Text("n=\(ps.matchCount)").font(.scoreboard(11)).foregroundStyle(FC.muted); Spacer(); if let st = ps.playstyle { Chip(text: "\(st.emoji) \(st.label)", color: FC.tone(st.tone), bg: FC.tone(st.tone).opacity(0.15)) } }
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                    mini("경기당 골", String(format: "%.2f", ps.goal)); mini("경기당 어시", String(format: "%.2f", ps.assist)); mini("슛/유효", String(format: "%.1f/%.1f", ps.shoot, ps.effectiveShoot))
                                    mini("패스 성공", ps.passRate.map { "\($0)%" } ?? "–"); mini("드리블 성공", ps.dribbleRate.map { "\($0)%" } ?? "–"); mini("태클+블록", String(format: "%.1f", ps.tackle + ps.block))
                                }
                            }
                        }
                    }
                    if p.seasons.count > 1 {
                        Panel(padding: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel("다른 시즌 카드")
                                FlowLayout(spacing: 6) { ForEach(p.seasons) { s in Button { router.push(.player(s.spid)) } label: { Chip(text: s.season, color: s.spid == p.spid ? FC.accentInk : FC.ink, bg: s.spid == p.spid ? FC.accent : FC.surface2) }.buttonStyle(.plain) } }
                            }
                        }
                    }
                    Button { router.pendingSquadImport = nil; router.tab = .squad; NotificationCenter.default.post(name: .squadAddPlayer, object: PlayerHit(spid: p.spid, pid: p.pid ?? p.spid % 1_000_000, name: p.name, season: p.season, seasons: p.seasons)) } label: {
                        Text("🛡️ 스쿼드 빌더에 배치").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }.padding(16)
            }
        }
        .fcScreen().navigationTitle(state.value?.name ?? "선수").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        let p = "/api/v1/player/\(spid)"
        if let hit: (value: PlayerDetail, isFresh: Bool) = await APIClient.shared.cachedValue(p) {
            state = .loaded(hit.value)
            if hit.isFresh { return }
        } else { state = .loading }
        do { state = .loaded(try await APIClient.shared.getAndCache(p, auth: false)) }
        catch { if state.value == nil { state = .failed(error) } }
    }
    private func mini(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) { Text(l).font(.system(size: 10)).foregroundStyle(FC.muted); Text(v).font(.scoreboard(14)).foregroundStyle(FC.ink) }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Notification.Name { static let squadAddPlayer = Notification.Name("fcscope.squadAddPlayer") }
