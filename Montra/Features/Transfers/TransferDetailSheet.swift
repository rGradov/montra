import SwiftData
import SwiftUI

/// A read-only view of a transfer pair. Editing one leg alone would break the
/// link between the accounts, so the row opens this instead of the operation
/// form.
struct TransferDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @Query private var legs: [Operation]

    init(transferID: UUID) {
        _legs = Query(filter: #Predicate<Operation> { $0.transferID == transferID })
    }

    private var outgoing: Operation? { legs.first { $0.kind == .expense } }
    private var incoming: Operation? { legs.first { $0.kind == .income } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "transaction.transfer"),
                subtitle: String(localized: "transfer.between_your_accounts"),
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(spacing: AppStyle.Spacing.small) {
                    if let outgoing {
                        legRow(
                            operation: outgoing,
                            caption: String(localized: "common.outgoing"),
                            symbol: "arrow.up.right"
                        )
                    }

                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.vertical, 2)

                    if let incoming {
                        legRow(
                            operation: incoming,
                            caption: String(localized: "common.incoming"),
                            symbol: "arrow.down.left"
                        )
                    }

                    if outgoing == nil && incoming == nil {
                        Text(String(localized: "transfer.transfer_not_found"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.vertical, 24)
                    }

                    if let date = outgoing?.date {
                        HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .semibold))
                            Text(AppDate.dayMonthTime.string(from: date))
                        }
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.top, AppStyle.Spacing.xSmall)
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.vertical, AppStyle.Spacing.small)
            }
            .sheetKeyboardScrolling()

            SheetFooter {
                Spacer(minLength: 0)
                Button(String(localized: "common.done")) { dismiss() }
                    .buttonStyle(.montra(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheetContentFrame(width: 470, height: 380)
        .background(AppColors.surfaceBase)
    }

    private func legRow(operation: Operation, caption: String, symbol: String) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            IconTile(
                symbol: operation.account?.iconName ?? "creditcard.fill",
                color: operation.account?.color.tileColor ?? AppColors.Chart.neutralTile,
                size: 32
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(operation.account?.name ?? String(localized: "common.account"))
                    .font(AppStyle.Typography.headline)
                HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                    Text(caption)
                }
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            Text(operation.amountText(masked: settings.hideBalances))
                .font(AppStyle.Typography.headline.numbers)
                .monospacedDigit()
                .foregroundStyle(operation.kind == .income ? AppColors.statusSafeText : AppColors.textPrimary)
        }
        .padding(.horizontal, AppStyle.Spacing.small)
        .padding(.vertical, AppStyle.Spacing.xSmall)
        .background(
            AppColors.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
        }
    }
}
