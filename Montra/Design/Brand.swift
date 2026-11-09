import SwiftUI

/// Decorative Montra artwork shared across the app.
struct MontraArtwork: View {
    let size: CGFloat

    var body: some View {
        Image("MontraArtwork")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct AppBrandMark: View {
    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            MontraArtwork(size: 22)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            Text(String(localized: "common.montra"))
                .font(AppStyle.Typography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "common.montra"))
    }
}
