import AppKit
import SwiftUI

/// Explains what iCloud is doing right now. Every word comes from
/// `CloudSyncState`'s appearance, so this sheet, the sidebar and the Settings
/// row can never disagree.
struct ICloudSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SyncService

    var body: some View {
        let appearance = sync.appearance

        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "common.icloud_sync"),
                subtitle: appearance.sentence,
                onClose: { dismiss() }
            )

            VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                InsetCard {
                    statusRow(appearance)

                    if case .failed(let message) = sync.state {
                        InsetCardDivider()
                        valueRow(title: String(localized: "common.error"), value: message, wraps: true)
                    }
                }

                Text(String(localized: "sync.why_icloud"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppStyle.Spacing.xxSmall)

                Text(String(localized: "sync.transfers_are_automatic"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppStyle.Spacing.xxSmall)
            }
            .padding(.horizontal, AppStyle.Spacing.large)
            .padding(.bottom, AppStyle.Spacing.medium)

            SheetFooter {
                Spacer(minLength: AppStyle.Spacing.small)

                if let action = appearance.action {
                    Button(action) {
                        if case .unknown = sync.state {
                            sync.refresh()
                        } else if case .failed = sync.state {
                            sync.refresh()
                        } else {
                            openAppleAccountSettings()
                        }
                    }
                    .buttonStyle(.montra(.secondary))
                }

                Button(String(localized: "common.done")) { dismiss() }
                    .buttonStyle(.montra(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 470)
        .background(AppColors.surfaceBase)
        .onAppear { sync.refresh() }
    }

    private func statusRow(_ appearance: CloudSyncAppearance) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            IconTile(
                symbol: appearance.symbol,
                color: appearance.needsAttention
                    ? AppColors.statusCheckText
                    : AppColors.Chart.neutralTile
            )
            Text(String(localized: "common.icloud"))
                .font(AppStyle.Typography.headline)
            Spacer(minLength: AppStyle.Spacing.small)
            AppBadge(text: appearance.badge, tone: appearance.tone)
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    private func valueRow(title: String, value: String, wraps: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.small) {
            Text(title)
                .font(AppStyle.Typography.body)
            Spacer(minLength: AppStyle.Spacing.small)
            Text(value)
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(wraps ? 3 : 1)
                .multilineTextAlignment(.trailing)
                .truncationMode(.tail)
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    /// Opens the Apple Account pane. The URL scheme is undocumented, so it falls
    /// back to System Settings itself rather than failing silently.
    private func openAppleAccountSettings() {
        let specific = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")
        let fallback = URL(string: "x-apple.systempreferences:")
        if let specific, NSWorkspace.shared.open(specific) { return }
        if let fallback { NSWorkspace.shared.open(fallback) }
    }
}
