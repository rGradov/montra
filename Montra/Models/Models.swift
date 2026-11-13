import Foundation
import SwiftData
import SwiftUI

// Every model is CloudKit-safe: attributes carry defaults, relationships are
// optional and inverses are declared, and there are no unique constraints. When
// the iCloud container is switched on, these records upload as they are.

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var currencyRaw: String = Currency.byn.rawValue
    var initialAmount: Decimal = 0
    /// Money the person keeps rather than spends. It still accepts deposits and
    /// withdrawals; the flag only labels the account for savings totals and,
    /// later, savings dynamics in analytics.
    var isSavings: Bool = false
    /// Keeps the account out of the Overview's total, bar and list without
    /// touching the money: the sidebar, the account page and analytics still
    /// show it, and operations stay attached to it as usual.
    var isHiddenFromOverview: Bool = false
    var iconName: String = "creditcard.fill"
    var colorRaw: String = PaletteColor.blue.rawValue
    var createdAt: Date = Date()
    var sortIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Operation.account)
    var operations: [Operation]? = []

    /// Planned payments that point at this account. Declared here only to give
    /// `PlannedOperation.account` the inverse CloudKit mirroring requires.
    @Relationship(deleteRule: .nullify, inverse: \PlannedOperation.account)
    var plannedOperations: [PlannedOperation]? = []

    init(
        name: String,
        currency: Currency,
        initialAmount: Decimal,
        iconName: String,
        color: PaletteColor,
        isSavings: Bool = false,
        isHiddenFromOverview: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.name = name
        self.currencyRaw = currency.rawValue
        self.initialAmount = initialAmount
        self.isSavings = isSavings
        self.isHiddenFromOverview = isHiddenFromOverview
        self.iconName = iconName
        self.colorRaw = color.rawValue
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .byn }
        set { currencyRaw = newValue.rawValue }
    }

    var color: PaletteColor {
        get { PaletteColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var sortedOperations: [Operation] {
        (operations ?? []).sorted { $0.date > $1.date }
    }

    /// Initial amount plus every income, minus every expense on this account.
    var balance: Decimal {
        (operations ?? []).reduce(initialAmount) { $0 + $1.signedAmount }
    }

    var operationCount: Int {
        operations?.count ?? 0
    }
}

enum StarterCategory: String, CaseIterable {
    case housing, food, transport, health, restaurants, entertainment, shopping, subscriptions
    case salary, freelance, gifts, investments, other

    private var localizationKey: String { "category.starter.\(rawValue)" }

    var displayName: String {
        Bundle.main.localizedString(forKey: localizationKey, value: storedName, table: nil)
    }

    // Keep the original persisted names so existing stores and the local API keep
    // the same identifiers even when macOS changes the app language.
    var storedName: String { Self.storedNames[self]! }

    private static let storedNames: [Self: String] = {
        return Dictionary(uniqueKeysWithValues: allCases.map { category in
            let name = AppLocalization.russianBundle.localizedString(forKey: category.localizationKey, value: nil, table: nil)
            return (category, name)
        })
    }()

    static func matching(storedName: String) -> Self? {
        storedNames.first { $0.value == storedName }?.key
    }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = OperationKind.expense.rawValue
    var colorRaw: String = PaletteColor.orange.rawValue
    var iconName: String = "tag.fill"
    var isMandatory: Bool = false
    var isSystem: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Operation.category)
    var operations: [Operation]? = []

    /// Inverse for `PlannedOperation.category`, required by CloudKit mirroring.
    @Relationship(deleteRule: .nullify, inverse: \PlannedOperation.category)
    var plannedOperations: [PlannedOperation]? = []
    /// One level of nesting is enough: a category may sit under a top-level one.
    var parent: Category?
    @Relationship(inverse: \Category.parent) var children: [Category]? = []

    init(
        name: String,
        kind: OperationKind,
        color: PaletteColor,
        iconName: String,
        isMandatory: Bool = false,
        isSystem: Bool = false,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorRaw = color.rawValue
        self.iconName = iconName
        self.isMandatory = isMandatory
        self.isSystem = isSystem
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    var starterCategory: StarterCategory? {
        isSystem ? StarterCategory.matching(storedName: name) : nil
    }

    var displayName: String {
        starterCategory?.displayName ?? name
    }

    var kind: OperationKind {
        get { OperationKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var color: PaletteColor {
        get { PaletteColor(rawValue: colorRaw) ?? .orange }
        set { colorRaw = newValue.rawValue }
    }

    var operationCount: Int {
        operations?.count ?? 0
    }
}

@Model
final class Operation {
    var id: UUID = UUID()
    var kindRaw: String = OperationKind.expense.rawValue
    var amount: Decimal = 0
    /// The account's currency at the moment the operation was made. Kept on the
    /// record so history stays readable if an account changes later.
    var currencyRaw: String = Currency.byn.rawValue
    var date: Date = Date()
    var place: String = ""
    var latitude: Double?
    var longitude: Double?
    var note: String = ""
    var createdAt: Date = Date()
    var account: Account?
    var category: Category?
    /// Both legs of a transfer share this id; nil for ordinary operations.
    var transferID: UUID?

    init(
        kind: OperationKind,
        amount: Decimal,
        currency: Currency,
        date: Date,
        place: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        note: String = "",
        account: Account?,
        category: Category?
    ) {
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currencyRaw = currency.rawValue
        self.date = date
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
        self.account = account
        self.category = category
        self.createdAt = .now
    }

    var kind: OperationKind {
        get { OperationKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .byn }
        set { currencyRaw = newValue.rawValue }
    }

    var isTransfer: Bool { transferID != nil }

    /// Positive for income, negative for expense.
    var signedAmount: Decimal {
        kind == .income ? amount : -amount
    }

    /// "−1 240,50 Br" for an expense, "+4 200,00 Br" for income.
    func amountText(masked: Bool = false) -> String {
        MoneyFormat.string(signedAmount, currency: currency, sign: .always, masked: masked)
    }

    /// The line under the title: account, then place or note when present.
    var detailText: String {
        var parts: [String] = []
        if let account { parts.append(account.name) }
        if !place.isEmpty { parts.append(place) }
        else if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

@Model
final class Period {
    var id: UUID = UUID()
    /// Start of the first day, local midnight.
    var start: Date = Date()
    /// End of the last day, inclusive.
    var end: Date = Date()
    /// True once the user moved a boundary by hand; regeneration keeps these.
    var isManual: Bool = false
    var createdAt: Date = Date()

    init(start: Date, end: Date, isManual: Bool = false) {
        self.start = start
        self.end = end
        self.isManual = isManual
        self.createdAt = .now
    }

    var days: Int { AppDate.daysBetween(start, end) }

    var title: String { AppDate.range(start, end) }

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

// MARK: - Queries used across screens

extension Operation {
    /// Newest first, with a stable tie-break so rows don't shuffle between edits.
    static func sorted(_ operations: [Operation]) -> [Operation] {
        operations.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.createdAt > $1.createdAt
        }
    }
}
