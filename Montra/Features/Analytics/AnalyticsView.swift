import SwiftData
import SwiftUI

/// The Analytics screen: how much left, where it went, whether the pace is
/// faster than the last period, and which days carried the spending.
struct AnalyticsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @EnvironmentObject private var rates: RateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: [SortDescriptor(\Operation.date, order: .reverse)]) private var operations: [Operation]
    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]

    var onNewOperation: () -> Void = {}

    @State private var scope: AnalyticsScope = .period
    @State private var selectedPeriodID: UUID?
    @State private var selectedMonthStart: Date?

    private var calendar: Calendar { .current }
    private var now: Date { .now }

    private var currentPeriod: Period? {
        PeriodService.currentPeriod(in: periods)
    }

    private var availablePeriods: [Period] {
        if let currentPeriod {
            return periods.filter { $0.start <= currentPeriod.start }
        }
        return periods.filter { $0.start <= now }
    }

    private var selectedPeriod: Period? {
        availablePeriods.first { $0.id == selectedPeriodID }
            ?? currentPeriod
            ?? availablePeriods.last
    }

    private var monthStarts: [Date] {
        let first = availablePeriods.first?.start ?? now
        let start = calendar.dateInterval(of: .month, for: first)?.start ?? first
        let current = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var months: [Date] = []
        var cursor = start
        while cursor <= current {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        if months.isEmpty { months = [current] }
        return months
    }

    private var selectedMonth: Date? {
        if let selectedMonthStart,
           monthStarts.contains(where: { calendar.isDate($0, equalTo: selectedMonthStart, toGranularity: .month) }) {
            return selectedMonthStart
        }
        return monthStarts.last
    }

    private var range: AnalyticsRange? {
        switch scope {
        case .period:
            guard let selectedPeriod else { return nil }
            let index = availablePeriods.firstIndex { $0.id == selectedPeriod.id }
            let previous = index.flatMap { $0 > 0 ? availablePeriods[$0 - 1] : nil }
            return AnalyticsEngine.periodRange(period: selectedPeriod, previous: previous)
        case .month:
            guard let selectedMonth else { return nil }
            return AnalyticsEngine.monthRange(containing: selectedMonth)
        }
    }

    private var snapshot: AnalyticsSnapshot? {
        guard let range else { return nil }
        return AnalyticsEngine.snapshot(
            range: range,
            operations: operations,
            displayCurrency: settings.primaryCurrency,
            rates: rates.rates
        )
    }

    private var displayCurrency: Currency { settings.primaryCurrency }
    private var masked: Bool { settings.hideBalances }

    private var subtitle: String {
        guard let snapshot else { return String(localized: "analytics.no_data") }
        var parts = [
            snapshot.range.spanTitle,
            Finance.operationsCountText(snapshot.operationsCount)
        ]
        if snapshot.range.isCurrent, snapshot.range.daysLeft > 0 {
            parts.append(Finance.daysText(snapshot.range.daysLeft) + String(localized: "period.time_left_suffix"))
        }
        return parts.joined(separator: " · ")
    }

    private var canGoBack: Bool {
        switch scope {
        case .period:
            guard let selectedPeriod,
                  let index = availablePeriods.firstIndex(where: { $0.id == selectedPeriod.id }) else { return false }
            return index > 0
        case .month:
            guard let selectedMonth,
                  let index = monthStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedMonth, toGranularity: .month) }) else { return false }
            return index > 0
        }
    }

    private var canGoForward: Bool {
        switch scope {
        case .period:
            guard let selectedPeriod,
                  let index = availablePeriods.firstIndex(where: { $0.id == selectedPeriod.id }) else { return false }
            return index < availablePeriods.count - 1
        case .month:
            guard let selectedMonth,
                  let index = monthStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedMonth, toGranularity: .month) }) else { return false }
            return index < monthStarts.count - 1
        }
    }

    private var headerKey: String {
        "\(scope.rawValue)|\(range?.title ?? "")|\(subtitle)|\(canGoBack)|\(canGoForward)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                if let snapshot, snapshot.hasExpenses {
                    AnalyticsSummaryCard(
                        snapshot: snapshot,
                        currency: displayCurrency,
                        masked: masked
                    )

                    AnalyticsBreakdownCard(
                        snapshot: snapshot,
                        currency: displayCurrency,
                        masked: masked
                    )

                    AnalyticsPaceCard(
                        snapshot: snapshot,
                        currency: displayCurrency,
                        masked: masked
                    )

                    AnalyticsHeatCard(
                        snapshot: snapshot,
                        currency: displayCurrency,
                        masked: masked
                    )
                } else {
                    OverviewCard {
                        EmptyState(
                            symbol: "chart.bar",
                            title: scope == .month
                                ? String(localized: "analytics.empty_month")
                                : String(localized: "analytics.empty_period"),
                            message: String(localized: "analytics.empty_message"),
                            actionTitle: String(localized: "transaction.new"),
                            action: onNewOperation
                        )
                    }
                }
            }
            .padding(.horizontal, AppDetailPageLayout.horizontalInset)
            .padding(.bottom, AppStyle.Spacing.large)
        }
        .background(AppColors.surfaceBase)
        .onAppear {
            if selectedPeriodID == nil {
                selectedPeriodID = currentPeriod?.id ?? availablePeriods.last?.id
            }
            if selectedMonthStart == nil {
                selectedMonthStart = calendar.dateInterval(of: .month, for: now)?.start
            }
            syncHeader()
        }
        .onChange(of: headerKey) { _, _ in syncHeader() }
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "navigation.analytics"),
            subtitle: subtitle,
            backTitle: nil,
            onBack: nil,
            trailing: AnyView(
                AnalyticsHeaderControls(
                    scope: scope,
                    title: range?.title ?? "",
                    canGoBack: canGoBack,
                    canGoForward: canGoForward,
                    onBack: { step(-1) },
                    onForward: { step(1) },
                    onScope: changeScope
                )
            )
        )
    }

    private func step(_ delta: Int) {
        switch scope {
        case .period:
            guard let selectedPeriod,
                  let index = availablePeriods.firstIndex(where: { $0.id == selectedPeriod.id }) else { return }
            let next = index + delta
            guard availablePeriods.indices.contains(next) else { return }
            selectedPeriodID = availablePeriods[next].id
        case .month:
            guard let selectedMonth,
                  let index = monthStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedMonth, toGranularity: .month) }) else { return }
            let next = index + delta
            guard monthStarts.indices.contains(next) else { return }
            selectedMonthStart = monthStarts[next]
        }
    }

    private func changeScope(_ newScope: AnalyticsScope) {
        guard newScope != scope else { return }
        switch newScope {
        case .month:
            let reference: Date
            if let selectedPeriod, selectedPeriod.contains(now) {
                reference = now
            } else {
                reference = selectedPeriod?.end ?? now
            }
            selectedMonthStart = calendar.dateInterval(of: .month, for: reference)?.start
        case .period:
            let month = selectedMonth ?? calendar.dateInterval(of: .month, for: now)?.start ?? now
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: month)?
                .addingTimeInterval(-1) ?? month
            let reference = min(now, monthEnd)
            selectedPeriodID = availablePeriods.first { $0.contains(reference) }?.id
                ?? currentPeriod?.id
                ?? availablePeriods.last?.id
        }
        withAnimation(reduceMotion ? nil : AppMotion.page) {
            scope = newScope
        }
    }
}

// MARK: - Header controls

private struct AnalyticsHeaderControls: View {
    let scope: AnalyticsScope
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onScope: (AnalyticsScope) -> Void

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            HStack(spacing: 0) {
                ForEach(AnalyticsScope.allCases) { option in
                    Button {
                        onScope(option)
                    } label: {
                        Text(option.title)
                            .font(AppStyle.Typography.metadataEmphasis)
                            .foregroundStyle(option == scope ? AppColors.textPrimary : AppColors.textSecondary)
                            .padding(.horizontal, AppStyle.Spacing.xSmall)
                            .frame(height: 20)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(option == scope ? AppColors.surfaceRaised : .clear)
                            }
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == scope ? .isSelected : [])
                }
            }
            .padding(2)
            .background {
                Capsule(style: .continuous).fill(AppColors.fillSecondary)
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }

            HStack(spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)
                .accessibilityLabel(String(localized: "analytics.previous"))

                HStack(spacing: AppStyle.Spacing.xxSmall) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityHidden(true)
                    Text(figures: title, style: AppStyle.Typography.metadata)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.horizontal, AppStyle.Spacing.xxSmall)
                .frame(height: 22)

                Button(action: onForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
                .accessibilityLabel(String(localized: "analytics.next"))
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 2)
            .background {
                Capsule(style: .continuous).fill(AppColors.fillSecondary)
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Summary

private struct AnalyticsSummaryCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool

    var body: some View {
        OverviewCard {
            HStack(alignment: .top, spacing: 0) {
                SummaryCell(
                    label: String(localized: "common.expenses"),
                    value: money(snapshot.expenses),
                    sub: AnyView(expenseSub)
                )

                divider

                SummaryCell(
                    label: String(localized: "common.income"),
                    value: money(snapshot.income),
                    sub: AnyView(incomeSub)
                )

                divider

                SummaryCell(
                    label: String(localized: "analytics.remaining"),
                    value: money(snapshot.remaining),
                    sub: AnyView(remainingSub)
                )
            }
            .padding(.vertical, AppStyle.Spacing.small)

            if snapshot.hasSavings {
                InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)
                VStack(spacing: 0) {
                    if snapshot.savingsIn > 0 {
                        savingsRow(
                            title: String(localized: "analytics.savings_in"),
                            detail: String(localized: "analytics.savings_in_detail"),
                            value: money(snapshot.savingsIn),
                            positive: true
                        )
                    }
                    if snapshot.savingsOut > 0 {
                        savingsRow(
                            title: String(localized: "analytics.savings_out"),
                            detail: String(localized: "analytics.savings_out_detail"),
                            value: money(-snapshot.savingsOut),
                            positive: false
                        )
                    }
                }
            }
        }
    }

    private func savingsRow(title: String, detail: String, value: String, positive: Bool) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.Chart.teal)
                .frame(width: AppStyle.Row.listIconFrameSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(title)
                    .font(AppStyle.Typography.headline)
                Text(detail)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            Text(value)
                .font(AnalyticsStyle.amount)
                .monospacedDigit()
                .foregroundStyle(positive ? AppColors.statusSafeText : AppColors.textSecondary)
        }
        .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.xSmall)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(width: 0.5)
            .padding(.vertical, AppStyle.Spacing.xxSmall)
    }

    @ViewBuilder
    private var expenseSub: some View {
        if snapshot.hasComparison, snapshot.comparisonTotal > 0 {
            let delta = delta
            HStack(spacing: 3) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(figures: String(localized: "analytics.vs_previous \(AnalyticsFormat.percent(delta))"),
                     style: AppStyle.Typography.metadata)
            }
            .foregroundStyle(delta >= 0 ? AppColors.statusCheckText : AppColors.statusSafeText)
        } else {
            Text(String(localized: "analytics.no_previous_period"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var incomeSub: some View {
        Text(figures: String(localized: "analytics.income_count \(snapshot.incomeCount)"),
             style: AppStyle.Typography.metadata)
            .foregroundStyle(AppColors.textSecondary)
    }

    @ViewBuilder
    private var remainingSub: some View {
        if snapshot.income > 0 {
            Text(figures: String(localized: "analytics.of_income \(AnalyticsFormat.percent(shareOfIncome, signed: false))"),
                 style: AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)
        } else {
            Text(String(localized: "analytics.no_income"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var delta: Double {
        let previous = NSDecimalNumber(decimal: snapshot.comparisonTotal).doubleValue
        guard previous > 0 else { return 0 }
        let current = NSDecimalNumber(decimal: snapshot.expenses).doubleValue
        return (current - previous) / previous * 100
    }

    private var shareOfIncome: Double {
        let income = NSDecimalNumber(decimal: snapshot.income).doubleValue
        guard income > 0 else { return 0 }
        return NSDecimalNumber(decimal: snapshot.remaining).doubleValue / income * 100
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

private struct SummaryCell: View {
    let label: String
    let value: String
    let sub: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AnalyticsStyle.figure)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            sub
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppStyle.Spacing.small)
    }
}

// MARK: - Breakdown

private struct AnalyticsBreakdownCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool

    @State private var dimension: AnalyticsDimension = .category
    @State private var filter: AnalyticsFilter = .all
    @State private var selectedSliceID: UUID?
    @State private var hoveredSliceID: UUID?
    @FocusState private var focusedSlice: UUID?

    private var visible: [AnalyticsSlice] {
        let list = dimension == .category ? snapshot.categories : snapshot.accounts
        guard dimension == .category else { return list }
        switch filter {
        case .all: return list
        case .mandatory: return list.filter(\.isMandatory)
        case .free: return list.filter { !$0.isMandatory }
        }
    }

    private var total: Decimal {
        visible.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var filterCounts: (all: Int, mandatory: Int, free: Int) {
        snapshot.filterCounts
    }

    var body: some View {
        OverviewCard {
            HStack {
                Text(String(localized: "analytics.where_money_went"))
                    .font(AppStyle.Typography.headline)
                Spacer(minLength: AppStyle.Spacing.small)
                HStack(spacing: AppStyle.Spacing.xxSmall) {
                    ForEach(AnalyticsDimension.allCases) { option in
                        Button {
                            dimension = option
                            selectedSliceID = nil
                            hoveredSliceID = nil
                        } label: {
                            Text(option.title)
                                .font(AppStyle.Typography.metadataEmphasis)
                                .foregroundStyle(option == dimension ? AppColors.textPrimary : AppColors.textSecondary)
                                .padding(.horizontal, AppStyle.Spacing.xSmall)
                                .frame(height: 24)
                                .background {
                                    RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                        .fill(option == dimension ? AppColors.surfaceRaised : .clear)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                        .strokeBorder(option == dimension ? AppColors.borderSubtle : .clear, lineWidth: 0.5)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == dimension ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xxSmall)

            if dimension == .category {
                HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                    filterButton(.all, count: filterCounts.all)
                    filterButton(.mandatory, count: filterCounts.mandatory)
                    filterButton(.free, count: filterCounts.free)
                }
                .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                .padding(.bottom, AppStyle.Spacing.xxSmall)
            }

            BalanceBar(
                segments: visible.map {
                    BalanceBar.Segment(
                        id: $0.id,
                        label: $0.name,
                        value: NSDecimalNumber(decimal: $0.amount).doubleValue,
                        color: $0.color
                    )
                },
                highlightedID: hoveredSliceID,
                onHover: { hoveredSliceID = $0 }
            )
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Spacing.xSmall)

            if visible.isEmpty {
                Text(String(localized: "analytics.no_filter_expenses"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                    .padding(.vertical, AppStyle.Spacing.medium)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, slice in
                        if index > 0 {
                            InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)
                        }
                        VStack(spacing: 0) {
                            row(slice)
                            if selectedSliceID == slice.id {
                                AnalyticsInlineOperations(
                                    operations: Array(slice.operations.prefix(4)),
                                    masked: masked
                                )
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: snapshot.range) { _, _ in
            selectedSliceID = nil
            hoveredSliceID = nil
        }
        .onChange(of: dimension) { _, _ in
            selectedSliceID = nil
            hoveredSliceID = nil
        }
        .onChange(of: filter) { _, _ in
            selectedSliceID = nil
            hoveredSliceID = nil
        }
    }

    private func filterButton(_ option: AnalyticsFilter, count: Int) -> some View {
        Button {
            filter = option
            selectedSliceID = nil
            hoveredSliceID = nil
        } label: {
            HStack(spacing: AppStyle.Spacing.xxSmall) {
                Text(option.title)
                    .font(AppStyle.Typography.metadataEmphasis)
                Text("\(count)")
                    .font(AppStyle.Typography.metadataEmphasis.numbers)
                    .foregroundStyle(option == filter ? AppColors.textSecondary : AppColors.textTertiary)
            }
            .foregroundStyle(option == filter ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppStyle.Spacing.xSmall)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(option == filter ? AppColors.surfaceRaised : AppColors.fillSecondary)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option == filter ? .isSelected : [])
    }

    private func row(_ slice: AnalyticsSlice) -> some View {
        Button {
            selectedSliceID = selectedSliceID == slice.id ? nil : slice.id
        } label: {
            HStack(spacing: AppStyle.Spacing.small) {
                ListRowIcon(
                    symbol: slice.symbol,
                    color: slice.color
                )

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(slice.name)
                        .font(AppStyle.Typography.headline)
                        .lineLimit(1)
                    Text(figures: Finance.operationsCountText(slice.operationCount),
                         style: AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppStyle.Spacing.small)

                VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(money(slice.amount))
                        .font(AnalyticsStyle.amount)
                        .monospacedDigit()
                        .lineLimit(1)

                    HStack(spacing: AppStyle.Spacing.xxxSmall) {
                        Text(figures: AnalyticsFormat.percent(share(slice), signed: false),
                             style: AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textTertiary)
                        if let delta = slice.delta {
                            Text("·")
                                .font(AppStyle.Typography.metadata)
                                .foregroundStyle(AppColors.textTertiary)
                            Text(figures: AnalyticsFormat.percent(delta),
                                 style: AppStyle.Typography.metadata)
                                .foregroundStyle(delta >= 0 ? AppColors.statusCheckText : AppColors.statusSafeText)
                        }
                    }
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.vertical, AppStyle.Spacing.xSmall)
            .background {
                (selectedSliceID == slice.id || hoveredSliceID == slice.id)
                    ? AppColors.fillSecondary.opacity(0.5)
                    : .clear
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSliceID = hovering ? slice.id : nil
        }
        .focused($focusedSlice, equals: slice.id)
        .onKeyPress(.downArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            selectedSliceID = nil
            return .handled
        }
        .pointingHandOnHover()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func moveFocus(by delta: Int) {
        guard !visible.isEmpty else { return }
        let current = focusedSlice ?? selectedSliceID
        let index = current.flatMap { id in visible.firstIndex { $0.id == id } } ?? (delta > 0 ? -1 : 0)
        let next = min(max(index + delta, 0), visible.count - 1)
        focusedSlice = visible[next].id
        selectedSliceID = visible[next].id
    }

    private func share(_ slice: AnalyticsSlice) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: slice.amount).doubleValue
            / NSDecimalNumber(decimal: total).doubleValue * 100
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

private struct AnalyticsInlineOperations: View {
    let operations: [Operation]
    let masked: Bool

    var body: some View {
        VStack(spacing: AppStyle.Spacing.xxSmall) {
            ForEach(operations, id: \.id) { operation in
                HStack(spacing: AppStyle.Spacing.xSmall) {
                    Text(figures: AppDate.short(operation.date), style: AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 42, alignment: .leading)
                    Text(figures: operation.displayTitle, style: AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: AppStyle.Spacing.xSmall)
                    Text(figures: operation.amountText(masked: masked),
                         style: AppStyle.Typography.metadataEmphasis)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(AppStyle.Spacing.xSmall)
        .background {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .fill(AppColors.fillSecondary)
        }
        .padding(.leading, 42)
        .padding(.trailing, AppStyle.Row.cardHorizontalPadding)
        .padding(.bottom, AppStyle.Spacing.xSmall)
    }
}

// MARK: - Pace

private struct AnalyticsPaceCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool

    var body: some View {
        OverviewCard {
            HStack {
                Text(String(localized: "analytics.pace"))
                    .font(AppStyle.Typography.headline)
                Spacer(minLength: AppStyle.Spacing.small)
                if snapshot.previousFullTotal > 0 {
                    AppBadge(
                        text: isFaster
                            ? String(localized: "analytics.faster")
                            : String(localized: "analytics.slower"),
                        tone: isFaster ? .warning : .safe
                    )
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xxSmall)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(localized: "analytics.average"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                Text(money(snapshot.average))
                    .font(AnalyticsStyle.figure)
                    .monospacedDigit()
                Text(String(localized: "analytics.per_day"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: AppStyle.Spacing.small)
                Text(figures: AnalyticsFormat.dayProgress(
                    elapsed: snapshot.range.elapsedDays,
                    total: snapshot.range.totalDays
                ), style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xSmall)

            AnalyticsPaceChart(
                snapshot: snapshot,
                currency: currency,
                masked: masked
            )
            .padding(.horizontal, AppStyle.Spacing.small)

            if let verdict {
                HStack(alignment: .top, spacing: AppStyle.Spacing.xxSmallPlus) {
                    if let symbol = verdictSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                    }
                    Text(figures: verdict, style: AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                .padding(.top, AppStyle.Spacing.xSmall)
                .padding(.bottom, AppStyle.Row.cardHorizontalPadding)
            }
        }
    }

    private var isFaster: Bool {
        guard snapshot.previousFullTotal > 0 else { return false }
        let pace = snapshot.previousFullTotal
            * Decimal(snapshot.range.elapsedDays)
            / Decimal(max(1, snapshot.range.totalDays))
        return snapshot.expenses > pace
    }

    private var isMore: Bool {
        snapshot.expenses >= snapshot.comparisonTotal
    }

    private var verdictSymbol: String? {
        snapshot.hasComparison ? (isMore ? "arrow.up.right" : "arrow.down.right") : nil
    }

    private var verdict: String? {
        guard snapshot.hasComparison else {
            return String(localized: "analytics.verdict_no_comparison \(Finance.daysText(snapshot.range.elapsedDays)) \(money(snapshot.expenses)) \(money(snapshot.average))")
        }
        let difference = abs(snapshot.expenses - snapshot.comparisonTotal)
        let daysLeft = snapshot.range.daysLeft

        if snapshot.range.scope == .month {
            if snapshot.range.isCurrent, daysLeft > 0 {
                if isMore {
                    return String(localized: "analytics.verdict_month_current_more \(Finance.daysText(snapshot.range.elapsedDays)) \(money(snapshot.comparisonTotal)) \(money(snapshot.expenses)) \(money(difference)) \(Finance.daysText(daysLeft))")
                }
                return String(localized: "analytics.verdict_month_current_less \(Finance.daysText(snapshot.range.elapsedDays)) \(money(snapshot.comparisonTotal)) \(money(snapshot.expenses)) \(money(difference)) \(Finance.daysText(daysLeft))")
            }
            if isMore {
                return String(localized: "analytics.verdict_month_past_more \(money(snapshot.comparisonTotal)) \(money(difference))")
            }
            return String(localized: "analytics.verdict_month_past_less \(money(snapshot.comparisonTotal)) \(money(difference))")
        }

        if snapshot.range.isCurrent, daysLeft > 0 {
            if isMore {
                return String(localized: "analytics.verdict_current_more \(money(snapshot.comparisonTotal)) \(money(difference)) \(Finance.daysText(daysLeft))")
            }
            return String(localized: "analytics.verdict_current_less \(money(snapshot.comparisonTotal)) \(money(difference)) \(Finance.daysText(daysLeft))")
        }
        if isMore {
            return String(localized: "analytics.verdict_past_more \(money(snapshot.comparisonTotal)) \(money(difference))")
        }
        return String(localized: "analytics.verdict_past_less \(money(snapshot.comparisonTotal)) \(money(difference))")
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

// MARK: - Heat map

private struct AnalyticsHeatCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool
    @State private var activeDay: Int?

    @FocusState private var gridFocused: Bool

    private var title: String {
        snapshot.range.scope == .month
            ? String(localized: "analytics.heat_month")
            : String(localized: "analytics.heat_period")
    }

    private var weekdays: [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { offset in
            symbols[(calendar.firstWeekday - 1 + offset) % 7].capitalized
        }
    }

    private var leadingBlanks: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekday = calendar.component(.weekday, from: snapshot.range.start)
        return (weekday - 2 + 7) % 7
    }

    private var rowCount: Int {
        (leadingBlanks + snapshot.days.count + 6) / 7
    }

    private func dayAt(row: Int, column: Int) -> AnalyticsDay? {
        let index = row * 7 + column - leadingBlanks
        guard snapshot.days.indices.contains(index) else { return nil }
        return snapshot.days[index]
    }

    var body: some View {
        OverviewCard {
            HStack {
                Text(figures: title, style: AppStyle.Typography.headline)
                Spacer(minLength: AppStyle.Spacing.small)
                legend
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xSmall)

            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(AppStyle.Typography.micro)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)

            VStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                        ForEach(0..<7, id: \.self) { column in
                            if let day = dayAt(row: row, column: column) {
                                cell(day)
                            } else {
                                Color.clear
                                    .frame(height: 44)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Spacing.xxSmallPlus)
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(.leftArrow) {
                moveHeat(by: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                moveHeat(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveHeat(by: -7)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveHeat(by: 7)
                return .handled
            }
            .onChange(of: gridFocused) { _, focused in
                if focused, activeDay == nil {
                    activeDay = snapshot.todayDay ?? snapshot.days.last(where: { !$0.isFuture })?.id ?? 1
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "analytics.heat_accessibility"))
            .onChange(of: snapshot.range) { _, _ in
                activeDay = nil
            }

            readout
                .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                .padding(.top, AppStyle.Spacing.xSmall)
                .padding(.bottom, AppStyle.Row.cardHorizontalPadding)
        }
    }

    private var legend: some View {
        HStack(spacing: AppStyle.Spacing.xxxSmall) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.Chart.amber.opacity(0.42))
                .frame(width: 8, height: 8)
            Text(String(localized: "analytics.above_average"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
            Text(String(localized: "analytics.less"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
            ForEach(1...4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColors.textPrimary.opacity(AnalyticsEngine.heatOpacities[index]))
                    .frame(width: 8, height: 8)
            }
            Text(String(localized: "analytics.more"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
        .accessibilityHidden(true)
    }

    private func cell(_ day: AnalyticsDay) -> some View {
        let isActive = activeDay == day.id
        let level = min(max(day.level, 0), AnalyticsEngine.heatOpacities.count - 1)
        let aboveAverage = day.amount > 0 && day.amount > snapshot.average
        let fill: Color
        if day.isFuture || day.amount <= 0 {
            fill = AppColors.fillSecondary
        } else if aboveAverage {
            fill = AppColors.Chart.amber.opacity(0.20 + Double(level) * 0.06)
        } else {
            fill = AppColors.textPrimary.opacity(AnalyticsEngine.heatOpacities[level])
        }
        let textColor = (day.isToday || day.level >= 3 || aboveAverage)
            ? AppColors.textPrimary
            : AppColors.textTertiary

        return ZStack {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .fill(fill)

            if !day.isFuture {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(AnalyticsStyle.heatDay)
                        .foregroundStyle(textColor)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        if day.amount > 0 {
                            Text(masked ? "••••" : MoneyFormat.number(day.amount, fractionDigits: 2))
                                .font(AnalyticsStyle.heatAmount)
                                .foregroundStyle(textColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .padding(AppStyle.Spacing.xxSmallPlus)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .overlay {
            if day.isFuture {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(
                        AppColors.borderStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(
                    isActive && !day.isToday ? AppColors.textSecondary : (day.isToday ? AppColors.textPrimary : .clear),
                    lineWidth: 1
                )
        }
        .opacity(day.isFuture ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { activeDay = day.id }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(day))
    }

    @ViewBuilder
    private var readout: some View {
        if let activeDay, let day = snapshot.days.first(where: { $0.id == activeDay }) {
            let date = AppDate.short(day.date)
            if day.amount > 0 {
                let above = day.amount > snapshot.average
                let suffix = above ? " · " + String(localized: "analytics.above_average") : ""
                Text(figures: "\(date) · \(money(day.amount)) · \(Finance.operationsCountText(day.operationCount))\(suffix)",
                     style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
            } else {
                Text(figures: "\(date) · \(String(localized: "analytics.no_day_expenses"))",
                     style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
            }
        } else {
            Text(String(localized: "analytics.hover_day"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private func moveHeat(by delta: Int) {
        let current = activeDay
            ?? snapshot.todayDay
            ?? snapshot.days.last(where: { !$0.isFuture })?.id
            ?? 1
        activeDay = min(max(current + delta, 1), max(1, snapshot.range.totalDays))
    }

    private func accessibilityText(_ day: AnalyticsDay) -> String {
        let date = AppDate.short(day.date)
        if day.amount > 0 {
            let above = day.amount > snapshot.average
            let suffix = above ? ", \(String(localized: "analytics.above_average"))" : ""
            return "\(date), \(money(day.amount)), \(Finance.operationsCountText(day.operationCount))\(suffix)"
        }
        return "\(date), \(String(localized: "analytics.no_day_expenses"))"
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

// MARK: - Shared styles and formatting

private enum AnalyticsStyle {
    static let figure = AppStyle.TextStyle(family: .rounded, size: 22, weight: .bold, tracking: 0)
    static let amount = AppStyle.TextStyle(family: .rounded, size: 15, weight: .semibold, tracking: 0)
    static let heatDay = AppStyle.TextStyle(family: .rounded, size: 10, weight: .semibold, tracking: 0)
    static let heatAmount = AppStyle.TextStyle(family: .rounded, size: 11, weight: .semibold, tracking: 0)
}

enum AnalyticsFormat {
    static func percent(_ value: Double, signed: Bool = true) -> String {
        let body = MoneyFormat.number(Decimal(abs(value)), fractionDigits: 1) + "%"
        guard signed else { return body }
        if value > 0 { return "+" + body }
        if value < 0 { return "−" + body }
        return body
    }

    static func dayProgress(elapsed: Int, total: Int) -> String {
        let word = (total % 10 == 1 && total % 100 != 11)
            ? String(localized: "analytics.day_genitive_one")
            : String(localized: "analytics.day_genitive_many")
        return "\(elapsed) \(String(localized: "analytics.of")) \(total) \(word)"
    }
}
