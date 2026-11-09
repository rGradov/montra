import SwiftUI

/// A row that folds its height to zero instead of disappearing, so switching a
/// filter reads as an accordion: unmatched rows compress upward, matched ones
/// unfold, and everything below moves with them.
struct CollapsibleRow<Content: View>: View {
    let isExpanded: Bool
    var delay: Double = 0
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            // The content keeps its natural height even while the outer frame is
            // collapsed, so it can be measured with the clip in place.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                if height > 0 { contentHeight = height }
            }
            .frame(height: rowHeight, alignment: .top)
            .clipped()
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .animation(
                reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86).delay(delay),
                value: isExpanded
            )
    }

    private var rowHeight: CGFloat? {
        if !isExpanded { return 0 }
        return contentHeight > 0 ? contentHeight : nil
    }
}
