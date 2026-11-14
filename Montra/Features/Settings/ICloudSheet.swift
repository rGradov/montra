import SwiftUI

struct ICloudSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "common.icloud_sync"),
                subtitle: String(localized: "sync.ready_to_set_up"),
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

                    #if os(macOS)
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                        Text(String(localized: "common.whats_ready"))
                            .font(AppStyle.Typography.metadataEmphasis)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppStyle.Spacing.xxSmall)

                        InsetCard {
                            bullet(
                                String(localized: "sync.all_accounts_transactions_categories_and")
                            )
                            InsetCardDivider()
                            bullet(String(localized: "sync.writes_go_through_repositories_giving"))
                            InsetCardDivider()
                            bullet(String(localized: "sync.app_settings_are_stored_separately"))
                        }
                    }
                    #endif

                    #if os(macOS)
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                        Text(String(localized: "sync.to_enable_sync"))
                            .font(AppStyle.Typography.callout.weight(.semibold))
                        Text(String(localized: "sync.setup_steps \(SyncService.containerIdentifier)"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, AppStyle.Spacing.xxSmall)
                    #else
                    Text(String(localized: "sync.not_connected_user_explanation"))
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AppStyle.Spacing.xxSmall)
                    #endif
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.bottom, AppStyle.Spacing.medium)
            }
            .sheetScrollHeight(480)
            .sheetKeyboardScrolling()

            SheetFooter {
                #if os(iOS)
                SheetActionButton(title: String(localized: "common.ok")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                #else
                Spacer(minLength: AppStyle.Spacing.small)
                Button(String(localized: "common.ok")) { dismiss() }
                    .buttonStyle(.montra(.primary))
                    .keyboardShortcut(.defaultAction)
                #endif
            }
        }
        .sheetContentFrame(width: 470, height: 580)
        .background(AppColors.surfaceBase)
    }

    private var statusRow: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            IconTile(symbol: "icloud.slash", color: AppColors.Chart.neutralTile)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(String(localized: "common.icloud"))
                    .font(AppStyle.Typography.headline)
                Group {
                    #if os(iOS)
                    Text(String(localized: "sync.your_data_stays_on_this_device"))
                    #else
                    Text(String(localized: "sync.your_data_stays_on_this"))
                    #endif
                }
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppStyle.Spacing.small)
            AppBadge(text: String(localized: "common.not_connected"), tone: .warning)
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

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.xSmall) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColors.statusSafeText)
                .padding(.top, 2)
            Text(text)
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }
}
