import SwiftData
import SwiftUI

struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var rates: RateStore
    @EnvironmentObject private var headerHost: DetailHeaderHost

    let account: Account
    let onBack: () -> Void
    let onEdit: () -> Void
    let onNewOperation: (OperationKind?) -> Void
    let onEditOperation: (Operation) -> Void
    let onOpenPlan: (PlannedOperation) -> Void

    /// Sorted and limited to this account by the store instead of sorting the
    /// relationship on every body evaluation.
    @Query private var operations: [Operation]
    @Query(sort: [SortDescriptor(\PlannedOperation.date, order: .forward)]) private var allPlans: [PlannedOperation]
    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]

    @State private var filter: OperationFilter = .all
    @State private var planFilter: PlanFilter = .all
    @State private var isScrolling = false
    @State private var selected: Set<UUID> = []
    @State private var deleteRequest: DeleteRequest?
    @StateObject private var newRows = NewRowHighlighter()

    init(
        account: Account,
        onBack: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onNewOperation: @escaping (OperationKind?) -> Void,
        onEditOperation: @escaping (Operation) -> Void,
        onOpenPlan: @escaping (PlannedOperation) -> Void
    ) {
        self.account = account
        self.onBack = onBack
        self.onEdit = onEdit
        self.onNewOperation = onNewOperation
        self.onEditOperation = onEditOperation
        self.onOpenPlan = onOpenPlan

        let accountID = account.id
        _operations = Query(
            filter: #Predicate<Operation> { $0.account?.id == accountID },
            sort: [SortDescriptor(\Operation.date, order: .reverse)]
        )
    }

    private var allOperations: [Operation] {
        operations
    }

    private var balance: Decimal {
        operations.reduce(account.initialAmount) { $0 + $1.signedAmount }
    }

    private var filteredOperations: [Operation] {
        switch filter {
        case .all: allOperations
        case .expense: allOperations.filter { $0.kind == .expense }
        case .income: allOperations.filter { $0.kind == .income }
        }
    }

    private var currentPeriod: Period? {
        PeriodService.currentPeriod(in: periods)
    }

    /// Every plan still waiting for a fact, across all periods. The mixed
    /// "Все/Расходы/Доходы" list trims this to the current period, while the
    /// "Пропущенные"/"Будущие" chips look beyond it.
    private var pendingPlans: [PlannedOperation] {
        allPlans.filter { plan in
            plan.account?.id == account.id && plan.linkedOperationID == nil
        }
    }

    private var periodPlans: [PlannedOperation] {
        guard let currentPeriod else { return pendingPlans }
        return pendingPlans.filter { currentPeriod.contains($0.date) }
    }

    private var filteredPlans: [PlannedOperation] {
        switch filter {
        case .all: periodPlans
        case .expense: periodPlans.filter { $0.kind == .expense }
        case .income: periodPlans.filter { $0.kind == .income }
        }
    }

    /// Plans on past days that were never linked to a fact — the "Пропущенные"
    /// list, newest missed first.
    private var missedPlans: [PlannedOperation] {
        pendingPlans.filter(\.isMissed).sorted { $0.date > $1.date }
    }

    /// Plans from today through the two-year horizon — the "Будущие" list,
    /// soonest first, so next week's rent sits right at the top.
    private var upcomingPlans: [PlannedOperation] {
        let horizon = PlanHorizon.limit()
        return pendingPlans
            .filter { $0.isUpcoming && $0.date <= min($0.seriesEnd, horizon) }
            .sorted { $0.date < $1.date }
    }

    private var visiblePlans: [PlannedOperation] {
        switch planFilter {
        case .all: []
        case .missed: missedPlans
        case .upcoming: upcomingPlans
        }
    }

    private var net: Decimal {
        allOperations.reduce(Decimal(0)) { $0 + $1.signedAmount }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                    hero
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                        filterRow
                        if planFilter == .all && !filteredOperations.isEmpty {
                            selectionRow
                        }
                    }
                    list
                }
                .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                .padding(.bottom, AppStyle.Spacing.large)
            }
            .onScrollPhaseChange { previous, current in
                guard previous.isScrolling != current.isScrolling else { return }
                isScrolling = current.isScrolling
            }
        }
        .background(AppColors.surfaceBase)
        .sheet(item: $deleteRequest) { request in
            DeleteOperationsSheet(items: request.items, totalText: request.totalText) {
                deleteOperations(Set(request.items.map(\.id)))
            }
        }
        .onChange(of: filter) { _, _ in
            withAnimation(AppMotion.row) { selected.removeAll() }
        }
        .onChange(of: planFilter) { _, _ in
            withAnimation(AppMotion.row) { selected.removeAll() }
        }
        .onAppear {
            syncHeader()
            newRows.track(operations.map(\.id))
        }
        .onChange(of: headerKey) { _, _ in syncHeader() }
        .onChange(of: operations.count) { _, _ in
            newRows.track(operations.map(\.id))
        }
    }

    private var headerKey: String {
        [account.id.uuidString, account.name, subtitle, "\(selected.count)", filter.rawValue, planFilter.rawValue]
            .joined(separator: "|")
    }

    private var headerTrailing: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            if !selected.isEmpty {
                Button {
                    deleteRequest = DeleteRequest.make(
                        operations: selectedOperations,
                        settings: settings,
                        rates: rates,
                        context: context
                    )
                } label: {
                    Label(String(localized: "action.delete_selection \(selected.count)"), systemImage: "trash")
                }
                .buttonStyle(.montra(.destructive))
            }

            Button(String(localized: "common.edit"), action: onEdit)
                .buttonStyle(.montra(.secondary))
            Button(action: presentNewOperation) {
                Label(String(localized: "transaction.new"), systemImage: "plus")
            }
            .buttonStyle(.montra(.primary))
        }
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: account.name,
            subtitle: subtitle,
            backTitle: String(localized: "navigation.overview"),
            onBack: onBack,
            trailing: AnyView(headerTrailing)
        )
    }

    private var subtitle: String {
        var parts = [account.currency.code]
        if account.isSavings { parts.append(String(localized: "account.savings_badge")) }
        if account.isHiddenFromOverview { parts.append(String(localized: "account.hidden_badge")) }
        let openingBalance = settings.money(account.initialAmount, currency: account.currency)
        parts.append(String(localized: "account.opening_balance_summary \(openingBalance)"))
        if account.currency != settings.primaryCurrency,
           let converted = rates.convert(balance, from: account.currency, to: settings.primaryCurrency) {
            parts.append("≈ \(settings.money(converted, currency: settings.primaryCurrency))")
        }
        return parts.joined(separator: " · ")
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.xSmall) {
            Text(settings.money(balance, currency: account.currency))
                .font(AppStyle.Typography.title.weight(.bold).numbers)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(String(localized: "account.in_this_account"))
                .font(AppStyle.Typography.rowTitle.numbers)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: AppStyle.Spacing.small)

            VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxxSmall) {
                Text(String(localized: "common.all_time"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                Text(settings.money(net, currency: account.currency, sign: .always))
                    .font(AppStyle.Typography.rowTitle.numbers)
                    .monospacedDigit()
                    .foregroundStyle(net >= 0 ? AppColors.statusSafeText : AppColors.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var filterRow: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            ForEach(OperationFilter.allCases) { item in
                FilterChip(
                    style: .tab,
                    label: item.title,
                    isSelected: planFilter == .all && filter == item,
                    leadingSystemImage: item.icon,
                    count: count(for: item)
                )
                .onTapGesture { selectKind(item) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(planFilter == .all && filter == item ? .isSelected : [])
            }

            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(width: 1, height: 18)
                .padding(.horizontal, AppStyle.Spacing.xxxSmall)
                .accessibilityHidden(true)

            ForEach([PlanFilter.missed, .upcoming]) { item in
                FilterChip(
                    style: .tab,
                    label: item.title,
                    isSelected: planFilter == item,
                    leadingSystemImage: item == .missed ? "exclamationmark.circle" : "calendar.badge.clock",
                    count: planCount(item)
                )
                .onTapGesture { togglePlanFilter(item) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(planFilter == item ? .isSelected : [])
                .help(item == .missed
                      ? String(localized: "account.past_scheduled_payments_without_a")
                      : String(localized: "account.payments_scheduled_over_the_next"))
            }

            Spacer(minLength: 0)
        }
    }

    /// Kind chips and plan chips share one row, so they are mutually
    /// exclusive: picking a plan status drops the kind and vice versa.
    private func selectKind(_ item: OperationFilter) {
        withAnimation(AppMotion.row) {
            filter = item
            planFilter = .all
        }
    }

    private func togglePlanFilter(_ item: PlanFilter) {
        withAnimation(AppMotion.row) {
            filter = .all
            planFilter = planFilter == item ? .all : item
        }
    }

    /// The active filter tells the sheet which tab to start on: after
    /// "Доходы" the form must open on "Доход", not on "Расход".
    private var newOperationKind: OperationKind? {
        guard planFilter == .all else { return nil }
        switch filter {
        case .all: return nil
        case .expense: return .expense
        case .income: return .income
        }
    }

    private func presentNewOperation() {
        onNewOperation(newOperationKind)
    }

    private var allVisibleSelected: Bool {
        !filteredOperations.isEmpty && filteredOperations.allSatisfy { selected.contains($0.id) }
    }

    private var selectedOperations: [Operation] {
        allOperations.filter { selected.contains($0.id) }
    }

    private var selectedTotalText: String {
        let total = rates.total(of: selectedOperations, to: settings.primaryCurrency)
        return settings.money(total, currency: settings.primaryCurrency, sign: total == 0 ? .none : .always)
    }

    private var selectionRow: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            Toggle(isOn: Binding(
                get: { allVisibleSelected },
                set: { isOn in
                    let ids = filteredOperations.map(\.id)
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
            .toggleStyle(.checkbox)
            .tint(AppColors.actionPrimary)

            Spacer(minLength: AppStyle.Spacing.small)

            if !selected.isEmpty {
                Text(String(localized: "transaction.selected_summary \(selected.count) \(selectedTotalText)"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.45), value: selected)
            }
        }
    }

    /// Small accounts keep the accordion; long ones switch to a lazy list so a
    /// thousand rows never get built (or measured) just to open the page.
    private let accordionLimit = 60

    private var allDaySections: [TransactionDaySection] {
        TransactionDaySection.sections(
            from: allOperations.map { .operation($0) } + periodPlans.map { .plan($0) }
        )
    }

    private var filteredDaySections: [TransactionDaySection] {
        TransactionDaySection.sections(
            from: filteredOperations.map { .operation($0) } + filteredPlans.map { .plan($0) }
        )
    }

    /// The plan-only lists group by day too: soonest first for "Будущие",
    /// most recent first for "Пропущенные".
    private var planDaySections: [TransactionDaySection] {
        TransactionDaySection.sections(
            from: visiblePlans.map { .plan($0) },
            ascending: planFilter == .upcoming
        )
    }

    @ViewBuilder
    private var list: some View {
        if planFilter != .all {
            planList
        } else if allOperations.isEmpty && periodPlans.isEmpty {
            emptyAllCard
        } else if allOperations.count <= accordionLimit {
            accordionList
        } else {
            lazyList
        }
    }

    private var planList: some View {
        Group {
            if visiblePlans.isEmpty {
                planEmptyCard
            } else {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(planDaySections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                if case .plan(let plan) = entry {
                                    planRow(plan, alignsWithSelection: false)
                                        .padding(.bottom, AppStyle.Spacing.xSmall)
                                        .transition(.rowReveal)
                                }
                            }
                        } header: {
                            OperationDateHeader(title: section.title)
                        }
                    }
                }
                .animation(AppMotion.insert, value: visiblePlans.count)
            }
        }
    }

    private var planEmptyCard: some View {
        OverviewCard {
            EmptyState(
                symbol: planFilter == .missed ? "checkmark.circle" : "calendar.badge.clock",
                title: planFilter == .missed ? String(localized: "account.no_missed_payments") : String(localized: "account.no_upcoming_payments"),
                message: planFilter == .missed
                    ? String(localized: "account.all_past_scheduled_payments_are")
                    : String(localized: "account.add_a_recurring_transaction_to"),
                actionTitle: String(localized: "transaction.new"),
                action: presentNewOperation
            )
        }
        .padding(.top, AppStyle.Spacing.xSmall)
        .transition(.opacity)
    }

    private var emptyAllCard: some View {
        OverviewCard {
            EmptyState(
                symbol: "arrow.up.right",
                title: String(localized: "common.no_transactions"),
                message: String(localized: "account.add_an_expense_or_income"),
                actionTitle: String(localized: "transaction.new"),
                action: presentNewOperation
            )
        }
    }

    private var emptyFilterCard: some View {
        OverviewCard {
            EmptyState(
                symbol: "arrow.up.right",
                title: String(localized: "common.no_transactions"),
                message: filter == .income
                    ? String(localized: "account.this_account_has_no_income")
                    : String(localized: "account.this_account_has_no_expenses"),
                actionTitle: String(localized: "transaction.new"),
                action: presentNewOperation
            )
        }
        .padding(.top, AppStyle.Spacing.xSmall)
        .transition(.opacity)
    }

    /// The rows stay mounted and fold their height, so changing a filter is an
    /// accordion rather than a page swap: income rows compress away, expense rows
    /// unfold into the space, and the list below moves smoothly.
    private var accordionList: some View {
        VStack(spacing: 0) {
            ForEach(allDaySections) { section in
                if section.entries.contains(where: matchesEntry) {
                    OperationDateHeader(title: section.title)
                        .transition(.opacity)
                }

                ForEach(section.entries) { entry in
                    switch entry {
                    case .operation(let operation):
                        CollapsibleRow(
                            isExpanded: matches(operation),
                            delay: 0
                        ) {
                            compactRow(operation)
                                // The gap belongs to the row, so it collapses with it
                                // and leaves no empty slot behind.
                                .padding(.bottom, AppStyle.Spacing.xSmall)
                        }
                    case .plan(let plan):
                        if matchesPlan(plan) {
                            planRow(plan, alignsWithSelection: true)
                                .padding(.bottom, AppStyle.Spacing.xSmall)
                                .transition(.opacity)
                        }
                    }
                }
            }

            if filteredOperations.isEmpty && filteredPlans.isEmpty {
                emptyFilterCard
            }
        }
        .animation(AppMotion.row, value: filter)
    }

    private var lazyList: some View {
        Group {
            if filteredOperations.isEmpty && filteredPlans.isEmpty {
                emptyFilterCard
            } else {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(filteredDaySections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                switch entry {
                                case .operation(let operation):
                                    compactRow(operation)
                                        .padding(.bottom, AppStyle.Spacing.xSmall)
                                        .transition(.rowReveal)
                                case .plan(let plan):
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
                .animation(AppMotion.insert, value: filteredOperations.count + filteredPlans.count)
            }
        }
    }

    private func matchesEntry(_ entry: TransactionEntry) -> Bool {
        switch entry {
        case .operation(let operation): matches(operation)
        case .plan(let plan): matchesPlan(plan)
        }
    }

    private func matchesPlan(_ plan: PlannedOperation) -> Bool {
        switch filter {
        case .all: true
        case .expense: plan.kind == .expense
        case .income: plan.kind == .income
        }
    }

    private func compactRow(_ operation: Operation) -> some View {
        OperationCompactRow(
            operation: operation,
            isNew: newRows.isNew(operation.id),
            masked: settings.hideBalances,
            onOpen: { onEditOperation(operation) },
            isSelectable: true,
            isSelected: selected.contains(operation.id),
            onToggle: { toggleSelection(operation) },
            animatesHover: !isScrolling
        )
    }

    /// The account page names the account in its header, so its plan cards do
    /// not repeat it in the metadata line.
    private func planRow(_ plan: PlannedOperation, alignsWithSelection: Bool) -> some View {
        PlannedOperationRow(
            plan: plan,
            masked: settings.hideBalances,
            showsAccount: false,
            alignsWithSelection: alignsWithSelection,
            onOpen: { onOpenPlan(plan) }
        )
    }

    private func matches(_ operation: Operation) -> Bool {
        switch filter {
        case .all: true
        case .expense: operation.kind == .expense
        case .income: operation.kind == .income
        }
    }

    private func toggleSelection(_ operation: Operation) {
        if selected.contains(operation.id) {
            selected.remove(operation.id)
        } else {
            selected.insert(operation.id)
        }
    }

    private func deleteOperations(_ ids: Set<UUID>) {
        // The second leg of a transfer lives on another account, so resolve ids
        // against the store instead of this account's relationship.
        let all = (try? context.fetch(FetchDescriptor<Operation>())) ?? []
        let targets = all.filter { ids.contains($0.id) }
        withAnimation(AppMotion.row) { selected.subtract(ids) }
        OperationRepository(context: context).delete(targets)
    }

    private func count(for filter: OperationFilter) -> Int {
        switch filter {
        case .all: allOperations.count
        case .expense: allOperations.filter { $0.kind == .expense }.count
        case .income: allOperations.filter { $0.kind == .income }.count
        }
    }

    private func planCount(_ item: PlanFilter) -> Int {
        switch item {
        case .all: pendingPlans.count
        case .missed: missedPlans.count
        case .upcoming: upcomingPlans.count
        }
    }
}
