import AppKit
import SwiftUI

/// Explains what iCloud is doing right now. Everything here comes from
/// `SyncService`: the account state plus the last time the ledger changed.
/// Nothing claims to know about a transfer in flight, because SwiftData does not
/// report one.
struct ICloudSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SyncService

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "common.icloud_sync"),
                subtitle: sync.state.title,
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    InsetCard {
                        statusRow
                        InsetCardDivider()
                        valueRow(title: String(localized: "common.container"), value: SyncService.containerIdentifier)
                        InsetCardDivider()
                        valueRow(title: String(localized: "common.storage"), value: String(localized: "common.swiftdata"))
                    }

                    Text(String(localized: "sync.transfers_are_automatic"))
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppStyle.Spacing.xxSmall)

                    if case .noAccount = sync.state {
                        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                            Text(String(localized: "sync.not_signed_in_hint"))
                                .font(AppStyle.Typography.callout)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(String(localized: "sync.no_icloud_account")) {
                                openAppleAccountSettings()
                            }
                            .buttonStyle(.montra(.secondary))
                        }
                        .padding(.horizontal, AppStyle.Spacing.xxSmall)
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.bottom, AppStyle.Spacing.medium)
            }
            .frame(maxHeight: 480)

            SheetFooter {
                Spacer(minLength: AppStyle.Spacing.small)
                Button(String(localized: "common.ok")) { dismiss() }
                    .buttonStyle(.montra(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 470, height: 520)
        .background(AppColors.surfaceBase)
        .onAppear { sync.refresh() }
    }

    private var statusRow: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            IconTile(
                symbol: sync.isConnected ? "checkmark.icloud" : "icloud.slash",
                color: sync.isConnected ? AppColors.statusSafeText : AppColors.Chart.neutralTile
            )
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(String(localized: "common.icloud"))
                    .font(AppStyle.Typography.headline)
                Text(sync.state.title)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppStyle.Spacing.small)
            AppBadge(
                text: sync.isConnected
                    ? String(localized: "sync.active")
                    : String(localized: "common.not_connected"),
                tone: sync.isConnected ? .safe : .warning
            )
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    private func valueRow(title: String, value: String) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Text(title)
                .font(AppStyle.Typography.body)
            Spacer(minLength: AppStyle.Spacing.small)
            Text(value)
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
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
