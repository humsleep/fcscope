import SwiftUI

/// 탭 루트 화면 공통 헤더 — 왼쪽 큰 제목(커뮤니티와 같은 서체·크기) + 오른쪽 화면별 버튼 + 내 정보.
/// 탭마다 가운데 작은 제목·워드마크·왼쪽 큰 제목이 섞여 있었고, 내 정보는 홈 아이콘 하나에만 숨어 있었다.
struct TabHeaderModifier<Actions: View>: ViewModifier {
    let title: String
    @ViewBuilder var actions: Actions
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                // iOS 26 유리 툴바는 제목 글자에도 캡슐 배경을 씌운다 — 제목은 맨 글자로.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { TabHeaderTitle(title: title) }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { TabHeaderTitle(title: title) }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    actions
                    Button { router.push(.me) } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("내 정보")
                }
            }
    }
}

struct TabHeaderTitle: View {
    let title: String
    var body: some View {
        // 툴바 항목은 최소 44pt 폭 안에서 가운데 정렬된다 — "홈"처럼 짧은 제목이 오른쪽으로 밀리지 않게 앞쪽 정렬.
        // iOS 26 유리 툴바는 앞 여백이 8pt 더 커서 본문(16pt) 선과 어긋난다 — 그만큼 당긴다.
        Text(title).fcRender(24, .bold).kerning(-0.6).foregroundStyle(FC.ink)
            .fixedSize().frame(minWidth: 44, alignment: .leading)
            .padding(.leading, Self.glassInset)
            .accessibilityAddTraits(.isHeader)
    }
    private static var glassInset: CGFloat { if #available(iOS 26.0, *) { -8 } else { 0 } }
}

extension View {
    func fcTabHeader(_ title: String) -> some View { modifier(TabHeaderModifier(title: title) { EmptyView() }) }
    func fcTabHeader<A: View>(_ title: String, @ViewBuilder actions: () -> A) -> some View { modifier(TabHeaderModifier(title: title, actions: actions)) }
}
