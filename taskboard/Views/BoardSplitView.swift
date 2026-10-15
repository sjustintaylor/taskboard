import SwiftUI

enum BoardSplitLayout {
    static func boardWidth(total: CGFloat, ratio: Double) -> CGFloat {
        let available = max(0, total - 8)
        return min(max(560, available * (ratio.isFinite ? ratio : 2.0 / 3.0)), max(0, available - 280))
    }
}

struct BoardSplitView<Board: View, Inspector: View>: View {
    let showsInspector: Bool
    @ViewBuilder var board: (CGFloat) -> Board
    @ViewBuilder var inspector: () -> Inspector
    @AppStorage("boardSplitRatio") private var ratio = 2.0 / 3.0
    @State private var dragStart: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let width = showsInspector ? BoardSplitLayout.boardWidth(total: geometry.size.width, ratio: ratio) : geometry.size.width
            HStack(spacing: 0) {
                board(width).frame(width: width)
                if showsInspector {
                    Rectangle().fill(.quaternary).frame(width: 8)
                        .contentShape(Rectangle())
                        .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if dragStart == nil { dragStart = width }
                            let available = max(1, geometry.size.width - 8)
                            ratio = BoardSplitLayout.boardWidth(total: geometry.size.width,
                                ratio: ((dragStart ?? width) + value.translation.width) / available) / available
                        }.onEnded { _ in dragStart = nil })
                        .accessibilityLabel("Board and task divider")
                        .accessibilityAdjustableAction { direction in
                            ratio = min(0.9, max(0.1, ratio + (direction == .increment ? 0.05 : -0.05)))
                        }
                    inspector().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
