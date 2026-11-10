import Foundation
import SwiftData

/// The starting state: a set of categories every account can use, and — on the
/// very first launch only — a small, believable month of money so the app never
/// opens on an empty canvas. Both can be reset from Settings.
@MainActor
enum SeedData {
    struct CategorySeed {
        let starter: StarterCategory
        let kind: OperationKind
        let icon: String
        let color: PaletteColor
        let mandatory: Bool
    }

    static let expenseCategories: [CategorySeed] = [
        .init(starter: .housing, kind: .expense, icon: "house.fill", color: .blue, mandatory: true),
        .init(starter: .food, kind: .expense, icon: "cart.fill", color: .green, mandatory: true),
        .init(starter: .transport, kind: .expense, icon: "tram.fill", color: .teal, mandatory: true),
        .init(starter: .health, kind: .expense, icon: "cross.case.fill", color: .red, mandatory: true),
        .init(starter: .restaurants, kind: .expense, icon: "fork.knife", color: .orange, mandatory: false),
        .init(starter: .entertainment, kind: .expense, icon: "gamecontroller.fill", color: .purple, mandatory: false),
        .init(starter: .shopping, kind: .expense, icon: "bag.fill", color: .pink, mandatory: false),
        .init(starter: .subscriptions, kind: .expense, icon: "repeat.circle.fill", color: .amber, mandatory: false),
        .init(starter: .other, kind: .expense, icon: "ellipsis.circle.fill", color: .graphite, mandatory: false),
    ]

    static let incomeCategories: [CategorySeed] = [
        .init(starter: .salary, kind: .income, icon: "banknote.fill", color: .green, mandatory: false),
        .init(starter: .freelance, kind: .income, icon: "laptopcomputer", color: .blue, mandatory: false),
        .init(starter: .gifts, kind: .income, icon: "gift.fill", color: .pink, mandatory: false),
        .init(starter: .investments, kind: .income, icon: "chart.line.uptrend.xyaxis", color: .amber, mandatory: false),
        .init(starter: .other, kind: .income, icon: "ellipsis.circle.fill", color: .graphite, mandatory: false),
    ]

    /// What the onboarding pre-selects: the three rows a budget starts with.
    /// Transport and Health stay unselected there even though they count as
    /// mandatory for the budget math.
    static let onboardingDefaultExpenses: Set<StarterCategory> = [.housing, .food]
    static let onboardingDefaultIncome: Set<StarterCategory> = [.salary]

    static var onboardingDefaults: [CategorySeed] {
        expenseCategories.filter { onboardingDefaultExpenses.contains($0.starter) }
            + incomeCategories.filter { onboardingDefaultIncome.contains($0.starter) }
    }

    static func bootstrap(context: ModelContext, settings: SettingsStore) {
        ensureCategories(context: context)
        // Demo rows are opt-in from Settings now: a first launch belongs to the
        // onboarding, which creates a real account instead of five fake ones.
        PeriodService.ensurePeriods(context: context, settings: settings)
    }

    /// Creates the default categories once, leaving any edits the user made.
    static func ensureCategories(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        guard existing.isEmpty else { return }
        insertCategories(context: context)
        try? context.save()
    }

    /// Creates only the categories picked during onboarding, plus the "Other"
    /// fallback of each kind. The fallback is what the first expense uses when
    /// the person skips the step, and what category deletion falls back to.
    static func createStarterCategories(context: ModelContext, selected: [CategorySeed]) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        var seeds = selected
        if let expenseFallback = expenseCategories.first(where: { $0.starter == .other }) {
            seeds.append(expenseFallback)
        }
        if let incomeFallback = incomeCategories.first(where: { $0.starter == .other }) {
            seeds.append(incomeFallback)
        }

        var seen = Set<String>()
        for seed in seeds {
            let key = "\(seed.kind.rawValue)-\(seed.starter.rawValue)"
            guard seen.insert(key).inserted else { continue }
            guard !existing.contains(where: { $0.kind == seed.kind && $0.name == seed.starter.storedName }) else { continue }

            let list = seed.kind == .expense ? expenseCategories : incomeCategories
            let sortIndex = list.firstIndex { $0.starter == seed.starter } ?? list.count
            context.insert(Category(
                name: seed.starter.storedName,
                kind: seed.kind,
                color: seed.color,
                iconName: seed.icon,
                isMandatory: seed.kind == .expense ? seed.mandatory : false,
                isSystem: true,
                sortIndex: sortIndex
            ))
        }
        try? context.save()
    }

    private static func insertCategories(context: ModelContext) {
        for (index, seed) in expenseCategories.enumerated() {
            context.insert(Category(
                name: seed.starter.storedName,
                kind: seed.kind,
                color: seed.color,
                iconName: seed.icon,
                isMandatory: seed.mandatory,
                isSystem: true,
                sortIndex: index
            ))
        }
        for (index, seed) in incomeCategories.enumerated() {
            context.insert(Category(
                name: seed.starter.storedName,
                kind: seed.kind,
                color: seed.color,
                iconName: seed.icon,
                isMandatory: false,
                isSystem: true,
                sortIndex: index
            ))
        }
    }

    static func seedDemo(context: ModelContext, settings: SettingsStore) {
        let accounts = makeAccounts(context: context)
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        func category(_ starter: StarterCategory) -> Category? {
            categories.first { $0.starterCategory == starter }
        }

        func day(_ offset: Int, hour: Int, minute: Int) -> Date {
            let calendar = Calendar.current
            let base = calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        let card = accounts["card"]
        let cash = accounts["cash"]
        let revolut = accounts["revolut"]
        let crypto = accounts["crypto"]

        let seeds: [(OperationKind, Decimal, Account?, Category?, Date, String, String)] = [
            (.income, 4200, card, category(.salary), day(-8, hour: 9, minute: 12), "", String(localized: "demo.october_salary")),
            (.expense, 950, card, category(.housing), day(-7, hour: 10, minute: 0), String(localized: "demo.landlord"), ""),
            (.expense, 214.30, card, category(.food), day(-6, hour: 18, minute: 40), "Green", ""),
            (.expense, 12.50, cash, category(.restaurants), day(-5, hour: 9, minute: 5), String(localized: "demo.local_coffee_shop"), ""),
            (.expense, 38, card, category(.transport), day(-5, hour: 8, minute: 30), "", String(localized: "demo.transit_pass")),
            (.expense, 9.99, revolut, category(.subscriptions), day(-4, hour: 12, minute: 0), "", "iCloud+"),
            (.expense, 86.40, card, category(.restaurants), day(-3, hour: 20, minute: 15), "Gastrobar", ""),
            (.expense, 24.80, card, category(.health), day(-2, hour: 17, minute: 25), String(localized: "demo.pharmacy_36_6"), ""),
            (.income, 300, crypto, category(.freelance), day(-2, hour: 14, minute: 0), "", String(localized: "demo.landing_page")),
            (.expense, 18.90, cash, category(.transport), day(-1, hour: 23, minute: 40), String(localized: "demo.city_center"), ""),
            (.expense, 64.20, card, category(.food), day(-1, hour: 12, minute: 10), "Green", ""),
            (.expense, 26, card, category(.entertainment), day(0, hour: 19, minute: 0), "Silver Screen", ""),
            (.income, 100, card, category(.gifts), day(-10, hour: 15, minute: 0), "", String(localized: "demo.birthday_gift")),
        ]

        for seed in seeds {
            guard let account = seed.2 else { continue }
            let operation = Operation(
                kind: seed.0,
                amount: seed.1,
                currency: account.currency,
                date: seed.4,
                place: seed.5,
                note: seed.6,
                account: account,
                category: seed.3
            )
            context.insert(operation)
        }

        try? context.save()
        PeriodService.ensurePeriods(context: context, settings: settings)
    }

    private static func makeAccounts(context: ModelContext) -> [String: Account] {
        let seeds: [(id: String, name: String, currency: Currency, amount: Decimal, icon: String, color: PaletteColor)] = [
            ("cash", String(localized: "demo.cash"), .byn, 420, "banknote.fill", .green),
            ("card", String(localized: "demo.card"), .byn, 3150, "creditcard.fill", .blue),
            ("revolut", "Revolut", .eur, 480, "building.columns.fill", .sky),
            ("crypto", String(localized: "demo.crypto"), .usdt, 1250, "bitcoinsign.circle.fill", .amber),
            ("savings", String(localized: "demo.savings"), .btc, 0.0128, "lock.fill", .orange),
        ]
        var result: [String: Account] = [:]
        for (index, seed) in seeds.enumerated() {
            let account = Account(
                name: seed.name,
                currency: seed.currency,
                initialAmount: seed.amount,
                iconName: seed.icon,
                color: seed.color,
                isSavings: seed.id == "savings",
                sortIndex: index
            )
            context.insert(account)
            result[seed.id] = account
        }
        return result
    }

    /// Empties the app without adding demo rows back.
    static func clearEverything(context: ModelContext, settings: SettingsStore) {
        for operation in (try? context.fetch(FetchDescriptor<Operation>())) ?? [] { context.delete(operation) }
        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] { context.delete(account) }
        for category in (try? context.fetch(FetchDescriptor<Category>())) ?? [] { context.delete(category) }
        for period in (try? context.fetch(FetchDescriptor<Period>())) ?? [] { context.delete(period) }
        for plan in (try? context.fetch(FetchDescriptor<PlannedOperation>())) ?? [] { context.delete(plan) }
        try? context.save()

        settings.didSeedDemo = true
        settings.hasCompletedOnboarding = false
        PeriodService.ensurePeriods(context: context, settings: settings)
    }
}
