import SwiftUI
import UserNotifications

@Observable
@MainActor
final class RecordViewModel {
    let nickname: String
    var matchType = 50
    var overview: Loadable<UserOverview> = .idle
    var report: Loadable<ReportResponse> = .idle
    var players: Loadable<PlayersResponse> = .idle
    var playstyle: Loadable<PlaystyleResponse> = .idle
    var section: Section = .matches
    enum Section: String, CaseIterable, Identifiable {
        case matches = "경기 기록", style = "플레이스타일", report = "종합 리포트", players = "선수 성적표"
        var id: String { rawValue }
        /// 칩에 쓰는 짧은 라벨 — 긴 라벨은 폭을 먹어 네 개가 한눈에 안 들어온다.
        var short: String {
            switch self {
            case .matches: "경기"
            case .report: "리포트"
            case .players: "선수"
            case .style: "스타일"
            }
        }
        var icon: String {
            switch self {
            case .matches: "list.bullet"
            case .report: "chart.bar.fill"
            case .players: "person.2.fill"
            case .style: "scope"
            }
        }
    }

    /// 콜드 조회 선행 프로필 — 경기 30건을 기다리는 동안 히어로를 먼저 그린다.
    var quickProfile: UserProfile?
    var loadedFromCache = false

    init(nickname: String) { self.nickname = nickname }
    private var enc: String { nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nickname }
    private var path: String { "/api/v1/user/\(enc)" }
    private var query: [String: String] { ["type": String(matchType)] }

    /**
     최적화 2종.

     1) **stale-while-revalidate** — 디스크에 남은 마지막 응답을 즉시 그린다.
        같은 구단주 재방문 시 서버가 넥슨 36콜 + match_cache 30행 쓰기를 반복하지 않는다.
     2) **2단계 조회** — 진짜 콜드일 때만 프로필(넥슨 2콜)을 선행 조회해 히어로를 먼저 띄운다.
        최대 60초 걸리는 경기 30건을 기다리며 빈 화면을 보는 문제를 없앤다.
     */
    func load(force: Bool = false) async {
        // 유형을 바꾸는 사이 늦게 온 이전 유형 응답이 새 유형 화면을 덮지 않도록, 요청 시점 유형과 대조한다.
        let type = matchType, q = query
        if !force, let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path, query: q) {
            guard type == matchType else { return }
            apply(hit.value)
            loadedFromCache = true
            if hit.isFresh { return } // 2분 이내 → 네트워크 생략
        } else if overview.value == nil {
            overview = .loading
            await loadQuickProfile()
        }
        do {
            let o: UserOverview = try await APIClient.shared.getAndCache(path, query: q, auth: false)
            guard type == matchType else { return }
            apply(o)
            loadedFromCache = false
        } catch {
            guard type == matchType else { return }
            if overview.value == nil { overview = .failed(error) }
        }
    }

    /// 프로필·등급만 (경기 팬아웃 없음). 실패해도 본 조회에 영향 없음.
    private func loadQuickProfile() async {
        struct ProfileOnly: Decodable { let profile: UserProfile }
        if let r: ProfileOnly = try? await APIClient.shared.get(path, query: ["stage": "profile"], auth: false) {
            if overview.value == nil { quickProfile = r.profile }
        }
    }

    /// 캐시 → 네트워크로 apply 가 두 번 불리므로 조회 1회는 한 번만 센다.
    private var viewTracked = false

    private func apply(_ o: UserOverview) {
        overview = .loaded(o)
        if !viewTracked {
            viewTracked = true
            Analytics.shared.track(.recordView, ["match_type": matchType])
        }
        quickProfile = nil
        LocalPrefs.shared.addRecent(o.profile.nickname)
        // 폼 스냅샷(홈 내 구단·즐겨찾기 델타·위젯)은 공식경기 기준이다 — 감독모드 승률이 섞이면 델타가 튄다.
        if o.matchType == 50 {
            LocalPrefs.shared.recordForm(nick: o.profile.nickname, winRate: o.summary.winRate, score: o.score, streak: o.perf.currentStreak, form: o.matches.prefix(5).map(\.result))
            // 홈 "지난 방문 이후 새 경기" 기준점 — 내 구단주 전적을 실제로 본 순간만 옮긴다.
            if let latest = o.matches.first, LocalPrefs.shared.myNickname?.caseInsensitiveCompare(o.profile.nickname) == .orderedSame {
                LocalPrefs.shared.markSeen(nick: o.profile.nickname, latestMatchDate: latest.matchDate)
            }
        }
        Task { await AdsManager.shared.requestConsentIfEligible() }
    }

    private var typeTask: Task<Void, Never>?
    /// 유형 전환 — 이전 유형의 진행 중 조회는 취소한다(응답이 늦게 와도 load 의 유형 대조가 한 번 더 막는다).
    func selectType(_ t: Int) {
        guard t != matchType else { return }
        matchType = t
        report = .idle; players = .idle; playstyle = .idle
        typeTask?.cancel()
        typeTask = Task {
            await load(force: true)
            guard !Task.isCancelled else { return }
            await loadSection()
        }
    }
    func loadSection() async {
        Analytics.shared.track(.sectionView, ["section": String(describing: section)])
        let type = matchType, q = query
        switch section {
        case .matches: break
        case .report:
            if report.value != nil { return }
            let p = "/api/v1/user/\(enc)/report"
            if let hit: (value: ReportResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: q) {
                guard type == matchType else { return }
                report = .loaded(hit.value)
                if hit.isFresh { return }
            } else { report = .loading }
            do { let r: ReportResponse = try await APIClient.shared.getAndCache(p, query: q, auth: false); guard type == matchType else { return }; report = .loaded(r) }
            catch { if type == matchType, report.value == nil { report = .failed(error) } }
        case .players:
            if players.value != nil { return }
            let p = "/api/v1/user/\(enc)/players"
            if let hit: (value: PlayersResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: q) {
                guard type == matchType else { return }
                players = .loaded(hit.value)
                if hit.isFresh { return }
            } else { players = .loading }
            do { let r: PlayersResponse = try await APIClient.shared.getAndCache(p, query: q, auth: false); guard type == matchType else { return }; players = .loaded(r) }
            catch { if type == matchType, players.value == nil { players = .failed(error) } }
        case .style:
            if playstyle.value != nil { return }
            let p = "/api/v1/user/\(enc)/playstyle"
            if let hit: (value: PlaystyleResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: q) {
                guard type == matchType else { return }
                playstyle = .loaded(hit.value)
                if hit.isFresh { return }
            } else { playstyle = .loading }
            do { let r: PlaystyleResponse = try await APIClient.shared.getAndCache(p, query: q, auth: false); guard type == matchType else { return }; playstyle = .loaded(r) }
            catch { if type == matchType, playstyle.value == nil { playstyle = .failed(error) } }
        }
    }
    func refresh() async {
        _ = try? await APIClient.shared.sendNoContent("/api/refresh/\(enc)", method: "POST")
        report = .idle; players = .idle; playstyle = .idle
        await load(force: true)
        await loadSection()
    }
}

struct RecordView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let nickname: String
    @State private var vm: RecordViewModel
    @State private var prefs = LocalPrefs.shared
    @Environment(AppRouter.self) private var router
    /// 알림 권한이 아직 결정 전일 때만 true — 이미 허용·거부한 기기에 다시 묻지 않는다.
    @State private var pushUndetermined = false

    init(nickname: String) {
        self.nickname = nickname
        _vm = State(initialValue: RecordViewModel(nickname: nickname))
    }

    /// 없는 구단주·오류 화면에서 즐겨찾기 별이 보이면 "없는 구단주를 저장"하게 된다.
    private var overviewFailed: Bool { if case .failed = vm.overview { return true }; return false }
    /// 섹션 오류의 "다시 시도" — 실패 상태엔 값이 없어 loadSection 이 그대로 재조회한다(GET).
    private func retrySection() { Task { await vm.loadSection() } }

    var body: some View {
        Group {
            switch vm.overview {
            case .idle, .loading:
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let p = vm.quickProfile {
                            // 2단계 조회: 프로필이 먼저 도착 → 히어로부터 표시
                            quickHero(p)
                            Text("최근 30경기를 불러오는 중이에요. 처음 조회하는 구단주는 조금 걸려요.")
                                .fcFont(12).foregroundStyle(FC.muted)
                        } else {
                            Skeleton(height: 120)
                        }
                        Skeleton(height: 90); Skeleton(height: 200)
                    }.padding(16)
                }
            case .failed(let err):
                errorView(err)
            case .loaded(let o):
                content(o)
            }
        }
        .fcScreen()
        .navigationTitle(vm.overview.value?.profile.nickname ?? nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    if !overviewFailed {
                        Button {
                            Haptic.light()
                            if !prefs.isFavorite(nickname) { Analytics.shared.track(.favoriteAdd) }
                            prefs.toggleFavorite(nickname)
                        } label: {
                            Image(systemName: prefs.isFavorite(nickname) ? "star.fill" : "star").foregroundStyle(FC.gold)
                        }
                        .accessibilityLabel(prefs.isFavorite(nickname) ? "즐겨찾기 해제" : "즐겨찾기 추가")
                    }
                    if let o = vm.overview.value {
                        ShareLink(item: AppConfig.absolute("/user/\(o.profile.nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nickname)")) { Image(systemName: "link") }.accessibilityLabel("전적 링크 공유")
                    }
                }
            }
        }
        .task { await vm.load() }
        .task { if !prefs.pushPromptDismissed { await refreshPushStatus() } }
        .refreshable { await vm.refresh() }
    }

    /// 선행 프로필 히어로 (경기 데이터 도착 전)
    private func quickHero(_ p: UserProfile) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(p.nickname).fcFont(26, weight: .bold).foregroundStyle(FC.ink)
                    (Text("LV.").foregroundStyle(FC.muted) + Text("\(p.level)").foregroundStyle(FC.accent)).font(.fcScoreboard(14, typeSize, weight: .semibold)).lineLimit(1).fixedSize()
                }
                ForEach(p.divisions) { d in divisionRow(d) }
            }
        }
    }

    private func errorView(_ err: Error) -> some View {
        let api = err as? APIError
        return ErrorState(
            title: api?.isUserNotFound == true ? "‘\(nickname)’ 구단주를 찾을 수 없어요" : (api?.code == "maintenance" || api?.code == "paused" || api?.code == "not_configured") ? "잠시 조회를 쉬고 있어요" : "전적을 불러오지 못했어요",
            message: api?.isUserNotFound == true ? "구단주명을 확인해 주세요. 구단주명을 방금 바꿨다면 반영까지 시간이 걸려요." : err.localizedDescription,
            error: err,
            retry: { Task { await vm.load(force: true) } }
        )
    }

    @ViewBuilder
    private func content(_ o: UserOverview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero(o)
                if isMine(o), pushUndetermined, !prefs.pushPromptDismissed { pushPrompt }
                // 선택 컨트롤을 먼저 — 진단 배지가 사이에 있으면 컨트롤이 화면 아래로 밀려
                // "탭이 있는 줄 모르는" 상태가 된다. 배지는 보조 정보라 아래로 내린다.
                typeTabs(o)
                sectionPicker
                // 카카오톡 채팅 목록처럼 상단 탭 바로 아래·목록 맨 위에 카드 하나(2026-09-21 운영자 결정). 화면당 1개.
                AdSlot()
                if let mt = o.diagnosis.type { badge("⚽", mt) { vm.section = .report; Task { await vm.loadSection() } } }
                switch vm.section {
                case .matches: MatchesSection(o: o, nickname: o.profile.nickname)
                case .report: ReportSection(state: vm.report, retry: retrySection)
                case .players: PlayersSection(state: vm.players, nickname: o.profile.nickname, overview: o, retry: retrySection)
                case .style: PlaystyleSection(state: vm.playstyle, retry: retrySection)
                }
                HStack { Spacer(); ShareCardButton(story: .user(o), label: "전적 카드 저장 · 공유"); Spacer() }.padding(.top, 8)
            }
            .padding(16)
        }
    }

    private func isMine(_ o: UserOverview) -> Bool { prefs.myNickname?.caseInsensitiveCompare(o.profile.nickname) == .orderedSame }

    /// 소프트 푸시 요청 — 온보딩에서 가치를 보기 전에 시스템 팝업을 띄우던 것을, 내 전적을 처음 본 뒤로 옮겼다.
    /// "받기"를 눌렀을 때만 시스템 팝업이 뜬다. "괜찮아요"는 영구히 닫는다(설정에서 언제든 켤 수 있다).
    private var pushPrompt: some View {
        Panel(padding: 12, highlight: FC.accent.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("🔔").fcFont(22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("일요일 밤 주간 성적표 받아볼래요?").fcFont(15, weight: .bold).foregroundStyle(FC.ink)
                        Text("이번 주 승률·연승 리캡만 보내요. 경기마다 알림하지 않아요.").fcFont(12).foregroundStyle(FC.muted)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        Haptic.light()
                        Task { await PushManager.shared.requestPermission(); await refreshPushStatus() }
                    } label: { Text("받기").fcFont(14, weight: .bold).frame(maxWidth: .infinity, minHeight: 36) }
                    .buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk)
                    Button { prefs.pushPromptDismissed = true } label: {
                        Text("괜찮아요").fcFont(14, weight: .semibold).foregroundStyle(FC.muted).frame(maxWidth: .infinity, minHeight: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func refreshPushStatus() async {
        pushUndetermined = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    private func hero(_ o: UserOverview) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(o.profile.nickname).fcFont(26, weight: .bold).foregroundStyle(FC.ink).lineLimit(2).minimumScaleFactor(0.7)
                    (Text("LV.").foregroundStyle(FC.muted) + Text("\(o.profile.level)").foregroundStyle(FC.accent)).font(.fcScoreboard(14, typeSize, weight: .semibold)).lineLimit(1).fixedSize()
                    Spacer()
                    if prefs.myNickname?.caseInsensitiveCompare(o.profile.nickname) != .orderedSame {
                        // 12pt 글자만 한 탭 영역이라 잘 안 눌렸다 — 레이아웃은 그대로, 탭 영역만 44pt.
                        Button { prefs.myNickname = o.profile.nickname; Haptic.success() } label: {
                            Text("내 구단으로").fcFont(12, weight: .semibold).foregroundStyle(FC.accent).lineLimit(1).fixedSize()
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(.vertical, -12)
                    } else { Chip(text: "내 구단", color: FC.accentInk, bg: FC.accent) }
                }
                if o.summary.played > 0 { headline(o) }
                ForEach(o.profile.divisions) { d in divisionRow(d) }
                if !o.profile.divisions.isEmpty { ShareCardButton(story: .rank(o), label: "🏆 계급 인증 카드", compact: true) }
            }
        }
    }

    /// 넥슨 division 은 "역대 최고 등급 + 달성일"이다. 날짜만 괄호로 붙이니 현재 등급으로 읽혔다 — "최고 등급"을 밝힌다.
    private func divisionRow(_ d: DivisionCard) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 4) {
            Text("\(d.matchTypeName) 최고 등급").fcFont(13).foregroundStyle(FC.muted)
            HStack(spacing: 4) {
                if let icon = d.iconUrl { RemoteImage(url: icon, size: 20) }
                Text(d.divisionName).fcFont(13, weight: .bold).foregroundStyle(FC.gold)
            }
            Text("\(d.date) 달성").fcFont(12).foregroundStyle(FC.muted)
        }
    }

    /// 머리 숫자는 두 개만 — 승률과 FC Scope 스코어. 평균 평점·주간 평균처럼 척도가 다른 숫자가 나란히 있으면 무엇이 기준인지 흐려진다.
    private func headline(_ o: UserOverview) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("최근 \(o.summary.played)경기 승률").fcFont(12).foregroundStyle(FC.muted)
                Text("\(o.summary.winRate)%").fcScoreboard(30).foregroundStyle(FC.accent)
                Text("\(o.summary.win)승 \(o.summary.draw)무 \(o.summary.lose)패").fcScoreboard(11).foregroundStyle(FC.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("FC Scope 스코어").fcFont(12).foregroundStyle(FC.muted)
                (Text(String(format: "%.1f", o.score)) + Text("/10").font(.fcScoreboard(13, typeSize)).foregroundStyle(FC.muted)).font(.fcScoreboard(30, typeSize)).foregroundStyle(FC.tone(o.tier.tone))
                Text(o.tier.label).fcScoreboard(11).foregroundStyle(FC.tone(o.tier.tone))
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ emoji: String, _ r: Rule, action: @escaping () -> Void) -> some View {
        Button(action: action) { Panel(padding: 12) { RuleBadge(rule: r, prefix: "\(emoji) ") } }.buttonStyle(.plain)
    }

    /// 매치 유형 — "어떤 경기를 볼지"를 정하는 최상위 필터.
    /// 가로 스크롤 칩이었는데 화면 밖 항목을 놓치기 쉬웠다. 항목이 3개뿐이라
    /// 세그먼트 컨트롤이 한 줄에 다 들어가고, iOS 에서 배타 선택의 표준 컨트롤이다.
    private func typeTabs(_ o: UserOverview) -> some View {
        Picker("매치 유형", selection: Binding(
            get: { vm.matchType },
            // $0 를 중첩 클로저 안에서 쓰면 Binding 의 2인자 오버로드로 해석된다 — 이름을 준다.
            set: { newType in vm.selectType(newType) }
        )) {
            ForEach(o.matchTabs) { t in Text(t.label).tag(t.type) }
        }
        .pickerStyle(.segmented)
    }

    /// 보기 전환 — 같은 데이터를 네 가지 시선으로 본다.
    /// 세그먼트 컨트롤에 네 개의 긴 한글 라벨을 넣으니 글자가 뭉개져 안 보였다.
    /// 짧은 라벨 + 선택 상태가 분명한 칩으로 바꾸고, 줄바꿈으로 전부 노출한다.
    private var sectionPicker: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(RecordViewModel.Section.allCases) { sec in
                Button {
                    guard vm.section != sec else { return }
                    vm.section = sec
                    Haptic.light()
                    Task { await vm.loadSection() }
                } label: {
                    HStack(spacing: 5) {
                        // 고정 12pt 아이콘은 글자만 커지고 아이콘은 그대로라 칩 안에서 어색했다 — 같은 배율로 키운다.
                        Image(systemName: sec.icon).font(.system(size: 12 * TypeScale.factor(typeSize), weight: .semibold))
                        Text(sec.short).fcFont(13, weight: .semibold)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(vm.section == sec ? FC.accent : FC.surface2, in: Capsule())
                    .foregroundStyle(vm.section == sec ? FC.accentInk : FC.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sec.rawValue)
                .accessibilityAddTraits(vm.section == sec ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - 경기 기록

struct MatchesSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let o: UserOverview
    let nickname: String
    @Environment(AppRouter.self) private var router
    /// 진단은 두 개(주간·성향)만 먼저 보이고 나머지는 접는다 — 경기 목록이 화면 아래로 밀려 "경기" 탭인데 경기가 안 보였다.
    @State private var moreDiagnosis = false
    /// 경기 목록은 10경기까지 먼저 — 30줄을 다 펼치면 아래 진단이 사라진다.
    @State private var allMatches = false
    private static let listPreview = 10

    var body: some View {
        if o.matches.isEmpty {
            Panel { Text(o.listOk ? "최근 경기 기록이 없어요." : "넥슨 조회가 일시적으로 원활하지 않아요. 잠시 후 당겨서 새로고침해 주세요.").fcFont(14).foregroundStyle(FC.muted).frame(maxWidth: .infinity) }
        } else {
            if o.loaded < o.requested {
                Text("⚠️ 최근 \(o.requested)경기 중 \(o.loaded)경기만 불러와 \(o.loaded)경기 기준으로 계산했어요.").fcFont(13).foregroundStyle(FC.muted)
                    .padding(10).background(FC.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            // 전적을 여는 가장 흔한 이유는 "방금 그 경기" — 맨 위에 슛맵·POTM 까지 바로 보여 준다.
            if let last = o.matches.first { LastMatchCard(m: last, me: o.profile.ouid) }
            matchList
            // 진단은 최대 두 장만 펼쳐 둔다: 이번 주 + 경기 성향.
            if o.week.games >= 3 { weekly(o.week) }
            if !o.diagnosis.notes.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("경기 성향 진단")
                        ForEach(o.diagnosis.notes) { RuleBadge(rule: $0) }
                    }
                }
            }
            Button { withAnimation(.snappy) { moreDiagnosis.toggle() }; Haptic.light() } label: {
                HStack {
                    Text(moreDiagnosis ? "진단 접기" : "진단 더 보기").fcFont(14, weight: .semibold)
                    Text("폼 · 연승 · 상대 전적 · 득실").fcFont(12).foregroundStyle(FC.muted)
                    Spacer()
                    Image(systemName: moreDiagnosis ? "chevron.up" : "chevron.down").fcFont(12)
                }
                .foregroundStyle(FC.ink).padding(12)
                .background(FC.surface2, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
            if moreDiagnosis {
                formPanel
                if o.streak.highlight { streakBanner(o.streak) }
                if let n = o.nemesis { revenge(n) }
                // 접근성 크기에서는 세 칸이 너무 좁아 숫자가 과하게 줄어든다 — 세로로 쌓는다.
                let tiles = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                tiles {
                    // 몰수(3:0)를 뺀 실제 경기 기준 — 몰수가 섞이면 득실 부호까지 뒤집혔다(데이터 감사 M1)
                    let gf = o.perf.goalsFor ?? o.summary.goalsFor, ga = o.perf.goalsAgainst ?? o.summary.goalsAgainst
                    let games = o.perf.normalPlayed.flatMap { $0 > 0 ? $0 : nil } ?? o.summary.played
                    StatTile(label: (o.perf.forfeits ?? 0) > 0 ? "득점 / 실점 (몰수 제외)" : "득점 / 실점", value: "\(gf) / \(ga)")
                    StatTile(label: "경기당 득점", value: String(format: "%.1f", Double(gf) / Double(max(1, games))))
                    StatTile(label: "평균 점유율", value: "\(o.summary.avgPossession)%")
                }
                if !o.rivals.isEmpty { rivals(o.rivals) }
            }
        }
    }

    /// 마지막 경기는 위 카드가 보여 주므로 목록은 그 이전 경기부터.
    private var matchList: some View {
        let rest = Array(o.matches.dropFirst())
        let shown = allMatches ? rest : Array(rest.prefix(Self.listPreview))
        return VStack(alignment: .leading, spacing: 6) {
            if !rest.isEmpty { SectionLabel("이전 경기") }
            LazyVStack(spacing: 6) {
                ForEach(shown) { m in
                    Button { router.push(.match(id: m.matchId, me: o.profile.ouid, fromRecord: true)) } label: { MatchRow(m: m) }.buttonStyle(.plain)
                        .contextMenu {
                            Button { router.push(.match(id: m.matchId, me: o.profile.ouid, fromRecord: true)) } label: { Label("슛맵 · 매치 리포트", systemImage: "soccerball") }
                            if let opp = m.opponent { Button { router.push(.user(opp.nickname)) } label: { Label("\(opp.nickname) 전적 보기", systemImage: "person") } }
                        }
                }
            }
            if rest.count > Self.listPreview {
                Button { withAnimation(.snappy) { allMatches.toggle() } } label: {
                    Text(allMatches ? "접기" : "나머지 \(rest.count - Self.listPreview)경기 더 보기").fcFont(13, weight: .semibold).foregroundStyle(FC.accent)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    /// 승률·스코어 큰 숫자는 히어로로 올렸다 — 여기엔 흐름(최근 10경기 폼·경기 평점 추이)만 남긴다.
    private var formPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("최근 10경기 폼").fcFont(12).foregroundStyle(FC.muted)
                    HStack(spacing: 4) { ForEach(o.matches.prefix(10)) { ResultBadge(result: $0.result, size: 24) } }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("경기 평점 추이 (과거 → 최근)").fcFont(12).foregroundStyle(FC.muted)
                    RatingSparkline(values: o.matches.reversed().map { $0.me.rating })
                }
                Text("FC Scope 스코어는 승패·득실차·경기 평점·점유율을 종합한 퍼포먼스 점수(10점 만점)예요.").fcFont(11).foregroundStyle(FC.muted)
            }
        }
    }

    private func weekly(_ w: WeeklyRecap) -> some View {
        // 접근성 크기에서는 오른쪽 카드 버튼이 폭을 먹어 기록이 잘렸다 — 버튼을 아래 줄로 내린다.
        let stacked = typeSize.isAccessibilitySize
        return Panel(padding: 12, highlight: FC.accent.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("📅").fcFont(24)
                    // 승·무·패와 보조 지표를 한 줄에 몰아넣으니 글자를 키우자마자 "12승 7 / 무 9패"
                    // 처럼 숫자 중간에서 줄바꿈됐다. 두 줄로 나눠 각자 한 줄을 갖게 한다.
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel("이번 주 · \(w.label)")
                        Text("\(w.win)승 \(w.draw)무 \(w.lose)패")
                            .fcFont(16, weight: .bold).foregroundStyle(w.winRate >= 50 ? FC.win : FC.lose)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        HStack(spacing: 6) {
                            // 서버 주간 avgScore 는 최근 스코어와 척도가 달라 나란히 두면 헷갈린다 — 승률만.
                            Text("승률 \(w.winRate)%").fcFont(12).foregroundStyle(FC.muted)
                            if w.bestStreak >= 2 { Text("🔥\(w.bestStreak)연승").fcFont(12, weight: .bold).foregroundStyle(FC.win) }
                        }
                        .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    if !stacked { ShareCardButton(story: .weekly(o), label: "주간 카드", compact: true) }
                }
                if stacked { ShareCardButton(story: .weekly(o), label: "주간 카드", compact: true) }
            }
        }
    }

    private func streakBanner(_ s: StreakInfo) -> some View {
        Panel(padding: 12, highlight: (s.color == "lose" ? FC.lose : FC.win).opacity(0.4)) {
            HStack(spacing: 10) {
                Text(s.color == "lose" ? "🥶" : "🔥").fcFont(24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.text).fcScoreboard(18).foregroundStyle(FC.tone(s.color))
                    // 문구가 길어 카드 버튼과 겹치며 어색하게 접혔다 — 짧게.
                    Text(s.color == "lose" ? "반등을 노려봐요" : "이 기세를 이어가요").fcFont(12).foregroundStyle(FC.muted)
                }
                Spacer()
                // 연패·하락 폼은 공유할 이유가 없다 — 좋은 폼일 때만 카드 버튼
                if s.color != "lose" { ShareCardButton(story: .streak(o), label: "폼 카드", compact: true) }
            }
        }
    }

    private func revenge(_ r: Rival) -> some View {
        Button { router.push(.user(r.nickname)) } label: {
            Panel(padding: 12, highlight: FC.lose.opacity(0.4)) {
                HStack(spacing: 10) {
                    Text("🎯").fcFont(24)
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("천적 복수전", color: FC.lose)
                        Text("\(r.nickname)에게 \(r.win)승 \(r.lose)패 — 아직 \(r.lose - r.win)점 뒤").fcFont(14, weight: .bold).foregroundStyle(FC.ink)
                    }
                    Spacer()
                    ShareCardButton(story: .rival(o, r), label: "맞대결 카드", compact: true)
                }
            }
        }.buttonStyle(.plain)
    }

    private func rivals(_ rs: [Rival]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("자주 만난 상대 H2H")
                ForEach(rs) { r in
                    Button { router.push(.user(r.nickname)) } label: {
                        HStack {
                            Text(r.nickname).fcFont(14, weight: .semibold).foregroundStyle(FC.ink).lineLimit(1)
                            Spacer()
                            Text("\(r.win)승 \(r.draw)무 \(r.lose)패").fcScoreboard(13).foregroundStyle(r.win > r.lose ? FC.win : r.win < r.lose ? FC.lose : FC.muted)
                            Text("\(r.games)경기").fcFont(12).foregroundStyle(FC.muted)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct RatingSparkline: View {
    let values: [Double]
    var body: some View {
        let vs = values.filter { $0 > 0 }
        if vs.count >= 3 {
            let lo = (vs.min() ?? 5) - 0.2, hi = (vs.max() ?? 8) + 0.2
            GeometryReader { geo in
                Path { p in
                    for (i, v) in vs.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(max(1, vs.count - 1))
                        let y = geo.size.height * (1 - CGFloat((v - lo) / max(0.1, hi - lo)))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(FC.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .frame(height: 36)
        }
    }
}

/// 마지막 경기 카드 — 결과·스코어·상대·날짜 + 작은 슛맵 + POTM. 누르면 매치 리포트.
/// 요약(MatchSummary)만으로 먼저 그리고, 매치 상세는 리포트 화면과 같은 캐시 키로 받아 슛맵·POTM 을 채운다.
/// 끝난 경기는 불변이라 한 번 받으면 리포트를 열 때 네트워크가 다시 돌지 않는다. 실패하면 슛맵 없이 둔다.
struct LastMatchCard: View {
    let m: MatchSummary
    /// 매치 리포트와 같은 `me`(ouid) — 캐시 키를 맞춘다.
    let me: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppRouter.self) private var router
    @State private var detail: MatchDetailResponse?
    @State private var loading = true

    var body: some View {
        Button { router.push(.match(id: m.matchId, me: me, fromRecord: true)) } label: {
            Panel(padding: 12, highlight: FC.resultColor(m.result).opacity(0.5)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel("마지막 경기", color: FC.accent)
                        Spacer()
                        Text(DateFmt.relative(m.matchDate)).fcFont(12).foregroundStyle(FC.muted)
                    }
                    HStack(spacing: 10) {
                        ResultBadge(result: m.result, size: 36)
                        (Text("\(m.me.goals)").foregroundStyle(FC.ink) + Text(" : ").foregroundStyle(FC.muted) + Text(m.opponent.map { "\($0.goals)" } ?? "-").foregroundStyle(FC.muted))
                            .fcScoreboard(28).lineLimit(1).fixedSize()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("vs \(m.opponent?.nickname ?? "상대 없음")").fcFont(15, weight: .bold).foregroundStyle(FC.ink).lineLimit(1)
                            HStack(spacing: 6) {
                                if m.forfeit { Chip(text: "몰수", color: FC.lose, bg: FC.lose.opacity(0.15)) }
                                Text("점유 \(m.me.possession)% · 경기 평점 \(String(format: "%.1f", m.me.rating))").fcFont(12).foregroundStyle(FC.muted).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").fcFont(12).foregroundStyle(FC.muted)
                    }
                    if let d = detail {
                        if !(d.me.shots.isEmpty && (d.opponent?.shots ?? []).isEmpty) {
                            VStack(alignment: .leading, spacing: 4) {
                                MiniShotMap(mine: d.me.shots, theirs: d.opponent?.shots ?? [])
                                HStack {
                                    Text("\(d.opponent?.nickname ?? "상대") 슛 \(d.opponent?.stats.shots ?? 0)").foregroundStyle(FC.lose)
                                    Spacer()
                                    Text("내 슛 \(d.me.stats.shots) (유효 \(d.me.stats.effectiveShots))").foregroundStyle(FC.accent)
                                }
                                .fcFont(11, weight: .medium).lineLimit(1)
                            }
                        }
                        if let p = d.potm {
                            HStack(spacing: 8) {
                                PlayerImage(spid: p.spId, size: 32, radius: 8)
                                Text("POTM").fcScoreboard(11, weight: .semibold).foregroundStyle(FC.gold)
                                (Text(p.name).foregroundStyle(FC.ink).bold() + Text(" · \(p.side)").foregroundStyle(FC.muted))
                                    .fcFont(13).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 4)
                                (Text("선수 평점 ").font(.fcFont(10, typeSize)).foregroundStyle(FC.muted) + Text(String(format: "%.1f", p.rating)).foregroundStyle(FC.gold))
                                    .fcScoreboard(16).lineLimit(1).fixedSize()
                            }
                        }
                    } else if loading {
                        Skeleton(height: 90)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: m.matchId) { await load() }
    }

    private func load() async {
        let p = "/api/v1/match/\(m.matchId)", q = ["me": me]
        if let hit: (value: MatchDetailResponse, isFresh: Bool) = await APIClient.shared.cachedValue(p, query: q) {
            detail = hit.value; loading = false; return
        }
        loading = true
        detail = try? await APIClient.shared.getAndCache(p, query: q, auth: false)
        loading = false
    }
}
