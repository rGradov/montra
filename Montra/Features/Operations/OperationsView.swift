import SwiftData
import SwiftUI

enum OperationFilter: String, CaseIterable, Identifiable {
    case all
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "common.all")
        case .expense: String(localized: "common.expenses")
        case .income: String(localized: "common.income")
        }
    }

    var icon: String? {
        switch self {
        case .all: "list.bullet"
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        }
    }
}

enum OperationPeriodScope: String, CaseIterable, Identifiable {
    case current
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: String(localized: "common.current_period")
        case .allTime: String(localized: "common.all_time_2")
        }
    }
}

enum PlanFilter: String, CaseIterable, Identifiable {
    case all
    case missed
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "common.all_scheduled")
        case .missed: String(localized: "common.missed")
        case .upcoming: String(localized: "common.upcoming")
        }
    }
}

enum OperationSort: String, CaseIterable, Identifiable {
    case date
    case amount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: String(localized: "common.by_date")
        case .amount: String(localized: "common.by_amount")
        }
    }
}

struct OperationsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var rates: RateStore
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Operation.date, order: .reverse)]) private var operations: [Operation]
    @Query(sort: [SortDescriptor(\PlannedOperation.date, order: .forward)]) private var plans: [PlannedOperation]
    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]

    let onBack: () -> Void
    let onNewOperation: (OperationKind?) -> Void
    let onEditOperation: (Operation) -> Void
    let onOpenPlan: (PlannedOperation) -> Void

    @State private var filter: OperationFilter = .all
    @State private var scope: OperationPeriodScope = .current
    @State private var sort: OperationSort = .date
    @State private var planFilter: PlanFilter = .all
    @State private var selected: Set<UUID> = []
    @State private var deleteRequest: DeleteRequest?
    @State private var searchText = ""
    @State private var searchFocusToken = 0
    @StateObject private var newRows = NewRowHighlighter()

    private var currentPeriod: Period? {
        PeriodService.currentPeriod(in: periods)
    }

    private var scopedOperations: [Operation] {
        switch scope {
        case .current:
            guard let currentPeriod else { return operations }
            return operations.filter { currentPeriod.contains($0.date) }
        case .allTime:
            return operations
        }
    }

    private var searchTokens: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything in the chosen period that matches the query, before the kind
    /// chip — the chips count against this, so "All 2 / Expenses 1 / Income 1".
    private var searchMatchedOperations: [Operation] {
        guard !searchTokens.isEmpty else { return scopedOperations }
        return scopedOperations.filter(matchesSearch)
    }

    /// Matches across every period, used to offer "search all time" when the
    /// current period has none.
    private var allTimeSearchMatches: [Operation] {
        guard !searchTokens.isEmpty else { return [] }
        return operations.filter(matchesSearch)
    }

    private var visibleOperations: [Operation] {
        let filtered: [Operation]
        switch filter {
        case .all: filtered = searchMatchedOperations
        case .expense: filtered = searchMatchedOperations.filter { $0.kind == .expense }
        case .income: filtered = searchMatchedOperations.filter { $0.kind == .income }
        }
        switch sort {
        case .date:
            return filtered.sorted { $0.date > $1.date }
        case .amount:
            return filtered.sorted { $0.amount > $1.amount }
        }
    }

    private var displayedTotal: Decimal {
        visibleOperations.reduce(Decimal(0)) { sum, operation in
            sum + (rates.convert(operation.signedAmount, from: operation.currency,
                                 to: settings.primaryCurrency) ?? 0)
        }
    }

    private var subtitle: String {
        if planFilter == .missed {
            return String(localized: "schedule.missed_summary \(visiblePlans.count)")
        }
        if planFilter == .upcoming {
            return String(localized: "schedule.upcoming_summary \(visiblePlans.count)")
        }

        let total = displayedTotal
        var text = "\(Finance.operationsCountText(visibleOperations.count)) · "
        text += settings.money(total, currency: settings.primaryCurrency, sign: total == 0 ? .none : .always)
        text += scope == .current ? String(localized: "transaction.in_period_suffix") : String(localized: "transaction.all_time_suffix")
        if !visiblePlans.isEmpty {
            text += String(localized: "schedule.count_suffix \(visiblePlans.count)")
        }
        return text
    }

    private func matchesSearch(_ operation: Operation) -> Bool {
        guard !searchTokens.isEmpty else { return true }
        let haystack = [
            operation.category?.displayName ?? "",
            operation.account?.name ?? "",
            operation.place,
            operation.note,
            operation.kind.title,
            operation.isTransfer ? String(localized: "transaction.transfer") : "",
            MoneyFormat.string(operation.amount, currency: operation.currency),
            "\(operation.amount)",
            AppDate.short(operation.date),
        ].joined(separator: " ")
        return searchTokens.allSatisfy { haystack.localizedStandardContains($0) }
    }

    private var pendingPlans: [PlannedOperation] {
        plans.filter { $0.linkedOperationID == nil }
    }

    private var planSearchMatched: [PlannedOperation] {
        guard !searchTokens.isEmpty else { return pendingPlans }
        return pendingPlans.filter(matchesSearch)
    }

    private var planKindMatched: [PlannedOperation] {
        switch filter {
        case .all: planSearchMatched
        case .expense: planSearchMatched.filter { $0.kind == .expense }
        case .income: planSearchMatched.filter { $0.kind == .income }
        }
    }

    private var scopedPlans: [PlannedOperation] {
        guard scope == .current, let currentPeriod else { return planKindMatched }
        return planKindMatched.filter { currentPeriod.contains($0.date) }
    }

    private var missedPlans: [PlannedOperation] {
        planKindMatched
            .filter(\.isMissed)
            .sorted { $0.date > $1.date }
    }

    private var upcomingPlans: [PlannedOperation] {
        let horizon = PlanHorizon.limit()
        return planKindMatched
            .filter { $0.isUpcoming && $0.date <= min($0.seriesEnd, horizon) }
            .sorted { $0.date < $1.date }
    }

    private var visiblePlans: [PlannedOperation] {
        switch planFilter {
        case .all: scopedPlans
        case .missed: missedPlans
        case .upcoming: upcomingPlans
        }
    }

    private var missedCount: Int { missedPlans.count }
    private var upcomingCount: Int { upcomingPlans.count }

    private var dayEntries: [TransactionEntry] {
        visibleOperations.map { .operation($0) } + visiblePlans.map { .plan($0) }
    }

    private var daySections: [TransactionDaySection] {
        TransactionDaySection.sections(from: dayEntries)
    }

    private var planDaySections: [TransactionDaySection] {
        TransactionDaySection.sections(
            from: visiblePlans.map { .plan($0) },
            ascending: planFilter == .upcoming
        )
    }

    private func matchesSearch(_ plan: PlannedOperation) -> Bool {
        guard !searchTokens.isEmpty else { return true }
        let haystack = [
            plan.category?.displayName ?? "",
            plan.account?.name ?? "",
            plan.place,
            plan.note,
            plan.kind.title,
            String(localized: "common.scheduled"),
            plan.frequency.adverb,
            MoneyFormat.string(plan.amount, currency: plan.currency),
            "\(plan.amount)",
            AppDate.short(plan.date),
        ].joined(separator: " ")
        return searchTokens.allSatisfy { haystack.localizedStandardContains($0) }
    }

    private var allSelected: Bool {
        !visibleOperations.isEmpty && visibleOperations.allSatisfy { selected.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            plansBar
            if planFilter == .all {
                selectAllRow
            }

            ScrollView {
                if planFilter != .all {
                    if visiblePlans.isEmpty {
                        planEmptyState
                            .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                            .padding(.bottom, AppStyle.Spacing.large)
                    } else {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(planDaySections) { section in
                                Section {
                                    ForEach(section.entries) { entry in
                                        if case .plan(let plan) = entry {
                                            PlannedOperationRow(
                                                plan: plan,
                                                masked: settings.hideBalances,
                                                onOpen: { onOpenPlan(plan) }
                                            )
                                            .padding(.bottom, AppStyle.Spacing.xSmall)
                                            .transition(.rowReveal)
                                        }
                                    }
                                } header: {
                                    OperationDateHeader(title: section.title)
                                }
                            }
                        }
                        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                        .padding(.bottom, AppStyle.Spacing.large)
                        .animation(AppMotion.insert, value: visiblePlans.count)
                    }
                } else if visibleOperations.isEmpty && visiblePlans.isEmpty {
                    Group {
                        if searchTokens.isEmpty {
                            OverviewCard {
                                EmptyState(
                                    symbol: filter == .income ? "arrow.down.left" : "arrow.up.right",
                                    title: String(localized: "transaction.list.nothing_here_yet"),
                                    message: scope == .current
                                        ? String(localized: "transaction.list.no_matching_transactions_in_the")
                                        : String(localized: "transaction.list.add_an_expense_or_income"),
                                    actionTitle: String(localized: "transaction.new"),
                                    action: presentNewOperation
                                )
                            }
                            .transition(.opacity)
                        } else {
                            searchEmptyState
                        }
                    }
                    .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                    .padding(.bottom, AppStyle.Spacing.large)
                } else if sort == .date {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(daySections) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    switch entry {
                                    case .operation(let operation):
                                        operationRow(operation)
                                            .padding(.bottom, AppStyle.Spacing.xSmall)
                                            .transition(.rowReveal)
                                    case .plan(let plan):
                                        PlannedOperationRow(
                                            plan: plan,
                                            masked: settings.hideBalances,
                                            alignsWithSelection: true,
                                            onOpen: { onOpenPlan(plan) }
                                        )
                                        .padding(.bottom, AppStyle.Spacing.xSmall)
                                        .transition(.rowReveal)
                                    }
                                }
                            } header: {
                                OperationDateHeader(title: section.title)
                            }
                        }
                    }
                    .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                    .padding(.bottom, AppStyle.Spacing.large)
                    .animation(AppMotion.insert, value: visibleOperations.count + visiblePlans.count)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleOperations) { operation in
                            operationRow(operation)
                                .padding(.bottom, AppStyle.Spacing.xSmall)
                                .transition(.rowReveal)
                        }

                        if !visiblePlans.isEmpty {
                            OperationDateHeader(title: String(localized: "common.scheduled_payments"))
                            ForEach(visiblePlans.sorted { $0.date < $1.date }) { plan in
                                PlannedOperationRow(
                                    plan: plan,
                                    masked: settings.hideBalances,
                                    alignsWithSelection: true,
                                    onOpen: { onOpenPlan(plan) }
                                )
                                .padding(.bottom, AppStyle.Spacing.xSmall)
                                .transition(.rowReveal)
                            }
                        }
                    }
                    .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                    .padding(.bottom, AppStyle.Spacing.large)
                    .animation(AppMotion.insert, value: visibleOperations.count + visiblePlans.count)
                }
            }
        }
        .background(AppColors.surfaceBase)
        .onAppear {
            syncHeader()
            newRows.track(operations.map(\.id))
        }
        .onChange(of: headerKey) { _, _ in syncHeader() }
        .onChange(of: operations.count) { _, _ in
            newRows.track(operations.map(\.id))
        }
        .sheet(item: $deleteRequest) { request in
            DeleteOperationsSheet(items: request.items, totalText: request.totalText) {
                let ids = Set(request.items.map(\.id))
                delete(operations.filter { ids.contains($0.id) })
            }
        }
        .onChange(of: scope) { _, _ in selected.removeAll() }
        .onChange(of: filter) { _, _ in selected.removeAll() }
        .onChange(of: planFilter) { _, _ in selected.removeAll() }
        .onChange(of: searchText) { _, _ in selected.removeAll() }
        .background {
            // ⌘F focuses the capsule, like the reference's Find action.
            Button("") { searchFocusToken += 1 }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var plansBar: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 10, weight: .semibold))
                Text(String(localized: "common.scheduled_payments"))
            }
            .font(AppStyle.Typography.callout.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)

            planChip(.missed, count: missedCount)
            planChip(.upcoming, count: upcomingCount)

            Spacer(minLength: AppStyle.Spacing.small)

            if planFilter != .all {
                Button(String(localized: "common.reset")) {
                    withAnimation(AppMotion.row) {
                        planFilter = .all
                        selected.removeAll()
                    }
                }
                .buttonStyle(.montra(.quiet, size: .small))
            }
        }
        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
        .padding(.bottom, AppStyle.Spacing.xSmall)
    }

    private func planChip(_ item: PlanFilter, count: Int) -> some View {
        let icon = item == .missed ? "exclamationmark.circle" : "calendar"
        return FilterChip(
            style: .tab,
            label: item.title,
            isSelected: planFilter == item,
            leadingSystemImage: icon,
            count: count
        )
        .onTapGesture {
            withAnimation(AppMotion.row) {
                planFilter = planFilter == item ? .all : item
                selected.removeAll()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(planFilter == item ? .isSelected : [])
    }

    private var planEmptyState: some View {
        VStack(spacing: AppStyle.Spacing.small) {
            if searchTokens.isEmpty {
                EmptyState(
                    symbol: planFilter == .missed ? "checkmark.circle" : "calendar.badge.clock",
                    title: planFilter == .missed ? String(localized: "account.no_missed_payments") : String(localized: "account.no_upcoming_payments"),
                    message: planFilter == .missed
                        ? String(localized: "account.all_past_scheduled_payments_are")
                        : String(localized: "transaction.list.create_a_recurring_transaction_to"),
                    actionTitle: String(localized: "transaction.new"),
                    action: presentNewOperation
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: AppStyle.Spacing.xSmall) {
                    Text(String(localized: "common.no_results"))
                        .font(AppStyle.Typography.sectionTitle)
                    Text(String(localized: "transaction.list.no_scheduled_payments_match \(trimmedSearch)"))
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "common.clear_search")) { clearSearch() }
                        .buttonStyle(.montra(.secondary))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var headerKey: String {
        [
            selectedSubtitle ?? subtitle,
            "\(selected.count)",
            filter.rawValue,
            planFilter.rawValue,
            scope.rawValue,
            sort.rawValue,
            trimmedSearch,
        ].joined(separator: "|")
    }

    private var headerTrailing: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            if selected.isEmpty {
                Button {} label: {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }
                .buttonStyle(.montra(.secondary))
                .disabled(true)
            } else {
                Button {
                    requestDelete(operations.filter { selected.contains($0.id) })
                } label: {
                    Label(String(localized: "action.delete_selection \(selected.count)"), systemImage: "trash")
                }
                .buttonStyle(.montra(.destructive))
            }

            Button(action: presentNewOperation) {
                Label(String(localized: "transaction.new"), systemImage: "plus")
            }
            .buttonStyle(.montra(.primary))
        }
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "transaction.all"),
            subtitle: selectedSubtitle ?? subtitle,
            backTitle: String(localized: "navigation.overview"),
            onBack: onBack,
            trailing: AnyView(headerTrailing)
        )
    }

    private var filterBar: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            ForEach(OperationFilter.allCases) { item in
                FilterChip(
                    style: .tab,
                    label: item.title,
                    isSelected: filter == item,
                    leadingSystemImage: item.icon,
                    count: count(for: item)
                )
                .onTapGesture { withAnimation(AppMotion.row) { filter = item } }
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(filter == item ? .isSelected : [])
            }

            Spacer(minLength: AppStyle.Spacing.small)

            CapsuleSearchField(
                query: $searchText,
                width: 220,
                focusToken: searchFocusToken
            )
        }
        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
        .padding(.top, AppStyle.Spacing.xSmall)
        .padding(.bottom, AppStyle.Spacing.xSmall)
    }

    private var selectAllRow: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            Toggle(isOn: Binding(
                get: { allSelected },
                set: { isOn in
                    let ids = visibleOperations.map(\.id)
                    if isOn {
                        selected.formUnion(ids)
                    } else {
                        selected.subtract(ids)
                    }
                }
            )) {
                Text(String(localized: "common.select_all"))
                    .font(AppStyle.Typography.body.weight(.medium))
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #else
            .toggleStyle(.touchCheckbox)
            #endif
            .tint(AppColors.actionPrimary)

            Spacer(minLength: AppStyle.Spacing.small)

            PopoverMenu(
                options: OperationPeriodScope.allCases,
                selection: scope,
                optionLabel: { $0.title },
                onSelect: { scope = $0 }
            ) {
                FilterChip(style: .dropdown, label: scope.title, leadingSystemImage: "calendar")
                    .contentShape(Capsule())
            }
            .accessibilityLabel(String(localized: "transaction.list.period \(scope.title)"))

            PopoverMenu(
                options: OperationSort.allCases,
                selection: sort,
                optionLabel: { $0.title },
                minimumWidth: 140,
                onSelect: { sort = $0 }
            ) {
                HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text(sort.title)
                }
                .font(AppStyle.Typography.headline)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppStyle.Spacing.small + 2)
                .frame(height: 30)
                .background(AppColors.fillSecondary, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous).strokeBorder(AppColors.borderStrong, lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .accessibilityLabel(String(localized: "transaction.list.sort \(sort.title)"))
        }
        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
        .padding(.top, AppStyle.Spacing.xSmall)
        .padding(.bottom, AppStyle.Spacing.small)
    }

    private func count(for filter: OperationFilter) -> Int {
        switch filter {
        case .all: searchMatchedOperations.count
        case .expense: searchMatchedOperations.filter { $0.kind == .expense }.count
        case .income: searchMatchedOperations.filter { $0.kind == .income }.count
        }
    }

    /// The active type chip sets the tab the create sheet opens on.
    private var newOperationKind: OperationKind? {
        switch filter {
        case .all: return nil
        case .expense: return .expense
        case .income: return .income
        }
    }

    private func presentNewOperation() {
        onNewOperation(newOperationKind)
    }

    private var searchEmptyState: some View {
        let hasMatchesInOtherPeriod = scope == .current
            && searchMatchedOperations.isEmpty
            && !allTimeSearchMatches.isEmpty
        let hasOtherKindMatches = !searchMatchedOperations.isEmpty

        let title: String
        let message: String
        let actionTitle: String
        let action: () -> Void

        if hasMatchesInOtherPeriod {
            title = String(localized: "transaction.list.nothing_in_the_current_period")
            message = String(localized: "transaction.list.matches_across_all_time \(trimmedSearch) \(Finance.operationsCountText(allTimeSearchMatches.count))")
            actionTitle = String(localized: "transaction.list.search_all_time")
            action = { withAnimation(AppMotion.row) { scope = .allTime } }
        } else if hasOtherKindMatches {
            title = String(localized: "transaction.list.nothing_matches_this_filter")
            message = String(localized: "transaction.list.matches_of_another_type \(trimmedSearch) \(Finance.operationsCountText(searchMatchedOperations.count))")
            actionTitle = String(localized: "common.show_all")
            action = { withAnimation(AppMotion.row) { filter = .all } }
        } else {
            title = String(localized: "common.no_results")
            message = String(localized: "transaction.list.no_transactions_match \(trimmedSearch)")
            actionTitle = String(localized: "common.clear_search")
            action = { clearSearch() }
        }

        return VStack(spacing: AppStyle.Spacing.xSmall) {
            Text(title)
                .font(AppStyle.Typography.sectionTitle)

            Text(message)
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Button(actionTitle, action: action)
                .buttonStyle(.montra(.secondary))
                .padding(.top, AppStyle.Spacing.xxSmall)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppStyle.Spacing.xLarge)
        .transition(.opacity)
    }

    private func clearSearch() {
        searchText = ""
        searchFocusToken += 1
    }

    private func operationRow(_ operation: Operation) -> some View {
        OperationListRow(
            operation: operation,
            isSelected: selected.contains(operation.id),
            isNew: newRows.isNew(operation.id),
            masked: settings.hideBalances,
            onToggle: { toggle(operation) },
            onEdit: { onEditOperation(operation) },
            onDelete: { requestDelete([operation]) }
        )
    }

    private func toggle(_ operation: Operation) {
        if selected.contains(operation.id) {
            selected.remove(operation.id)
        } else {
            selected.insert(operation.id)
        }
    }

    private var selectedSubtitle: String? {
        let targets = operations.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return nil }
        let total = rates.total(of: targets, to: settings.primaryCurrency)
        return String(localized: "transaction.selected_summary \(targets.count) \(settings.money(total, currency: settings.primaryCurrency, sign: total == 0 ? .none : .always))")
    }

    private func requestDelete(_ targets: [Operation]) {
        deleteRequest = DeleteRequest.make(
            operations: targets,
            settings: settings,
            rates: rates,
            context: context
        )
    }

    private func delete(_ targets: [Operation]) {
        withAnimation(AppMotion.row) {
            selected.subtract(targets.map(\.id))
        }
        OperationRepository(context: context).delete(targets)
    }
}

// MARK: - Row

struct OperationListRow: View {
    let operation: Operation
    let isSelected: Bool
    var isNew: Bool = false
    let masked: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                #if os(macOS)
                .toggleStyle(.checkbox)
                #else
                .toggleStyle(.touchCheckbox)
                #endif
                .tint(AppColors.actionPrimary)
                .accessibilityLabel(String(localized: "common.select_transaction"))

            Button(action: onEdit) {
                HStack(spacing: AppStyle.Spacing.small) {
                    ListRowIcon(
                        symbol: operation.displayIcon,
                        color: operation.displayColor
                    )

                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                        Text(operation.displayTitle)
                            .font(AppStyle.Typography.headline)
                            .lineLimit(1)

                        Text(figures: detail, style: AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    .frame(minHeight: 32, alignment: .leading)

                    Spacer(minLength: AppStyle.Spacing.small)

                    VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxSmallPlus) {
                        Text(operation.amountText(masked: masked))
                            .font(AppStyle.Typography.rowTitle.numbers)
                            .monospacedDigit()
                            .foregroundStyle(operation.kind == .income ? AppColors.statusSafeText : AppColors.textPrimary)

                        if let badge {
                            AppBadge(text: badge.0, tone: badge.1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
        }
        .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.small)
        .background {
            let shape = RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
            ZStack {
                shape.fill(isNew ? AppColors.fillSecondaryHover : (isHovering ? AppColors.fillSecondaryHover : AppColors.fillSecondary))
                NewRowVeil(isNew: isNew, cornerRadius: AppStyle.Radius.lg)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                .strokeBorder(
                    isNew || isSelected ? AppColors.borderStrong : AppColors.borderSubtle,
                    lineWidth: 0.5
                )
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(AppMotion.highlight, value: isNew)
        .contextMenu {
            Button(operation.isTransfer ? String(localized: "common.open_transfer") : String(localized: "common.edit_2"), action: onEdit)
            Divider()
            Button(String(localized: "common.delete"), role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        var parts = [AppDate.dayMonthTime.string(from: operation.date)]
        parts.append(operation.detailText)
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var badge: (String, AppBadge.Tone)? {
        guard !operation.isTransfer else { return nil }
        switch operation.kind {
        case .income:
            return (String(localized: "transaction.income"), .safe)
        case .expense:
            let mandatory = operation.category?.isMandatory == true
                || operation.category?.parent?.isMandatory == true
            return mandatory ? (String(localized: "common.essential"), .warning) : nil
        }
    }
}
