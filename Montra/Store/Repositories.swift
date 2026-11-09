import Foundation
import SwiftData

/// Every write goes through one of these, so a sync engine has a single place
/// to observe changes later instead of chasing `context.insert` calls in views.
@MainActor
struct AccountRepository {
    let context: ModelContext

    @discardableResult
    func create(
        name: String, currency: Currency, initialAmount: Decimal, iconName: String, color: PaletteColor,
        isSavings: Bool = false, isHiddenFromOverview: Bool = false, saveImmediately: Bool = true
    ) -> Account {
        let account = Account(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currency,
            initialAmount: initialAmount,
            iconName: iconName,
            color: color,
            isSavings: isSavings,
            isHiddenFromOverview: isHiddenFromOverview,
            sortIndex: nextSortIndex()
        )
        context.insert(account)
        if saveImmediately { try? context.save() }
        return account
    }

    func update(
        _ account: Account,
        name: String,
        initialAmount: Decimal,
        iconName: String,
        color: PaletteColor,
        isSavings: Bool,
        isHiddenFromOverview: Bool
    ) {
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.initialAmount = initialAmount
        account.iconName = iconName
        account.color = color
        account.isSavings = isSavings
        account.isHiddenFromOverview = isHiddenFromOverview
        try? context.save()
    }

    func delete(_ account: Account) {
        // Operations cascade with the account; planned occurrences are not
        // owned by it, so remove them explicitly instead of leaving orphans.
        let plans = (try? context.fetch(FetchDescriptor<PlannedOperation>())) ?? []
        for plan in plans where plan.account?.id == account.id {
            context.delete(plan)
        }
        context.delete(account)
        try? context.save()
    }

    private func nextSortIndex() -> Int {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        return (accounts.map(\.sortIndex).max() ?? -1) + 1
    }
}

@MainActor
struct OperationRepository {
    let context: ModelContext

    @discardableResult
    func create(
        kind: OperationKind,
        amount: Decimal,
        account: Account,
        category: Category?,
        date: Date,
        place: String,
        latitude: Double?,
        longitude: Double?,
        note: String,
        saveImmediately: Bool = true
    ) -> Operation {
        let operation = Operation(
            kind: kind,
            amount: amount,
            currency: account.currency,
            date: date,
            place: place.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            account: account,
            category: category
        )
        context.insert(operation)
        if saveImmediately { try? context.save() }
        return operation
    }

    func update(
        _ operation: Operation,
        kind: OperationKind,
        amount: Decimal,
        account: Account,
        category: Category?,
        date: Date,
        place: String,
        latitude: Double?,
        longitude: Double?,
        note: String
    ) {
        operation.kind = kind
        operation.amount = amount
        operation.currency = account.currency
        operation.account = account
        operation.category = category
        operation.date = date
        operation.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        operation.latitude = latitude
        operation.longitude = longitude
        operation.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
    }

    func delete(_ operations: [Operation]) {
        for operation in operations { context.delete(operation) }
        try? context.save()
    }
}

/// A transfer is two linked operations — money out of the source account and
/// into the destination one, each in its own currency. The person chooses both
/// amounts, so a bank's rate or fee never has to be guessed.
@MainActor
struct TransferRepository {
    let context: ModelContext

    @discardableResult
    func create(
        from source: Account,
        to destination: Account,
        sent: Decimal,
        received: Decimal,
        date: Date = .now,
        transferID: UUID = UUID(),
        saveImmediately: Bool = true
    ) -> UUID {
        let outgoing = Operation(
            kind: .expense,
            amount: sent,
            currency: source.currency,
            date: date,
            note: String(localized: "transfer.note_to \(destination.name)"),
            account: source,
            category: nil
        )
        outgoing.transferID = transferID

        let incoming = Operation(
            kind: .income,
            amount: received,
            currency: destination.currency,
            date: date,
            note: String(localized: "transfer.note_from \(source.name)"),
            account: destination,
            category: nil
        )
        incoming.transferID = transferID

        context.insert(outgoing)
        context.insert(incoming)
        if saveImmediately { try? context.save() }
        return transferID
    }
}

@MainActor
struct CategoryRepository {
    let context: ModelContext

    @discardableResult
    func create(
        name: String,
        kind: OperationKind,
        color: PaletteColor,
        iconName: String,
        isMandatory: Bool,
        parent: Category? = nil,
        saveImmediately: Bool = true
    ) -> Category {
        let category = Category(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            color: color,
            iconName: iconName,
            isMandatory: kind == .expense ? isMandatory : false,
            isSystem: false,
            sortIndex: nextSortIndex(for: kind)
        )
        category.parent = parent
        context.insert(category)
        if saveImmediately { try? context.save() }
        return category
    }

    func update(
        _ category: Category,
        name: String,
        color: PaletteColor,
        iconName: String,
        isMandatory: Bool,
        parent: Category?
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != category.displayName {
            category.name = trimmed
        }
        category.color = color
        category.iconName = iconName
        category.isMandatory = category.kind == .expense ? isMandatory : false
        category.parent = parent
        try? context.save()
    }

    /// Deletes a custom category, moving its operations to the fallback category
    /// of the same kind first so no operation is left without a name.
    func delete(_ category: Category) {
        guard !category.isSystem else { return }
        let fallback = (try? context.fetch(FetchDescriptor<Category>()))?
            .first { $0.kind == category.kind && $0.name == StarterCategory.other.storedName && $0.id != category.id }
        // Subcategories survive their parent: they become top-level instead of
        // being deleted along with it.
        let allCategories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        for child in allCategories where child.parent?.id == category.id {
            child.parent = nil
        }
        for operation in category.operations ?? [] {
            operation.category = fallback
        }
        let plans = (try? context.fetch(FetchDescriptor<PlannedOperation>())) ?? []
        for plan in plans where plan.category?.id == category.id {
            plan.category = fallback
        }
        context.delete(category)
        try? context.save()
    }

    private func nextSortIndex(for kind: OperationKind) -> Int {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        return (categories.filter { $0.kind == kind }.map(\.sortIndex).max() ?? -1) + 1
    }
}
