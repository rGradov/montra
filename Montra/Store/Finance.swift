import Foundation
import SwiftData

/// Figures shared by the Overview, an account and the period card. All of it is
/// pure, so the same numbers back every screen and a snapshot.
enum Finance {
    static func balance(of account: Account) -> Decimal {
        account.balance
    }

    static func total(_ accounts: [Account]) -> Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    static func accounts(_ accounts: [Account], in currency: Currency) -> [Account] {
        accounts.filter { $0.currency == currency }
    }

    /// Currencies that actually hold an account, in the app's stable order.
    static func currencies(in accounts: [Account]) -> [Currency] {
        let present = Set(accounts.map(\.currency))
        return Currency.allCases.filter { present.contains($0) }
    }

    static func operations(_ operations: [Operation], in period: Period?) -> [Operation] {
        guard let period else { return operations }
        return operations.filter { period.contains($0.date) }
    }

    static func sum(_ operations: [Operation], kind: OperationKind, currency: Currency) -> Decimal {
        operations
            .filter { $0.kind == kind && $0.currency == currency }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    static func net(_ operations: [Operation], currency: Currency) -> Decimal {
        operations
            .filter { $0.currency == currency }
            .reduce(Decimal(0)) { $0 + $1.signedAmount }
    }

    static func mandatoryExpenses(_ operations: [Operation], currency: Currency) -> Decimal {
        operations
            .filter {
                $0.kind == .expense
                    && $0.currency == currency
                    && (($0.category?.isMandatory ?? false) || ($0.category?.parent?.isMandatory ?? false))
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    static func share(_ part: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return (part as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue
    }

    /// "12,3%", "0%", "<0,1%" — the way the reference shows a share.
    static func shareText(_ share: Double) -> String {
        if share <= 0 { return "0%" }
        if share < 0.001 { return String(localized: "common.0_1") }
        return MoneyFormat.number(Decimal(share * 100), fractionDigits: 1) + "%"
    }

    /// "across 5 accounts" — the hero's line under the total.
    static func onAccountsText(_ count: Int) -> String {
        String(localized: "finance.on_accounts \(count)")
    }

    /// Every account's balance converted into `currency`. Accounts whose rate is
    /// missing are left out rather than counted at a guessed price.
    static func totalConverted(_ accounts: [Account], to currency: Currency, rates: ExchangeRates) -> Decimal {
        accounts.reduce(Decimal(0)) { sum, account in
            sum + (rates.convert(account.balance, from: account.currency, to: currency) ?? 0)
        }
    }

    static func converted(_ value: Decimal, from: Currency, to: Currency, rates: ExchangeRates) -> Decimal? {
        rates.convert(value, from: from, to: to)
    }

    static func sumConverted(
        _ operations: [Operation],
        kind: OperationKind,
        to currency: Currency,
        rates: ExchangeRates
    ) -> Decimal {
        operations
            .filter { $0.kind == kind && $0.transferID == nil }
            .reduce(Decimal(0)) { sum, operation in
                sum + (rates.convert(operation.amount, from: operation.currency, to: currency) ?? 0)
            }
    }

    static func mandatoryConverted(
        _ operations: [Operation],
        to currency: Currency,
        rates: ExchangeRates
    ) -> Decimal {
        operations
            .filter {
                $0.kind == .expense
                    && $0.transferID == nil
                    && (($0.category?.isMandatory ?? false) || ($0.category?.parent?.isMandatory ?? false))
            }
            .reduce(Decimal(0)) { sum, operation in
                sum + (rates.convert(operation.amount, from: operation.currency, to: currency) ?? 0)
            }
    }

    static func operationsCountText(_ count: Int) -> String {
        String(localized: "finance.transaction_count \(count)")
    }

    static func accountsCountText(_ count: Int) -> String {
        String(localized: "finance.account_count \(count)")
    }

    static func daysSuffix(_ days: Int) -> String {
        String(daysText(days).drop(while: { $0.isNumber || $0.isWhitespace }))
    }

    static func daysText(_ days: Int) -> String {
        String(localized: "finance.day_count \(days)")
    }

    /// Operations of one currency in one period, with the figures the Overview
    /// and the period card quote.
    struct PeriodSummary {
        let income: Decimal
        let expense: Decimal
        let mandatory: Decimal

        var net: Decimal { income - expense }
        var free: Decimal { income - mandatory }
    }

    static func summary(for operations: [Operation], currency: Currency) -> PeriodSummary {
        PeriodSummary(
            income: sum(operations, kind: .income, currency: currency),
            expense: sum(operations, kind: .expense, currency: currency),
            mandatory: mandatoryExpenses(operations, currency: currency)
        )
    }
}
