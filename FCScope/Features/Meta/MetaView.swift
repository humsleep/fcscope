import SwiftUI

struct MetaView: View {
    @State private var state: Loadable<MetaResponse> = .idle
    @State private var matchType = 50
    @State private var query = ""
    @State private var hits: [PlayerHit] = []
    @Environment(AppRouter.self) private var router

    private var modeName: String { matchType == 52 ? "감독모드" : "공식경기" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("픽 랭킹", color: FC.accent)
                Text("최근 \(modeName)에서 선발로 가장 많이 쓰인 카드와, 그 카드의 넥슨 상위 랭커 성적.\(state.value?.date.map { " (\($0) 스냅샷)" } ?? "")").fcFont(13).foregroundStyle(FC.muted)
                // 빈 라벨이면 VoiceOver 가 이름 없는 컨트롤로 읽는다 — 라벨은 주고 화면에서만 숨긴다.
                Picker("매치 유형", selection: $matchType) { Text("공식경기").tag(50); Text("감독모드").tag(52) }.pickerStyle(.segmented).labelsHidden()
                    .onChange(of: matchType) { _, _ in Task { await load() } }
                if !hits.isEmpty {
                    Panel(padding: 8) {
                        VStack(spacing: 0) {
                            ForEach(hits.prefix(8)) { h in
                                Button { router.push(.player(h.spid)); query = ""; hits = [] } label: {
                                    HStack { PlayerImage(spid: h.spid, size: 32, radius: 8); Text(h.name).fcFont(14, weight: .semibold).foregroundStyle(FC.ink); SeasonBadge(spid: h.spid, season: h.season); Spacer(); Text("\(h.seasons.count)시즌").fcFont(11).foregroundStyle(FC.muted) }.padding(8)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                switch state {
                case .idle, .loading: Skeleton(height: 300)
                case .failed(let e): ErrorState(title: "픽 랭킹을 불러오지 못했어요", message: e.localizedDescription, error: e, retry: { Task { await load() } })
                case .loaded(let m):
                    if m.lines.isEmpty {
                        // 작은 패널 한 칸 + 광고만 남아 고장난 화면처럼 보였다 — 시스템 빈 상태로 이유를 설명한다.
                        ContentUnavailableView {
                            Label("아직 픽 랭킹 데이터가 없어요", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text("최근 경기와 랭커 기록을 매일 모아 픽 랭킹을 만들어요. 오늘 스냅샷이 쌓이면 여기에 표시돼요.")
                        }
                        .padding(.top, 24)
                    } else {
                        if let mv = m.mover { moverCard(mv) }
                        ForEach(m.lines) { line in lineBlock(line) }
                        Text("순위: FC Scope에 조회된 최근 \(modeName)에서 선발로 뛴 횟수. 골·패스는 넥슨 상위 랭커 기록(카드당 최근 20경기).").fcFont(11).foregroundStyle(FC.muted)
                    }
                }
                // 빈 화면에 광고만 덩그러니 있으면 광고가 본문처럼 보인다 — 데이터가 있을 때만.
                if !(state.value?.lines.isEmpty ?? false) { AdSlot() }
            }.padding(16)
        }
        .fcScreen().navigationTitle("픽 랭킹").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "선수 이름으로 도감 검색")
        .task(id: query) { await search(query) }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        // 유형을 빠르게 바꾸면 늦게 온 이전 유형 응답이 덮어쓴다 — 요청 시점 유형과 다르면 버린다.
        let type = matchType, q = ["type": String(matchType)]
        if let hit: (value: MetaResponse, isFresh: Bool) = await APIClient.shared.cachedValue("/api/v1/meta", query: q) {
            guard type == matchType else { return }
            state = .loaded(hit.value)
            if hit.isFresh { return }
        } else if state.value == nil { state = .loading }
        do { let r: MetaResponse = try await APIClient.shared.getAndCache("/api/v1/meta", query: q, auth: false); guard type == matchType else { return }; state = .loaded(r) }
        catch { if type == matchType, state.value == nil { state = .failed(error) } }
    }
    /// 번들 인덱스 로컬 검색 (서버 왕복 0). 인덱스 미탑재 시에만 서버 폴백.
    private func search(_ q: String) async {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { hits = []; return }
        if PlayerIndex.shared.isReady {
            hits = await PlayerIndex.shared.search(t)
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
                    VStack(alignment: .leading, spacing: 2) { SectionLabel("⚡ 오늘의 급상승", color: FC.win); Text(m.name).fcFont(15, weight: .bold).foregroundStyle(FC.ink); Text("\(m.positionLabel) · \(m.lineTitle ?? m.line)\(m.usage.map { " · 선발 \($0)회" } ?? "")").fcFont(12).foregroundStyle(FC.muted) }
                    Spacer()
                    Text(m.isNew ? "NEW 진입" : "▲\(m.deltaValue ?? 0)").fcScoreboard(14).foregroundStyle(m.isNew ? FC.gold : FC.win).padding(.horizontal, 8).padding(.vertical, 5).background((m.isNew ? FC.gold : FC.win).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.buttonStyle(.plain)
    }

    private func lineBlock(_ line: MetaLine) -> some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(line.title)
                let maxCount = max(1, line.rows.map(\.count).max() ?? 1)
                ForEach(Array(line.rows.enumerated()), id: \.element.id) { i, r in
                    Button { router.push(.player(r.spId)) } label: {
                        HStack(spacing: 8) {
                            Text("\(i + 1)").fcScoreboard(13).foregroundStyle(i < 3 ? FC.gold : FC.muted).frame(width: 20)
                            PlayerImage(spid: r.spId, size: 34, radius: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) { Text(r.name).fcFont(13, weight: .semibold).foregroundStyle(FC.ink).lineLimit(1); if !r.season.isEmpty { SeasonBadge(spid: r.spId, season: r.season, height: 14) } }
                                GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(FC.surface2); Capsule().fill(FC.accent).frame(width: g.size.width * CGFloat(r.count) / CGFloat(maxCount)) } }.frame(height: 4)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(r.usage.map { "\($0)회" } ?? "n=\(r.matchCount)").fcScoreboard(11).foregroundStyle(FC.muted)
                                if r.isNew { Text("NEW").fcScoreboard(11).foregroundStyle(FC.gold) }
                                else if let d = r.deltaValue, d != 0 { Text(d > 0 ? "▲\(d)" : "▼\(-d)").fcScoreboard(11).foregroundStyle(d > 0 ? FC.win : FC.lose) }
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
            case .failed(let e): ErrorState(title: "선수 정보를 불러오지 못했어요", message: e.localizedDescription, error: e, retry: { Task { await load() } })
            case .loaded(let p):
                // 서버 `season` 은 요청한 카드가 아니라 최신 시즌(예: PTG 카드를 열어도 "26 TOTS")을 내려준다(2026-09-15 실측).
                // 칩 강조(spid 기준)는 맞고 헤더가 틀렸다 — 같은 응답의 seasons 에서 spid 로 찾은 값을 우선한다.
                let season = p.seasons.first { $0.spid == p.spid }?.season ?? p.season
                VStack(alignment: .leading, spacing: 12) {
                    Panel {
                        HStack(spacing: 12) {
                            PlayerImage(spid: p.spid, size: 72, radius: 16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).fcFont(22, weight: .bold).foregroundStyle(FC.ink)
                                if !season.isEmpty { SeasonBadge(spid: p.spid, season: season, height: 22) }
                                if p.ranker.totalMatches > 0 {
                                    Text("넥슨 상위 랭커 최근 \(p.ranker.totalMatches)경기 평균\(p.ranker.date.map { " · \($0)" } ?? "")").fcFont(12).foregroundStyle(FC.muted)
                                }
                            }
                        }
                    }
                    if p.ranker.positions.isEmpty {
                        Panel { Text("아직 이 카드의 랭커 기록이 없어요. 많이 쓰이는 카드부터 매일 모아요.").fcFont(13).foregroundStyle(FC.muted) }
                    }
                    ForEach(p.ranker.positions) { ps in
                        Panel(padding: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(ps.positionLabel).fcScoreboard(16).foregroundStyle(FC.accent); Text("n=\(ps.matchCount)").fcScoreboard(11).foregroundStyle(FC.muted); Spacer(); if let st = ps.playstyle { Chip(text: "\(st.emoji) \(st.label)", color: FC.tone(st.tone), bg: FC.tone(st.tone).opacity(0.15)) } }
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
                                FlowLayout(spacing: 6) { ForEach(p.seasons) { s in Button { if s.spid != p.spid { router.push(.player(s.spid)) } } label: { SeasonBadge(spid: s.spid, season: s.season, height: 18).padding(.horizontal, 6).padding(.vertical, 4).background(s.spid == p.spid ? FC.accent : FC.surface2, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) } }
                            }
                        }
                    }
                    Button {
                        let hit = PlayerHit(spid: p.spid, pid: p.pid ?? p.spid % 1_000_000, name: p.name, season: season, seasons: p.seasons)
                        // 랭커가 가장 많이 뛴 포지션의 라인에 넣는다 — 골키퍼가 공격 슬롯에 들어가지 않게.
                        let main = p.ranker.positions.filter { $0.positionLabel != "SUB" }.max { $0.matchCount < $1.matchCount }?.positionLabel
                        router.pendingSquadImport = .add(hit, line: main.map(Formation.lineOf))
                        router.tab = .squad
                    } label: {
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
        VStack(alignment: .leading, spacing: 1) { Text(l).fcFont(10).foregroundStyle(FC.muted); Text(v).fcScoreboard(14).foregroundStyle(FC.ink) }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 8))
    }
}

