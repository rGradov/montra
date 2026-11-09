import SwiftUI

/// A place for the charts that come next. Nothing is computed here on purpose:
/// the section exists so the navigation is final, and the empty state says so.
struct AnalyticsView: View {
    @EnvironmentObject private var headerHost: DetailHeaderHost

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                    OverviewCard {
                        VStack(spacing: AppStyle.Spacing.large) {
                            previewArtwork
                                .padding(.top, AppStyle.Spacing.large)

                            VStack(spacing: AppStyle.Spacing.xxSmall) {
                                Text(String(localized: "analytics.charts_are_coming"))
                                    .font(AppStyle.Typography.sectionTitle)
                                Text(String(localized: "analytics.this_space_is_reserved_for"))
                                    .font(AppStyle.Typography.callout)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 380)
                            }
                            .padding(.bottom, AppStyle.Spacing.large)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                .padding(.bottom, AppStyle.Spacing.large)
            }
        }
        .background(AppColors.surfaceBase)
        .onAppear { syncHeader() }
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "navigation.analytics"),
            subtitle: String(localized: "common.coming_soon"),
            backTitle: nil,
            onBack: nil,
            trailing: AnyView(EmptyView())
        )
    }

    private var previewArtwork: some View {
        let previewHeight: CGFloat = 110
        // Keep the same space as the seven bars and six gaps in the former chart sketch.
        let previewWidth = 7 * 26 + 6 * AppStyle.Spacing.small

        return MontraArtwork(size: previewHeight)
            .frame(width: previewWidth, height: previewHeight, alignment: .bottom)
    }
}
