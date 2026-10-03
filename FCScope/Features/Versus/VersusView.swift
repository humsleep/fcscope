import SwiftUI

/**
 친구랑 VS — 다른 구단주명을 넣으면 내 전적과 나란히 비교하고, 스토리 카드로 공유한다.

 넥슨 레이트리밋: 새 백엔드 호출은 없다. 이미 있는 `/api/v1/user/:nickname` 만 쓴다.
 - 내 쪽은 전적 화면이 방금 받아 둔 응답 캐시를 그대로 쓴다(신선도와 무관하게 — 비교용이라 2분 지난 값도 충분).
 - 친구 쪽은 캐시가 신선하면 네트워크 없이, 아니면 1회 조회. "비교" 버튼을 누를 때만 부르고, 조회 중엔 버튼을 막는다.
 */
@Observable
@MainActor
final class VersusViewModel {
    let me: String
    let matchType: Int
    var mine: Loadable<UserOverview> = .idle
    var other: Loadable<UserOverview> = .idle
    var otherName = ""

    init(me: String, matchType: Int) { self.me = me; self.matchType = matchType }

    private func path(_ nick: String) -> String {
        "/api/v1/user/\(nick.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nick)"
    }
    private var query: [String: String] { ["type": String(matchType)] }

    func loadMine() async {
        if mine.value != nil { return }
        if let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path(me), query: query) {
            mine = .loaded(hit.value); return
        }
        mine = .loading
        do { mine = .loaded(try await APIClient.shared.getAndCache(path(me), query: query, auth: false)) }
        catch { mine = .failed(error) }
    }

    /// 구단주명 검사 — API 경로에 끼우므로 경로 구분자·".." 는 막는다(AppRouter 딥링크 규칙과 같다).
    static func validate(_ raw: String) -> String? {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(n.count), !n.contains("/"), !n.contains("..") else { return nil }
        return n
    }

    func compare(_ raw: String) async {
        guard let n = Self.validate(raw) else { other = .failed(VersusError.invalid); return }
        guard n.caseInsensitiveCompare(me) != .orderedSame else { other = .failed(VersusError.same); return }
        if case .loading = other { return }
        otherName = n
        if let hit: (value: UserOverview, isFresh: Bool) = await APIClient.shared.cachedValue(path(n), query: query), hit.isFresh {
            other = .loaded(hit.value); Analytics.shared.track(.sectionView, ["section": "versus", "cached": true]); return
        }
        other = .loading
        do {
            let o: UserOverview = try await APIClient.shared.getAndCache(path(n), query: query, auth: false)
            other = .loaded(o)
            Analytics.shared.track(.sectionView, ["section": "versus", "cached": false])
        } catch { other = .failed(error) }
    }

    enum VersusError: LocalizedError {
        case invalid, same
        var errorDescription: String? {
            switch self {
            case .invalid: "구단주명을 다시 확인해 주세요."
            case .same: "나 말고 다른 구단주를 넣어 주세요."
            }
        }
    }
}

struct VersusView: View {
    @State private var vm: VersusViewModel
    @State private var input: String
    @State private var prefs = LocalPrefs.shared
    @FocusState private var focused: Bool
    @Environment(AppRouter.self) private var router
    private let initialOther: String?

    init(me: String, matchType: Int = 50, initialOther: String? = nil) {
        _vm = State(initialValue: VersusViewModel(me: me, matchType: matchType))
        _input = State(initialValue: initialOther ?? "")
        self.initialOther = initialOther
    }

    /// 즐겨찾기 → 최근 검색 → 자주 만난 상대 → 최근 상대 순(내 전적 응답 안 — 추가 호출 없음). 나와 중복은 뺀다.
    private var suggestions: [String] {
        var seen = Set<String>()
        let rivals = vm.mine.value?.rivals.map(\.nickname) ?? []
        // 맞대결 2경기 이상(rivals)이 없으면 최근 상대로 채운다 — 같은 응답 안의 경기 목록이라 역시 추가 호출 없음.
        let recentOpps = vm.mine.value?.matches.compactMap { $0.forfeit ? nil : $0.opponent?.nickname } ?? []
        return (prefs.favorites + prefs.recentSearches + rivals + recentOpps).filter {
            $0.caseInsensitiveCompare(vm.me) != .orderedSame && seen.insert($0.lowercased()).inserted
        }.prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro
                inputPanel
                result
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .fcScreen()
        .navigationTitle("친구랑 VS")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadMine()
            if let o = initialOther, vm.other.value == nil { await vm.compare(o) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(vm.me).foregroundStyle(FC.ink) + Text(" vs ").foregroundStyle(FC.muted) + Text(vm.other.value?.profile.nickname ?? "친구").foregroundStyle(FC.tint))
                .fcFont(24, weight: .bold).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(modeName) 최근 30경기로 승률 · 폼 티어 · 득실 · 스코어를 붙여 봐요.").fcFont(13).foregroundStyle(FC.muted)
        }
    }

    private var modeName: String {
        vm.mine.value.flatMap { o in o.matchTabs.first { $0.type == o.matchType }?.label } ?? (vm.matchType == 52 ? "감독모드" : vm.matchType == 40 ? "클래식 1on1" : "공식경기")
    }

    private var busy: Bool { if case .loading = vm.other { return true }; return false }

    private var inputPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(FC.muted)
                        TextField("친구 구단주명", text: $input)
                            .fcFont(16).foregroundStyle(FC.ink)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.go).focused($focused)
                            .onSubmit(go)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(FC.surface2, in: RoundedRectangle(cornerRadius: Radius.control))
                    Button(action: go) {
                        if busy { ProgressView().controlSize(.small).tint(FC.brandInk) } else { Text("비교") }
                    }
                    .buttonStyle(BrandButtonStyle(compact: true))
                    .frame(minHeight: 44)
                    .disabled(busy || VersusViewModel.validate(input) == nil)
                }
                // 결과가 나오면 추천 줄을 접는다 — 공유 버튼이 첫 화면 안에 들어오게.
                if !suggestions.isEmpty, vm.other.value == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { n in
                                Button { input = n; go() } label: {
                                    HStack(spacing: 4) {
                                        if prefs.isFavorite(n) { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(FC.gold) }
                                        Text(n).fcFont(13, weight: .semibold).foregroundStyle(FC.ink)
                                    }
                                    .padding(.horizontal, 12).frame(height: 32)
                                    .background(FC.surface2, in: Capsule())
                                    .tapTarget()
                                }
                                .buttonStyle(.plain)
                                .disabled(busy)
                            }
                        }
                    }
                }
            }
        }
    }

    private func go() {
        focused = false
        Haptic.light()
        Task { await vm.compare(input) }
    }

    @ViewBuilder private var result: some View {
        switch (vm.mine, vm.other) {
        case (.failed(let e), _):
            ErrorState(title: "내 전적을 불러오지 못했어요", message: e.localizedDescription, error: e, retry: { Task { await vm.loadMine() } })
        case (_, .failed(let e)):
            let api = e as? APIError
            ErrorState(title: api?.isUserNotFound == true ? "‘\(vm.otherName)’ 구단주를 찾을 수 없어요" : "비교하지 못했어요",
                       message: api?.isUserNotFound == true ? "구단주명을 확인해 주세요. 방금 바꾼 이름이면 반영까지 시간이 걸려요." : e.localizedDescription,
                       error: e)
        case (.loaded(let a), .loaded(let b)):
            loaded(VersusComparison(a: a, b: b))
        case (_, .loading):
            VStack(spacing: 10) {
                Text("\(vm.otherName) 최근 30경기를 불러오는 중이에요. 처음 조회하는 구단주는 조금 걸려요.").fcFont(12).foregroundStyle(FC.muted)
                Skeleton(height: 120); Skeleton(height: 260)
            }
        default:
            emptyHint
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Text("⚔️").font(.system(size: 40))
            Text("같이 하는 친구 이름을 넣어 봐요").fcFont(15, weight: .semibold).foregroundStyle(FC.ink)
            Text("결과는 스토리 카드로 바로 공유할 수 있어요.").fcFont(13).foregroundStyle(FC.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private func loaded(_ c: VersusComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if c.a.summary.played == 0 || c.b.summary.played == 0 {
                Panel { Text("\(c.a.summary.played == 0 ? c.a.profile.nickname : c.b.profile.nickname) 님은 \(modeName) 최근 기록이 없어 비교할 수 없어요.").fcFont(14).foregroundStyle(FC.muted) }
            } else {
                VersusCompareCard(c: c)
                ShareCardButton(story: .versus(c.a, c.b), label: "VS 카드 스토리로 공유", style: .hero)
                HStack(spacing: 8) {
                    Button { router.push(.user(c.b.profile.nickname)) } label: {
                        Text("\(c.b.profile.nickname) 전적 보기").fcFont(13, weight: .semibold).foregroundStyle(FC.tint)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("폼 티어는 FC Scope 가 최근 경기(승률 50% · 득실 25% · 스코어 25%)로 계산한 등급이에요. 넥슨 공식 등급이 아니에요.")
                    .fcFont(11).foregroundStyle(FC.muted)
            }
        }
    }
}

/// 화면용 비교 카드 — 가운데 라벨, 양옆 값. 이긴 쪽 값만 win 색(의미 색 규칙).
struct VersusCompareCard: View {
    let c: VersusComparison
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let (x, y) = c.tally
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                side(c.a, tier: c.tierA, align: .leading)
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        CountUp(target: Double(x)) { v in Text("\(Int(v.rounded()))").font(.fcScoreboard(40, typeSize)).foregroundStyle(x >= y ? FC.ink : FC.muted) }
                        Text(":").fcScoreboard(26).foregroundStyle(FC.muted)
                        CountUp(target: Double(y)) { v in Text("\(Int(v.rounded()))").font(.fcScoreboard(40, typeSize)).foregroundStyle(y >= x ? FC.ink : FC.muted) }
                    }
                    Text("항목 승").fcFont(10).foregroundStyle(FC.muted)
                }
                .fixedSize()
                side(c.b, tier: c.tierB, align: .trailing)
            }
            Text(c.verdict).fcFont(14, weight: .bold).foregroundStyle(x == y ? FC.tint : FC.gold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(x == y ? FC.tint : FC.gold, lineWidth: 1.5))
            VStack(spacing: 6) {
                ForEach(Array(c.rows.enumerated()), id: \.element.id) { i, r in
                    row(r)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 8)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.3).delay(0.15 + Double(i) * 0.05), value: appeared)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                FC.surface
                RadialGradient(colors: [FC.tint.opacity(0.2), .clear], center: .top, startRadius: 0, endRadius: 280)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FC.line, lineWidth: 1))
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared) { _, new in new && x > y }
    }

    private func side(_ o: UserOverview, tier: FormTier, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 6) {
            Text(o.profile.nickname).fcFont(17, weight: .bold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.6)
            FormTierBadge(tier: tier, size: .compact)
            if let d = o.profile.divisions.first(where: { $0.matchType == o.matchType }) ?? o.profile.divisions.first {
                HStack(spacing: 3) {
                    if let icon = d.iconUrl { RemoteImage(url: icon, size: 14) }
                    Text("최고 \(d.divisionName)").fcFont(11).foregroundStyle(FC.muted).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
    }

    private func row(_ r: VersusComparison.Row) -> some View {
        HStack(spacing: 6) {
            value(r.left, win: r.winner == .a, align: .leading)
            Text(r.label).fcFont(12, weight: .semibold).foregroundStyle(FC.muted).lineLimit(1).fixedSize()
            value(r.right, win: r.winner == .b, align: .trailing)
        }
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(FC.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.label): \(c.a.profile.nickname) \(r.left), \(c.b.profile.nickname) \(r.right)"
            + (r.winner == .a ? ", \(c.a.profile.nickname) 우세" : r.winner == .b ? ", \(c.b.profile.nickname) 우세" : ""))
    }

    private func value(_ s: String, win: Bool, align: Alignment) -> some View {
        let ascii = s.unicodeScalars.allSatisfy(\.isASCII)
        return HStack(spacing: 4) {
            if win, align == .trailing { Image(systemName: "arrowtriangle.left.fill").font(.system(size: 8)).foregroundStyle(FC.win) }
            Group {
                if ascii { Text(s).fcScoreboard(18) } else { Text(s).fcFont(14, weight: .bold) }
            }
            .foregroundStyle(win ? FC.win : FC.ink).lineLimit(1).minimumScaleFactor(0.6)
            if win, align == .leading { Image(systemName: "arrowtriangle.right.fill").font(.system(size: 8)).foregroundStyle(FC.win) }
        }
        .frame(maxWidth: .infinity, alignment: align)
    }
}
