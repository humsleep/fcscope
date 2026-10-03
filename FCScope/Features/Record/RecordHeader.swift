import SwiftUI

/**
 전적 헤더 v2 — "캡처하고 싶은 한 장"(UX-AUDIT-GENZ #4, 목업 ux-mockups/01-record.png).

 위에서 아래로: 계급 엠블럼 74pt + 닉네임 + 폼 티어 → 요즘 흐름 띠(서버 진단 유형) →
 3칸 타일(승률 · 스코어 링 · 경기당 득점) → 최근 10경기 폼 블록 → "스토리로 자랑" + "계급 카드" + VS.

 다이어트(디자인 리뷰 1라운드 M8, 목표 ≤ 380pt): 몰수 각주는 승률 타일의 ⓘ 팝오버로, 진단 설명은 최대 2줄,
 "친구랑 비교" 풀폭 행은 CTA 줄 오른쪽 원형 버튼으로, "내 구단으로"는 내비 메뉴로 옮겼다.

 이름 규칙(유저 패널 "내 타입이 화면마다 다르다"): **플레이스타일** = 성향 분석(압박 사냥꾼 등, 스타일 탭·전적 카드).
 이 띠는 서버 진단 유형(리빌딩 시즌 등) — 지금 상태라 **"요즘 흐름"**으로 부른다. 두 개념에 같은 이름을 쓰지 않는다.

 색 규칙(Theme.swift 머리 주석): 중립 숫자(승률·경기당 득점)는 ink, 좋고 나쁨이 있는 값(스코어)만 의미 색.
 */
struct RecordHeader: View {
    let o: UserOverview
    let isMine: Bool
    var onTypeTap: () -> Void
    var onVersus: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showBasis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecordIdentityRow(profile: o.profile, matchType: o.matchType, tier: o.summary.played > 0 ? o.formTier : nil, isMine: isMine)
            if let t = o.diagnosis.type { nowBand(t) }
            if o.summary.played > 0 {
                tiles
                formStrip
            } else {
                Text("이 모드는 최근 기록이 없어요.").fcText(.callout).foregroundStyle(FC.muted)
            }
            ctas
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                FC.surface
                // 은은한 바이올렛 글로우 — 목업의 보라 톤. 데이터 위에 깔리지 않게 오른쪽 위에만.
                RadialGradient(colors: [FC.tint.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [FC.brandEnd.opacity(0.08), .clear], center: .bottomLeading, startRadius: 0, endRadius: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FC.line, lineWidth: 1))
    }

    /// 화면 높이 700pt 미만(SE 등) — 헤더를 조금 줄여 첫 화면에 아래 탭 줄이 보이게
    static var compactHeight: Bool {
        let h = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }.first ?? 900
        return h < 700
    }

    // MARK: 요즘 흐름 (서버 진단 유형)

    private func nowBand(_ t: Rule) -> some View {
        // 서버 desc 는 "경기당 3골 이상 — 일단 상대보다 한 골 더 넣으면 됩니다" 형태 — 한 줄로 이어 최대 2줄.
        let desc = t.desc.replacingOccurrences(of: " — ", with: " · ")
        // 설명은 제목 아래 전체 폭으로 — 오른쪽 칸에 두면 SE·AX 에서 "…상…"으로 잘렸다(QA P2-2)
        return Button(action: onTypeTap) {
            HStack(alignment: .center, spacing: 12) {
                Text(Self.emoji(for: t)).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("요즘 흐름").fcText(.caption, weight: .semibold).foregroundStyle(FC.muted)
                        Text(t.title).fcRender(17, .bold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    // 높이가 작은 기기(SE)는 1줄 — 첫 화면에 탭 줄이 들어오게(디자인 2R N-1). 전문은 탭하면 리포트에.
                    Text(desc).fcText(.meta).foregroundStyle(FC.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : Self.compactHeight ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FC.muted)
            }
            .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
            // surface2 + 왼쪽 3pt 바. 가로 브랜드 그라디언트를 3pt 로 자르면 시작색(빨강)만 보여 경고 띠처럼 읽혔다(디자인 2R N-3)
            // → 세로 tint 그라디언트 — 경고색 없이 브랜드 바이올렛만.
            .background(FC.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [FC.tint, FC.tint.opacity(0.55)], startPoint: .top, endPoint: .bottom)).frame(width: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("요즘 흐름 \(t.title). \(t.desc)")
        .accessibilityHint("종합 리포트를 열어요")
    }

    /// 서버 진단 유형 id → 이모지. 모르는 유형은 공.
    static func emoji(for t: Rule) -> String {
        let key = t.id + " " + t.title
        if key.contains("화력") || key.contains("fire") || key.contains("attack") { return "🔥" }
        if key.contains("철벽") || key.contains("wall") || key.contains("defen") { return "🧱" }
        if key.contains("점유") || key.contains("possession") || key.contains("tiki") { return "🎯" }
        if key.contains("역습") || key.contains("counter") { return "⚡️" }
        if key.contains("리빌딩") || key.contains("rebuild") { return "🌱" }
        if t.tone == "lose" || t.tone == "warn" { return "🌱" }
        return "⚽️"
    }

    // MARK: 타일

    private var forfeits: Int { o.perf.forfeits ?? 0 }
    /// 몰수 제외 승률(있을 때만)
    private var normalWinRate: Int? {
        guard forfeits > 0, let np = o.perf.normalPlayed, np > 0, let nw = o.perf.normalWin else { return nil }
        return Int((Double(nw) / Double(np) * 100).rounded())
    }

    private var tiles: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            tile("승률", info: forfeits > 0, sub: "\(o.summary.win)승 \(o.summary.draw)무 \(o.summary.lose)패") {
                CountUp(target: Double(o.summary.winRate)) { v in
                    (Text("\(Int(v.rounded()))") + Text("%").font(.fcScoreboard(14, typeSize)).foregroundStyle(FC.muted))
                        .font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.ink)
                }
            }
            tile("스코어", sub: FCCopy.tier(o.tier.label), subColor: FC.tone(o.tier.tone)) {
                HStack(alignment: .center, spacing: 6) {
                    CountUp(target: o.score, delay: 0.05) { v in
                        Text(String(format: "%.1f", v)).font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.tone(o.tier.tone))
                    }
                    Spacer(minLength: 0)
                    ScoreRing(score: o.score, color: FC.tone(o.tier.tone), lineWidth: 4).frame(width: 24, height: 24)
                }
            }
            .accessibilityLabel("FC Scope 스코어 \(String(format: "%.1f", o.score))점, 10점 만점. \(FCCopy.tier(o.tier.label))")
            // "실점 2.5 · 몰수 제외"가 SE 에서 잘려 기준이 사라졌다(QA P2-1) — 기준은 ⓘ 팝오버에 모았다.
            tile("경기당 득점", sub: "실점 \(String(format: "%.1f", o.goalsAgainstPerGame))") {
                CountUp(target: o.goalsForPerGame, delay: 0.1) { v in
                    Text(String(format: "%.1f", v)).font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.ink)
                }
            }
        }
    }

    /// 몰수 기준 — 예전엔 타일 아래 각주 한 줄이었다. 승률(몰수 포함)과 득실(몰수 제외)의 기준이 다르다는 걸 한곳에서 밝힌다.
    private var basisNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("몰수 \(forfeits)경기가 섞여 있어요").fcText(.callout, weight: .bold).foregroundStyle(FC.ink)
            Text("· 승률은 몰수 포함 — 넥슨 공식 전적과 같은 기준" + (normalWinRate.map { " (빼면 \($0)%)" } ?? ""))
            Text("· 경기당 득점·실점, 리포트 득실은 몰수(3:0)를 뺀 실제 경기 기준")
        }
        .fcText(.meta).foregroundStyle(FC.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }

    private func tile<V: View>(_ label: String, info: Bool = false, sub: String, subColor: Color = FC.muted, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(label).fcText(.meta, weight: .semibold).foregroundStyle(FC.muted).lineLimit(1)
                if info {
                    Button { showBasis = true } label: {
                        Image(systemName: "info.circle").font(.system(size: 11, weight: .semibold)).foregroundStyle(FC.muted)
                            .frame(width: 22, height: 18).contentShape(Rectangle().inset(by: -10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("몰수 경기 기준 설명")
                    // 팝오버는 ⓘ 버튼에 건다 — 타일 묶음 전체에 걸면 화살표가 가운데(스코어) 타일을 가리켰다(QA 2R P2-6)
                    .popover(isPresented: $showBasis, arrowEdge: .top) {
                        basisNote.presentationCompactAdaptation(.popover)
                    }
                }
            }
            value().lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).fcText(.meta, weight: subColor == FC.muted ? .regular : .semibold).foregroundStyle(subColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FC.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FC.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: 폼 스트립 + 범례

    private var formStrip: some View {
        let recent = o.matches.prefix(10)
        let hasForfeit = recent.contains(where: \.forfeit)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("최근\(recent.count)").fcText(.caption, weight: .semibold).foregroundStyle(FC.muted).fixedSize()
                FormBlocks(matches: o.matches)
            }
            // 점선(몰수)·굵은 테두리(가장 최근)에 범례가 없었다(디자인 M8). 높이가 작은 기기는 몰수 범례만(있을 때).
            if !Self.compactHeight || hasForfeit {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if !Self.compactHeight { legend(dashed: false, "최근 경기") }
                    if hasForfeit { legend(dashed: true, "몰수") }
                }
            }
        }
    }

    private func legend(dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(dashed ? FC.muted : FC.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                .frame(width: 12, height: 10)
            Text(text).fcText(.caption).foregroundStyle(FC.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dashed ? "점선 칸은 몰수 경기" : "굵은 테두리는 가장 최근 경기")
    }

    // MARK: CTA

    private var ctas: some View {
        HStack(spacing: 8) {
            if o.summary.played > 0 {
                ShareCardButton(story: .user(o), label: "스토리로 자랑", style: .hero)
                    .layoutPriority(1)
            }
            if !o.profile.divisions.isEmpty {
                // 주 CTA 가 layoutPriority 로 폭을 다 가져가므로 보조 버튼은 폭을 고정한다(maxWidth 만 주면 0으로 눌렸다).
                if o.summary.played > 0 {
                    ShareCardButton(story: .rank(o), label: "🏆 계급", style: .secondary).frame(width: 92)
                } else {
                    ShareCardButton(story: .rank(o), label: "🏆 계급 카드", style: .secondary)
                }
            }
            // 친구 VS — 풀폭 행이던 것을 보조 원형 버튼으로(헤더 다이어트 · 디자인 M8)
            Button(action: { Haptic.light(); onVersus() }) {
                Text("VS").fcScoreboard(15).foregroundStyle(FC.tint)
                    .frame(width: 50, height: 50)
                    .background(FC.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(FC.tint.opacity(0.7), lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("친구랑 비교 VS")
            .accessibilityHint("승률 · 폼 티어 맞대결을 열어요")
        }
    }
}

/// 엠블럼 74pt + 닉네임 + 레벨 + 최고 등급 한 줄 + 폼 티어. 콜드 조회 선행 프로필(경기 도착 전)에도 같이 쓴다.
/// "내 구단으로"는 카드 모서리 링크(padding -12 로 붙어 있던 것)를 내비 메뉴로 옮겼다(QA P2-3).
struct RecordIdentityRow: View {
    let profile: UserProfile
    var matchType: Int = 50
    var tier: FormTier?
    var isMine: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 보고 있는 모드의 최고 등급 → 없으면 공식경기 → 아무거나
    private var division: DivisionCard? {
        profile.divisions.first { $0.matchType == matchType } ?? profile.divisions.first { $0.matchType == 50 } ?? profile.divisions.first
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            emblem
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(profile.nickname).fcFont(26, weight: .bold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.6)
                    (Text("LV.").foregroundStyle(FC.muted) + Text("\(profile.level)").foregroundStyle(FC.ink))
                        .font(.fcScoreboard(13, typeSize, weight: .semibold)).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    if isMine { Chip(text: "내 구단", color: FC.tintInk, bg: FC.tint).fixedSize() }
                }
                if let d = division {
                    // 넥슨 division 은 "역대 최고 + 달성일"이다 — 현재 등급으로 읽히지 않게 "역대 최고"를 밝힌다.
                    (Text(d.divisionName).foregroundStyle(FC.gold).bold() + Text(" · \(d.matchTypeName) 역대 최고").foregroundStyle(FC.muted))
                        .font(.fcText(.meta, typeSize)).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityLabel("\(d.matchTypeName) 역대 최고 등급 \(d.divisionName), \(d.date) 달성")
                }
                if let tier { FormTierButton(tier: tier) }
            }
            Spacer(minLength: 0)
        }
    }

    private var emblem: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(RadialGradient(colors: [FC.tint.opacity(0.35), FC.surface2], center: .center, startRadius: 4, endRadius: 52))
            if let icon = division?.iconUrl {
                RemoteImage(url: icon, size: 58)
            } else if let d = division {
                // 서버 iconUrl 이 없는 등급(마스터 등) — 글자 두 개("마스")는 깨진 이미지처럼 보였다(QA 2R P2-10).
                // 왕관 + 등급 이름 + 단계 숫자 배지로 "일부러 만든 엠블럼"처럼.
                LetterEmblem(name: d.divisionName)
            } else {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 30)).foregroundStyle(FC.muted)
            }
        }
        .frame(width: 74, height: 74)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
            LinearGradient(colors: [FC.gold.opacity(0.7), FC.tint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

/// 모드 드롭다운 알약 + 이번 주 요약 → 아래 줄에 밑줄 탭.
///
/// 선택 UI 문법 통일(디자인 M6): 1차 탭 밑줄은 전 화면 `FC.ink` 2.5pt(그라디언트는 CTA 전용),
/// 모드 알약은 `FC.surface2` 채움 + ink 글자(흰/검정 채움 알약이 화면에서 가장 센 요소였다).
/// 글자는 역할 토큰 — 탭 15 · 칩 13 · 메타 12 렌더(커뮤니티와 같은 크기).
struct RecordTabBar: View {
    let tabs: [MatchTab]
    let matchType: Int
    let week: WeeklyRecap?
    @Binding var section: RecordViewModel.Section
    var onType: (Int) -> Void
    var onSection: (RecordViewModel.Section) -> Void
    @Namespace private var underline

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    Picker("매치 유형", selection: Binding(get: { matchType }, set: { newType in onType(newType) })) {
                        ForEach(tabs) { t in Text(t.label).tag(t.type) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tabs.first { $0.type == matchType }?.label ?? "공식경기").fcText(.chip)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(FC.ink)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(FC.surface2, in: Capsule())
                    .overlay(Capsule().strokeBorder(FC.line, lineWidth: 1))
                    .tapTarget()
                }
                .accessibilityLabel("매치 유형 \(tabs.first { $0.type == matchType }?.label ?? "공식경기"), 바꾸기")
                if let w = week, w.games > 0 {
                    Text("이번 주 \(w.games)판 · \(w.win)승 \(w.draw)무 \(w.lose)패")
                        .fcText(.meta).foregroundStyle(FC.muted).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 22) {
                ForEach(RecordViewModel.Section.allCases) { sec in
                    let on = section == sec
                    Button {
                        guard section != sec else { return }
                        withAnimation(.snappy(duration: 0.25)) { section = sec }
                        onSection(sec)
                    } label: {
                        VStack(spacing: 0) {
                            Text(sec.short).fcText(.tab, weight: on ? .bold : .semibold).foregroundStyle(on ? FC.ink : FC.muted)
                                .frame(minHeight: 40)
                            ZStack {
                                Color.clear.frame(height: 2.5)
                                if on { Capsule().fill(FC.ink).frame(height: 2.5).matchedGeometryEffect(id: "u", in: underline) }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sec.rawValue)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(CM.hair).frame(height: 1) }
        }
    }
}


/// 아이콘이 없는 등급용 엠블럼 — "마스터2" → 왕관 · "마스터" · 단계 배지 "2".
struct LetterEmblem: View {
    let name: String
    private var parts: (base: String, step: String?) {
        let digits = name.reversed().prefix { $0.isNumber }
        let base = String(name.dropLast(digits.count)).trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? name : base, digits.isEmpty ? nil : String(digits.reversed()))
    }
    var body: some View {
        let p = parts
        VStack(spacing: 1) {
            Image(systemName: "crown.fill").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [FC.gold, FC.gold.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            Text(p.base).fcRender(12, .bold).foregroundStyle(FC.gold).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 6)
        }
        .frame(width: 74, height: 74)
        .overlay(alignment: .bottomTrailing) {
            if let s = p.step {
                Text(s).font(.scoreboard(12)).foregroundStyle(Color.black.opacity(0.85))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(FC.gold, in: Circle())
                    .offset(x: 4, y: 4)
            }
        }
    }
}
