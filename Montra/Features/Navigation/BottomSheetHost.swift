#if os(iOS)
import SwiftUI

/// The one place the port's sheets get their iOS presentation chrome: detents
/// per sheet, a drag indicator, and the centred form sheet at iPad regular
/// width. No `presentationBackground` is applied on purpose — iOS 26 gives
/// partial sheets their inset Liquid Glass material, and a custom background
/// suppresses it.
struct BottomSheetHost<Content: View>: View {
    let sheet: AppSheet
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            base.presentationSizing(.form)
        } else {
            base
        }
    }

    private var base: some View {
        content
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
    }

    /// Forms open tall; reference sheets that are short lists open half height
    /// and can be pulled up. About is a long read, so it opens tall.
    private var detents: Set<PresentationDetent> {
        switch sheet {
        case .newOperation, .editOperation,
             .newAccount, .editAccount,
             .newCategory, .editCategory,
             .about:
            [.large]
        case .periods, .iCloud:
            [.large]
        case .transferDetails, .planActions:
            [.medium, .large]
        }
    }
}
#endif
