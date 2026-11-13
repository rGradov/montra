import SwiftData
import SwiftUI

/// Creating and editing an operation. Expense or income, the account supplies
/// the currency, the category list follows the kind, the date defaults to right
/// now, and a place can be typed or read from Core Location.
struct OperationSheet: View {
    enum Mode {
        case create(OperationSource)
        case edit(Operation)
    }

    enum FormTab: String, CaseIterable, Identifiable {
        case expense
        case income
        case transfer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .expense: String(localized: "transaction.expense")
            case .income: String(localized: "transaction.income")
            case .transfer: String(localized: "transaction.transfer")
            }
        }

        var icon: String {
            switch self {
            case .expense: "arrow.up.right"
            case .income: "arrow.down.left"
            case .transfer: "arrow.left.arrow.right"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var rates: RateStore

    @Query(sort: [SortDescriptor(\Account.sortIndex, order: .forward)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Category.sortIndex, order: .forward)]) private var categories: [Category]
    @Query private var allOperations: [Operation]

    let mode: Mode

    @State private var kind: OperationKind
    @State private var isTransfer: Bool
    @State private var fromAccountID: UUID?
    @State private var toAccountID: UUID?
    @State private var sentText: String
    @State private var receivedText = ""
    @State private var receivedEdited = false
    @State private var amountText: String
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var date: Date
    @State private var place: String
    @State private var note: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var didPrepare = false
    @State private var isConfirmingDelete = false
    @State private var isCategoryPickerPresented = false
    @State private var sourcePlan: PlannedOperation?
    @State private var repeats = false
    @State private var planFrequency: PlanFrequency = .month
    @State private var planWeekdays: Set<Int> = []
    @State private var planEnd: Date
    @StateObject private var location = LocationProvider()

    init(mode: Mode, initialTab: FormTab? = nil, previewSent: String = "", initialAmount: String = "", initialRepeats: Bool = false) {
        self.mode = mode
        switch mode {
        case .create(let source):
            if let planned = source.planned {
                _kind = State(initialValue: planned.kind)
                _amountText = State(initialValue: initialAmount.isEmpty ? Self.editableAmount(planned.amount) : initialAmount)
                _accountID = State(initialValue: planned.account?.id)
                _categoryID = State(initialValue: planned.category?.id)
                _date = State(initialValue: .now)
                _place = State(initialValue: planned.place)
                _note = State(initialValue: planned.note)
                _latitude = State(initialValue: nil)
                _longitude = State(initialValue: nil)
                _sourcePlan = State(initialValue: planned)
            } else {
                _kind = State(initialValue: source.kind ?? .expense)
                _amountText = State(initialValue: initialAmount)
                _accountID = State(initialValue: source.account?.id)
                _categoryID = State(initialValue: nil)
                _date = State(initialValue: .now)
                _place = State(initialValue: "")
                _note = State(initialValue: "")
                _latitude = State(initialValue: nil)
                _longitude = State(initialValue: nil)
            }
        case .edit(let operation):
            _kind = State(initialValue: operation.kind)
            _amountText = State(initialValue: Self.editableAmount(operation.amount))
            _accountID = State(initialValue: operation.account?.id)
            _categoryID = State(initialValue: operation.category?.id)
            _date = State(initialValue: operation.date)
            _place = State(initialValue: operation.place)
            _note = State(initialValue: operation.note)
            _latitude = State(initialValue: operation.latitude)
            _longitude = State(initialValue: operation.longitude)
        }

        var startsInTransfer = false
        if case .create = mode, initialTab == .transfer {
            startsInTransfer = true
        }
        _isTransfer = State(initialValue: startsInTransfer)
        _sentText = State(initialValue: previewSent)
        _repeats = State(initialValue: initialRepeats)

        let startDate: Date
        switch mode {
        case .create: startDate = .now
        case .edit(let operation): startDate = operation.date
        }
        _planEnd = State(initialValue: Calendar.current.date(byAdding: .year, value: 1, to: startDate) ?? startDate)
    }

    private var editingOperation: Operation? {
        if case .edit(let operation) = mode { return operation }
        return nil
    }

    private var isEditing: Bool { editingOperation != nil }

    private var selectedAccount: Account? {
        accounts.first { $0.id == accountID } ?? accounts.first
    }

    private var currency: Currency { selectedAccount?.currency ?? .byn }

    private var availableCategories: [Category] {
        categories.filter { $0.kind == kind }.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var amount: Decimal? {
        guard let value = Self.parseAmount(amountText), value > 0 else { return nil }
        return value
    }

    private var isValid: Bool {
        amount != nil && selectedAccount != nil && categoryID != nil
    }

    private var selectedTab: FormTab {
        isTransfer ? .transfer : (kind == .income ? .income : .expense)
    }

    private var visibleTabs: [FormTab] {
        isEditing ? [.expense, .income] : FormTab.allCases
    }

    private var fromAccount: Account? {
        accounts.first { $0.id == fromAccountID } ?? accounts.first
    }

    private var toAccount: Account? {
        if let selected = accounts.first(where: { $0.id == toAccountID }),
           selected.id != fromAccount?.id {
            return selected
        }
        return accounts.first { $0.id != fromAccount?.id }
    }

    private var sentAmount: Decimal? { Self.parseAmount(sentText) }
    private var receivedAmount: Decimal? { Self.parseAmount(receivedText) }

    private var transferIsValid: Bool {
        guard let fromAccount, let toAccount,
              let sent = sentAmount, let received = receivedAmount else { return false }
        return fromAccount.id != toAccount.id && sent > 0 && received > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isEditing ? String(localized: "common.transaction") : String(localized: "transaction.new"),
                subtitle: isTransfer ? String(localized: "transaction.form.transfer_between_accounts") : "\(kind.title) · \(currency.code)",
                onClose: { dismiss() }
            )

            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                kindRow
                if !isTransfer {
                    amountField
                }
            }
            .padding(.horizontal, AppStyle.Spacing.large)
            .padding(.bottom, AppStyle.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        if isTransfer {
                            transferFields
                            dateField
                        } else {
                            #if os(iOS)
                            // Two half-width values on a phone leave neither
                            // readable (the account name is the first to go), so
                            // each field takes its own row.
                            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                                accountField
                                dateField
                            }
                            #else
                            HStack(alignment: .top, spacing: AppStyle.Spacing.small) {
                                accountField
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                dateField
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            #endif

                            categoryField

                            if !isEditing && sourcePlan == nil {
                                repeatSection
                                    .id("repeat-section")
                            }

                            detailsDivider
                            placeField
                            noteField
                        }
                    }
                    .padding(.horizontal, AppStyle.Spacing.large)
                    .padding(.bottom, AppStyle.Spacing.medium)
                    .onChange(of: repeats) { _, isOn in
                        guard isOn else { return }
                        withAnimation(AppMotion.row) {
                            proxy.scrollTo("repeat-section", anchor: .top)
                        }
                    }
                    .onAppear {
                        guard repeats else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo("repeat-section", anchor: .top)
                        }
                    }
                }
                #if os(macOS)
                .frame(height: isTransfer ? 494 : 413)
                #else
                .frame(maxHeight: .infinity)
                #endif
                .sheetKeyboardScrolling()
            }

            SheetFooter {
                if isEditing {
                    Button(String(localized: "common.delete")) { isConfirmingDelete = true }
                        .buttonStyle(.montra(.destructive))
                }
                Spacer(minLength: AppStyle.Spacing.small)
                Button(String(localized: "common.cancel")) { dismiss() }
                    .buttonStyle(.montra(.quiet))
                Button(footerTitle) { save() }
                    .buttonStyle(.montra(.primary))
                    .disabled(isTransfer ? !transferIsValid : (repeats && !isEditing ? (!isValid || !planIsValid) : !isValid))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheetContentFrame(width: 470)
        .background(AppColors.surfaceBase)
        .onAppear(perform: prepare)
        .onChange(of: kind) { _, _ in
            if !availableCategories.contains(where: { $0.id == categoryID }) {
                categoryID = availableCategories.first?.id
            }
        }
        .onChange(of: isTransfer) { _, transfer in
            if transfer { prepareTransferAccounts() }
        }
        .onChange(of: sentText) { _, _ in updateTransferReceived() }
        .onChange(of: fromAccountID) { _, _ in
            receivedEdited = false
            updateTransferReceived()
        }
        .onChange(of: toAccountID) { _, _ in
            receivedEdited = false
            updateTransferReceived()
        }
        .onChange(of: date) { _, newDate in
            guard repeats else { return }
            let calendar = Calendar.current
            if calendar.startOfDay(for: planEnd) < calendar.startOfDay(for: newDate) {
                planEnd = calendar.date(byAdding: .year, value: 1, to: newDate) ?? newDate
            }
        }
        .onChange(of: repeats) { _, isOn in
            guard isOn else { return }
            let calendar = Calendar.current
            if planWeekdays.isEmpty {
                planWeekdays = [calendar.component(.weekday, from: date)]
            }
            if calendar.startOfDay(for: planEnd) < calendar.startOfDay(for: date) {
                planEnd = calendar.date(byAdding: .year, value: 1, to: date) ?? date
            }
        }
        .onChange(of: planFrequency) { _, frequency in
            guard frequency == .week, planWeekdays.isEmpty else { return }
            planWeekdays = [Calendar.current.component(.weekday, from: date)]
        }
        .onChange(of: location.reading) { _, reading in
            guard let reading else { return }
            place = reading.name
            latitude = reading.latitude
            longitude = reading.longitude
        }
        .onChange(of: place) { _, newValue in
            guard let reading = location.reading else {
                latitude = nil
                longitude = nil
                return
            }
            if newValue != reading.name {
                latitude = nil
                longitude = nil
            }
        }
        .alert(String(localized: "common.delete_transaction"), isPresented: $isConfirmingDelete) {
            Button(String(localized: "common.delete"), role: .destructive) { deleteOperation() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "transaction.form.this_action_cant_be_undone"))
        }
    }

    // MARK: - Fields

    private var kindRow: some View {
        ChipGroup(
            options: visibleTabs,
            selection: selectedTab,
            label: { $0.title },
            icon: { $0.icon },
            onSelect: selectTab
        )
    }

    private func selectTab(_ tab: FormTab) {
        withAnimation(AppMotion.row) {
            switch tab {
            case .expense:
                isTransfer = false
                kind = .expense
            case .income:
                isTransfer = false
                kind = .income
            case .transfer:
                isTransfer = true
                prepareTransferAccounts()
            }
        }
        if !isTransfer, !availableCategories.contains(where: { $0.id == categoryID }) {
            categoryID = availableCategories.first?.id
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            FieldLabel(title: String(localized: "common.amount"), trailing: currency.name)

            HStack(spacing: AppStyle.Spacing.small) {
                TextField("0", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)

                Text(currency.symbol)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .frame(height: 48)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
        }
    }

    private var accountField: some View {
        accountPicker(title: String(localized: "common.account"), selected: selectedAccount) { id in
            accountID = id
            fromAccountID = id
        }
    }

    private func accountPicker(
        title: String,
        selected: Account?,
        onSelect: @escaping (UUID) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.xSmall) {
                Text(title)
                    .font(AppStyle.Typography.callout.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                if let selected {
                    Text(settings.money(selected.balance, currency: selected.currency))
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textTertiary)
                }
                Spacer(minLength: 0)
            }

            if accounts.isEmpty {
                Text(String(localized: "transaction.form.create_an_account_first"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                PopoverMenu(
                    options: accounts.map(\.id),
                    selection: selected?.id ?? accounts[0].id,
                    optionLabel: { id in
                        guard let account = accounts.first(where: { $0.id == id }) else { return "" }
                        return "\(account.name) · \(account.currency.code)"
                    },
                    minimumWidth: 204,
                    fillsWidth: true,
                    onSelect: onSelect
                ) {
                    HStack(spacing: AppStyle.Spacing.xSmall) {
                        if let selected {
                            IconTile(symbol: selected.iconName, color: selected.color.tileColor, size: 18)
                        }
                        Text(
                            figures: selected.map { "\($0.name) · \($0.currency.code)" }
                                ?? String(localized: "transaction.form.choose_an_account"),
                            style: AppStyle.Typography.body
                        )
                        .lineLimit(1)
                        Spacer(minLength: AppStyle.Spacing.xxSmall)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .accessibilityLabel(
                    "\(title), \(selected.map { "\($0.name) · \($0.currency.code)" } ?? String(localized: "transaction.form.choose_an_account"))"
                )
            }
        }
    }

    private var transferFields: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            if accounts.count < 2 {
                Text(String(localized: "transaction.form.you_need_at_least_two"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
            }

            #if os(iOS)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                accountPicker(title: String(localized: "common.from"), selected: fromAccount, onSelect: selectFrom)

                HStack {
                    Spacer(minLength: 0)
                    swapTransferButton
                    Spacer(minLength: 0)
                }

                accountPicker(title: String(localized: "common.to"), selected: toAccount, onSelect: selectTo)
            }
            #else
            HStack(alignment: .top, spacing: AppStyle.Spacing.xSmall) {
                accountPicker(title: String(localized: "common.from"), selected: fromAccount, onSelect: selectFrom)
                    .frame(maxWidth: .infinity, alignment: .leading)

                swapTransferButton
                    .padding(.top, 23)

                accountPicker(title: String(localized: "common.to"), selected: toAccount, onSelect: selectTo)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            #endif

            TransferAmountField(
                title: String(localized: "transfer.amount_sent"),
                text: $sentText,
                currency: fromAccount?.currency
            )

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                TransferAmountField(
                    title: String(localized: "transfer.amount_received"),
                    text: Binding(
                        get: { receivedText },
                        set: {
                            receivedText = $0
                            receivedEdited = true
                        }
                    ),
                    currency: toAccount?.currency,
                    trailing: transferRateText
                )

                if receivedEdited {
                    HStack(spacing: AppStyle.Spacing.xSmall) {
                        Text(transferRateHint)
                            .font(AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: AppStyle.Spacing.xSmall)

                        Button(String(localized: "transaction.form.at_the_current_rate")) {
                            receivedEdited = false
                            updateTransferReceived()
                        }
                        .buttonStyle(.montra(.quiet, size: .small))
                    }
                }

                Text(String(localized: "transaction.form.the_rate_is_approximate_enter"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var swapTransferButton: some View {
        Button {
            swapTransferAccounts()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.montra(.secondary, width: .square))
        .platformHelp(String(localized: "transaction.form.swap_accounts"))
        .accessibilityLabel(String(localized: "transaction.form.swap_accounts"))
    }

    private var transferRateHint: String {
        guard let fromAccount, let toAccount else {
            return String(localized: "transaction.form.choose_accounts_to_see_the")
        }
        if fromAccount.currency == toAccount.currency {
            return String(localized: "transaction.form.same_currency_you_can_adjust")
        }
        guard let sent = sentAmount, sent > 0 else {
            return String(localized: "transaction.form.enter_the_amount_sent_to")
        }
        guard let converted = rates.convert(sent, from: fromAccount.currency, to: toAccount.currency) else {
            return String(localized: "transaction.form.the_rate_is_unavailable_enter")
        }
        return String(localized: "transfer.estimated_amount \(MoneyFormat.number(converted, fractionDigits: toAccount.currency.fractionDigits)) \(toAccount.currency.code)")
    }

    private var transferRateText: String? {
        guard let fromAccount, let toAccount, fromAccount.currency != toAccount.currency else { return nil }
        guard let rate = rates.convert(1, from: toAccount.currency, to: fromAccount.currency) else { return nil }
        return "1 \(toAccount.currency.code) ≈ \(MoneyFormat.number(rate, fractionDigits: 2)) \(fromAccount.currency.code)"
    }

    private func updateTransferReceived() {
        guard !receivedEdited else { return }
        guard let fromAccount, let toAccount,
              let sent = sentAmount, sent > 0,
              let converted = rates.convert(sent, from: fromAccount.currency, to: toAccount.currency) else {
            receivedText = ""
            return
        }
        receivedText = MoneyFormat.number(converted, fractionDigits: toAccount.currency.fractionDigits, grouping: false)
    }

    private func prepareTransferAccounts() {
        if fromAccountID == nil {
            fromAccountID = accountID ?? accounts.first?.id
        }
        guard let fromAccount else { return }

        if toAccountID == nil || toAccountID == fromAccount.id {
            toAccountID = accounts.first { $0.id != fromAccount.id && $0.currency != fromAccount.currency }?.id
                ?? accounts.first { $0.id != fromAccount.id }?.id
        }
        if sentText.isEmpty, !amountText.isEmpty {
            sentText = amountText
        }
        updateTransferReceived()
    }

    private func selectFrom(_ id: UUID) {
        if id == toAccountID { toAccountID = fromAccountID }
        fromAccountID = id
    }

    private func selectTo(_ id: UUID) {
        if id == fromAccountID { fromAccountID = toAccountID }
        toAccountID = id
    }

    private func swapTransferAccounts() {
        guard let fromAccount, let toAccount else { return }
        let sent = sentText
        let received = receivedText

        selectFrom(toAccount.id)
        sentText = received
        receivedText = sent
        receivedEdited = false
        updateTransferReceived()
    }

    private var categoryUsage: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for operation in allOperations {
            guard let id = operation.category?.id else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }

    private var quickCategories: [Category] {
        let sorted = availableCategories.sorted { left, right in
            let leftCount = categoryUsage[left.id, default: 0]
            let rightCount = categoryUsage[right.id, default: 0]
            if leftCount != rightCount { return leftCount > rightCount }
            return left.sortIndex < right.sortIndex
        }

        var quick = Array(sorted.prefix(5))
        if let selected = availableCategories.first(where: { $0.id == categoryID }),
           !quick.contains(where: { $0.id == selected.id }) {
            quick = Array(quick.prefix(4)) + [selected]
        }
        return quick
    }

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            FieldLabel(title: String(localized: "common.category"), trailing: availableCategories.isEmpty ? nil : "\(availableCategories.count)")

            FlowLayout(spacing: AppStyle.Spacing.xSmall, lineSpacing: AppStyle.Spacing.xSmall) {
                ForEach(quickCategories) { category in
                    categoryChip(category)
                }

                Button {
                    isCategoryPickerPresented = true
                } label: {
                    HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(String(localized: "common.more"))
                            .font(AppStyle.Typography.body)
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
                    .background(AppColors.fillSecondary, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .popover(isPresented: $isCategoryPickerPresented, arrowEdge: .bottom) {
                    CategoryPickerPopover(categories: availableCategories, selection: $categoryID)
                }
                .accessibilityLabel(String(localized: "common.all_categories"))
            }
        }
    }

    private func categoryChip(_ category: Category) -> some View {
        let isSelected = category.id == categoryID
        return Button {
            withAnimation(AppMotion.row) { categoryID = category.id }
        } label: {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                // A category glyph is one string: an SF Symbol or an emoji,
                // exactly like an account's. Draw the emoji as text so a
                // category can use the same appearance picker as an account.
                if AppIconGlyph.isEmoji(category.iconName) {
                    Text(category.iconName)
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: AppIconSymbol.resolved(category.iconName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? AppColors.textPrimary : category.color.color)
                        .accessibilityHidden(true)
                }
                Text(category.displayName)
                    .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .regular))
                if category.isMandatory || (category.parent?.isMandatory ?? false) {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppColors.statusCheckText)
                }
            }
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
            .background(
                isSelected ? AppColors.surfaceRaised : AppColors.fillSecondary,
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footerTitle: String {
        if isTransfer { return String(localized: "common.transfer") }
        if isEditing || sourcePlan != nil { return String(localized: "common.save") }
        return repeats ? String(localized: "common.create_schedule") : String(localized: "common.add")
    }

    private var planDates: [Date] {
        PlanSchedule.dates(
            start: date,
            end: planEnd,
            frequency: planFrequency,
            weekdays: planWeekdays
        )
    }

    private var planIsValid: Bool {
        let dates = planDates
        return !dates.isEmpty && dates.count < PlanSchedule.maxOccurrences
    }

    private var planEndLimit: Date {
        Calendar.current.date(byAdding: .year, value: 5, to: date) ?? date
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            HStack(alignment: .top, spacing: AppStyle.Spacing.small) {
                Image(systemName: "repeat")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "common.repeat"))
                        .font(AppStyle.Typography.body.weight(.medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(String(localized: "transaction.form.schedule_future_payments_without_recording"))
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(RepeatCaption.lineLimit)
                        .minimumScaleFactor(0.92)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppStyle.Spacing.small)

                Toggle("", isOn: $repeats)
                    .toggleStyle(.switch)
                    .tint(AppColors.actionPrimary)
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "common.repeat"))
            }

            if repeats {
                Rectangle()
                    .fill(AppColors.borderSubtle)
                    .frame(height: 0.5)

                ChipGroup(
                    options: PlanFrequency.allCases,
                    selection: planFrequency,
                    label: { $0.title },
                    icon: nil,
                    onSelect: { frequency in
                        withAnimation(AppMotion.row) { planFrequency = frequency }
                    },
                    chipBackground: AppColors.surfaceBase
                )

                if planFrequency == .week {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                        FieldLabel(title: String(localized: "transaction.form.days_of_the_week"), trailing: planWeekdays.isEmpty ? String(localized: "common.choose_days") : nil)
                        HStack(spacing: 4) {
                            ForEach(PlanWeekday.allCases) { day in
                                let selected = planWeekdays.contains(day.rawValue)
                                Button {
                                    if selected {
                                        planWeekdays.remove(day.rawValue)
                                    } else {
                                        planWeekdays.insert(day.rawValue)
                                    }
                                } label: {
                                    Text(day.short)
                                        .font(AppStyle.Typography.metadataEmphasis)
                                        .foregroundStyle(selected ? AppColors.textPrimary : AppColors.textSecondary)
                                        .frame(width: 34, height: 28)
                                        .background(
                                            selected ? AppColors.surfaceRaised : AppColors.surfaceBase,
                                            in: RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                                                .strokeBorder(
                                                    selected ? AppColors.borderStrong : AppColors.borderSubtle,
                                                    lineWidth: 1
                                                )
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(day.full)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                }

                FormField(title: String(localized: "common.repeat_until")) {
                    DatePickerField(
                        date: $planEnd,
                        showsTime: false,
                        range: Calendar.current.startOfDay(for: date)...planEndLimit
                    )
                }

                Text(planSummary)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(planIsValid ? AppColors.textSecondary : AppColors.statusCheckText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.small)
        .background(
            AppColors.fillSecondary,
            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
        }
    }

    private var planSummary: String {
        let dates = planDates
        guard !dates.isEmpty else {
            return planFrequency == .week && planWeekdays.isEmpty
                ? String(localized: "transaction.form.choose_at_least_one_day")
                : String(localized: "transaction.form.check_the_recurrence_dates")
        }
        guard dates.count < PlanSchedule.maxOccurrences else {
            return String(localized: "transaction.form.too_many_payments_choose_a")
        }

        let payments = String(localized: "schedule.payment_count \(dates.count)")
        var text = "\(payments) · \(planFrequency.adverb)"
        if planFrequency == .week {
            let weekdays = PlanWeekday.allCases
                .filter { planWeekdays.contains($0.rawValue) }
                .map(\.short)
                .joined(separator: ", ")
            text += " · \(weekdays)"
        }
        text += String(localized: "schedule.until \(AppDate.short(planEnd)) \(String(Calendar.current.component(.year, from: planEnd)))")
        return text
    }

    private var detailsDivider: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var dateField: some View {
        FormField(title: String(localized: "transaction.form.date_and_time")) {
            DatePickerField(date: $date)
        }
    }

    private var placeField: some View {
        FormField(title: String(localized: "common.payment_location")) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
                HStack(spacing: AppStyle.Spacing.xSmall) {
                    MontraTextField(placeholder: String(localized: "transaction.form.for_example_green"), text: $place)

                    Button {
                        location.requestLocation()
                    } label: {
                        if location.isLocating {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                                .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.montra(.secondary, width: .square))
                    .frame(width: 32, height: 32)
                    .platformHelp(String(localized: "transaction.form.use_my_location"))
                    .disabled(location.isLocating)
                    .accessibilityLabel(String(localized: "transaction.form.use_my_location"))
                }

                if let message = location.errorMessage {
                    Text(message)
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.statusCheckText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var noteField: some View {
        FormField(title: String(localized: "common.note")) {
            MontraTextField(
                placeholder: String(localized: "common.optional"),
                text: $note,
                axis: .vertical,
                lineLimit: 2...4,
                height: 48
            )
        }
    }

    // MARK: - Actions

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        if accountID == nil { accountID = accounts.first?.id }
        if categoryID == nil { categoryID = availableCategories.first?.id }
        if isTransfer { prepareTransferAccounts() }
    }

    private func save() {
        if isTransfer {
            guard let fromAccount, let toAccount,
                  let sent = sentAmount, let received = receivedAmount,
                  transferIsValid else { return }
            TransferRepository(context: context).create(
                from: fromAccount,
                to: toAccount,
                sent: sent,
                received: received,
                date: date
            )
            dismiss()
            return
        }

        guard let amount, let account = selectedAccount else { return }
        let category = categories.first { $0.id == categoryID }

        if repeats && !isEditing {
            guard planIsValid else { return }
            PlanRepository(context: context).create(
                kind: kind,
                amount: amount,
                account: account,
                category: category,
                date: date,
                place: place,
                note: note,
                frequency: planFrequency,
                weekdays: planWeekdays,
                end: planEnd
            )
            dismiss()
            return
        }

        let repository = OperationRepository(context: context)

        if let operation = editingOperation {
            repository.update(
                operation,
                kind: kind,
                amount: amount,
                account: account,
                category: category,
                date: date,
                place: place,
                latitude: latitude,
                longitude: longitude,
                note: note
            )
        } else {
            let created = repository.create(
                kind: kind,
                amount: amount,
                account: account,
                category: category,
                date: date,
                place: place,
                latitude: latitude,
                longitude: longitude,
                note: note
            )
            if let sourcePlan {
                PlanRepository(context: context).link(sourcePlan, to: created)
            }
        }
        dismiss()
    }

    private func deleteOperation() {
        guard let operation = editingOperation else { return }
        OperationRepository(context: context).delete([operation])
        dismiss()
    }

    private static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0 else { return nil }
        return value
    }

    private static func editableAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}


/// The repeat switch's caption fits one line on the Mac's 470 pt sheet; a phone
/// needs the second line rather than an ellipsis in the middle of the sentence.
private enum RepeatCaption {
    static var lineLimit: Int {
        #if os(iOS)
        2
        #else
        1
        #endif
    }
}
