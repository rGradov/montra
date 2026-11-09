import CryptoKit
import Foundation
import SwiftData

private enum Action: String, Decodable, CaseIterable {
    case status
    case listAccounts = "list_accounts"
    case listCategories = "list_categories"
    case listOperations = "list_operations"
    case createAccount = "create_account"
    case createCategory = "create_category"
    case createOperation = "create_operation"
    case recategorizeOperations = "recategorize_operations"
    case previewImport = "preview_import"
    case importOperations = "import_operations"
    case previewDeleteAccount = "preview_delete_account"
    case deleteAccount = "delete_account"
    case getBalances = "get_balances"
    case getTransfer = "get_transfer"
    case createTransfer = "create_transfer"
    case listPlans = "list_plans"
    case createPlan = "create_plan"
    case linkPlan = "link_plan"
    case recordPlan = "record_plan"
    case previewDeletePlan = "preview_delete_plan"
    case deletePlan = "delete_plan"
    case previewDeleteOperations = "preview_delete_operations"
    case deleteOperations = "delete_operations"

    var writes: Bool {
        switch self {
        case .createAccount, .createCategory, .createOperation, .recategorizeOperations, .importOperations, .deleteAccount,
             .createTransfer, .createPlan, .linkPlan, .recordPlan, .deletePlan, .deleteOperations: true
        case .status, .listAccounts, .listCategories, .listOperations, .previewImport, .previewDeleteAccount,
             .getBalances, .getTransfer, .listPlans, .previewDeletePlan, .previewDeleteOperations: false
        }
    }
}

struct LedgerError: LocalizedError {
    let message: String
    let status: Int
    init(_ message: String, status: Int = 422) {
        self.message = message
        self.status = status
    }
    var errorDescription: String? { message }
}

private struct Request: Decodable {
    let action: Action
}

private struct AccountInput: Decodable {
    let name: String
    @CurrencyCode var currency: Currency
    let initialAmount: String?
    let iconName: String?
    let color: String?
    let isSavings: Bool?
    let isHiddenFromOverview: Bool?
}

private struct CategoryInput: Decodable {
    let name: String
    let kind: OperationKind
    let iconName: String?
    let color: String?
    let isMandatory: Bool?
    let parentId: UUID?
}

private struct AccountSelection: Decodable {
    let accountId: UUID
    let previewToken: String?
}

private struct LedgerOperationFilter: Decodable {
    let accountId: UUID?
    let categoryId: UUID?
    let kind: LedgerOperationKind?
    let query: String?
    let fromDate: Date?
    let beforeDate: Date?
    let limit: Int?
    let offset: Int?
}

private enum LedgerOperationKind: String, Decodable {
    case expense, income, transfer

    func matches(_ operation: Operation) -> Bool {
        if self == .transfer { return operation.isTransfer }
        return !operation.isTransfer && rawValue == operation.kind.rawValue
    }
}

private struct ImportRow: Decodable {
    let externalId: String?
    let date: Date
    let kind: OperationKind
    let amount: String
    let categoryId: UUID?
    let place: String?
    let note: String?
    let allowPossibleDuplicate: Bool?
}

private struct ImportInput: Decodable {
    let accountId: UUID
    @CurrencyCode var currency: Currency
    let source: String?
    let requestId: UUID?
    let operation: ImportRow?
    let rows: [ImportRow]?
    let previewToken: String?
}

private struct OperationRecategorization: Decodable {
    let operationIds: [UUID]
    let categoryId: UUID
}

private typealias JSONObject = [String: Any]


@propertyWrapper
private struct CurrencyCode: Decodable {
    let wrappedValue: Currency

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let currency = Currency(rawValue: raw.lowercased()) else {
            throw LedgerError("Unsupported currency.")
        }
        wrappedValue = currency
    }
}

@MainActor
struct LedgerAPI {
    let context: ModelContext

    func execute(_ data: Data, allowDelete: Bool) throws -> Data {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            try strictTimestamp(decoder.singleValueContainer().decode(String.self))
        }
        let action = try decoder.decode(Request.self, from: data).action
        if !allowDelete && [.deleteAccount, .deleteOperations, .deletePlan].contains(action) {
            throw LedgerError("Deletion is disabled in Montra's integration settings.", status: 403)
        }
        if action.writes && context.hasChanges {
            throw LedgerError("Montra has unsaved changes. Finish the current edit and retry.", status: 409)
        }
        let store = Store(context: context)
        do {
            let output: JSONObject
            switch action {
            case .status:
                output = [
                    "version": 1, "account_delete_enabled": allowDelete, "entry_delete_enabled": allowDelete,
                    "actions": Action.allCases.map(\.rawValue).sorted(),
                ]
            case .listAccounts:
                output = try store.listAccounts()
            case .listCategories:
                output = try store.listCategories()
            case .listOperations:
                output = try store.listOperations(decoder.decode(LedgerOperationFilter.self, from: data))
            case .createAccount:
                output = try store.createAccount(decoder.decode(AccountInput.self, from: data))
            case .createCategory:
                output = try store.createCategory(decoder.decode(CategoryInput.self, from: data))
            case .createOperation, .previewImport, .importOperations:
                output = try store.handleImport(decoder.decode(ImportInput.self, from: data), action: action)
            case .recategorizeOperations:
                output = try store.recategorizeOperations(decoder.decode(OperationRecategorization.self, from: data))
            case .previewDeleteAccount, .deleteAccount:
                output = try store.handleDelete(decoder.decode(AccountSelection.self, from: data), apply: action.writes)
            case .getBalances:
                output = try store.balances()
            case .getTransfer:
                output = try store.getTransfer(decoder.decode(TransferSelection.self, from: data).transferId)
            case .createTransfer:
                output = try store.createTransfer(decoder.decode(TransferInput.self, from: data))
            case .listPlans:
                output = try store.listPlans(decoder.decode(LedgerPlanFilter.self, from: data))
            case .createPlan:
                output = try store.createPlan(decoder.decode(PlanInput.self, from: data))
            case .linkPlan:
                output = try store.linkPlan(decoder.decode(PlanLink.self, from: data))
            case .recordPlan:
                output = try store.recordPlan(decoder.decode(PlanRecord.self, from: data))
            case .previewDeletePlan, .deletePlan:
                output = try store.deletePlan(decoder.decode(PlanDeletion.self, from: data), apply: action.writes)
            case .previewDeleteOperations, .deleteOperations:
                output = try store.deleteOperations(decoder.decode(OperationDeletion.self, from: data), apply: action.writes)
            }
            let result = try jsonData(output)
            if action.writes && context.hasChanges { try context.save() }
            return result
        } catch {
            // The context was clean on entry and no other main-actor task can interleave.
            if action.writes && context.hasChanges { context.rollback() }
            throw error
        }
    }
}

private func jsonData(_ value: JSONObject) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private func previewToken(_ value: JSONObject) throws -> String {
    SHA256.hash(data: try jsonData(value)).map { String(format: "%02x", $0) }.joined()
}

@MainActor
private struct Store {
    let context: ModelContext

    func listAccounts() throws -> JSONObject {
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [.init(\.sortIndex)]))
        return ["accounts": accounts.map(accountJSON)]
    }

    func listCategories() throws -> JSONObject {
        let categories = try context.fetch(FetchDescriptor<Category>(sortBy: [.init(\.kindRaw), .init(\.sortIndex)]))
        return ["categories": categories.map(categoryJSON)]
    }

    func listOperations(_ filter: LedgerOperationFilter) throws -> JSONObject {
        let account = try filter.accountId.map(findAccount)
        let candidates = try account.map { $0.operations ?? [] } ?? context.fetch(FetchDescriptor<Operation>())
        let query = try clean(filter.query ?? "", max: 250)
        let tokens = query.split(whereSeparator: \.isWhitespace)
        let operations = candidates.filter { operation in
            (filter.fromDate.map { operation.date >= $0 } ?? true) &&
            (filter.beforeDate.map { operation.date < $0 } ?? true) &&
            (filter.categoryId.map { operation.category?.id == $0 || operation.category?.parent?.id == $0 } ?? true) &&
            (filter.kind?.matches(operation) ?? true) &&
            matchesSearch(operation, tokens: tokens)
        }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
        try validateDateRange(filter.fromDate, filter.beforeDate)
        let (page, next) = try paginate(operations, limit: filter.limit, offset: filter.offset)
        return [
            "account": account.map(accountJSON) as Any? ?? NSNull(),
            "operations": page.map(operationJSON),
            "total": operations.count,
            "next_offset": next,
        ]
    }

    func createAccount(_ input: AccountInput) throws -> JSONObject {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let name = try clean(input.name, max: 100, required: true)
        let amount = try money(input.initialAmount ?? "0", currency: input.currency)
        let icon = try clean(input.iconName ?? "creditcard.fill", max: 100, required: true)
        let color = try paletteColor(input.color ?? "blue")
        let matches = accounts.filter { $0.name == name && $0.currency == input.currency }
        if let existing = matches.first {
            let savingsMatches = input.isSavings.map { $0 == existing.isSavings } ?? true
            let hiddenMatches = input.isHiddenFromOverview.map { $0 == existing.isHiddenFromOverview } ?? true
            guard matches.count == 1, existing.initialAmount == amount, savingsMatches, hiddenMatches else {
                throw LedgerError("An account already has this name and currency. Inspect list_accounts before proceeding.")
            }
            return ["created": false, "account": accountJSON(existing)]
        }
        let account = Account(
            name: name, currency: input.currency, initialAmount: amount,
            iconName: icon, color: color, isSavings: input.isSavings ?? false,
            isHiddenFromOverview: input.isHiddenFromOverview ?? false,
            sortIndex: (accounts.map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(account)
        return ["created": true, "account": accountJSON(account)]
    }

    func createCategory(_ input: CategoryInput) throws -> JSONObject {
        let categories = try context.fetch(FetchDescriptor<Category>()).filter { $0.kind == input.kind }
        let name = try clean(input.name, max: 100, required: true)
        let icon = try clean(input.iconName ?? "tag.fill", max: 100, required: true)
        let color = try paletteColor(input.color ?? "orange")
        let mandatory = input.isMandatory ?? false
        let parent: Category? = try input.parentId.map { parentID in
            guard let parent = categories.first(where: { $0.id == parentID }), parent.parent == nil else {
                throw LedgerError("Choose a top-level parent category of the same kind.")
            }
            return parent
        }
        let matches = categories.filter { $0.name == name && $0.parent?.id == parent?.id }
        if let existing = matches.first {
            guard matches.count == 1 else { throw LedgerError("This name is ambiguous. Use the category IDs in list_categories.") }
            return ["created": false, "category": categoryJSON(existing)]
        }
        guard input.kind == .expense || !mandatory else {
            throw LedgerError("Only expense categories can be mandatory.")
        }
        let category = CategoryRepository(context: context).create(
            name: name, kind: input.kind, color: color,
            iconName: icon, isMandatory: mandatory, parent: parent, saveImmediately: false
        )
        return ["created": true, "category": categoryJSON(category)]
    }

    func handleDelete(_ selection: AccountSelection, apply: Bool) throws -> JSONObject {
        let account = try findAccount(selection.accountId)
        let snapshot = accountJSON(account)
        let operationIDs = Set((account.operations ?? []).map(\.id))
        let ids = operationIDs.map(id).sorted()
        let allPlans = try context.fetch(FetchDescriptor<PlannedOperation>())
        let plans = allPlans.filter { $0.account?.id == account.id }
        let otherLinkedPlans = allPlans.filter {
            $0.account?.id != account.id && ($0.linkedOperationID.map(operationIDs.contains) ?? false)
        }
        let planIDs = plans.map { id($0.id) }.sorted()
        let token = try previewToken([
            "action": "delete_account",
            "account": snapshot,
            "operation_ids": ids,
            "plan_ids": planIDs,
            "reopened_plan_ids": otherLinkedPlans.map { id($0.id) }.sorted(),
        ])
        if apply {
            guard selection.previewToken == token else {
                throw LedgerError("The account, its operations or its plans changed. Run preview_delete_account again.", status: 409)
            }
            for plan in otherLinkedPlans { plan.linkedOperationID = nil }
            for plan in plans { context.delete(plan) }
            context.delete(account)
            return [
                "deleted_account_id": id(selection.accountId),
                "deleted_operation_count": ids.count,
                "deleted_plan_count": planIDs.count,
                "reopened_plan_count": otherLinkedPlans.count,
            ]
        }
        return [
            "account": snapshot,
            "operation_count": ids.count,
            "plan_count": planIDs.count,
            "reopened_plan_count": otherLinkedPlans.count,
            "preview_token": token,
        ]
    }

    func handleImport(_ input: ImportInput, action: Action) throws -> JSONObject {
        let account = try findAccount(input.accountId)
        guard account.currencyRaw == input.currency.rawValue else {
            throw LedgerError("Currency mismatch. Use the settled amount in the account's currency.")
        }
        let inputRows: [ImportRow]
        let namespace: String
        if action == .createOperation {
            guard let operation = input.operation, input.requestId != nil else {
                throw LedgerError("Provide operation and request_id.")
            }
            inputRows = [operation]
            namespace = "manual"
        } else {
            guard let source = input.source,
                  source.range(of: #"\A[a-z0-9][a-z0-9._-]{0,59}\z"#, options: .regularExpression) != nil,
                  let rows = input.rows, (1...100).contains(rows.count) else {
                throw LedgerError("Provide a valid source and 1 to 100 rows.")
            }
            inputRows = rows
            namespace = "statement:" + source
        }
        let externalIds = try inputRows.map {
            try clean(action == .createOperation ? input.requestId.map(id) ?? "" : $0.externalId ?? "", max: 160, required: true)
        }
        let rowIds = externalIds.map { operationUUID(account: account.id, source: namespace, externalId: $0) }
        guard Set(rowIds).count == rowIds.count else { throw LedgerError("Duplicate external IDs in this batch.") }
        let previous = try context.fetch(FetchDescriptor<Operation>(
            predicate: #Predicate { rowIds.contains($0.id) }
        ))
        let byId = Dictionary(grouping: previous, by: \.id)
        let categories = try context.fetch(FetchDescriptor<Category>())
        let categoriesById = Dictionary(grouping: categories, by: \.id)
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: account.operations ?? []) { calendar.startOfDay(for: $0.date) }

        var pending: [(row: ImportRow, operationId: UUID, place: String, note: String, amount: Decimal, category: Category?)] = []
        var rows: [JSONObject] = []
        var blocked = 0
        var alreadyImported = 0
        var income: Decimal = 0
        var expense: Decimal = 0

        for (index, row) in inputRows.enumerated() {
            let externalId = externalIds[index]
            let operationId = rowIds[index]
            let place = try clean(row.place ?? "", max: 250)
            let note = try clean(row.note ?? "", max: 500)
            let allowDuplicate = row.allowPossibleDuplicate ?? false
            let amount = try money(row.amount, currency: input.currency)
            guard amount > 0 else { throw LedgerError("Amount must be positive for row \(externalId).") }
            var detail: JSONObject = [
                "external_id": externalId, "operation_id": id(operationId),
                "date": row.date.ISO8601Format(), "kind": row.kind.rawValue, "amount": amountText(amount),
                "place": place, "note": note,
            ]

            if let matches = byId[operationId], let existing = matches.first {
                guard matches.count == 1, existing.account?.id == account.id, existing.currency == input.currency,
                      existing.kind == row.kind, existing.amount == amount, existing.date == row.date else {
                    throw LedgerError("External ID \(externalId) conflicts with a saved operation. Review the source and Montra entry.")
                }
                detail["category"] = existing.category.map(categoryJSON) as Any? ?? NSNull()
                detail["status"] = "already_imported"
                alreadyImported += 1
            } else {
                let category: Category?
                if let categoryId = row.categoryId {
                    guard let matches = categoriesById[categoryId], matches.count == 1,
                          let selected = matches.first, selected.kind == row.kind else {
                        throw LedgerError("Choose an existing category of kind \(row.kind.rawValue) for row \(externalId).")
                    }
                    category = selected
                } else {
                    category = nil
                }
                detail["category"] = category.map(categoryJSON) as Any? ?? NSNull()
                let candidates = (byDay[calendar.startOfDay(for: row.date)] ?? []).filter {
                    $0.kind == row.kind && $0.amount == amount && $0.currency == input.currency
                }
                detail["possible_duplicate_ids"] = candidates.map { id($0.id) }.sorted()
                detail["allow_possible_duplicate"] = allowDuplicate
                if !candidates.isEmpty && !allowDuplicate {
                    detail["status"] = "possible_duplicate"
                    blocked += 1
                } else {
                    detail["status"] = "ready"
                    pending.append((row, operationId, place, note, amount, category))
                    if row.kind == .income { income += amount } else { expense += amount }
                }
            }
            rows.append(detail)
        }

        let plan: JSONObject = [
            "account_id": id(account.id), "account_name": account.name, "currency": input.currency.code,
            "rows": rows, "to_create": pending.count, "already_imported": alreadyImported,
            "needs_review": blocked, "income_to_create": amountText(income), "expense_to_create": amountText(expense),
        ]
        let token = try previewToken(plan)
        if action == .previewImport {
            var preview = plan
            preview["preview_token"] = token
            return preview
        }
        guard blocked == 0 else {
            throw LedgerError("Possible duplicates need review. Use preview_import and list_operations before retrying.")
        }
        if action == .importOperations && !pending.isEmpty && input.previewToken != token {
            throw LedgerError("The import preview changed. Run preview_import again and confirm the updated plan.", status: 409)
        }
        for item in pending {
            let operation = Operation(
                kind: item.row.kind, amount: item.amount, currency: input.currency, date: item.row.date,
                place: item.place, note: item.note, account: account, category: item.category
            )
            operation.id = item.operationId
            context.insert(operation)
        }
        return [
            "account_id": id(account.id), "created": pending.count, "already_imported": alreadyImported,
            "operation_ids": rowIds.map(id),
        ]
    }

    private func findAccount(_ accountId: UUID) throws -> Account {
        let matches = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == accountId }))
        guard matches.count == 1, let account = matches.first else {
            throw LedgerError("Account ID is missing or ambiguous. Run list_accounts.")
        }
        return account
    }
}

private func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

private func amountText(_ amount: Decimal) -> String { NSDecimalNumber(decimal: amount).stringValue }

private func strictTimestamp(_ value: String) throws -> Date {
    let pattern = #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])\z"#
    let invalid = LedgerError("Use a valid timestamp with seconds and a UTC offset.")
    guard value.range(of: pattern, options: .regularExpression) != nil,
          let date = try? Date(value, strategy: .iso8601) else { throw invalid }
    var localDate = date
    if !value.hasSuffix("Z") {
        let zone = value.suffix(6)
        guard let hours = Int(zone.dropFirst().prefix(2)), let minutes = Int(zone.suffix(2)) else { throw invalid }
        let sign = zone.hasPrefix("-") ? -1 : 1
        localDate = date.addingTimeInterval(Double(sign * (hours * 60 + minutes) * 60))
    }
    // Foundation can normalize impossible calendar dates. Compare the wall time.
    guard localDate.ISO8601Format().prefix(19) == value.prefix(19) else { throw invalid }
    return date
}

private func money(_ input: String, currency: Currency) throws -> Decimal {
    let pattern = "\\A[0-9]{1,18}(\\.[0-9]{1,\(currency.fractionDigits)})?\\z"
    guard input.range(of: pattern, options: .regularExpression) != nil,
          let amount = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")) else {
        throw LedgerError("Use a decimal string in \(currency.code) with up to \(currency.fractionDigits) decimal places.")
    }
    return amount
}

private func paletteColor(_ input: String) throws -> PaletteColor {
    guard let color = PaletteColor(rawValue: input) else { throw LedgerError("Unknown Montra color.") }
    return color
}

private func accountJSON(_ account: Account) -> JSONObject {
    [
        "id": id(account.id), "name": account.name, "currency": account.currency.code,
        "initial_amount": amountText(account.initialAmount), "balance": amountText(account.balance),
        "is_savings": account.isSavings,
        "is_hidden_from_overview": account.isHiddenFromOverview,
        "operation_count": account.operationCount, "icon_name": account.iconName, "color": account.colorRaw,
    ]
}

private func categoryJSON(_ category: Category) -> JSONObject {
    [
        "id": id(category.id), "name": category.name, "kind": category.kind.rawValue,
        "is_mandatory": category.isMandatory, "is_system": category.isSystem,
        "parent_id": category.parent.map { id($0.id) } as Any? ?? NSNull(),
        "effective_is_mandatory": category.isMandatory || (category.parent?.isMandatory ?? false),
        "icon_name": category.iconName, "color": category.colorRaw,
    ]
}

private func operationJSON(_ operation: Operation) -> JSONObject {
    [
        "id": id(operation.id), "kind": operation.kind.rawValue, "amount": amountText(operation.amount),
        "currency": operation.currency.code, "date": operation.date.ISO8601Format(),
        "category": operation.category.map(categoryJSON) as Any? ?? NSNull(),
        "account_id": operation.account.map { id($0.id) } as Any? ?? NSNull(),
        "transfer_id": operation.transferID.map(id) as Any? ?? NSNull(),
        "place": operation.place, "note": operation.note,
    ]
}

private func clean(_ input: String, max: Int, required: Bool = false) throws -> String {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.unicodeScalars.count <= max, !required || !value.isEmpty else {
        throw LedgerError("Invalid text field. Check required fields and length limits.")
    }
    return value
}

private func operationUUID(account: UUID, source: String, externalId: String) -> UUID {
    // Match the original MCP's Python json.dumps and uuid5 to preserve imported IDs.
    func quote(_ value: String) -> String {
        var result = "\""
        for unit in value.utf16 {
            switch unit {
            case 0x22: result += "\\\""
            case 0x5c: result += "\\\\"
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0a: result += "\\n"
            case 0x0c: result += "\\f"
            case 0x0d: result += "\\r"
            case 0x20...0x7e: result.append(Character(UnicodeScalar(unit)!))
            default: result += String(format: "\\u%04x", unit)
            }
        }
        return result + "\""
    }
    var data = withUnsafeBytes(of: account.uuid) { Data($0) }
    data.append(contentsOf: "[\(quote(source)), \(quote(externalId))]".utf8)
    var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

// MARK: - Transfers, plans, and operation removal

private struct TransferSelection: Decodable {
    let transferId: UUID
}

private struct TransferInput: Decodable {
    let sourceAccountId: UUID
    let destinationAccountId: UUID
    let requestId: UUID
    let date: Date
    let sent: String
    let received: String?
}

private struct LedgerPlanFilter: Decodable {
    let accountId: UUID?
    let seriesId: UUID?
    let status: Status?
    let fromDate: Date?
    let beforeDate: Date?
    let limit: Int?
    let offset: Int?

    enum Status: String, Decodable {
        case all, pending, upcoming, missed, linked

        func matches(_ plan: PlannedOperation, today: Date) -> Bool {
            switch self {
            case .all: true
            case .pending: !plan.isLinked
            case .upcoming: !plan.isLinked && plan.date >= today
            case .missed: !plan.isLinked && plan.date < today
            case .linked: plan.isLinked
            }
        }
    }
}

private struct PlanInput: Decodable {
    let accountId: UUID
    @CurrencyCode var currency: Currency
    let requestId: UUID
    let operation: ImportRow
    let frequency: String
    let weekdays: [Int]?
    let endDate: Date
}

private struct PlanLink: Decodable {
    let planId: UUID
    let operationId: UUID
}

private struct PlanRecord: Decodable {
    let planId: UUID
    let date: Date?
}

private struct PlanDeletion: Decodable {
    let planId: UUID
    let scope: Scope?
    let previewToken: String?

    enum Scope: String, Decodable {
        case occurrence, series
    }
}

private struct OperationDeletion: Decodable {
    let operationIds: [UUID]
    let previewToken: String?
}

private extension Store {
    func balances() throws -> JSONObject {
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [.init(\.sortIndex)]))
        let groups = Dictionary(grouping: accounts, by: \.currency)
        let totals: [JSONObject] = Currency.allCases.compactMap { currency in
            guard let accounts = groups[currency] else { return nil }
            return ["currency": currency.code, "balance": amountText(Finance.total(accounts))]
        }
        return ["accounts": accounts.map(accountJSON), "totals": totals]
    }

    func getTransfer(_ transferID: UUID) throws -> JSONObject {
        let legs = try transferLegs(transferID)
        guard !legs.isEmpty else { throw LedgerError("Transfer not found.", status: 404) }
        return transferJSON(transferID, legs: legs)
    }

    func createTransfer(_ input: TransferInput) throws -> JSONObject {
        let source = try findAccount(input.sourceAccountId)
        let destination = try findAccount(input.destinationAccountId)
        guard source.id != destination.id else { throw LedgerError("Choose two different accounts.") }
        let sent = try money(input.sent, currency: source.currency)
        guard let receivedText = input.received ?? (source.currency == destination.currency ? input.sent : nil) else {
            throw LedgerError("Provide the received amount for a transfer between different currencies.")
        }
        let received = try money(receivedText, currency: destination.currency)
        guard sent > 0, received > 0 else { throw LedgerError("Both transfer amounts must be positive.") }

        let transferID = input.requestId
        let previous = try transferLegs(transferID)
        if !previous.isEmpty {
            guard previous.count == 2,
                  previous.contains(where: {
                      $0.kind == .expense && $0.account?.id == source.id && $0.amount == sent && $0.date == input.date
                  }),
                  previous.contains(where: {
                      $0.kind == .income && $0.account?.id == destination.id && $0.amount == received && $0.date == input.date
                  }) else { throw LedgerError("This request_id already identifies a different or incomplete transfer.", status: 409) }
            return ["created": false, "transfer": transferJSON(transferID, legs: previous)]
        }
        TransferRepository(context: context).create(
            from: source, to: destination, sent: sent, received: received, date: input.date,
            transferID: transferID, saveImmediately: false
        )
        let legs = try transferLegs(transferID)
        guard legs.count == 2 else { throw LedgerError("Could not stage both transfer legs.", status: 500) }
        return ["created": true, "transfer": transferJSON(transferID, legs: legs)]
    }

    func listPlans(_ filter: LedgerPlanFilter) throws -> JSONObject {
        if let accountID = filter.accountId { _ = try findAccount(accountID) }
        try validateDateRange(filter.fromDate, filter.beforeDate)
        let today = Calendar.current.startOfDay(for: .now)
        let status = filter.status ?? .pending
        let plans = try context.fetch(FetchDescriptor<PlannedOperation>()).filter { plan in
            (filter.accountId.map { plan.account?.id == $0 } ?? true) &&
            (filter.seriesId.map { plan.seriesID == $0 } ?? true) &&
            (filter.fromDate.map { plan.date >= $0 } ?? true) &&
            (filter.beforeDate.map { plan.date < $0 } ?? true) &&
            status.matches(plan, today: today)
        }.sorted {
            if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
            return status == .missed ? $0.date > $1.date : $0.date < $1.date
        }
        let (page, next) = try paginate(plans, limit: filter.limit, offset: filter.offset)
        return ["plans": page.map(planJSON), "total": plans.count, "next_offset": next]
    }

    func createPlan(_ input: PlanInput) throws -> JSONObject {
        let account = try findAccount(input.accountId)
        guard account.currency == input.currency else { throw LedgerError("Currency mismatch. Use the account's currency.") }
        guard let frequency = PlanFrequency(rawValue: input.frequency) else { throw LedgerError("Unknown plan frequency.") }
        let days = input.weekdays ?? []
        let weekdays = Set(days)
        guard days.count <= 7, weekdays.allSatisfy({ (1...7).contains($0) }), weekdays.isEmpty || frequency == .week else {
            throw LedgerError("Weekdays are only for weekly plans and must be integers from 1 to 7.")
        }
        let row = input.operation
        let amount = try money(row.amount, currency: account.currency)
        guard amount > 0 else { throw LedgerError("Amount must be positive.") }
        let category = try row.categoryId.map { try findCategory($0, kind: row.kind) }
        let place = try clean(row.place ?? "", max: 250)
        let note = try clean(row.note ?? "", max: 500)
        let seriesID = input.requestId
        let previous = try planSeries(seriesID)
        if !previous.isEmpty {
            guard previous.allSatisfy({
                $0.account?.id == account.id && $0.currency == account.currency &&
                $0.kind == row.kind && $0.amount == amount && $0.category?.id == category?.id &&
                $0.frequency == frequency && $0.weekdays == weekdays && $0.seriesStart == row.date &&
                $0.seriesEnd == input.endDate && $0.place == place && $0.note == note
            }) else { throw LedgerError("This request_id already identifies a different plan series.", status: 409) }
            return ["created": false, "series_id": id(seriesID), "plan_count": previous.count]
        }
        let plans = PlanRepository(context: context).create(
            kind: row.kind, amount: amount, account: account, category: category, date: row.date,
            place: place, note: note, frequency: frequency, weekdays: weekdays, end: input.endDate,
            seriesID: seriesID, saveImmediately: false
        )
        guard !plans.isEmpty else { throw LedgerError("The schedule does not contain any occurrences.") }
        return ["created": true, "series_id": id(seriesID), "plan_count": plans.count]
    }

    func linkPlan(_ input: PlanLink) throws -> JSONObject {
        let plan = try findPlan(input.planId)
        let operation = try findOperation(input.operationId)
        if plan.linkedOperationID == operation.id {
            return ["linked": false, "plan": planJSON(plan)]
        }
        guard !plan.isLinked, operation.kind == plan.kind, !operation.isTransfer else {
            throw LedgerError("Choose an unlinked plan and a non-transfer operation of the same kind.")
        }
        let operationID = operation.id
        let matches = try context.fetchCount(FetchDescriptor<PlannedOperation>(
            predicate: #Predicate { $0.linkedOperationID == operationID }
        ))
        guard matches == 0 else { throw LedgerError("This operation is already linked to a plan.", status: 409) }
        plan.linkedOperationID = operationID
        return ["linked": true, "plan": planJSON(plan)]
    }

    func recordPlan(_ input: PlanRecord) throws -> JSONObject {
        let plan = try findPlan(input.planId)
        if let operationID = plan.linkedOperationID {
            let operation = try findOperation(operationID)
            if let date = input.date, date != operation.date {
                throw LedgerError("This plan is already linked to an operation with a different date.", status: 409)
            }
            return ["created": false, "operation": operationJSON(operation), "plan": planJSON(plan)]
        }
        guard let account = plan.account, account.currency == plan.currency else {
            throw LedgerError("The plan's account is missing or its currency changed.")
        }
        let operation = OperationRepository(context: context).create(
            kind: plan.kind, amount: plan.amount, account: account, category: plan.category,
            date: input.date ?? .now, place: plan.place, latitude: nil, longitude: nil,
            note: plan.note, saveImmediately: false
        )
        plan.linkedOperationID = operation.id
        return ["created": true, "operation": operationJSON(operation), "plan": planJSON(plan)]
    }

    func deletePlan(_ input: PlanDeletion, apply: Bool) throws -> JSONObject {
        let selected = try findPlan(input.planId)
        let scope = input.scope ?? .occurrence
        let plans = scope == .series ? try planSeries(selected.seriesID) : [selected]
        let snapshots = plans.sorted { $0.id.uuidString < $1.id.uuidString }.map(planJSON)
        let token = try previewToken(["action": "delete_plan", "plan_id": id(selected.id), "scope": scope.rawValue, "plans": snapshots])
        if apply {
            guard input.previewToken == token else {
                throw LedgerError("The plan changed. Run preview_delete_plan again.", status: 409)
            }
            for plan in plans { context.delete(plan) }
            return ["deleted_plan_count": plans.count]
        }
        return [
            "plan": planJSON(selected), "plan_count": plans.count, "scope": scope.rawValue,
            "linked_operation_count": plans.filter(\.isLinked).count, "preview_token": token,
        ]
    }

    func recategorizeOperations(_ input: OperationRecategorization) throws -> JSONObject {
        let operations = try selectOperations(input.operationIds)
        guard operations.allSatisfy({ !$0.isTransfer }) else {
            throw LedgerError("Transfers cannot be recategorized.")
        }
        guard let kind = operations.first?.kind, operations.allSatisfy({ $0.kind == kind }) else {
            throw LedgerError("Choose operations of the same kind.")
        }
        let category = try findCategory(input.categoryId, kind: kind)
        let changed = operations.filter { $0.category?.id != category.id }
        for operation in changed { operation.category = category }
        return [
            "updated_count": changed.count,
            "operations": operations.map(operationJSON),
        ]
    }

    func deleteOperations(_ input: OperationDeletion, apply: Bool) throws -> JSONObject {
        let selected = try selectOperations(input.operationIds)

        // Selecting one leg removes the whole transfer, as in the app.
        var targets = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        for transferID in Set(selected.compactMap(\.transferID)) {
            for operation in try transferLegs(transferID) { targets[operation.id] = operation }
        }
        let operations = targets.values.sorted { $0.id.uuidString < $1.id.uuidString }
        let ids = Set(targets.keys)
        let plans = try context.fetch(FetchDescriptor<PlannedOperation>()).filter {
            $0.linkedOperationID.map(ids.contains) ?? false
        }
        let snapshots = operations.map(operationJSON)
        let token = try previewToken([
            "action": "delete_operations", "operations": snapshots, "plan_ids": plans.map { id($0.id) }.sorted(),
        ])
        if apply {
            guard input.previewToken == token else {
                throw LedgerError("The selection changed. Run preview_delete_operations again.", status: 409)
            }
            for plan in plans { plan.linkedOperationID = nil }
            for operation in operations { context.delete(operation) }
            return ["deleted_operation_count": operations.count, "reopened_plan_count": plans.count]
        }
        return [
            "operations": snapshots, "operation_count": operations.count,
            "linked_plan_count": plans.count, "preview_token": token,
        ]
    }

    func transferLegs(_ transferID: UUID) throws -> [Operation] {
        try context.fetch(FetchDescriptor<Operation>(predicate: #Predicate { $0.transferID == transferID }))
            .sorted { $0.kindRaw == $1.kindRaw ? $0.id.uuidString < $1.id.uuidString : $0.kindRaw < $1.kindRaw }
    }

    func planSeries(_ seriesID: UUID) throws -> [PlannedOperation] {
        try context.fetch(FetchDescriptor<PlannedOperation>(predicate: #Predicate { $0.seriesID == seriesID }))
    }

    func findPlan(_ planID: UUID) throws -> PlannedOperation {
        let plans = try context.fetch(FetchDescriptor<PlannedOperation>(predicate: #Predicate { $0.id == planID }))
        guard plans.count == 1, let plan = plans.first else { throw LedgerError("Plan not found or ambiguous.", status: 404) }
        return plan
    }

    func findOperation(_ operationID: UUID) throws -> Operation {
        let matches = try context.fetch(FetchDescriptor<Operation>(predicate: #Predicate { $0.id == operationID }))
        guard matches.count == 1, let operation = matches.first else {
            throw LedgerError("Operation not found or ambiguous.", status: 404)
        }
        return operation
    }

    func selectOperations(_ requestedIDs: [UUID]) throws -> [Operation] {
        let uniqueIDs = Set(requestedIDs)
        guard (1...100).contains(requestedIDs.count), uniqueIDs.count == requestedIDs.count else {
            throw LedgerError("Provide 1 to 100 distinct operation IDs.")
        }
        let selected = try context.fetch(FetchDescriptor<Operation>(predicate: #Predicate { requestedIDs.contains($0.id) }))
        guard selected.count == requestedIDs.count, Set(selected.map(\.id)) == uniqueIDs else {
            throw LedgerError("One or more operations were not found or are ambiguous.", status: 404)
        }
        let byID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        return requestedIDs.compactMap { byID[$0] }
    }

    func findCategory(_ categoryID: UUID, kind: OperationKind) throws -> Category {
        let matches = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == categoryID }))
        guard matches.count == 1, let category = matches.first, category.kind == kind else {
            throw LedgerError("Choose an existing category of kind \(kind.rawValue).")
        }
        return category
    }
}

private func matchesSearch(_ operation: Operation, tokens: [Substring]) -> Bool {
    guard !tokens.isEmpty else { return true }
    let russian = AppLocalization.russianBundle
    let kindKey = operation.kind == .expense ? "transaction.expense" : "transaction.income"
    let legacyKind = russian.localizedString(forKey: kindKey, value: nil, table: nil)
    let transfer = operation.isTransfer ? String(localized: "transaction.transfer") : ""
    let legacyTransfer = operation.isTransfer
        ? russian.localizedString(forKey: "transaction.transfer", value: nil, table: nil) : ""
    let searchable = [
        operation.account?.name ?? "", operation.category?.name ?? "", operation.category?.displayName ?? "",
        operation.category?.parent?.name ?? "", operation.category?.parent?.displayName ?? "",
        operation.place, operation.note, operation.kind.title, legacyKind, transfer, legacyTransfer,
        amountText(operation.amount), MoneyFormat.string(operation.amount, currency: operation.currency),
        operation.date.ISO8601Format(), AppDate.short(operation.date),
    ].joined(separator: " ")
    return tokens.allSatisfy { searchable.localizedStandardContains($0) }
}

private func validateDateRange(_ start: Date?, _ end: Date?) throws {
    if let start, let end, start >= end { throw LedgerError("from_date must be earlier than before_date.") }
}

private func paginate<T>(_ rows: [T], limit: Int?, offset: Int?) throws -> (ArraySlice<T>, Any) {
    let offset = offset ?? 0
    let limit = limit ?? 25
    guard (1...100).contains(limit), (0...1_000_000).contains(offset) else {
        throw LedgerError("Invalid limit or offset.")
    }
    let page = rows.dropFirst(offset).prefix(limit)
    let end = offset + page.count
    return (page, end < rows.count ? end as Any : NSNull())
}

private func transferJSON(_ transferID: UUID, legs: [Operation]) -> JSONObject {
    [
        "id": id(transferID), "operations": legs.map(operationJSON),
        "complete": legs.count == 2 && Set(legs.map(\.kind)) == Set([.expense, .income]),
    ]
}

private func planJSON(_ plan: PlannedOperation) -> JSONObject {
    let status = plan.isLinked ? "linked" : plan.isMissed ? "missed" : plan.isDueToday ? "today" : "upcoming"
    return [
        "id": id(plan.id), "series_id": id(plan.seriesID), "kind": plan.kind.rawValue,
        "amount": amountText(plan.amount), "currency": plan.currency.code, "date": plan.date.ISO8601Format(),
        "account_id": plan.account.map { id($0.id) } as Any? ?? NSNull(),
        "category": plan.category.map(categoryJSON) as Any? ?? NSNull(),
        "place": plan.place, "note": plan.note, "frequency": plan.frequency.rawValue,
        "weekdays": plan.weekdays.sorted(), "series_start": plan.seriesStart.ISO8601Format(),
        "series_end": plan.seriesEnd.ISO8601Format(), "status": status,
        "linked_operation_id": plan.linkedOperationID.map(id) as Any? ?? NSNull(),
    ]
}
