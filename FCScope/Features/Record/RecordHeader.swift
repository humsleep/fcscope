import SwiftUI

/**
 전적 헤더 v2 — "캡처하고 싶은 한 장"(UX-AUDIT-GENZ #4, 목업 ux-mockups/01-record.png).

 위에서 아래로: 계급 엠블럼 74pt + 닉네임 + 폼 티어 → MY TYPE 띠(플레이스타일 칭호) →
 3칸 타일(승률 · 스코어 링 · 경기당 득점) → 최근 10경기 폼 블록 → "스토리로 자랑" + "계급 카드" → 친구랑 VS.

 색 규칙(Theme.swift 머리 주석): 중립 숫자(승률·경기당 득점)는 ink, 좋고 나쁨이 있는 값(스코어)만 의미 색.
 브랜드 그라디언트는 MY TYPE 띠와 주 CTA 두 군데만.
 */
struct RecordHeader: View {
    let o: UserOverview
    let isMine: Bool
    var onMakeMine: () -> Void
    var onTypeTap: () -> Void
    var onVersus: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecordIdentityRow(profile: o.profile, matchType: o.matchType, tier: o.summary.played > 0 ? o.formTier : nil,
                              isMine: isMine, onMakeMine: onMakeMine)
            if let t = o.diagnosis.type { myType(t) }
            if o.summary.played > 0 {
                tiles
                if let f = o.perf.forfeits, f > 0, let np = o.perf.normalPlayed, np > 0, let nw = o.perf.normalWin {
                    // 기준 라벨 — 승률은 앱 전체가 몰수 포함(넥슨 공식 전적과 같은 기준). 뺀 값도 밝혀 웹·카드와 숫자가 달라 보이는 일을 막는다.
                    Text("승률은 몰수 \(f)경기 포함 · 빼면 \(Int((Double(nw) / Double(np) * 100).rounded()))%")
                        .fcFont(11).foregroundStyle(FC.muted).padding(.top, -6)
                }
                HStack(spacing: 8) {
                    Text("최근\(min(10, o.matches.count))").fcFont(11, weight: .semibold).foregroundStyle(FC.muted).fixedSize()
                    FormBlocks(matches: o.matches)
                }
            } else {
                Text("이 모드는 최근 기록이 없어요.").fcFont(13).foregroundStyle(FC.muted)
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

    // MARK: MY TYPE

    private func myType(_ t: Rule) -> some View {
        // 서버 desc 는 "경기당 3골 이상 — 일단 상대보다 한 골 더 넣으면 됩니다" 형태 — 근거와 한 줄을 나눠 오른쪽에 둔다.
        let parts = t.desc.components(separatedBy: " — ")
        return Button(action: onTypeTap) {
            HStack(spacing: 12) {
                Text(Self.emoji(for: t)).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 1) {
                    Text("MY TYPE").fcScoreboard(10, weight: .semibold).kerning(2).foregroundStyle(FC.muted)
                    Text(t.title).fcFont(19, weight: .bold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.8)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(parts.first ?? t.desc).fcFont(11).foregroundStyle(FC.muted)
                    if parts.count > 1 { Text(parts.dropFirst().joined(separator: " — ")).fcFont(11).foregroundStyle(FC.muted) }
                }
                .multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [FC.brandStart.opacity(0.20), FC.brandEnd.opacity(0.10)], startPoint: .leading, endPoint: .trailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LinearGradient(colors: [FC.brandStart.opacity(0.55), FC.brandEnd.opacity(0.35)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("내 유형 \(t.title). \(t.desc)")
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

    private var tiles: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            tile("승률", sub: "\(o.summary.win)승 \(o.summary.draw)무 \(o.summary.lose)패") {
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
            tile("경기당 득점", sub: (o.perf.forfeits ?? 0) > 0 ? "실점 \(String(format: "%.1f", o.goalsAgainstPerGame)) · 몰수 제외" : "실점 \(String(format: "%.1f", o.goalsAgainstPerGame))") {
                CountUp(target: o.goalsForPerGame, delay: 0.1) { v in
                    Text(String(format: "%.1f", v)).font(.fcScoreboard(28, typeSize)).foregroundStyle(FC.ink)
                }
            }
        }
    }

    private func tile<V: View>(_ label: String, sub: String, subColor: Color = FC.muted, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).fcFont(11, weight: .semibold).foregroundStyle(FC.muted).lineLimit(1)
            value().lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).fcFont(11, weight: subColor == FC.muted ? .regular : .semibold).foregroundStyle(subColor).lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FC.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FC.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: CTA

    private var ctas: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if o.summary.played > 0 {
                    ShareCardButton(story: .user(o), label: "스토리로 자랑", style: .hero)
                        .layoutPriority(1)
                }
                if !o.profile.divisions.isEmpty {
                    // 주 CTA 가 layoutPriority 로 폭을 다 가져가므로 보조 버튼은 폭을 고정한다(maxWidth 만 주면 0으로 눌렸다).
                    if o.summary.played > 0 {
                        ShareCardButton(story: .rank(o), label: "🏆 계급 카드", style: .secondary).frame(width: 128)
                    } else {
                        ShareCardButton(story: .rank(o), label: "🏆 계급 카드", style: .secondary)
                    }
                }
            }
            Button(action: { Haptic.light(); onVersus() }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill").font(.system(size: 13, weight: .bold))
                    Text("친구랑 비교 (VS)").fcFont(14, weight: .bold)
                    Text("승률 · 폼 티어 맞대결").fcFont(12).foregroundStyle(FC.muted)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
                }
                .foregroundStyle(FC.tint)
                .padding(.horizontal, 4)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 엠블럼 74pt + 닉네임 + 레벨 + 최고 등급 한 줄 + 폼 티어. 콜드 조회 선행 프로필(경기 도착 전)에도 같이 쓴다.
struct RecordIdentityRow: View {
    let profile: UserProfile
    var matchType: Int = 50
    var tier: FormTier?
    var isMine: Bool
    var onMakeMine: (() -> Void)?
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
                }
                if let d = division {
                    // 넥슨 division 은 "역대 최고 + 달성일"이다 — 현재 등급으로 읽히지 않게 "역대 최고"를 밝힌다.
                    (Text(d.divisionName).foregroundStyle(FC.gold).bold() + Text(" · \(d.matchTypeName) 역대 최고").foregroundStyle(FC.muted))
                        .font(.fcFont(12, typeSize)).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityLabel("\(d.matchTypeName) 역대 최고 등급 \(d.divisionName), \(d.date) 달성")
                }
                if let tier { FormTierBadge(tier: tier) }
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) { mineControl }
    }

    @ViewBuilder private var mineControl: some View {
        if isMine {
            Chip(text: "내 구단", color: FC.tintInk, bg: FC.tint)
        } else if let onMakeMine {
            Button(action: onMakeMine) {
                Text("내 구단으로").fcFont(12, weight: .semibold).foregroundStyle(FC.tint).lineLimit(1).fixedSize()
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, -12)
        }
    }

    private var emblem: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(RadialGradient(colors: [FC.tint.opacity(0.35), FC.surface2], center: .center, startRadius: 4, endRadius: 52))
            if let icon = division?.iconUrl {
                RemoteImage(url: icon, size: 58)
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

/// 모드 드롭다운 칩 + 이번 주 요약 칩 → 아래 줄에 밑줄 탭. 두 줄이던 탭(세그먼트 + 칩)을 한 덩어리로 합쳤다.
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
                        Text(tabs.first { $0.type == matchType }?.label ?? "공식경기").fcFont(13, weight: .bold)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(FC.bg)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(FC.ink, in: Capsule())
                    .tapTarget()
                }
                .accessibilityLabel("매치 유형 \(tabs.first { $0.type == matchType }?.label ?? "공식경기"), 바꾸기")
                if let w = week, w.games > 0 {
                    Text("이번 주 \(w.games)판 · \(w.win)승 \(w.draw)무 \(w.lose)패")
                        .fcFont(12).foregroundStyle(FC.muted).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(FC.surface2, in: Capsule())
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
                        VStack(spacing: 7) {
                            Text(sec.short).fcFont(15, weight: on ? .bold : .semibold).foregroundStyle(on ? FC.ink : FC.muted)
                            ZStack {
                                Capsule().fill(Color.clear).frame(height: 3)
                                if on { Capsule().fill(FC.brand).frame(height: 3).matchedGeometryEffect(id: "u", in: underline) }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sec.rawValue)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(FC.line).frame(height: 1) }
        }
    }
}
