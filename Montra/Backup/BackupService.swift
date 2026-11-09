import Foundation
import SwiftData

/// Reads the whole store into a backup and puts a backup back into an empty
/// store. All SwiftData writes stay here so the file format and the data rules
/// live in one place instead of being spread across views.
@MainActor
enum BackupService {
    /// The parts of the running app that live outside SwiftData: the rate table
    /// and the local API switches. Tokens and other machine secrets stay out.
    struct Environment {
        var rates: ExchangeRates
        var integrationEnabled: Bool
        var integrationAllowsDelete: Bool
    }

    struct RestoreReport {
        var summary: BackupSummary
        /// A rate table to install after the restore, when the file carries one.
        var rates: ExchangeRates?
        var integration: IntegrationBackup?
    }

    // MARK: - Capture

    static func capture(
        context: ModelContext,
        settings: SettingsStore,
        environment: Environment,
        createdAt: Date = .now
    ) throws -> MontraBackup {
        let accounts: [Account]
        let categories: [Category]
        let operations: [Operation]
        let plans: [PlannedOperation]
        let periods: [Period]
        do {
            accounts = try context.fetch(FetchDescriptor<Account>())
            categories = try context.fetch(FetchDescriptor<Category>())
            operations = try context.fetch(FetchDescriptor<Operation>())
            plans = try context.fetch(FetchDescriptor<PlannedOperation>())
            periods = try context.fetch(FetchDescriptor<Period>())
        } catch {
            throw BackupError.captureFailed(error)
        }

        let payload = BackupPayload(
            accounts: accounts.sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map(AccountBackup.init),
            categories: categories.sorted { lhs, rhs in
                if lhs.kindRaw != rhs.kindRaw { return lhs.kindRaw < rhs.kindRaw }
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map(CategoryBackup.init),
            operations: operations.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map(OperationBackup.init),
            plannedOperations: plans.sorted { lhs, rhs in
                if lhs.seriesID != rhs.seriesID { return lhs.seriesID.uuidString < rhs.seriesID.uuidString }
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map(PlannedOperationBackup.init),
            periods: periods.sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map(PeriodBackup.init),
            settings: SettingsBackup(settings),
            rates: RatesBackup(environment.rates),
            integration: IntegrationBackup(
                enabled: environment.integrationEnabled,
                allowDelete: environment.integrationAllowsDelete
            )
        )

        return try BackupCoding.seal(payload, createdAt: createdAt)
    }

    // MARK: - Restore

    /// Replaces everything in the store with the archive's contents. Every value
    /// is decoded and every reference checked before the first delete, so a
    /// damaged file leaves the current data untouched.
    static func restore(
        _ backup: MontraBackup,
        context: ModelContext,
        settings: SettingsStore
    ) throws -> RestoreReport {
        let payload = backup.payload
        let prepared = try PreparedPayload(payload)

        do {
            try deleteAll(context)
            insert(prepared, payload: payload, into: context)
            try context.save()
        } catch let error as BackupError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw BackupError.restoreFailed(error)
        }

        // A store with accounts belongs to someone who has finished the welcome
        // flow, exactly as the launch path decides it.
        apply(payload.settings, hasAccounts: !payload.accounts.isEmpty, to: settings)
        PeriodService.ensurePeriods(context: context, settings: settings)

        return RestoreReport(
            summary: payload.summary,
            rates: prepared.rates,
            integration: payload.integration
        )
    }

    // MARK: - Files

    static func write(_ backup: MontraBackup, to url: URL) throws {
        do {
            try BackupCoding.encode(backup).write(to: url, options: .atomic)
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.saveFailed(error)
        }
    }

    static func read(from url: URL) throws -> MontraBackup {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.unreadable(error)
        }
        return try BackupCoding.decode(data)
    }

    // MARK: - The store, emptied and filled

    private static func deleteAll(_ context: ModelContext) throws {
        for operation in try context.fetch(FetchDescriptor<Operation>()) {
            context.delete(operation)
        }
        for plan in try context.fetch(FetchDescriptor<PlannedOperation>()) {
            context.delete(plan)
        }
        for account in try context.fetch(FetchDescriptor<Account>()) {
            context.delete(account)
        }
        for category in try context.fetch(FetchDescriptor<Category>()) {
            context.delete(category)
        }
        for period in try context.fetch(FetchDescriptor<Period>()) {
            context.delete(period)
        }
    }

    private static func insert(
        _ prepared: PreparedPayload,
        payload: BackupPayload,
        into context: ModelContext
    ) {
        var accounts: [UUID: Account] = [:]
        for (index, row) in payload.accounts.enumerated() {
            let account = Account(
                name: row.name,
                currency: Currency(rawValue: row.currency) ?? .byn,
                initialAmount: prepared.accountAmounts[index],
                iconName: row.iconName,
                color: PaletteColor(rawValue: row.color) ?? .blue,
                isSavings: row.isSavings,
                isHiddenFromOverview: row.isHiddenFromOverview,
                sortIndex: row.sortIndex,
                createdAt: row.createdAt
            )
            account.id = row.id
            context.insert(account)
            accounts[row.id] = account
        }

        var categories: [UUID: Category] = [:]
        var categoryParents: [(Category, UUID)] = []
        for row in payload.categories {
            let category = Category(
                name: row.name,
                kind: OperationKind(rawValue: row.kind) ?? .expense,
                color: PaletteColor(rawValue: row.color) ?? .orange,
                iconName: row.iconName,
                isMandatory: row.isMandatory,
                isSystem: row.isSystem,
                sortIndex: row.sortIndex
            )
            category.id = row.id
            category.createdAt = row.createdAt
            context.insert(category)
            categories[row.id] = category
            if let parentID = row.parentID {
                categoryParents.append((category, parentID))
            }
        }
        // Parents are linked in a second pass, so the order inside the file
        // never matters.
        for (category, parentID) in categoryParents {
            category.parent = categories[parentID]
        }

        for (index, row) in payload.operations.enumerated() {
            let operation = Operation(
                kind: OperationKind(rawValue: row.kind) ?? .expense,
                amount: prepared.operationAmounts[index],
                currency: Currency(rawValue: row.currency) ?? .byn,
                date: row.date,
                place: row.place,
                latitude: row.latitude,
                longitude: row.longitude,
                note: row.note,
                account: row.accountID.flatMap { accounts[$0] },
                category: row.categoryID.flatMap { categories[$0] }
            )
            operation.id = row.id
            operation.createdAt = row.createdAt
            operation.transferID = row.transferID
            context.insert(operation)
        }

        for (index, row) in payload.plannedOperations.enumerated() {
            let plan = PlannedOperation(
                seriesID: row.seriesID,
                kind: OperationKind(rawValue: row.kind) ?? .expense,
                amount: prepared.planAmounts[index],
                currency: Currency(rawValue: row.currency) ?? .byn,
                date: row.date,
                place: row.place,
                note: row.note,
                frequency: PlanFrequency(rawValue: row.frequency) ?? .month,
                weekdays: [],
                seriesStart: row.seriesStart,
                seriesEnd: row.seriesEnd,
                account: row.accountID.flatMap { accounts[$0] },
                category: row.categoryID.flatMap { categories[$0] }
            )
            plan.id = row.id
            plan.createdAt = row.createdAt
            // The stored mask keeps a weekly series on exactly the same days,
            // even if it was built from a different locale's weekday order.
            plan.weekdayMask = row.weekdayMask
            plan.linkedOperationID = row.linkedOperationID
            context.insert(plan)
        }

        for row in payload.periods {
            let period = Period(start: row.start, end: row.end, isManual: row.isManual)
            period.id = row.id
            period.createdAt = row.createdAt
            context.insert(period)
        }
    }

    private static func apply(_ backup: SettingsBackup, hasAccounts: Bool, to settings: SettingsStore) {
        settings.hideBalances = backup.hideBalances
        settings.primaryCurrency = Currency(rawValue: backup.primaryCurrency) ?? .byn
        settings.appearance = SettingsStore.Appearance(rawValue: backup.appearance) ?? .auto
        settings.periodMode = SettingsStore.PeriodMode(rawValue: backup.periodMode) ?? .payday
        settings.paydayDay = min(max(backup.paydayDay, 1), 31)
        settings.fixedLengthDays = min(max(backup.fixedLengthDays, 1), 90)
        settings.periodAnchor = backup.periodAnchor
        settings.didSeedDemo = backup.didSeedDemo
        // Restoring is something a person can only do from inside the app, so the
        // welcome flow has already been opened on this Mac. A copy written before
        // the flag existed must not make an interrupted run look like a legacy
        // install on the next launch.
        settings.hasStartedOnboarding = backup.hasStartedOnboarding ?? true
        settings.hasCompletedOnboarding = backup.hasCompletedOnboarding || hasAccounts
    }

    // MARK: - Validation

    /// Decimals are parsed and references resolved before anything is deleted.
    /// A corrupt file therefore cannot leave a half-empty store behind.
    private struct PreparedPayload {
        let accountAmounts: [Decimal]
        let operationAmounts: [Decimal]
        let planAmounts: [Decimal]
        let rates: ExchangeRates?

        init(_ payload: BackupPayload) throws {
            accountAmounts = try payload.accounts.map { try BackupDecimal.value($0.initialAmount) }
            operationAmounts = try payload.operations.map { try BackupDecimal.value($0.amount) }
            planAmounts = try payload.plannedOperations.map { try BackupDecimal.value($0.amount) }

            // Duplicate ids would make every reference ambiguous; a valid file
            // never has them.
            guard Self.hasUniqueIDs(payload.accounts.map(\.id)),
                  Self.hasUniqueIDs(payload.categories.map(\.id)),
                  Self.hasUniqueIDs(payload.operations.map(\.id)),
                  Self.hasUniqueIDs(payload.plannedOperations.map(\.id)),
                  Self.hasUniqueIDs(payload.periods.map(\.id))
            else { throw BackupError.corrupted }

            let accountIDs = Set(payload.accounts.map(\.id))
            let categoryIDs = Set(payload.categories.map(\.id))
            let parents = Dictionary(
                uniqueKeysWithValues: payload.categories.map { ($0.id, $0.parentID) }
            )

            for category in payload.categories {
                guard let parentID = category.parentID else { continue }
                guard parentID != category.id, categoryIDs.contains(parentID) else {
                    throw BackupError.corrupted
                }
                // The model allows one level of nesting. Following the chain
                // catches a crafted cycle that would otherwise confuse every
                // category list after the restore.
                var seen: Set<UUID> = []
                var current: UUID? = category.id
                while let id = current {
                    guard seen.insert(id).inserted else { throw BackupError.corrupted }
                    guard let next = parents[id].flatMap({ $0 }) else { break }
                    current = next
                }
            }
            for operation in payload.operations {
                if let accountID = operation.accountID, !accountIDs.contains(accountID) {
                    throw BackupError.corrupted
                }
                if let categoryID = operation.categoryID, !categoryIDs.contains(categoryID) {
                    throw BackupError.corrupted
                }
            }
            for plan in payload.plannedOperations {
                if let accountID = plan.accountID, !accountIDs.contains(accountID) {
                    throw BackupError.corrupted
                }
                if let categoryID = plan.categoryID, !categoryIDs.contains(categoryID) {
                    throw BackupError.corrupted
                }
            }
            for period in payload.periods where period.start > period.end {
                throw BackupError.corrupted
            }

            rates = try Self.makeRates(payload.rates)
        }

        private static func hasUniqueIDs(_ ids: [UUID]) -> Bool {
            Set(ids).count == ids.count
        }

        private static func makeRates(_ backup: RatesBackup?) throws -> ExchangeRates? {
            guard let backup else { return nil }
            var table: [Currency: Decimal] = [:]
            for (raw, text) in backup.bynPerUnit {
                guard let currency = Currency(rawValue: raw) else { continue }
                let value = try BackupDecimal.value(text)
                if value > 0 { table[currency] = value }
            }
            // Without the BYN pivot a table cannot convert anything; leaving the
            // current rates alone is better than installing a broken one.
            guard table[.byn] != nil else { return nil }
            return ExchangeRates(
                bynPerUnit: table,
                date: backup.date,
                fetchedAt: backup.fetchedAt,
                source: RateSource(rawValue: backup.source) ?? .cache
            )
        }
    }
}

// MARK: - Model → file

private extension AccountBackup {
    init(_ account: Account) {
        self.init(
            id: account.id,
            name: account.name,
            currency: account.currencyRaw,
            initialAmount: BackupDecimal.text(account.initialAmount),
            isSavings: account.isSavings,
            isHiddenFromOverview: account.isHiddenFromOverview,
            iconName: account.iconName,
            color: account.colorRaw,
            createdAt: account.createdAt,
            sortIndex: account.sortIndex
        )
    }
}

private extension CategoryBackup {
    init(_ category: Category) {
        self.init(
            id: category.id,
            name: category.name,
            kind: category.kindRaw,
            color: category.colorRaw,
            iconName: category.iconName,
            isMandatory: category.isMandatory,
            isSystem: category.isSystem,
            sortIndex: category.sortIndex,
            createdAt: category.createdAt,
            parentID: category.parent?.id
        )
    }
}

private extension OperationBackup {
    init(_ operation: Operation) {
        self.init(
            id: operation.id,
            kind: operation.kindRaw,
            amount: BackupDecimal.text(operation.amount),
            currency: operation.currencyRaw,
            date: operation.date,
            place: operation.place,
            latitude: operation.latitude,
            longitude: operation.longitude,
            note: operation.note,
            createdAt: operation.createdAt,
            accountID: operation.account?.id,
            categoryID: operation.category?.id,
            transferID: operation.transferID
        )
    }
}

private extension PlannedOperationBackup {
    init(_ plan: PlannedOperation) {
        self.init(
            id: plan.id,
            seriesID: plan.seriesID,
            kind: plan.kindRaw,
            amount: BackupDecimal.text(plan.amount),
            currency: plan.currencyRaw,
            date: plan.date,
            place: plan.place,
            note: plan.note,
            createdAt: plan.createdAt,
            frequency: plan.frequencyRaw,
            weekdayMask: plan.weekdayMask,
            seriesStart: plan.seriesStart,
            seriesEnd: plan.seriesEnd,
            accountID: plan.account?.id,
            categoryID: plan.category?.id,
            linkedOperationID: plan.linkedOperationID
        )
    }
}

private extension PeriodBackup {
    init(_ period: Period) {
        self.init(
            id: period.id,
            start: period.start,
            end: period.end,
            isManual: period.isManual,
            createdAt: period.createdAt
        )
    }
}

private extension SettingsBackup {
    @MainActor
    init(_ settings: SettingsStore) {
        self.init(
            appearance: settings.appearance.rawValue,
            hideBalances: settings.hideBalances,
            primaryCurrency: settings.primaryCurrency.rawValue,
            periodMode: settings.periodMode.rawValue,
            paydayDay: settings.paydayDay,
            fixedLengthDays: settings.fixedLengthDays,
            periodAnchor: settings.periodAnchor,
            didSeedDemo: settings.didSeedDemo,
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            hasStartedOnboarding: settings.hasStartedOnboarding
        )
    }
}

private extension RatesBackup {
    init(_ rates: ExchangeRates) {
        var table: [String: String] = [:]
        for (currency, value) in rates.bynPerUnit {
            table[currency.rawValue] = BackupDecimal.text(value)
        }
        self.init(source: rates.source.rawValue, date: rates.date, fetchedAt: rates.fetchedAt, bynPerUnit: table)
    }
}
