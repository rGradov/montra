import SwiftUI

/// A planned payment in the list. It uses the same card, icon, type scale
/// and amount alignment as a recorded transaction. The status badge reads
/// "Scheduled", "Today", or "Missed". The whole card opens the plan
/// actions sheet, so there is no separate menu button.
struct PlannedOperationRow: View {
    let plan: PlannedOperation
    let masked: Bool
    /// The account page already names the account in its header, so it hides
    /// the repeated name; "All Transactions" keeps it.
    var showsAccount = true
    /// In a mixed list facts sit behind a checkbox, so the plan card reserves
    /// that slot and keeps its icon and title in the same column as the facts.
    var alignsWithSelection = false
    let onOpen: () -> Void

    @State private var isHovering = false

    private var categoryColor: Color {
        if let color = plan.category?.color.color { return color }
        return plan.kind == .income ? AppColors.statusSafeText : AppColors.actionPrimary
    }

    private var categoryIcon: String {
        plan.category?.iconName ?? (plan.kind == .income ? "arrow.down.left" : "arrow.up.right")
    }

    private var title: String {
        plan.category?.displayName ?? (plan.kind == .income ? String(localized: "common.scheduled_income") : String(localized: "common.scheduled_payment"))
    }

    private var statusTitle: String {
        if plan.isMissed { return String(localized: "common.missed_2") }
        if plan.isDueToday { return String(localized: "date.today") }
        return String(localized: "common.scheduled")
    }

    private var statusColor: Color {
        if plan.isMissed { return AppColors.statusCheckText }
        if plan.isDueToday { return AppColors.actionPrimary }
        return AppColors.textTertiary
    }

    private var metadata: String {
        var parts = [AppDate.dayMonthTime.string(from: plan.date)]
        if showsAccount, let account = plan.account { parts.append(account.name) }
        parts.append(plan.frequency.adverb)
        if plan.frequency == .week, !plan.weekdaySummary.isEmpty {
            parts.append(plan.weekdaySummary)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppStyle.Spacing.small) {
                if alignsWithSelection {
                    Color.clear
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }

                IconTile(symbol: categoryIcon, color: categoryColor)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(title)
                        .font(AppStyle.Typography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text(metadata)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .frame(minHeight: 32, alignment: .leading)

                Spacer(minLength: AppStyle.Spacing.small)

                VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxSmall) {
                    Text(MoneyFormat.string(plan.amount, currency: plan.currency, masked: masked))
                        .font(AppStyle.Typography.headline.numbers)
                        .monospacedDigit()
                        .foregroundStyle(plan.kind == .income ? AppColors.statusSafeText : AppColors.textPrimary)
                        .lineLimit(1)

                    Text(statusTitle)
                        .font(AppStyle.Typography.metadataEmphasis)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, AppStyle.Spacing.xxSmallPlus)
                        .padding(.vertical, AppStyle.Spacing.xxxSmall)
                        .background(
                            statusColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                        )
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.vertical, AppStyle.Spacing.small)
            .background {
                RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                    .fill(isHovering ? AppColors.fillSecondaryHover : AppColors.fillSecondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .pointingHandOnHover()
        .accessibilityLabel(accessibilityText)
        .help(String(localized: "schedule.open_scheduled_payment"))
    }

    private var accessibilityText: String {
        var text = String(localized: "schedule.scheduled_2 \(title) \(MoneyFormat.string(plan.amount, currency: plan.currency, masked: masked))")
        if let account = plan.account { text += ", \(account.name)" }
        text += ", \(statusTitle.lowercased()), \(AppDate.dayMonthTime.string(from: plan.date))"
        return text
    }
}
