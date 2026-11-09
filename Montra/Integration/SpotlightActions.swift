import AppIntents
import SwiftUI

@available(macOS 26.0, *)
struct SpotlightAddExpense: AppIntent {
    static let title: LocalizedStringResource = "common.add_expense"
    static let description = IntentDescription("spotlight.records_an_expense_in_montra")
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.add_expense \(\.$amount) \(\.$account) \(\.$category)")
    }

    @Parameter(title: "common.amount") var amount: String
    @Parameter(title: "common.account") var account: SpotlightAccount
    @Parameter(title: "common.category", query: SpotlightExpenseCategoryQuery())
    var category: SpotlightCategory
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try ledger.createOperation(
            kind: .expense, amount: SpotlightLedger.parseAmount(amount), accountID: account.id, categoryID: category.id
        )
        return spotlightReceipt("common.expense_recorded")
    }
}

@available(macOS 26.0, *)
struct SpotlightAddIncome: AppIntent {
    static let title: LocalizedStringResource = "common.add_income"
    static let description = IntentDescription("spotlight.records_income_in_montra")
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.add_income \(\.$amount) \(\.$account) \(\.$category)")
    }

    @Parameter(title: "common.amount") var amount: String
    @Parameter(title: "common.account") var account: SpotlightAccount
    @Parameter(title: "common.category", query: SpotlightIncomeCategoryQuery())
    var category: SpotlightCategory
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try ledger.createOperation(
            kind: .income, amount: SpotlightLedger.parseAmount(amount), accountID: account.id, categoryID: category.id
        )
        return spotlightReceipt("common.income_recorded")
    }
}

@available(macOS 26.0, *)
struct SpotlightTransfer: AppIntent {
    static let title: LocalizedStringResource = "spotlight.transfer_between_accounts"
    static let description = IntentDescription("spotlight.records_a_transfer_between_montra")
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.transfer \(\.$sent) \(\.$source) \(\.$destination) \(\.$received)")
    }

    @Parameter(title: "common.source_account") var source: SpotlightAccount
    @Parameter(title: "common.destination_account") var destination: SpotlightAccount
    @Parameter(title: "transfer.amount_sent") var sent: String
    @Parameter(title: "transfer.amount_received", description: "spotlight.enter_this_when_transferring_between")
    var received: String?
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let received = try received.flatMap { input in
            input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try SpotlightLedger.parseAmount(input)
        }
        try ledger.transfer(
            from: source.id, to: destination.id, sent: SpotlightLedger.parseAmount(sent), received: received
        )
        return spotlightReceipt("common.transfer_recorded")
    }
}

@available(macOS 26.0, *)
struct SpotlightCreateAccount: AppIntent {
    static let title: LocalizedStringResource = "common.create_account"
    static let description = IntentDescription("spotlight.creates_an_account_for_tracking")
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.create_account \(\.$name) \(\.$currency) \(\.$initialAmount)")
    }

    @Parameter(title: "common.name") var name: String
    @Parameter(title: "common.currency") var currency: Currency
    @Parameter(title: "common.opening_balance_2", default: "0") var initialAmount: String
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try ledger.createAccount(name: name, currency: currency, initialAmount: SpotlightLedger.parseAmount(initialAmount))
        return spotlightReceipt("common.account_created")
    }
}

@available(macOS 26.0, *)
struct SpotlightCreateCategory: AppIntent {
    static let title: LocalizedStringResource = "common.create_category"
    static let description = IntentDescription("spotlight.creates_an_income_or_expense")
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.create_category \(\.$name) \(\.$kind)") {
            \.$isMandatory
        }
    }

    @Parameter(title: "common.name") var name: String
    @Parameter(title: "common.type") var kind: OperationKind
    @Parameter(title: "common.essential_expense", default: false) var isMandatory: Bool
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try ledger.createCategory(name: name, kind: kind, isMandatory: isMandatory)
        return spotlightReceipt("common.category_created")
    }
}

@available(macOS 26.0, *)
struct SpotlightCreateSubcategory: AppIntent {
    static let title: LocalizedStringResource = "common.create_subcategory"
    static let description = IntentDescription("spotlight.creates_a_subcategory_under_an")
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.create_subcategory \(\.$name) \(\.$parent)")
    }

    @Parameter(title: "common.name") var name: String
    @Parameter(title: "common.parent_category", query: SpotlightParentCategoryQuery())
    var parent: SpotlightCategory
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try ledger.createSubcategory(name: name, parentID: parent.id)
        return spotlightReceipt("common.subcategory_created")
    }
}

@available(macOS 26.0, *)
struct SpotlightAccountBalance: AppIntent {
    static let title: LocalizedStringResource = "common.account_balance"
    static let description = IntentDescription("spotlight.shows_the_balance_of_a")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.account_balance \(\.$account)")
    }

    @Parameter(title: "common.account") var account: SpotlightAccount
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let balance = try ledger.balance(id: account.id)
        return .result(dialog: "spotlight.balance_dialog \(balance.name) \(balance.amount)", view: VStack(alignment: .leading, spacing: 5) {
            Text(balance.name)
                .foregroundStyle(.secondary)
            Text(balance.amount)
                .font(.title2.weight(.semibold).monospacedDigit())
        }.padding())
    }
}

@available(macOS 26.0, *)
struct SpotlightAllBalances: AppIntent {
    static let title: LocalizedStringResource = "common.all_accounts"
    static let description = IntentDescription("spotlight.shows_the_total_and_individual")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var parameterSummary: some ParameterSummary {
        Summary("spotlight.summary.all_accounts \(\.$currency)")
    }

    @Parameter(title: "common.total_currency") var currency: Currency?
    @Dependency private var ledger: SpotlightLedger

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let overview = try ledger.overview(currency: currency)
        let dialog: IntentDialog
        if overview.accounts.isEmpty {
            dialog = "spotlight.there_are_no_accounts_in"
        } else if !overview.missingCurrencies.isEmpty {
            dialog = "spotlight.partial_total \(overview.total)"
        } else if overview.usesApproximateRates {
            dialog = "spotlight.estimated_total \(overview.total)"
        } else {
            dialog = "spotlight.total_across_accounts \(overview.total)"
        }
        return .result(dialog: dialog, view: SpotlightOverviewView(overview: overview))
    }
}

private func spotlightReceipt(_ title: LocalizedStringResource) -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    .result(dialog: IntentDialog(title), view: Label {
        Text(title)
    } icon: {
        Image(systemName: "checkmark.circle")
    }.padding())
}

private struct SpotlightOverviewView: View {
    let overview: SpotlightOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if overview.accounts.isEmpty {
                Text(String(localized: "spotlight.there_are_no_accounts_in"))
            } else {
                Text(overview.missingCurrencies.isEmpty ? String(localized: "spotlight.total_across_accounts_2") : String(localized: "common.partial_total"))
                    .foregroundStyle(.secondary)
                Text(overview.total)
                    .font(.title2.weight(.semibold).monospacedDigit())
                if !overview.missingCurrencies.isEmpty {
                    Text(String(localized: "spotlight.no_exchange_rate_for \(overview.missingCurrencies.joined(separator: ", "))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if overview.usesApproximateRates {
                    Text(String(localized: "spotlight.using_approximate_rates"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(overview.accounts) { account in
                            HStack(spacing: 12) {
                                Text(account.name)
                                Spacer(minLength: 0)
                                Text(account.amount)
                                    .monospacedDigit()
                                    .fixedSize()
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
    }
}

@available(macOS 26.0, *)
struct MontraAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SpotlightAddExpense(), phrases: ["spotlight.phrase.add_expense \(.applicationName)"],
                    shortTitle: "common.add_expense", systemImageName: "minus.circle")
        AppShortcut(intent: SpotlightAddIncome(), phrases: ["spotlight.phrase.add_income \(.applicationName)"],
                    shortTitle: "common.add_income", systemImageName: "plus.circle")
        AppShortcut(intent: SpotlightTransfer(), phrases: ["spotlight.phrase.transfer \(.applicationName)"],
                    shortTitle: "spotlight.transfer_between_accounts", systemImageName: "arrow.left.arrow.right")
        AppShortcut(intent: SpotlightCreateAccount(), phrases: ["spotlight.phrase.create_account \(.applicationName)"],
                    shortTitle: "common.create_account", systemImageName: "creditcard")
        AppShortcut(intent: SpotlightCreateCategory(), phrases: ["spotlight.phrase.create_category \(.applicationName)"],
                    shortTitle: "common.create_category", systemImageName: "tag")
        AppShortcut(intent: SpotlightCreateSubcategory(), phrases: ["spotlight.phrase.create_subcategory \(.applicationName)"],
                    shortTitle: "common.create_subcategory", systemImageName: "tag.circle")
        AppShortcut(intent: SpotlightAccountBalance(), phrases: ["spotlight.phrase.account_balance \(.applicationName)"],
                    shortTitle: "common.account_balance", systemImageName: "wallet.bifold")
        AppShortcut(intent: SpotlightAllBalances(), phrases: ["spotlight.phrase.all_accounts \(.applicationName)"],
                    shortTitle: "common.all_accounts", systemImageName: "list.bullet.rectangle")
    }
}
