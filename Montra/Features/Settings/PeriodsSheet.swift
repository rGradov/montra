import SwiftData
import SwiftUI

/// The financial-month editor. The rule sets the default, and any single month
/// can be moved: adjusting a boundary drags the neighbouring periods with it, so
/// the timeline never overlaps or leaves a gap.
struct PeriodsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore

    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]

    @State private var selectedID: UUID?
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var didSelect = false
    @State private var showRecalculateAlert = false

    private var currentPeriod: Period? {
        PeriodService.currentPeriod(in: periods)
    }

    private var selectedPeriod: Period? {
        periods.first { $0.id == selectedID } ?? currentPeriod ?? periods.last
    }

    private var selectedIndex: Int? {
        guard let selectedPeriod else { return nil }
        return periods.firstIndex { $0.id == selectedPeriod.id }
    }

    private var previousPeriod: Period? {
        guard let index = selectedIndex, index > 0 else { return nil }
        return periods[index - 1]
    }

    private var nextPeriod: Period? {
        guard let index = selectedIndex, index + 1 < periods.count else { return nil }
        return periods[index + 1]
    }

    private var isDirty: Bool {
        guard let period = selectedPeriod else { return false }
        let calendar = Calendar.current
        return !calendar.isDate(startDate, inSameDayAs: period.start)
            || !calendar.isDate(endDate, inSameDayAs: period.end)
    }

    private var validPeriodsRange: ClosedRange<Date> {
        let minDate = previousPeriod.map { $0.start.addingTimeInterval(86_400) }
            ?? Calendar.current.date(byAdding: .day, value: -62, to: .now)!
        let maxDate = nextPeriod.map { $0.end.addingTimeInterval(-1) }
            ?? Calendar.current.date(byAdding: .day, value: 62, to: .now)!
        if minDate > maxDate { return maxDate...maxDate }
        return minDate...maxDate
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "common.periods"),
                subtitle: String(localized: "period.a_financial_month_from_payday"),
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                    ruleSection
                    editSection
                    listSection
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.bottom, AppStyle.Spacing.medium)
            }
            .frame(maxHeight: 520)

            SheetFooter {
                Text(String(localized: "period.adjacent_periods_will_move_with"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer(minLength: AppStyle.Spacing.small)
                Button(String(localized: "common.done")) { dismiss() }
                    .buttonStyle(.montra(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 520, height: 660)
        .background(AppColors.surfaceBase)
        .onAppear(perform: selectCurrent)
        .onChange(of: periods.count) { _, _ in
            if selectedID == nil { selectCurrent() }
        }
        .alert(String(localized: "common.recalculate_periods"), isPresented: $showRecalculateAlert) {
            Button(String(localized: "common.recalculate"), role: .destructive) {
                PeriodService.regenerate(context: context, settings: settings)
                selectedID = nil
                selectCurrent()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "period.automatic_periods_will_be_rebuilt"))
        }
    }

    // MARK: - Rule

    private var ruleSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            Text(String(localized: "common.rule"))
                .font(AppStyle.Typography.metadataEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppStyle.Spacing.xxSmall)

            InsetCard {
                HStack(alignment: .center, spacing: AppStyle.Spacing.medium) {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                        Text(String(localized: "period.how_to_calculate_the_period"))
                            .font(AppStyle.Typography.body)
                        Text(settings.periodMode == .payday
                             ? String(localized: "period.periods_start_on_payday_adjusted")
                             : String(localized: "period.a_fixed_number_of_days"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: AppStyle.Spacing.small)
                    DropdownMenu(
                        options: SettingsStore.PeriodMode.allCases,
                        selection: settings.periodMode,
                        selectionLabel: settings.periodMode.title,
                        optionLabel: { $0.title },
                        onSelect: { settings.periodMode = $0 }
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)

                InsetCardDivider()

                HStack(alignment: .center, spacing: AppStyle.Spacing.medium) {
                    Text(settings.periodMode == .payday ? String(localized: "common.payday") : String(localized: "common.period_length"))
                        .font(AppStyle.Typography.body)
                    Spacer(minLength: AppStyle.Spacing.small)

                    if settings.periodMode == .payday {
                        NumberStepper(
                            value: $settings.paydayDay,
                            range: 1...31,
                            label: { String(localized: "period.payday_ordinal \($0)") },
                            suffix: { _ in String(localized: "period.payday_suffix") },
                            accessibilityTitle: String(localized: "common.payday")
                        )
                    } else {
                        NumberStepper(
                            value: $settings.fixedLengthDays,
                            range: 1...90,
                            label: { Finance.daysText($0) },
                            suffix: { Finance.daysSuffix($0) },
                            accessibilityTitle: String(localized: "common.period_length")
                        )
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)

                InsetCardDivider()

                HStack(spacing: AppStyle.Spacing.small) {
                    Text(String(localized: "period.manual_adjustments_are_kept"))
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer(minLength: AppStyle.Spacing.small)
                    Button(String(localized: "common.recalculate")) { showRecalculateAlert = true }
                        .buttonStyle(.montra(.secondary, size: .small))
                }
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)
            }
        }
    }

    // MARK: - Edit

    private var editSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            Text(String(localized: "common.selected_period"))
                .font(AppStyle.Typography.metadataEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppStyle.Spacing.xxSmall)

            InsetCard {
                HStack(alignment: .center, spacing: AppStyle.Spacing.medium) {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                        Text(String(localized: "common.period"))
                            .font(AppStyle.Typography.body)
                        Text(selectedPeriod.map { "\($0.title) · \(Finance.daysText($0.days))" } ?? String(localized: "common.no_periods"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: AppStyle.Spacing.small)
                    DropdownMenu(
                        options: periods.map(\.id),
                        selection: selectedPeriod?.id ?? UUID(),
                        selectionLabel: selectedPeriod?.title ?? String(localized: "common.select"),
                        optionLabel: { id in
                            periods.first { $0.id == id }?.title ?? ""
                        },
                        onSelect: { id in
                            guard let period = periods.first(where: { $0.id == id }) else { return }
                            load(period)
                        }
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)

                InsetCardDivider()

                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    HStack(spacing: AppStyle.Spacing.small) {
                        Text(String(localized: "common.start"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 60, alignment: .leading)
                        DatePickerField(date: $startDate, showsTime: false, range: validPeriodsRange)
                    }

                    HStack(spacing: AppStyle.Spacing.small) {
                        Text(String(localized: "common.end"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 60, alignment: .leading)
                        DatePickerField(
                            date: $endDate,
                            showsTime: false,
                            range: max(startDate, validPeriodsRange.lowerBound)...validPeriodsRange.upperBound
                        )
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)

                InsetCardDivider()

                HStack(spacing: AppStyle.Spacing.small) {
                    Button(String(localized: "period.reset_to_rule")) { resetSelectedPeriod() }
                        .buttonStyle(.montra(.quiet, size: .small))
                        .disabled(selectedPeriod?.isManual != true)

                    Spacer(minLength: AppStyle.Spacing.small)

                    Button(String(localized: "common.save_period")) { applyEdits() }
                        .buttonStyle(.montra(.primary, size: .small))
                        .disabled(!isDirty)
                }
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)
            }
        }
    }

    // MARK: - List

    /// The current period with one before it and a few after, so the list reads
    /// as "what is happening now" rather than as an archive.
    private var nearbyPeriods: [Period] {
        guard let current = currentPeriod else { return Array(periods.suffix(4)) }
        let past = periods.filter { $0.end < current.start }.suffix(1)
        let future = periods.filter { $0.start > current.end }.prefix(4)
        return Array(past) + [current] + Array(future)
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            Text(String(localized: "common.nearby_periods"))
                .font(AppStyle.Typography.metadataEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppStyle.Spacing.xxSmall)

            InsetCard {
                let visible = nearbyPeriods
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, period in
                    if index > 0 {
                        InsetCardDivider()
                    }
                    periodRow(period)
                }
            }
        }
    }

    private func periodRow(_ period: Period) -> some View {
        let isCurrent = currentPeriod?.id == period.id
        let isSelected = selectedPeriod?.id == period.id
        return Button {
            load(period)
        } label: {
            HStack(spacing: AppStyle.Spacing.small) {
                Circle()
                    .fill(isCurrent ? AppColors.statusSafeText : AppColors.borderStrong)
                    .frame(width: 6, height: 6)

                Text(period.title)
                    .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)

                if isCurrent {
                    AppBadge(text: String(localized: "common.current"), tone: .safe)
                }
                if period.isManual {
                    AppBadge(text: String(localized: "common.manual"), tone: .accent)
                }

                Spacer(minLength: AppStyle.Spacing.small)

                Text(Finance.daysText(period.days))
                    .font(AppStyle.Typography.metadata.numbers)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.small)
            .background(isSelected ? AppColors.fillSecondary.opacity(0.5) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Actions

    private func selectCurrent() {
        if let currentPeriod {
            load(currentPeriod)
        } else if let last = periods.last {
            load(last)
        }
        didSelect = true
    }

    private func load(_ period: Period) {
        selectedID = period.id
        startDate = period.start
        endDate = period.end
    }

    private func applyEdits() {
        guard let period = selectedPeriod else { return }
        withAnimation(AppMotion.row) {
            PeriodService.update(period: period, startDay: startDate, endDay: endDate, context: context)
        }
        startDate = period.start
        endDate = period.end
    }

    private func resetSelectedPeriod() {
        guard let period = selectedPeriod else { return }
        let generated = PeriodService.generatedPeriods(rule: settings.rule, covering: period.start)
        guard let rulePeriod = generated.first(where: { $0.contains(period.start) }) else { return }
        withAnimation(AppMotion.row) {
            PeriodService.update(period: period, startDay: rulePeriod.start, endDay: rulePeriod.end, context: context)
        }
        load(period)
    }
}
