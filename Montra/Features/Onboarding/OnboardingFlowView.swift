import AppKit
import SwiftData
import SwiftUI

// MARK: - Layout and shared pieces

enum OnboardingLayout {
    /// The column the welcome copy and the forms live in, as in the reference.
    static let contentMaxWidth: CGFloat = 520
    static let horizontalPadding: CGFloat = 48
    static let verticalPadding: CGFloat = 40
    static let buttonWidth: CGFloat = 240
    static let formWidth: CGFloat = 360
}

private enum OnboardingTransitions {
    static func step(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .modifier(
            active: StepBlurModifier(blur: 8, opacity: 0),
            identity: StepBlurModifier(blur: 0, opacity: 1)
        )
    }
}

private struct StepBlurModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity)
    }
}

/// Elements arrive one after another, as on the reference welcome screen.
private struct OnboardingBlurInModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    func body(content: Content) -> some View {
        content
            .blur(radius: revealed || reduceMotion ? 0 : 10)
            .opacity(revealed || reduceMotion ? 1 : 0)
            .onAppear {
                guard !revealed else { return }
                if reduceMotion {
                    revealed = true
                } else {
                    withAnimation(.easeOut(duration: 0.45).delay(Double(index) * 0.08)) {
                        revealed = true
                    }
                }
            }
    }
}

extension View {
    func onboardingBlurIn(index: Int) -> some View {
        modifier(OnboardingBlurInModifier(index: index))
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var leadingSystemImage: String?
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                if let leadingSystemImage {
                    Image(systemName: leadingSystemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .buttonStyle(.montra(.primary, size: .large, width: .fixed(OnboardingLayout.buttonWidth)))
        .keyboardShortcut(.return, modifiers: [])
    }
}

struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.montra(.secondary, size: .large, width: .fixed(OnboardingLayout.buttonWidth)))
    }
}

// MARK: - Flow

/// First run: welcome, one real account, an optional first expense, and a short
/// celebration. Follows the reference onboarding: a centred column, 240 pt
/// buttons, steps that cross-fade with a blur, and no sidebar in the way.
struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\Category.sortIndex, order: .forward)]) private var categories: [Category]

    let onFinish: () -> Void

    @State private var step: OnboardingStep
    @State private var accountName: String
    @State private var currency: Currency
    @State private var accountIcon: String
    @State private var accountColor: PaletteColor
    @State private var showsStylePicker = false
    @State private var accountAmountText: String
    @State private var expenseAmountText: String
    @State private var categoryID: UUID?
    @State private var createdAccount: Account?
    @State private var createdExpense: Operation?
    @State private var selectedExpenses: Set<StarterCategory>
    @State private var selectedIncome: Set<StarterCategory>

    private let isPreview: Bool

    init(
        initialStep: OnboardingStep = .welcome,
        previewAccount: Account? = nil,
        previewExpense: Operation? = nil,
        isPreview: Bool = false,
        onFinish: @escaping () -> Void
    ) {
        self.onFinish = onFinish
        self.isPreview = isPreview
        _step = State(initialValue: initialStep)
        _createdAccount = State(initialValue: previewAccount)
        _createdExpense = State(initialValue: previewExpense)
        _accountName = State(initialValue: previewAccount?.name ?? "")
        _currency = State(initialValue: previewAccount?.currency ?? .byn)
        _accountIcon = State(initialValue: previewAccount?.iconName ?? "creditcard.fill")
        _accountColor = State(initialValue: previewAccount?.color ?? .blue)
        _accountAmountText = State(initialValue: previewAccount.map { Self.editable($0.initialAmount) } ?? "")
        _expenseAmountText = State(initialValue: previewExpense.map { Self.editable($0.amount) } ?? "")
        _categoryID = State(initialValue: previewExpense?.category?.id)
        _selectedExpenses = State(initialValue: SeedData.onboardingDefaultExpenses)
        _selectedIncome = State(initialValue: SeedData.onboardingDefaultIncome)
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.kind == .expense }.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var accountAmount: Decimal? {
        Self.parse(accountAmountText, allowZero: true)
    }

    private var expenseAmount: Decimal? {
        Self.parse(expenseAmountText, allowZero: false)
    }

    private var accountIsValid: Bool {
        !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && accountAmount != nil
    }

    private var expenseIsValid: Bool {
        createdAccount != nil && expenseAmount != nil && categoryID != nil
    }

    private var displayCurrency: Currency {
        createdAccount?.currency ?? currency
    }

    var body: some View {
        ZStack {
            AppColors.surfaceBase.ignoresSafeArea()

            VStack(spacing: 0) {
                stepBody
                    .id(step)
                    .transition(OnboardingTransitions.step(reduceMotion: reduceMotion))
                    .frame(maxWidth: OnboardingLayout.contentMaxWidth, maxHeight: .infinity)
                    .padding(.horizontal, OnboardingLayout.horizontalPadding)
                    .padding(.top, OnboardingLayout.verticalPadding)

                footer
                    .padding(.horizontal, OnboardingLayout.horizontalPadding)
                    .padding(.top, AppStyle.Spacing.medium)
                    .padding(.bottom, OnboardingLayout.verticalPadding)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: step)
        .frame(minWidth: AppWindowLayout.width, minHeight: AppWindowLayout.minHeight)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStepView()
        case .account:
            accountStep
        case .categories:
            categoriesStep
        case .expense:
            expenseStep
        case .done:
            OnboardingDoneStep(
                account: createdAccount,
                expense: createdExpense,
                isPreview: isPreview
            )
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: AppStyle.Spacing.small) {
            switch step {
            case .welcome:
                OnboardingPrimaryButton(title: String(localized: "common.get_started"), systemImage: "arrow.forward") {
                    advance(to: .account)
                }
            case .account:
                OnboardingPrimaryButton(title: String(localized: "common.create_account"), leadingSystemImage: "plus") {
                    createAccount()
                }
                .disabled(!accountIsValid)
            case .categories:
                OnboardingPrimaryButton(title: String(localized: "common.continue"), systemImage: "arrow.forward") {
                    commitCategories()
                }

                OnboardingSecondaryButton(title: String(localized: "common.skip")) {
                    skipCategories()
                }
            case .expense:
                OnboardingPrimaryButton(title: String(localized: "common.add_expense"), leadingSystemImage: "plus") {
                    addExpense()
                }
                .disabled(!expenseIsValid)

                OnboardingSecondaryButton(title: String(localized: "common.skip")) {
                    advance(to: .done)
                }
            case .done:
                OnboardingPrimaryButton(title: String(localized: "common.open_montra"), systemImage: "arrow.forward", action: onFinish)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: step)
    }

    // MARK: - Account

    private var accountStep: some View {
        VStack(spacing: AppStyle.Spacing.large) {
            VStack(spacing: AppStyle.Spacing.xSmall) {
                Text(String(localized: "onboarding.your_first_account"))
                    .font(AppStyle.Typography.title)
                    .multilineTextAlignment(.center)
                Text(String(localized: "onboarding.start_tracking_with_cash_a"))
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingBlurIn(index: 0)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                FormField(title: String(localized: "common.name")) {
                    HStack(spacing: AppStyle.Spacing.xSmall) {
                        Button {
                            showsStylePicker = true
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                IconTile(symbol: accountIcon, color: accountColor.tileColor, size: 36)
                                Image(systemName: "pencil")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(width: 14, height: 14)
                                    .background(AppColors.surfaceRaised, in: Circle())
                                    .overlay {
                                        Circle().strokeBorder(AppColors.borderStrong, lineWidth: 1)
                                    }
                                    .offset(x: 3, y: 3)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "onboarding.account_icon_and_color"))
                        .accessibilityLabel(String(localized: "onboarding.account_icon_and_color"))
                        .popover(isPresented: $showsStylePicker, arrowEdge: .bottom) {
                            OnboardingAccountStylePicker(icon: $accountIcon, color: $accountColor)
                        }

                        MontraTextField(placeholder: String(localized: "onboarding.for_example_cash"), text: $accountName)
                    }
                }

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                    FieldLabel(title: String(localized: "common.currency"))
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: AppStyle.Spacing.xSmall), count: 3),
                        spacing: AppStyle.Spacing.xSmall
                    ) {
                        ForEach(Currency.allCases) { item in
                            currencyChip(item)
                        }
                    }
                }

                FormField(title: String(localized: "common.current_balance")) {
                    HStack(spacing: AppStyle.Spacing.small) {
                        TextField("0", text: $accountAmountText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        // The slot is fixed so switching Br → USDT → ₿ never
                        // nudges the amount; only the glyph rolls.
                        ZStack(alignment: .trailing) {
                            Text(currency.symbol)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                                .id(currency)
                                .transition(.asymmetric(
                                    insertion: .offset(y: 7).combined(with: .opacity),
                                    removal: .offset(y: -7).combined(with: .opacity)
                                ))
                        }
                        .frame(width: 42, alignment: .trailing)
                        .animation(AppMotion.row, value: currency)
                        .accessibilityHidden(true)
                    }
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .frame(height: 44)
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
            .frame(width: OnboardingLayout.formWidth)
            .onboardingBlurIn(index: 1)

            Text(String(localized: "onboarding.your_data_stays_on_this"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .onboardingBlurIn(index: 2)
        }
    }

    private func currencyChip(_ item: Currency) -> some View {
        let isSelected = item == currency
        return Button {
            withAnimation(AppMotion.row) { currency = item }
        } label: {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                if item.symbol != item.code {
                    Text(item.symbol)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                Text(item.code)
                    .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
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
        .accessibilityLabel("\(item.code), \(item.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Categories

    private var expenseChoices: [SeedData.CategorySeed] {
        SeedData.expenseCategories.filter { $0.starter != .other }
    }

    private var incomeChoices: [SeedData.CategorySeed] {
        SeedData.incomeCategories.filter { $0.starter != .other }
    }

    private var categoriesStep: some View {
        VStack(spacing: AppStyle.Spacing.large) {
            VStack(spacing: AppStyle.Spacing.xSmall) {
                Text(String(localized: "common.your_categories"))
                    .font(AppStyle.Typography.title)
                    .multilineTextAlignment(.center)
                Text(String(localized: "onboarding.select_what_you_need_you"))
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingBlurIn(index: 0)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                categoryChoiceSection(
                    title: String(localized: "common.expenses"),
                    seeds: expenseChoices,
                    selection: $selectedExpenses
                )
                categoryChoiceSection(
                    title: String(localized: "common.income"),
                    seeds: incomeChoices,
                    selection: $selectedIncome
                )
            }
            .frame(width: OnboardingLayout.formWidth)
            .onboardingBlurIn(index: 1)

            Text(String(localized: "onboarding.well_add_other_for_expenses"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: OnboardingLayout.formWidth)
                .onboardingBlurIn(index: 2)
        }
    }

    private func categoryChoiceSection(
        title: String,
        seeds: [SeedData.CategorySeed],
        selection: Binding<Set<StarterCategory>>
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            FieldLabel(title: title)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppStyle.Spacing.xSmall), count: 3),
                spacing: AppStyle.Spacing.xSmall
            ) {
                ForEach(seeds, id: \.starter) { seed in
                    OnboardingCategoryChip(
                        name: seed.starter.displayName,
                        icon: seed.icon,
                        color: seed.color.color,
                        isSelected: selection.wrappedValue.contains(seed.starter)
                    ) {
                        withAnimation(AppMotion.row) {
                            if selection.wrappedValue.contains(seed.starter) {
                                selection.wrappedValue.remove(seed.starter)
                            } else {
                                selection.wrappedValue.insert(seed.starter)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Expense

    private var expenseStep: some View {
        VStack(spacing: AppStyle.Spacing.medium + 2) {
            VStack(spacing: AppStyle.Spacing.xSmall) {
                Text(String(localized: "onboarding.your_first_expense"))
                    .font(AppStyle.Typography.title)
                    .multilineTextAlignment(.center)
                Text(String(localized: "onboarding.record_an_expense_to_see"))
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingBlurIn(index: 0)

            if let account = createdAccount {
                HStack(spacing: AppStyle.Spacing.xSmall) {
                    IconTile(symbol: account.iconName, color: account.color.tileColor, size: 24)
                    Text(account.name)
                        .font(AppStyle.Typography.callout.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)
                    Text(MoneyFormat.string(account.balance, currency: account.currency, masked: settings.hideBalances))
                        .font(AppStyle.Typography.callout.numbers)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .onboardingBlurIn(index: 1)
            }

            HStack(spacing: AppStyle.Spacing.small) {
                TextField("0", text: $expenseAmountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(displayCurrency.symbol)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .frame(width: OnboardingLayout.formWidth, height: 52)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
            .onboardingBlurIn(index: 2)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                FieldLabel(title: String(localized: "common.category"))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AppStyle.Spacing.xSmall), count: 3),
                    spacing: AppStyle.Spacing.xSmall
                ) {
                    ForEach(expenseCategories) { category in
                        expenseCategoryChip(category)
                    }
                }
            }
            .frame(width: OnboardingLayout.formWidth)
            .onboardingBlurIn(index: 3)
        }
        .onAppear { prepareCategoryIfNeeded() }
    }

    private func expenseCategoryChip(_ category: Category) -> some View {
        OnboardingCategoryChip(
            name: category.displayName,
            icon: category.iconName,
            color: category.color.color,
            isSelected: category.id == categoryID
        ) {
            withAnimation(AppMotion.row) { categoryID = category.id }
        }
    }

    // MARK: - Actions

    private func prepareCategoryIfNeeded() {
        guard categoryID == nil else { return }
        let preferred = expenseCategories.first { $0.starterCategory == .food } ?? expenseCategories.first
        categoryID = preferred?.id
    }

    private func advance(to next: OnboardingStep) {
        if next == .expense { prepareCategoryIfNeeded() }
        if reduceMotion {
            step = next
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { step = next }
        }
    }

    private func commitCategories() {
        let chosen = SeedData.expenseCategories.filter {
            $0.starter != .other && selectedExpenses.contains($0.starter)
        } + SeedData.incomeCategories.filter {
            $0.starter != .other && selectedIncome.contains($0.starter)
        }
        createCategories(chosen)
    }

    private func skipCategories() {
        createCategories([])
    }

    private func createCategories(_ chosen: [SeedData.CategorySeed]) {
        SeedData.createStarterCategories(context: context, selected: chosen)
        refreshExpenseCategorySelection()
        advance(to: .expense)
    }

    /// The new rows are already in the store, so pick the first expense
    /// category by fetching instead of waiting for the @Query to refresh.
    private func refreshExpenseCategorySelection() {
        let all = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let expense = all
            .filter { $0.kind == .expense }
            .sorted { $0.sortIndex < $1.sortIndex }
        categoryID = (expense.first { $0.starterCategory == .food } ?? expense.first)?.id
    }

    private func createAccount() {
        guard let amount = accountAmount, accountIsValid, createdAccount == nil else { return }
        let repository = AccountRepository(context: context)
        let account = repository.create(
            name: accountName,
            currency: currency,
            initialAmount: amount,
            iconName: accountIcon,
            color: accountColor
        )
        createdAccount = account
        settings.primaryCurrency = currency
        advance(to: .categories)
    }

    private func addExpense() {
        guard let account = createdAccount,
              let amount = expenseAmount,
              let category = categories.first(where: { $0.id == categoryID }) else { return }

        let operation = OperationRepository(context: context).create(
            kind: .expense,
            amount: amount,
            account: account,
            category: category,
            date: .now,
            place: "",
            latitude: nil,
            longitude: nil,
            note: ""
        )
        createdExpense = operation
        advance(to: .done)
    }

    // MARK: - Parsing

    private static func parse(_ text: String, allowZero: Bool) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty {
            return allowZero ? 0 : nil
        }
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if allowZero { return value >= 0 ? value : nil }
        return value > 0 ? value : nil
    }

    private static func editable(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}

enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case account
    case categories
    case expense
    case done
}

// MARK: - Welcome

private struct OnboardingWelcomeStepView: View {
    var body: some View {
        VStack(spacing: AppStyle.Spacing.xLarge) {
            MontraArtwork(size: 148)
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
                .onboardingBlurIn(index: 0)

            VStack(spacing: -AppStyle.Spacing.xxSmall) {
                Text(String(localized: "common.welcome_to"))
                    .font(AppStyle.Typography.sectionTitle.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.8))
                Text(String(localized: "common.montra"))
                    .font(AppStyle.Typography.displayLarge.weight(.semibold))
            }
            .multilineTextAlignment(.center)
            .onboardingBlurIn(index: 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "onboarding.welcome_to_montra"))

            Text(String(localized: "onboarding.track_accounts_in_multiple_currencies"))
                .font(AppStyle.Typography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
                .onboardingBlurIn(index: 2)
        }
    }
}

// MARK: - Done

private struct OnboardingDoneStep: View {
    let account: Account?
    let expense: Operation?
    let isPreview: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedBalance: Double = 0
    @State private var sparkleAppeared = false
    @State private var sparkleBreathe = false

    private var targetBalance: Decimal {
        account?.balance ?? 0
    }

    private var balanceText: String {
        guard let account else { return "0" }
        return MoneyFormat.string(Decimal(animatedBalance), currency: account.currency)
    }

    var body: some View {
        VStack(spacing: AppStyle.Spacing.large) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(sparkleAppeared ? 1 : 0.55)
                .scaleEffect(sparkleBreathe ? 1.06 : 1)
                .rotationEffect(.degrees(sparkleBreathe ? 2.5 : -2.5))
                .shadow(
                    color: AppColors.textPrimary.opacity(sparkleBreathe ? 0.18 : 0.02),
                    radius: sparkleBreathe ? 14 : 4
                )
                .onAppear(perform: animateSparkles)
                .onboardingBlurIn(index: 0)
                .accessibilityHidden(true)

            VStack(spacing: AppStyle.Spacing.xxxSmall) {
                Text(account?.name ?? String(localized: "common.account"))
                    .font(AppStyle.Typography.sectionTitle.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)

                Text(balanceText)
                    .font(AppStyle.Typography.displayLarge.numbers)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(String(localized: "account.in_this_account"))
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .onboardingBlurIn(index: 1)

            InsetCard {
                if let account {
                    doneRow(
                        symbol: account.iconName,
                        color: account.color.tileColor,
                        title: account.name,
                        detail: String(localized: "common.account_created"),
                        value: account.currency.code
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: OnboardingHeroSourceKey.self,
                                value: OnboardingHeroFrame(
                                    accountID: account.id,
                                    rect: proxy.frame(in: .named(OnboardingHero.coordinateSpace))
                                )
                            )
                        }
                    }
                }
                if let expense {
                    InsetCardDivider()
                    doneRow(
                        symbol: expense.category?.iconName ?? "cart.fill",
                        color: expense.category?.color.tileColor ?? AppColors.Chart.neutralTile,
                        title: expense.category?.displayName ?? String(localized: "transaction.expense"),
                        detail: String(localized: "onboarding.your_first_expense"),
                        value: expense.amountText()
                    )
                }
            }
            .frame(width: OnboardingLayout.formWidth)
            .onboardingBlurIn(index: 2)

            Text(expense == nil
                 ? String(localized: "onboarding.your_account_is_ready_you")
                 : String(localized: "onboarding.youre_ready_to_add_transactions"))
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
                .onboardingBlurIn(index: 3)
        }
        .onAppear(perform: animateBalance)
    }

    private func animateSparkles() {
        guard !reduceMotion else {
            sparkleAppeared = true
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.64)) {
            sparkleAppeared = true
        }
        withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true).delay(0.3)) {
            sparkleBreathe = true
        }
    }

    private func doneRow(symbol: String, color: Color, title: String, detail: String, value: String) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(title)
                    .font(AppStyle.Typography.headline)
                    .lineLimit(1)
                Text(detail)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppStyle.Spacing.small)
            Text(value)
                .font(AppStyle.Typography.callout.weight(.medium).numbers)
                .monospacedDigit()
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    private func animateBalance() {
        let target = (targetBalance as NSDecimalNumber).doubleValue
        guard !isPreview, !reduceMotion else {
            animatedBalance = target
            return
        }
        animatedBalance = 0
        withAnimation(.easeOut(duration: 0.85)) { animatedBalance = target }
    }
}

/// Compact icon + colour editor used by the first-account step. The full grids
/// live in the account sheet; here they fit in a popover anchored to the tile,
/// so the onboarding column never grows past the window.
private struct OnboardingAccountStylePicker: View {
    @Binding var icon: String
    @Binding var color: PaletteColor

    private let colorColumns = Array(repeating: GridItem(.fixed(28), spacing: AppStyle.Spacing.xSmall), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(String(localized: "onboarding.icon_and_color"))
                .font(AppStyle.Typography.headline)

            IconPicker(selection: $icon)

            Text(String(localized: "common.color"))
                .font(AppStyle.Typography.metadataEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, AppStyle.Spacing.xxxSmall)

            LazyVGrid(columns: colorColumns, alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                ForEach(PaletteColor.allCases) { item in
                    Button {
                        color = item
                    } label: {
                        Circle()
                            .fill(item.tileColor)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                            }
                            .overlay {
                                if color == item {
                                    Circle()
                                        .inset(by: -3)
                                        .strokeBorder(AppColors.textPrimary, lineWidth: 2)
                                }
                            }
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                    .help(item.title)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(color == item ? .isSelected : [])
                }
            }
        }
        .padding(AppStyle.Spacing.medium)
        .frame(width: 360)
    }
}

/// A category capsule shared by the onboarding selection step and the first
/// expense step, so both are the same control.
private struct OnboardingCategoryChip: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : color)
                Text(name)
                    .font(AppStyle.Typography.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .padding(.horizontal, AppStyle.Spacing.xxSmallPlus)
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
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
