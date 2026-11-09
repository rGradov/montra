import Foundation
import SwiftData

/// Runs on the same context as the app so successful writes update open views.
@MainActor
final class SpotlightLedger {
    private let context: ModelContext
    private let settings: SettingsStore
    private let rates: RateStore
    private let available: Bool

    init(context: ModelContext, settings: SettingsStore, rates: RateStore, available: Bool = true) {
        self.context = context
        self.settings = settings
        self.rates = rates
        self.available = available
    }

    func accounts() throws -> [Account] {
        try requireStore()
        return try context.fetch(FetchDescriptor<Account>(sortBy: [.init(\.sortIndex), .init(\.name)]))
    }

    func categories() throws -> [Category] {
        try requireStore()
        return try context.fetch(FetchDescriptor<Category>(sortBy: [.init(\.sortIndex), .init(\.name)]))
    }

    func createAccount(name: String, currency: Currency, initialAmount: Decimal) throws {
        let name = try validatedName(name)
        try validateAmount(initialAmount, currency: currency, allowZero: true)
        try save {
            AccountRepository(context: context).create(
                name: name, currency: currency, initialAmount: initialAmount,
                iconName: "creditcard.fill", color: .blue, saveImmediately: false
            )
        }
    }

    func createCategory(name: String, kind: OperationKind, isMandatory: Bool) throws {
        try createCategory(name: name, kind: kind, isMandatory: isMandatory, parent: nil)
    }

    func createSubcategory(name: String, parentID: UUID) throws {
        let parent = try category(id: parentID)
        guard parent.parent == nil else { throw SpotlightLedgerError.invalidParent }
        try createCategory(name: name, kind: parent.kind, isMandatory: false, parent: parent)
    }

    private func createCategory(name: String, kind: OperationKind, isMandatory: Bool, parent: Category?) throws {
        let name = try validatedName(name)
        try save {
            CategoryRepository(context: context).create(
                name: name, kind: kind, color: kind == .expense ? .orange : .green,
                iconName: kind == .expense ? "fork.knife" : "banknote.fill",
                isMandatory: isMandatory, parent: parent, saveImmediately: false
            )
        }
    }

    func createOperation(kind: OperationKind, amount: Decimal, accountID: UUID, categoryID: UUID) throws {
        let account = try account(id: accountID)
        let category = try category(id: categoryID)
        guard category.kind == kind else { throw SpotlightLedgerError.categoryKind }
        try validateAmount(amount, currency: account.currency)
        try save {
            OperationRepository(context: context).create(
                kind: kind, amount: amount, account: account, category: category, date: .now,
                place: "", latitude: nil, longitude: nil, note: "", saveImmediately: false
            )
        }
    }

    func transfer(from sourceID: UUID, to destinationID: UUID, sent: Decimal, received: Decimal?) throws {
        guard sourceID != destinationID else { throw SpotlightLedgerError.sameAccount }
        let source = try account(id: sourceID)
        let destination = try account(id: destinationID)
        try validateAmount(sent, currency: source.currency)
        guard let credited = received ?? (source.currency == destination.currency ? sent : nil) else {
            throw SpotlightLedgerError.receivedRequired
        }
        try validateAmount(credited, currency: destination.currency)
        try save {
            TransferRepository(context: context).create(
                from: source, to: destination, sent: sent, received: credited, saveImmediately: false
            )
        }
    }

    func balance(id: UUID) throws -> SpotlightBalance {
        balanceRow(for: try account(id: id))
    }

    func overview(currency: Currency?) throws -> SpotlightOverview {
        let accounts = try accounts()
        let currencies = Finance.currencies(in: accounts)
        let primary = settings.primaryCurrency
        let target = currency ?? (currencies.contains(primary) ? primary : currencies.first ?? primary)
        let table = rates.rates
        let missing = currencies.filter { table.convert(1, from: $0, to: target) == nil }
        let total = Finance.totalConverted(accounts, to: target, rates: table)
        return SpotlightOverview(
            accounts: accounts.map(balanceRow),
            total: settings.money(total, currency: target),
            missingCurrencies: missing.map(\.code),
            usesApproximateRates: table.source.isApproximate && currencies.contains { $0 != target }
        )
    }

    private func balanceRow(for account: Account) -> SpotlightBalance {
        SpotlightBalance(
            id: account.id, name: account.name,
            amount: settings.money(Finance.balance(of: account), currency: account.currency)
        )
    }

    private func account(id: UUID) throws -> Account {
        try requireStore()
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        guard let account = try context.fetch(descriptor).first else { throw SpotlightLedgerError.accountMissing }
        return account
    }

    private func category(id: UUID) throws -> Category {
        try requireStore()
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        guard let category = try context.fetch(descriptor).first else { throw SpotlightLedgerError.categoryMissing }
        return category
    }

    private func requireStore() throws {
        guard available else { throw SpotlightLedgerError.storeUnavailable }
    }

    private func save(_ insert: () -> Void) throws {
        try requireStore()
        guard settings.hasCompletedOnboarding else { throw SpotlightLedgerError.setupRequired }
        guard !context.hasChanges else { throw SpotlightLedgerError.unsavedChanges }

        // Only the new records belong to this action. Never roll back an open edit.
        insert()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw SpotlightLedgerError.saveFailed
        }
    }

    private func validatedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SpotlightLedgerError.emptyName }
        return name
    }

    // Use a text parameter in Spotlight to keep amounts exact at the point of entry.
    static func parseAmount(_ text: String) throws -> Decimal {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard input.range(of: #"\A[0-9]{1,18}(\.[0-9]{1,8})?\z"#, options: .regularExpression) != nil,
              let amount = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")) else {
            throw SpotlightLedgerError.amountFormat
        }
        return amount
    }

    private func validateAmount(_ value: Decimal, currency: Currency, allowZero: Bool = false) throws {
        guard value.isFinite, allowZero ? value >= 0 : value > 0 else {
            throw SpotlightLedgerError.invalidAmount(allowZero: allowZero)
        }
        var input = value
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &input, currency.fractionDigits, .plain)
        guard rounded == value else { throw SpotlightLedgerError.amountPrecision(currency) }
    }
}

struct SpotlightBalance: Identifiable {
    let id: UUID
    let name: String
    let amount: String
}

struct SpotlightOverview {
    let accounts: [SpotlightBalance]
    let total: String
    let missingCurrencies: [String]
    let usesApproximateRates: Bool
}

enum SpotlightLedgerError: LocalizedError {
    case storeUnavailable, setupRequired, unsavedChanges, saveFailed
    case accountMissing, categoryMissing, categoryKind, invalidParent, emptyName
    case sameAccount, receivedRequired, amountFormat, invalidAmount(allowZero: Bool), amountPrecision(Currency)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable: String(localized: "spotlight.error.the_montra_data_store_is")
        case .setupRequired: String(localized: "spotlight.error.finish_setting_up_montra_first")
        case .unsavedChanges: String(localized: "spotlight.error.montra_has_unsaved_changes_finish")
        case .saveFailed: String(localized: "spotlight.error.couldnt_save_the_data_in")
        case .accountMissing: String(localized: "spotlight.error.account_not_found_choose_a")
        case .categoryMissing: String(localized: "spotlight.error.category_not_found_choose_a")
        case .categoryKind: String(localized: "spotlight.error.choose_a_category_of_the")
        case .invalidParent: String(localized: "spotlight.error.choose_a_top_level_category")
        case .emptyName: String(localized: "spotlight.error.enter_a_name")
        case .sameAccount: String(localized: "spotlight.error.choose_two_different_accounts")
        case .receivedRequired: String(localized: "spotlight.error.enter_the_amount_received_when")
        case .amountFormat: String(localized: "spotlight.error.enter_the_amount_in_digits")
        case .invalidAmount(let allowZero):
            allowZero ? String(localized: "spotlight.error.the_amount_must_be_zero") : String(localized: "spotlight.error.the_amount_must_be_greater")
        case .amountPrecision(let currency):
            String(localized: "spotlight.error.enter_an_amount_in_with \(currency.code) \(currency.fractionDigits)")
        }
    }
}
