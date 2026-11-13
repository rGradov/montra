import SwiftUI

extension View {
    /// iPad windows and Stage Manager scenes get very wide. The desktop design is
    /// one 980pt column, so the pages that are mine to lay out clamp their column
    /// and centre it instead of stretching across 1366pt. macOS keeps its fixed
    /// window width, so this is an iOS clamp only.
    @ViewBuilder
    func platformReadableWidth(_ maxWidth: CGFloat = 760) -> some View {
        #if os(iOS)
        self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }
}
