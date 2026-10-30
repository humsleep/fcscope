import SwiftUI

/// 계산기 허브 — 데이터가 있는 것만 직접 계산하고, 없는 것(클럽·국가 팀컬러, 강화 확률·급여)은 공식 데이터센터 도구로 보낸다.
/// 근거: 넥슨 오픈API 메타에 급여·소속 클럽·OVR 이 없다(2026-10-30 확인, docs/STRATEGY-2026-11.md).
struct CalculatorHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("계산기", color: FC.tint)
                SquadAnalysisPanel()
                FeeCalculatorPanel()
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("공식 데이터센터 도구")
                    DataCenterLink(title: "클럽·국가 팀컬러 / 감독", path: "teamcolor")
                    DataCenterLink(title: "강화 부스트 도우미", path: "playergrow")
                    DataCenterLink(title: "훈련코치 · 특성 도우미", path: "coachhelper")
                    DataCenterLink(title: "스쿼드 메이커 (급여·BP 합계)", path: "squadmaker")
                    DataCenterLink(title: "라이브 퍼포먼스", path: "playerlpList")
                    Text("넥슨 공식 사이트가 Safari 로 열려요. 급여·시세·클럽 팀컬러는 공식 API 에 없어 직접 계산하지 않아요.")
                        .fcFont(11).foregroundStyle(FC.muted)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .fcScreen().navigationTitle("계산기").navigationBarTitleDisplayMode(.inline)
    }
}

/// 시즌 팀컬러 — 같은 시즌 카드 수(웹 app/squad/SeasonMix.tsx 와 같은 규칙: 상위 6개, 3장 이상 강조).
struct SeasonMixRow: View {
    let seasons: [String?]

    private struct Count { let season: String; let n: Int }
    private var counts: [Count] {
        var byName: [String: Int] = [:]
        for s in seasons {
            let key = s?.trimmingCharacters(in: .whitespaces) ?? ""
            byName[key.isEmpty ? "기타" : key, default: 0] += 1
        }
        let all = byName.map { Count(season: $0.key, n: $0.value) }
        return Array(all.sorted { $0.n != $1.n ? $0.n > $1.n : $0.season < $1.season }.prefix(6))
    }

    var body: some View {
        let counts = counts
        if let best = counts.first {
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    Text("팀컬러 (시즌)").fcFont(12, weight: .bold).foregroundStyle(FC.muted)
                    ForEach(counts, id: \.season) { c in
                        Text("\(c.season) ×\(c.n)").fcScoreboard(12)
                            .foregroundStyle(c.n >= 3 ? FC.gold : FC.muted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(c.n >= 3 ? FC.gold.opacity(0.18) : FC.surface, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(best.n >= 3 ? "주력 시즌 팀컬러: \(best.season) \(best.n)장 — 같은 시즌을 모을수록 게임 내 팀컬러 보너스에 유리해요."
                                 : "같은 시즌 카드를 3장 이상 모으면 시즌 팀컬러 구성에 유리해요.")
                    .fcFont(12).foregroundStyle(FC.muted)
            }
            .padding(10)
            .background(FC.surface2.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.control))
            .accessibilityElement(children: .combine)
        }
    }
}

/// 내 스쿼드 분석 — 최근 공식경기 선발 11명(/api/squad/from-user)의 시즌 팀컬러 + 강화 단계 분포.
private struct SquadAnalysisPanel: View {
    @State private var nick = LocalPrefs.shared.myNickname ?? ""
    @State private var state: Loadable<FromUserResponse> = .idle

    var body: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("🛡️ 스쿼드 분석 · 시즌 팀컬러 · 강화 단계").fcFont(15, weight: .bold).foregroundStyle(FC.ink)
                Text("최근 공식경기 선발 11명으로 계산해요.").fcFont(12).foregroundStyle(FC.muted)
                HStack(spacing: 8) {
                    TextField("구단주명", text: $nick)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
                        .onSubmit { Task { await load() } }
                        .fcFont(15).foregroundStyle(FC.ink)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(FC.surface2, in: RoundedRectangle(cornerRadius: Radius.control))
                    Button("분석") { Task { await load() } }
                        .buttonStyle(BrandButtonStyle(compact: true))
                        .disabled(nick.trimmingCharacters(in: .whitespaces).isEmpty || state.isLoading)
                }
                switch state {
                case .idle: EmptyView()
                case .loading: Skeleton(height: 120)
                case .failed(let e): Text(e.localizedDescription).fcFont(13).foregroundStyle(FC.lose)
                case .loaded(let r):
                    SeasonMixRow(seasons: r.players.map(\.season))
                    gradeSection(r.players)
                }
            }
        }
    }

    private func load() async {
        let n = nick.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        state = .loading
        do { state = .loaded(try await APIClient.shared.get("/api/squad/from-user", query: ["nickname": n], auth: false)) }
        catch { state = .failed(error) }
    }

    @ViewBuilder private func gradeSection(_ players: [FromUserResponse.ImportedPlayer]) -> some View {
        let graded = players.filter { $0.grade != nil }
        if graded.isEmpty {
            // 옛 서버(강화 단계 필드 없음)
            Text("강화 단계는 서버 업데이트 후 보여요.").fcFont(12).foregroundStyle(FC.muted)
        } else {
            let grades = graded.compactMap(\.grade)
            let avg = Double(grades.reduce(0, +)) / Double(grades.count)
            let dist = Dictionary(grouping: grades, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.0 > $1.0 }
            let maxN = dist.map(\.1).max() ?? 1
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("강화 단계").fcFont(12, weight: .bold).foregroundStyle(FC.muted)
                    Spacer()
                    Text("평균 +\(String(format: "%.1f", avg))").fcScoreboard(14).foregroundStyle(FC.ink)
                }
                ForEach(dist, id: \.0) { g, n in
                    HStack(spacing: 8) {
                        Text("+\(g)").fcScoreboard(12).foregroundStyle(g >= 8 ? FC.gold : FC.ink).frame(width: 32, alignment: .leading)
                        RatioBar(ratio: CGFloat(n) / CGFloat(maxN), color: g >= 8 ? FC.gold : FC.tint, height: 6)
                        Text("\(n)명").fcFont(12).foregroundStyle(FC.muted).frame(width: 36, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                let low = graded.filter { ($0.grade ?? 0) < Int(avg.rounded(.down)) }.prefix(3)
                if !low.isEmpty {
                    Text("평균보다 낮은 강화: " + low.map { "\($0.name)(\($0.pos) +\($0.grade ?? 0))" }.joined(separator: ", "))
                        .fcFont(12).foregroundStyle(FC.ink)
                }
            }
        }
    }
}

/// 이적시장 수수료 계산기 — 요율은 비공식 통설이라 사용자가 고칠 수 있게 둔다(FeeMath.swift 주석).
private struct FeeCalculatorPanel: View {
    @State private var priceText = ""
    /// 고가 카드는 억 단위라 기본 입력 단위를 "억"으로
    @State private var unitEok = true
    @AppStorage("fcscope.fee.base") private var baseRate = 40
    @AppStorage("fcscope.fee.pc") private var pcRate = 30
    @AppStorage("fcscope.fee.top") private var topRate = 20
    @AppStorage("fcscope.fee.usePC") private var usePC = false
    @AppStorage("fcscope.fee.useTop") private var useTop = false
    @State private var coupon = 0

    private var price: Int64 {
        let v = Double(priceText.replacingOccurrences(of: ",", with: "")) ?? 0
        return Int64((v * (unitEok ? 100_000_000 : 1)).rounded(.down))
    }
    private var result: FeeResult {
        transferFee(FeeInput(price: price, baseRate: baseRate,
                             discounts: [usePC ? pcRate : 0, useTop ? topRate : 0, coupon]))
    }

    var body: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("💸 이적시장 수수료 계산기").fcFont(15, weight: .bold).foregroundStyle(FC.ink)
                HStack(spacing: 8) {
                    TextField("판매 금액", text: $priceText).keyboardType(.decimalPad)
                        .fcFont(16).foregroundStyle(FC.ink)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(FC.surface2, in: RoundedRectangle(cornerRadius: Radius.control))
                    Picker("단위", selection: $unitEok) { Text("억").tag(true); Text("BP").tag(false) }
                        .pickerStyle(.segmented).frame(width: 110)
                }
                Toggle("프리미엄 PC방 (−\(pcRate)%)", isOn: $usePC).fcFont(14)
                Toggle("TOP CLASS (−\(topRate)%)", isOn: $useTop).fcFont(14)
                Picker("할인 쿠폰", selection: $coupon) {
                    ForEach([0, 30, 40, 50, 100], id: \.self) { Text($0 == 0 ? "없음" : "\($0)%").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("수수료 할인 쿠폰")
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("수수료").fcFont(13).foregroundStyle(FC.muted); Spacer(); Text(Self.bp(result.fee)).fcScoreboard(15).foregroundStyle(FC.lose) }
                    HStack { Text("받는 금액").fcFont(13, weight: .semibold).foregroundStyle(FC.ink); Spacer(); Text(Self.bp(result.net)).fcScoreboard(18).foregroundStyle(FC.win) }
                    Text("적용 수수료율 \(String(format: "%.1f", result.effectiveRate))%").fcFont(11).foregroundStyle(FC.muted)
                }
                .padding(10).background(FC.surface2, in: RoundedRectangle(cornerRadius: Radius.control))
                DisclosureGroup("요율 바꾸기") {
                    Stepper("기본 수수료 \(baseRate)%", value: $baseRate, in: 0...100)
                    Stepper("PC방 할인 \(pcRate)%", value: $pcRate, in: 0...100)
                    Stepper("TOP CLASS 할인 \(topRate)%", value: $topRate, in: 0...100)
                }
                .fcFont(13).tint(FC.tint)
                Text("기본 40%·PC방 30%·TOP CLASS 20% 는 공식 공지로 확인하지 못한 통설 값이에요. 할인은 합산, 1 BP 단위 내림으로 계산해요. 실제 금액은 게임 판매 화면이 기준이고, 무료 즉시 판매에는 할인이 적용되지 않아요.")
                    .fcFont(11).foregroundStyle(FC.muted)
            }
        }
    }

    /// 1,234억 5,678만 BP
    static func bp(_ v: Int64) -> String {
        let eok = v / 100_000_000, man = (v % 100_000_000) / 10_000
        if eok > 0 { return man > 0 ? "\(eok.formatted())억 \(man.formatted())만 BP" : "\(eok.formatted())억 BP" }
        if man > 0 { return "\(man.formatted())만 BP" }
        return "\(v.formatted()) BP"
    }
}
