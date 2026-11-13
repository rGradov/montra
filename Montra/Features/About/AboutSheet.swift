import SwiftData
import SwiftUI

/// About as a bottom sheet on iOS/iPadOS. It carries the same content as the
/// macOS About page; `BottomSheetHost` supplies the detents, the drag indicator
/// and the form sizing, and iOS 26 supplies the inset Liquid Glass material —
/// so no background is painted here on purpose.
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var rates: RateStore

    let onReplayOnboarding: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "common.about"),
                subtitle: String(localized: "about.version_data_and_onboarding"),
                onClose: { dismiss() }
            )

            ScrollView {
                AboutContent(onReplayOnboarding: onReplayOnboarding)
                    .platformReadableWidth(AboutContent.contentMaxWidth)
                    .padding(.horizontal, AppStyle.Spacing.large)
                    .padding(.bottom, AppStyle.Spacing.medium)
            }
        }
    }
}
