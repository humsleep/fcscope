import SwiftUI

/// 스쿼드 배틀 카드 — 투표 전엔 표 수를 숨기고(밴드왜건 방지) 투표하면 결과를 공개한다(SPEC 8절).
/// A = tint(바이올렛) · B = coral. `win`/`lose` 는 쓰지 않는다(B 가 "진 쪽"으로 읽히던 문제).
struct BattleCard: View {
    let postId: String
    let squadA: String
    let squadB: String
    /// "댓글로 이유를 남겨 보세요" → 입력창 포커스
    var onCommentPrompt: () -> Void = {}

    @State private var votes: BattleVotes?
    @State private var mine: String?
    @State private var voting = false
    @State private var voteError: String?
    @State private var revealed: CGFloat = 0
    @State private var a: Squad?
    @State private var b: Squad?
    @State private var cprefs = CommunityPrefs.shared
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            Text(mine == nil ? "어느 쪽이 이길까요? 투표하면 결과가 보여요" : "투표 완료 · \(CMFormat.count(total))명 참여")
                .cmText(13.5, .semibold).foregroundStyle(FC.muted)
                .multilineTextAlignment(.center)
            ZStack {
                HStack(spacing: 10) {
                    side("A", squadA, a, FC.tint)
                    side("B", squadB, b, CM.coral)
                }
                Text("VS").cmScore(13, .bold).foregroundStyle(FC.ink)
                    .frame(width: 34, height: 34)
                    .background(FC.bg, in: Circle())
                    .overlay(Circle().stroke(FC.line, lineWidth: 1))
                    .accessibilityHidden(true)
            }
            if mine == nil {
                HStack(spacing: 10) {
                    voteButton("A", FC.tint)
                    voteButton("B", CM.coral)
                }
            } else {
                results
            }
            if let e = voteError { Text(e).cmText(12.5).foregroundStyle(CM.coral) }
        }
        .padding(14)
        .background(FC.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(FC.line, lineWidth: 1))
        .task { await load() }
        .sensoryFeedback(.success, trigger: mine) { old, new in old == nil && new != nil }
    }

    private var total: Int { (votes?.a ?? 0) + (votes?.b ?? 0) }

    private func side(_ letter: String, _ id: String, _ s: Squad?, _ color: Color) -> some View {
        let picked = mine == letter
        return Button { router.push(.squad(id)) } label: {
            VStack(spacing: 4) {
                Text(letter).cmScore(24, .bold).foregroundStyle(color)
                Text(s?.name ?? "\(letter)팀 스쿼드").cmText(15, .semibold).foregroundStyle(FC.ink).lineLimit(1).minimumScaleFactor(0.8)
                Text(s.map { "\(Formation.get($0.formation).name) · \($0.slots.count)명" } ?? " ").cmText(12.5).foregroundStyle(CM.faint)
                HStack(spacing: 2) {
                    Text("스쿼드 보기").cmText(12.5, .medium)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(FC.muted).padding(.top, 6)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 8)
            .background(picked ? FC.tint.opacity(0.10) : FC.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(picked ? FC.tint : .clear, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if picked {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(FC.tint, FC.tintInk)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(letter)팀 \(s?.name ?? ""). 스쿼드 보기\(picked ? ". 내 선택" : "")")
    }

    private func voteButton(_ pick: String, _ color: Color) -> some View {
        Button { Task { await vote(pick) } } label: {
            Text("\(pick)에 한 표").cmText(16, .bold).foregroundStyle(CM.voteInk)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(voting ? 0.6 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(voting)
        .sensoryFeedback(.impact(weight: .medium), trigger: voting) { _, new in new }
    }

    private var results: some View {
        let av = votes?.a ?? 0, bv = votes?.b ?? 0
        let t = max(1, av + bv)
        let ra = CGFloat(av) / CGFloat(t)
        let pa = Int((Double(av) / Double(t) * 100).rounded()), pb = 100 - pa
        let aLeads = av >= bv
        return VStack(spacing: 8) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    // 우세 쪽 채움 / 열세 쪽 10% 틴트
                    HStack(spacing: 2) {
                        Rectangle().fill(aLeads ? FC.tint : FC.tint.opacity(0.14))
                            .frame(width: max(0, (w - 2) * ra * revealed))
                        Rectangle().fill(aLeads ? CM.coral.opacity(0.14) : CM.coral)
                    }
                    HStack {
                        // 채움 위 글자: 다크는 남흑, 라이트는 흰색 — 라이트 #6D3FE0 위 남흑은 3.1:1 이었다(디자인 2R N-2, 흰색 ≈ 6:1)
                        Text("\(pa)%").cmScore(16, .bold).foregroundStyle(aLeads ? FC.tintInk : FC.tint)
                        Spacer()
                        Text("\(pb)%").cmScore(16, .bold).foregroundStyle(aLeads ? CM.coral : FC.tintInk)
                    }
                    .padding(.horizontal, 12)
                    .opacity(revealed)
                }
            }
            .frame(height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A \(pa)퍼센트 \(av)표, B \(pb)퍼센트 \(bv)표")
            HStack {
                Text("A \(CMFormat.count(av))표\(mine == "A" ? " · 내 선택" : "")").cmText(12.5).foregroundStyle(FC.muted)
                Spacer()
                Text("B \(CMFormat.count(bv))표\(mine == "B" ? " · 내 선택" : "")").cmText(12.5).foregroundStyle(FC.muted)
            }
            Button(action: onCommentPrompt) {
                Text("댓글로 이유를 남겨 보세요 👇").cmText(13).foregroundStyle(FC.muted).frame(minHeight: 32)
            }
            .buttonStyle(.plain)
        }
        .onAppear { reveal() }
    }

    private func reveal() {
        if reduceMotion { revealed = 1; return }
        revealed = 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) { revealed = 1 }
    }

    private func load() async {
        async let sa = try? CommunityAPI.squad(squadA)
        async let sb = try? CommunityAPI.squad(squadB)
        if let v = try? await CommunityAPI.battle(postId) {
            votes = v
            // 서버 mine(v2) 우선, 없으면 기기에 기억한 표
            mine = v.mine ?? cprefs.battlePick(postId)
        } else {
            mine = cprefs.battlePick(postId)
        }
        a = await sa
        b = await sb
    }

    private func vote(_ pick: String) async {
        voting = true
        defer { voting = false }
        do {
            let v = try await CommunityAPI.vote(postId, pick)
            votes = v
            cprefs.setBattlePick(postId, pick)
            voteError = nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { mine = v.mine ?? pick }
        } catch {
            voteError = "투표를 반영하지 못했어요. 잠시 후 다시 시도해 주세요."
            Haptic.warning()
        }
    }
}
