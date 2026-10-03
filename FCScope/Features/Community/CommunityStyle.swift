import SwiftUI
import UIKit

/// 커뮤니티 v2 전용 색 토큰(docs/community-v2/SPEC.md 3-1).
///
/// `FC`(Theme.swift)의 S-spot 팔레트를 그대로 쓰고, 커뮤니티에서만 필요한 다섯 개를 여기에 더한다.
/// Theme.swift 를 다른 작업이 함께 고치고 있어 이름 충돌을 피하려고 별도 네임스페이스(`CM`)로 둔다.
/// `win`/`lose` 는 커뮤니티에서 쓰지 않는다 — 데이터 의미 전용(배틀 B팀이 "진 쪽"으로 읽히던 문제).
enum CM {
    /// 목록 행 구분선 — ink 14%(다크) / 9%(라이트)
    static let hair = Color(UIColor { t in
        t.userInterfaceStyle == .light ? UIColor(hex: 0x15132b).withAlphaComponent(0.09) : UIColor(hex: 0xeeedf8).withAlphaComponent(0.14)
    })
    /// 메타 줄·시간·답글 달기 (다크 5.3:1 · 라이트 4.7:1)
    static let faint = dyn(0x8580b3, 0x6e6994)
    /// 본문·댓글 본문 — 제목(ink)보다 한 단계 낮춘 위계
    static let ink2 = dyn(0xd9d5f2, 0x2a2550)
    /// 배틀 B팀 · HOT · 추천 50↑ · 내가 누른 추천
    static let coral = dyn(0xff7a45, 0xb4400f)
    /// 클럽·대회 계열 말머리
    static let teal = dyn(0x3fd0c2, 0x0a7366)
    /// 투표 버튼 글자 — 다크/라이트 모두 남흑(tint·coral 채움 위 6.2:1 · 7.5:1)
    static let voteInk = Color(UIColor(hex: 0x0b0a1f))
    /// 골드 채움(BEST 배지) 위 글자 — 다크 #F7C948 위 남흑 / 라이트 #A66A00 위 흰색
    static let onGold = dyn(0x0b0a1f, 0xffffff)

    private static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark) })
    }

    /// 아바타 8색 — 닉네임 해시로 고른다(같은 사람은 늘 같은 색). 틴트 아바타(색 16% 채움 + 같은 색 글자)로 쓴다.
    /// 원색 채움(Tailwind 600)은 "연락처 앱" 느낌이었고, 초록은 승리색과 겹쳐 뺐다(디자인 N1).
    /// 바이올렛 · 인디고 · 코랄 · 틸 · 스카이 · 핑크 · 앰버 · 슬레이트 — 다크/라이트 각각 글자 대비를 맞춘 두 값.
    static let avatarColors: [Color] = [
        dyn(0xa78bfa, 0x6d28d9), dyn(0x818cf8, 0x4338ca), dyn(0xff8a65, 0xc2410c), dyn(0x2dd4bf, 0x0f766e),
        dyn(0x7dd3fc, 0x0369a1), dyn(0xf472b6, 0xbe185d), dyn(0xfbbf24, 0xa16207), dyn(0xa5b4cb, 0x475569),
    ]
    static func avatarColor(_ seed: String) -> Color {
        // String.hashValue 는 실행마다 바뀐다 — 고정 해시(djb2)로.
        var h: UInt32 = 5381
        for u in seed.unicodeScalars { h = (h &* 33) &+ u.value }
        return avatarColors[Int(h % UInt32(avatarColors.count))]
    }
}

// MARK: - 글자 — 렌더 기준(보정 없는) 크기

/// 커뮤니티 화면은 `TypeScale.readable()`(20pt 미만 ×1.15)을 거치지 않는다 — 운영자 "글자가 너무 크다"의 원인.
/// 코드의 숫자가 곧 렌더 크기다. Dynamic Type 배율(최대 1.6배)은 그대로 따른다.
/// 앱 공용 역할 토큰(`fcText`, Theme.swift)과 **같은 경로**를 쓴다 — 탭 15·칩 13·메타 12 가 전 화면에서 같은 크기.
extension View {
    /// 커뮤니티 본문 서체(Pretendard) — 렌더 기준 크기 + Dynamic Type.
    func cmText(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        fcRender(size, weight)
    }
    /// 커뮤니티 숫자 서체(Chakra Petch) — 렌더 기준 크기 + Dynamic Type.
    func cmScore(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> some View {
        fcRender(size, weight, scoreboard: true)
    }
}

extension Font {
    /// `Text + Text` 연결처럼 Font 값이 필요한 곳용.
    static func cm(_ size: CGFloat, _ typeSize: DynamicTypeSize, _ weight: Font.Weight = .regular) -> Font {
        .pretendard(size * TypeScale.factor(typeSize), weight)
    }
    static func cmScore(_ size: CGFloat, _ typeSize: DynamicTypeSize, _ weight: Font.Weight = .semibold) -> Font {
        .scoreboard(size * TypeScale.factor(typeSize), weight: weight)
    }
}

// MARK: - 숫자 표기

enum CMFormat {
    /// 1만 이상은 `1.2만`, 그 아래는 천 단위 쉼표.
    static func count(_ n: Int) -> String {
        if n >= 10_000 {
            let v = Double(n) / 10_000
            let s = v >= 10 ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".0", with: "")
            return "\(s)만"
        }
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - 말머리

/// 말머리 3계열(스쿼드 tint · 배틀 coral · 클럽·대회 teal) — 디자인 회의 (c) 강조 예산.
enum PostFamily {
    case squad, battle, club
    init(type: String) {
        switch type {
        case "squad_battle": self = .battle
        case "club_recruit", "club_match", "tournament": self = .club
        default: self = .squad
        }
    }
    var color: Color {
        switch self { case .squad: return FC.tint; case .battle: return CM.coral; case .club: return CM.teal }
    }
}

enum PostTypeNames {
    /// 서버 `shortLabel` 이 오기 전(구 서버)용 짧은 이름 — lib/community/post-types.ts 와 같은 값.
    static let fallback: [String: String] = [
        "squad_show": "자랑", "squad_rate": "평가", "squad_make": "만들어줘", "squad_battle": "배틀",
        "club_recruit": "클럽모집", "club_match": "클럽전", "tournament": "대회",
    ]
    static func short(_ type: String, types: [PostTypeInfo], label: String? = nil) -> String {
        if let s = types.first(where: { $0.type == type })?.shortLabel, !s.isEmpty { return s }
        return fallback[type] ?? label ?? type
    }
}

/// 말머리 태그(11.5 Bold, 높이 19, 반경 5). 마감 글은 `마감`(faint).
struct PostTag: View {
    let text: String
    let color: Color
    var closed = false
    var body: some View {
        Text(closed ? "마감" : text)
            .cmText(11.5, .bold)
            .lineLimit(1)
            .foregroundStyle(closed ? CM.faint : color)
            .padding(.horizontal, 6)
            .frame(minHeight: 19)
            .background((closed ? CM.faint : color).opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}

/// 운영자 배지 — 골드
struct OperatorBadge: View {
    var body: some View {
        Text("운영자").cmText(11, .bold).foregroundStyle(FC.gold)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(FC.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize()
            .accessibilityLabel("운영자 계정")
    }
}

/// 닉네임 첫 글자 + 해시 색 원형 아바타
struct NickAvatar: View {
    let nickname: String
    var size: CGFloat = 36
    var body: some View {
        let c = CM.avatarColor(nickname)
        Circle().fill(c.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(Text(String(nickname.prefix(1))).font(.pretendard(size * 0.42, .semibold)).foregroundStyle(c))
            .accessibilityHidden(true)
    }
}

/// 행 모양 스켈레톤 막대 — shimmer 1.2s, Reduce Motion 이면 정적.
struct ShimmerBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Capsule().fill(FC.surface2)
            .overlay {
                if !reduceMotion {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, FC.line.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.6)
                            .offset(x: phase * g.size.width * 1.6)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(width: width, height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
