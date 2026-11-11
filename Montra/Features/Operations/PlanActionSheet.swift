import SwiftUI
import SwiftData

/// The single place where a planned occurrence can be acted on: link an
/// existing fact, save it as a new fact, delete just this date, or drop the
/// whole series. The plan itself never touches balances.
struct PlanActionSheet: View {
    let planID: UUID
    let onSaveAsFact: (PlannedOperation) -> Void

    private enum Mode {
        case actions
        case link
    }

    private enum DeleteScope: String, Identifiable {
        case single
        case series
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore

    @Query private var plans: [PlannedOperation]
    @Query(sort: [SortDescriptor(\Operation.date, order: .reverse)]) private var operations: [Operation]

    @State private var mode: Mode = .actions
    @State private var searchText = ""
    @State private var deleteScope: DeleteScope?

    private var plan: PlannedOperation? {
        plans.first { $0.id == planID }
    }

    private var seriesCount: Int {
        guard let plan else { return 0 }
        return plans.filter { $0.seriesID == plan.seriesID }.count
    }

    private var linkedOperationIDs: Set<UUID> {
        Set(plans.compactMap(\.linkedOperationID))
    }

    private var searchTokens: [String] {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private var linkCandidates: [Operation] {
        guard let plan else { return [] }
        return operations
            .filter { operation in
                operation.kind == plan.kind
                    && !linkedOperationIDs.contains(operation.id)
                    && matchesSearch(operation)
            }
            .sorted { left, right in
                abs(left.date.timeIntervalSince(plan.date)) < abs(right.date.timeIntervalSince(plan.date))
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let plan {
                SheetHeader(
                    title: mode == .actions ? String(localized: "common.scheduled") : String(localized: "schedule.link_to_transaction"),
                    subtitle: mode == .actions
                        ? (plan.isMissed ? String(localized: "common.missed_payment") : String(localized: "common.scheduled_payment"))
                        : String(localized: "schedule.choose_a_transaction_youve_already"),
                    onClose: { dismiss() }
                )

                ScrollView {
                    if mode == .actions {
                        actionsContent(plan)
                    } else {
                        linkContent(plan)
                    }
                }
                .frame(height: 500)

                footer(plan)
            } else {
                SheetHeader(title: String(localized: "common.scheduled"), onClose: { dismiss() })
                Text(String(localized: "schedule.payment_not_found"))
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding()
                Spacer()
            }
        }
        .frame(width: 470)
        .background(AppColors.surfaceBase)
        .alert(
            deleteScope == .series ? String(localized: "schedule.delete_the_entire_series") : String(localized: "schedule.delete_this_payment"),
            isPresented: Binding(
                get: { deleteScope != nil },
                set: { if !$0 { deleteScope = nil } }
            )
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let deleteScope { delete(deleteScope) }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: - Actions

    private func actionsContent(_ plan: PlannedOperation) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                Text(settings.money(
                    plan.amount,
                    currency: plan.currency,
                    sign: plan.kind == .income ? .always : .none
                ))
                .font(AppStyle.Typography.display)
                .monospacedDigit()
                .foregroundStyle(plan.kind == .income ? AppColors.statusSafeText : AppColors.textPrimary)

                HStack(spacing: AppStyle.Spacing.xSmall) {
                    Text(plan.category?.displayName ?? String(localized: "common.uncategorized"))
                        .font(AppStyle.Typography.headline)
                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)
                    Text(plan.kind.title)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer(minLength: AppStyle.Spacing.small)
                    statusBadge(plan)
                }
            }

            VStack(spacing: AppStyle.Spacing.xSmall) {
                detailRow(String(localized: "common.account"), plan.account?.name ?? String(localized: "common.account_deleted"))
                detailRow(String(localized: "common.payment"), AppDate.dayMonthTime.string(from: plan.date))
                detailRow(String(localized: "common.recurrence"), recurrenceText(plan))
                detailRow(String(localized: "common.repeat_until"), dateText(plan.seriesEnd))
                detailRow(String(localized: "schedule.in_this_series"), "\(seriesCount)")
                if !plan.place.isEmpty {
                    detailRow(String(localized: "common.location"), plan.place)
                }
                if !plan.note.isEmpty {
                    detailRow(String(localized: "common.note"), plan.note)
                }
            }
            .padding(AppStyle.Spacing.small)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }

            if plan.isMissed {
                Text(String(localized: "schedule.this_payment_is_overdue_link"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.statusCheckText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                Button {
                    deleteScope = .single
                } label: {
                    Label(String(localized: "schedule.delete_this_payment_2"), systemImage: "trash")
                }
                .buttonStyle(.montra(.quiet, size: .small))
                .foregroundStyle(AppColors.statusDangerText)

                Button {
                    deleteScope = .series
                } label: {
                    Label(String(localized: "schedule.delete_entire_series"), systemImage: "trash.slash")
                }
                .buttonStyle(.montra(.quiet, size: .small))
                .foregroundStyle(AppColors.statusDangerText)

                Text(String(localized: "schedule.linked_transactions_will_stay_in"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.large)
        .padding(.bottom, AppStyle.Spacing.medium)
    }

    private func recurrenceText(_ plan: PlannedOperation) -> String {
        var text = plan.frequency.adverb
        if plan.frequency == .week, !plan.weekdaySummary.isEmpty {
            text += " · \(plan.weekdaySummary)"
        }
        if plan.frequency == .month {
            let day = Calendar.current.component(.day, from: plan.seriesStart)
            text += String(localized: "schedule.day_of_month_suffix \(day)")
        }
        if plan.frequency == .year {
            text += " · \(AppDate.short(plan.seriesStart))"
        }
        return text
    }

    private func dateText(_ date: Date) -> String {
        "\(AppDate.short(date)) \(Calendar.current.component(.year, from: date))"
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.small) {
            Text(title)
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func statusBadge(_ plan: PlannedOperation) -> some View {
        let title = plan.isMissed ? String(localized: "common.missed_2") : (plan.isDueToday ? String(localized: "date.today") : String(localized: "common.scheduled"))
        let color = plan.isMissed ? AppColors.statusCheckText : (plan.isDueToday ? AppColors.actionPrimary : AppColors.textTertiary)
        return Text(title)
            .font(AppStyle.Typography.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule(style: .continuous))
    }

    // MARK: - Link mode

    private func linkContent(_ plan: PlannedOperation) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack {
                Text(String(localized: "schedule.scheduled \(settings.money(plan.amount, currency: plan.currency))"))
                    .font(AppStyle.Typography.callout.weight(.medium))
                Spacer()
                CapsuleSearchField(query: $searchText, width: 220)
            }

            if linkCandidates.isEmpty {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                    Text(searchTokens.isEmpty ? String(localized: "schedule.no_matching_transactions") : String(localized: "common.no_results"))
                        .font(AppStyle.Typography.headline)
                    Text(String(localized: "schedule.add_a_transaction_of_this"))
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppStyle.Spacing.large)
            } else {
                LazyVStack(spacing: AppStyle.Spacing.xSmall) {
                    ForEach(linkCandidates) { operation in
                        Button {
                            PlanRepository(context: context).link(plan, to: operation)
                            dismiss()
                        } label: {
                            HStack(spacing: AppStyle.Spacing.small) {
                                ListRowIcon(symbol: operation.displayIcon, color: operation.displayColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(operation.displayTitle)
                                        .font(AppStyle.Typography.headline)
                                        .lineLimit(1)
                                    Text(candidateDetail(operation))
                                        .font(AppStyle.Typography.metadata)
                                        .foregroundStyle(AppColors.textTertiary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: AppStyle.Spacing.small)

                                Text(operation.amountText(masked: settings.hideBalances))
                                    .font(AppStyle.Typography.rowTitle.numbers)
                                    .monospacedDigit()
                                    .foregroundStyle(operation.kind == .income ? AppColors.statusSafeText : AppColors.textPrimary)
                            }
                            .padding(AppStyle.Spacing.small)
                            .background(
                                AppColors.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandOnHover()
                    }
                }
            }
        }
        .padding(.horizontal, AppStyle.Spacing.large)
        .padding(.bottom, AppStyle.Spacing.medium)
    }

    private func candidateDetail(_ operation: Operation) -> String {
        var parts = [AppDate.dayMonthTime.string(from: operation.date)]
        if let account = operation.account { parts.append(account.name) }
        if let category = operation.category { parts.append(category.displayName) }
        return parts.joined(separator: " · ")
    }

    private func matchesSearch(_ operation: Operation) -> Bool {
        guard !searchTokens.isEmpty else { return true }
        let haystack = [
            operation.category?.displayName ?? "",
            operation.account?.name ?? "",
            operation.place,
            operation.note,
            operation.kind.title,
            MoneyFormat.string(operation.amount, currency: operation.currency),
            "\(operation.amount)",
            AppDate.short(operation.date),
        ].joined(separator: " ")
        return searchTokens.allSatisfy { haystack.localizedStandardContains($0) }
    }

    // MARK: - Footer / delete

    private func footer(_ plan: PlannedOperation) -> some View {
        SheetFooter {
            if mode == .link {
                Button(String(localized: "common.back")) { mode = .actions }
                    .buttonStyle(.montra(.quiet))
            }
            Spacer(minLength: AppStyle.Spacing.small)
            if mode == .actions {
                Button(String(localized: "schedule.link_to_transaction")) { mode = .link }
                    .buttonStyle(.montra(.secondary))
                    .disabled(operations.isEmpty)
                Button(String(localized: "schedule.record_as_transaction")) { onSaveAsFact(plan) }
                    .buttonStyle(.montra(.primary))
            } else {
                Button(String(localized: "schedule.record_as_transaction")) { onSaveAsFact(plan) }
                    .buttonStyle(.montra(.primary))
            }
        }
    }

    private var deleteMessage: String {
        guard let plan else { return "" }
        if deleteScope == .series {
            return String(localized: "schedule.delete_series_message \(seriesCount)")
        }
        return String(localized: "schedule.only_the_payment_scheduled_for \(AppDate.dayMonthTime.string(from: plan.date))")
    }

    private func delete(_ scope: DeleteScope) {
        guard let plan else { return }
        let repository = PlanRepository(context: context)
        switch scope {
        case .single: repository.delete(plan)
        case .series: repository.deleteSeries(plan)
        }
        dismiss()
    }
}
