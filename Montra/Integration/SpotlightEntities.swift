import AppIntents
import Foundation

extension Currency: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "common.currency"
    static let caseDisplayRepresentations: [Currency: DisplayRepresentation] = [
        .byn: "BYN", .eur: "EUR", .usd: "USD", .usdc: "USDC", .usdt: "USDT", .btc: "BTC", .eth: "ETH"
    ]
}

extension OperationKind: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "common.category_type"
    static let caseDisplayRepresentations: [OperationKind: DisplayRepresentation] = [
        .expense: "transaction.expense", .income: "transaction.income"
    ]
}

@available(macOS 26.0, *)
struct SpotlightAccount: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "common.montra_account"
    static let defaultQuery = SpotlightAccountQuery()

    let id: UUID
    let name: String
    let currency: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(currency)")
    }

    @MainActor
    init(_ account: Account) {
        id = account.id
        name = account.name
        currency = account.currency.code
    }
}

@available(macOS 26.0, *)
struct SpotlightAccountQuery: EntityStringQuery {
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func suggestedEntities() async throws -> [SpotlightAccount] {
        try ledger.accounts().map(SpotlightAccount.init)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SpotlightAccount] {
        let accounts = try await suggestedEntities()
        let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { byID[$0] }
    }

    @MainActor
    func entities(matching string: String) async throws -> [SpotlightAccount] {
        let accounts = try await suggestedEntities()
        guard !string.isEmpty else { return accounts }
        return accounts.filter {
            $0.name.localizedStandardContains(string) || $0.currency.localizedStandardContains(string)
        }
    }
}

@available(macOS 26.0, *)
struct SpotlightCategory: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "common.montra_category"
    static let defaultQuery = SpotlightCategoryQuery()

    let id: UUID
    let name: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    @MainActor
    init(_ category: Category) {
        id = category.id
        name = category.displayName
        subtitle = [category.kind.title, category.parent?.displayName].compactMap { $0 }.joined(separator: " · ")
    }
}

@available(macOS 26.0, *)
protocol SpotlightCategoryPickingQuery: EntityStringQuery {
    var ledger: SpotlightLedger { get }
    static func includes(_ category: Category) -> Bool
}

@available(macOS 26.0, *)
extension SpotlightCategoryPickingQuery {
    @MainActor
    func suggestedEntities() async throws -> [SpotlightCategory] {
        try matchingCategories()
    }

    @MainActor
    private func matchingCategories() throws -> [SpotlightCategory] {
        try ledger.categories().filter(Self.includes).map(SpotlightCategory.init)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SpotlightCategory] {
        let categories = try matchingCategories()
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { byID[$0] }
    }

    @MainActor
    func entities(matching string: String) async throws -> [SpotlightCategory] {
        let categories = try matchingCategories()
        guard !string.isEmpty else { return categories }
        return categories.filter {
            $0.name.localizedStandardContains(string) || $0.subtitle.localizedStandardContains(string)
        }
    }
}

@available(macOS 26.0, *)
struct SpotlightCategoryQuery: SpotlightCategoryPickingQuery {
    typealias Entity = SpotlightCategory
    typealias Result = [SpotlightCategory]
    @Dependency var ledger: SpotlightLedger
    static func includes(_ category: Category) -> Bool { true }
}

@available(macOS 26.0, *)
struct SpotlightExpenseCategoryQuery: SpotlightCategoryPickingQuery {
    typealias Entity = SpotlightCategory
    typealias Result = [SpotlightCategory]
    @Dependency var ledger: SpotlightLedger
    static func includes(_ category: Category) -> Bool { category.kind == .expense }
}

@available(macOS 26.0, *)
struct SpotlightIncomeCategoryQuery: SpotlightCategoryPickingQuery {
    typealias Entity = SpotlightCategory
    typealias Result = [SpotlightCategory]
    @Dependency var ledger: SpotlightLedger
    static func includes(_ category: Category) -> Bool { category.kind == .income }
}

@available(macOS 26.0, *)
struct SpotlightParentCategoryQuery: SpotlightCategoryPickingQuery {
    typealias Entity = SpotlightCategory
    typealias Result = [SpotlightCategory]
    @Dependency var ledger: SpotlightLedger
    static func includes(_ category: Category) -> Bool { category.parent == nil }
}
