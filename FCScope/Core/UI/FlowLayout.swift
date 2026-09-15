import SwiftUI

/// 칩이 한 줄에 다 안 들어가면 **아래로 줄바꿈**하는 레이아웃.
///
/// 가로 스크롤 대신 쓴다. 가로 스크롤은 화면 밖 항목이 있다는 걸 알기 어려워
/// (스크롤 힌트가 없으면 더욱) 사용자가 항목을 통째로 놓친다.
/// 필터·태그처럼 **선택지 전체를 봐야 고를 수 있는 것**은 줄바꿈이 맞다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    /// 줄 간격. 지정하지 않으면 `spacing` 과 같다.
    var lineSpacing: CGFloat?

    private var line: CGFloat { lineSpacing ?? spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300
        let rows = rows(subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + line * CGFloat(max(0, rows.count - 1))
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                // 높이가 다른 칩이 섞여도 한 줄 안에서 세로 가운데 정렬
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + line
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var out: [Row] = []
        var cur = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = cur.indices.isEmpty ? size.width : cur.width + spacing + size.width
            if needed > maxWidth, !cur.indices.isEmpty {
                out.append(cur)
                cur = Row(indices: [i], width: size.width, height: size.height)
            } else {
                cur.indices.append(i)
                cur.width = needed
                cur.height = max(cur.height, size.height)
            }
        }
        if !cur.indices.isEmpty { out.append(cur) }
        return out
    }
}
