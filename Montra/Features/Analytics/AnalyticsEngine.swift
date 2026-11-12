import Foundation
import SwiftUI

/// The Analytics screen's two scopes. The period is the app's unit of money;
/// the month is the calendar view for people who think in months.
enum AnalyticsScope: String, CaseIterable, Identifiable {
    case period
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .period: String(localized: "common.period")
        case .month: String(localized: "common.month")
        case .year: String(localized: "common.year")
        }
    }
}

enum AnalyticsDimension: String, CaseIterable, Identifiable {
    case category
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: String(localized: "common.categories")
        case .account: String(localized: "common.accounts")
        }
    }
}

enum AnalyticsFilter: String, CaseIterable, Identifiable {
    case all
    case mandatory
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "common.all")
        case .mandatory: String(localized: "analytics.essential")
        case .free: String(localized: "analytics.discretionary")
        }
    }
}

/// One concrete window of money: a financial period or a calendar month.
struct AnalyticsRange: Equatable {
    let scope: AnalyticsScope
    let start: Date
    let end: Date
    let totalDays: Int
    let elapsedDays: Int
    let isCurrent: Bool
    let previousStart: Date?
    let previousEnd: Date?
    let previousTotalDays: Int

    var daysLeft: Int { max(0, totalDays - elapsedDays) }

    /// The stepper's label: the whole period, or the month name.
    var title: String {
        switch scope {
        case .period:
            AppDate.range(start, end)
        case .month:
            AppDate.monthYear.string(from: start).capitalized
        case .year:
            String(Calendar.current.component(.year, from: start))
        }
    }

    /// The subtitle's date span. A running month stops at today, so the header
    /// never claims to include days that have not happened.
    var spanTitle: String {
        switch scope {
        case .period:
            return AppDate.range(start, end)
        case .month:
            let last = Calendar.current.date(byAdding: .day, value: max(0, elapsedDays - 1), to: start) ?? start
            return AppDate.range(start, last)
        case .year:
            return String(Calendar.current.component(.year, from: start))
        }
    }

    var previousTitle: String? {
        guard let previousStart, let previousEnd else { return nil }
        switch scope {
        case .period:
            return AppDate.range(previousStart, previousEnd)
        case .month:
            return AppDate.monthYear.string(from: previousStart).capitalized
        case .year:
            return String(Calendar.current.component(.year, from: previousStart))
        }
    }
}

struct AnalyticsSlice: Identifiable {
    let id: UUID
    let name: String
    let symbol: String
    /// The bar and icon shade.
    let color: Color
    let amount: Decimal
    let operationCount: Int
    let operations: [Operation]
    let isMandatory: Bool
    let previousAmount: Decimal?
    let delta: Double?
}

/// One category's share of a day, already converted to the display currency.
/// The day popup shows one row per group instead of one row per operation.
struct AnalyticsDayGroup: Identifiable {
    /// Stable key: the category's UUID string, `"transfer"` or `"uncategorized"`.
    let id: String
    let title: String
    /// Sum of the group's operations in the display currency, positive.
    let amount: Decimal
    let count: Int
    /// Representative operation for the icon and colour.
    let sample: Operation
}

struct AnalyticsDay: Identifiable {
    let id: Int
    let date: Date
    let amount: Decimal
    let operationCount: Int
    let operations: [Operation]
    /// `operations` rolled up by category, largest first.
    let groups: [AnalyticsDayGroup]
    let level: Int
    let isToday: Bool
    let isFuture: Bool
}

struct AnalyticsSnapshot {
    let range: AnalyticsRange
    let expenses: Decimal
    let income: Decimal
    let mandatory: Decimal
    let freeExpenses: Decimal
    let remaining: Decimal
    let operationsCount: Int
    let incomeCount: Int
    let savingsIn: Decimal
    let savingsOut: Decimal
    let categories: [AnalyticsSlice]
    let accounts: [AnalyticsSlice]
    let days: [AnalyticsDay]
    let currentCumulative: [Decimal?]
    let previousCumulative: [Decimal]
    let pace: [Decimal]
    let previousFullTotal: Decimal
    let comparisonTotal: Decimal
    let hasComparison: Bool
    let average: Decimal
    /// The typical day that had spending: the median of the daily totals on the
    /// elapsed days with expenses.
    let medianSpendingDay: Decimal
    /// How many elapsed days carried spending — the population of the median.
    let spendingDayCount: Int
    let chartMax: Double

    var hasExpenses: Bool { expenses > 0 }
    var hasSavings: Bool { savingsIn > 0 || savingsOut > 0 }
    var todayDay: Int? { range.isCurrent && range.elapsedDays > 0 ? range.elapsedDays : nil }

    var filterCounts: (all: Int, mandatory: Int, free: Int) {
        let essential = categories.filter(\.isMandatory).count
        return (categories.count, essential, max(0, categories.count - essential))
    }
}

enum AnalyticsEngine {
    private static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let noAccountID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    // MARK: - Ranges

    static func periodRange(
        period: Period,
        previous: Period?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AnalyticsRange {
        let total = AppDate.daysBetween(period.start, period.end)
        let current = period.contains(now)
        let elapsed = current
            ? min(max(AppDate.daysBetween(period.start, now), 1), total)
            : total
        let previousDays = previous.map { AppDate.daysBetween($0.start, $0.end) } ?? 0
        return AnalyticsRange(
            scope: .period,
            start: period.start,
            end: period.end,
            totalDays: total,
            elapsedDays: elapsed,
            isCurrent: current,
            previousStart: previous?.start,
            previousEnd: previous?.end,
            previousTotalDays: previousDays
        )
    }

    static func monthRange(
        containing date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AnalyticsRange {
        let start = calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let end = next.addingTimeInterval(-1)
        let total = calendar.range(of: .day, in: .month, for: start)?.count ?? AppDate.daysBetween(start, end)
        let current = calendar.isDate(now, equalTo: start, toGranularity: .month)
        let elapsed = current ? min(max(calendar.component(.day, from: now), 1), total) : total

        let previousStart = calendar.date(byAdding: .month, value: -1, to: start)
        let previousNext = previousStart.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        let previousEnd = previousNext?.addingTimeInterval(-1)
        let previousDays = previousStart.map {
            calendar.range(of: .day, in: .month, for: $0)?.count ?? 0
        } ?? 0

        return AnalyticsRange(
            scope: .month,
            start: start,
            end: end,
            totalDays: total,
            elapsedDays: elapsed,
            isCurrent: current,
            previousStart: previousStart,
            previousEnd: previousEnd,
            previousTotalDays: previousDays
        )
    }

    static func yearRange(
        containing date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AnalyticsRange {
        let start = calendar.dateInterval(of: .year, for: date)?.start
            ?? calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        let end = next.addingTimeInterval(-1)
        let total = calendar.range(of: .day, in: .year, for: start)?.count ?? AppDate.daysBetween(start, end)
        let current = calendar.isDate(now, equalTo: start, toGranularity: .year)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let elapsed = current ? min(max(dayOfYear, 1), total) : total

        let previousStart = calendar.date(byAdding: .year, value: -1, to: start)
        let previousNext = previousStart.flatMap { calendar.date(byAdding: .year, value: 1, to: $0) }
        let previousEnd = previousNext?.addingTimeInterval(-1)
        let previousDays = previousStart.flatMap {
            calendar.range(of: .day, in: .year, for: $0)?.count
        } ?? 0

        return AnalyticsRange(
            scope: .year,
            start: start,
            end: end,
            totalDays: total,
            elapsedDays: elapsed,
            isCurrent: current,
            previousStart: previousStart,
            previousEnd: previousEnd,
            previousTotalDays: previousDays
        )
    }

    // MARK: - Snapshot

    static func snapshot(
        range: AnalyticsRange,
        operations allOperations: [Operation],
        displayCurrency: Currency,
        rates: ExchangeRates,
        hiddenCategoryIDs: Set<UUID> = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))?
            .addingTimeInterval(-1) ?? range.end
        let effectiveEnd = range.isCurrent ? min(range.end, endOfToday) : range.end

        let visibleOperations = allOperations.filter { operation in
            guard let category = operation.category else { return true }
            return !hiddenCategoryIDs.contains(category.id)
        }
        let rangeOps = visibleOperations.filter {
            $0.date >= range.start && $0.date <= effectiveEnd
        }
        let currentOps = rangeOps.filter { $0.transferID == nil }
        let expenseOps = currentOps.filter { $0.kind == .expense }
        let incomeOps = currentOps.filter { $0.kind == .income }
        let transferOps = rangeOps.filter { $0.transferID != nil }
        let savingsIn = transferOps
            .filter { $0.kind == .income && ($0.account?.isSavings ?? false) }
            .reduce(Decimal(0)) { total, operation in
                total + (rates.convert(operation.amount, from: operation.currency, to: displayCurrency) ?? 0)
            }
        let savingsOut = transferOps
            .filter { $0.kind == .expense && ($0.account?.isSavings ?? false) }
            .reduce(Decimal(0)) { total, operation in
                total + (rates.convert(operation.amount, from: operation.currency, to: displayCurrency) ?? 0)
            }

        let previousFullOps: [Operation]
        let comparisonOps: [Operation]
        if let previousStart = range.previousStart, let previousEnd = range.previousEnd {
            previousFullOps = visibleOperations.filter {
                $0.transferID == nil && $0.date >= previousStart && $0.date <= previousEnd
            }
            if range.scope == .month {
                let windowDays = min(range.elapsedDays, range.previousTotalDays)
                let windowEnd = windowDays > 0
                    ? calendar.date(byAdding: .day, value: windowDays - 1, to: previousStart)?
                        .addingTimeInterval(86_399) ?? previousStart
                    : previousStart.addingTimeInterval(-1)
                comparisonOps = previousFullOps.filter { $0.date <= windowEnd }
            } else {
                comparisonOps = previousFullOps
            }
        } else {
            previousFullOps = []
            comparisonOps = []
        }

        let expenses = sumExpenses(expenseOps, currency: displayCurrency, rates: rates)
        let income = sumIncome(incomeOps, currency: displayCurrency, rates: rates)
        let mandatory = expenseOps
            .filter { operation in
                let category = operation.category
                return (category?.isMandatory ?? false) || (category?.parent?.isMandatory ?? false)
            }
            .reduce(Decimal(0)) { total, operation in
                total + (rates.convert(operation.amount, from: operation.currency, to: displayCurrency) ?? 0)
            }

        let previousFullTotal = sumExpenses(previousFullOps, currency: displayCurrency, rates: rates)
        let comparisonTotal = sumExpenses(comparisonOps, currency: displayCurrency, rates: rates)
        let hasComparison = range.previousStart != nil && comparisonTotal > 0

        let categories = categorySlices(
            operations: expenseOps,
            previous: comparisonOps,
            currency: displayCurrency,
            rates: rates,
            hasComparison: hasComparison
        )
        let accounts = accountSlices(
            operations: expenseOps,
            previous: comparisonOps,
            currency: displayCurrency,
            rates: rates,
            hasComparison: hasComparison
        )

        let calendarStart = calendar.startOfDay(for: range.start)
        var dailyAmounts = [Decimal](repeating: 0, count: range.totalDays)
        var dailyCounts = [Int](repeating: 0, count: range.totalDays)
        var dailyOperations = [[Operation]](repeating: [], count: range.totalDays)
        for operation in expenseOps {
            let offset = calendar.dateComponents(
                [.day],
                from: calendarStart,
                to: calendar.startOfDay(for: operation.date)
            ).day ?? -1
            guard offset >= 0, offset < range.totalDays else { continue }
            let value = rates.convert(operation.amount, from: operation.currency, to: displayCurrency) ?? 0
            dailyAmounts[offset] += value
            dailyCounts[offset] += 1
            dailyOperations[offset].append(operation)
        }

        let levels = heatLevels(dailyAmounts)
        let days = (0..<range.totalDays).map { index -> AnalyticsDay in
            let date = calendar.date(byAdding: .day, value: index, to: calendarStart) ?? calendarStart
            let day = index + 1
            let operations = dailyOperations[index].sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.createdAt > $1.createdAt
            }
            return AnalyticsDay(
                id: day,
                date: date,
                amount: dailyAmounts[index],
                operationCount: dailyCounts[index],
                operations: operations,
                groups: dayGroups(for: operations, currency: displayCurrency, rates: rates),
                level: levels[index],
                isToday: range.isCurrent && day == range.elapsedDays,
                isFuture: range.isCurrent && day > range.elapsedDays
            )
        }

        var currentCumulative = [Decimal?](repeating: nil, count: range.totalDays)
        var running = Decimal(0)
        for index in 0..<range.totalDays {
            running += dailyAmounts[index]
            if index < range.elapsedDays { currentCumulative[index] = running }
        }

        var previousCumulative = [Decimal]()
        if range.previousTotalDays > 0 {
            var previousDaily = [Decimal](repeating: 0, count: range.previousTotalDays)
            let previousStart = range.previousStart ?? calendarStart
            let previousCalendarStart = calendar.startOfDay(for: previousStart)
            for operation in previousFullOps where operation.kind == .expense {
                let offset = calendar.dateComponents(
                    [.day],
                    from: previousCalendarStart,
                    to: calendar.startOfDay(for: operation.date)
                ).day ?? -1
                guard offset >= 0, offset < range.previousTotalDays else { continue }
                previousDaily[offset] += rates.convert(
                    operation.amount,
                    from: operation.currency,
                    to: displayCurrency
                ) ?? 0
            }
            var previousRunning = Decimal(0)
            previousCumulative = previousDaily.map { value in
                previousRunning += value
                return previousRunning
            }
        }

        let pace: [Decimal]
        if previousFullTotal > 0 {
            pace = (1...range.totalDays).map { day in
                previousFullTotal * Decimal(day) / Decimal(range.totalDays)
            }
        } else {
            pace = []
        }

        // Median of the days that had spending. Zero days are left out on
        // purpose: including them would report a median of zero for anyone who
        // does not spend every day, which says nothing about a typical day.
        let spendingAmounts = days
            .prefix(range.elapsedDays)
            .map(\.amount)
            .filter { $0 > 0 }
            .sorted()
        let medianSpendingDay: Decimal
        if spendingAmounts.isEmpty {
            medianSpendingDay = 0
        } else if spendingAmounts.count.isMultiple(of: 2) {
            let upper = spendingAmounts[spendingAmounts.count / 2]
            let lower = spendingAmounts[spendingAmounts.count / 2 - 1]
            medianSpendingDay = (lower + upper) / 2
        } else {
            medianSpendingDay = spendingAmounts[spendingAmounts.count / 2]
        }

        var peak = expenses
        if previousFullTotal > peak { peak = previousFullTotal }
        for value in currentCumulative.compactMap({ $0 }) where value > peak { peak = value }
        for value in previousCumulative where value > peak { peak = value }
        let peakNumber = NSDecimalNumber(decimal: peak).doubleValue
        let chartMax = max(800, (peakNumber / 400).rounded(.up) * 400)

        return AnalyticsSnapshot(
            range: range,
            expenses: expenses,
            income: income,
            mandatory: mandatory,
            freeExpenses: expenses - mandatory,
            remaining: income - expenses,
            operationsCount: rangeOps.count,
            incomeCount: incomeOps.count,
            savingsIn: savingsIn,
            savingsOut: savingsOut,
            categories: categories,
            accounts: accounts,
            days: days,
            currentCumulative: currentCumulative,
            previousCumulative: previousCumulative,
            pace: pace,
            previousFullTotal: previousFullTotal,
            comparisonTotal: comparisonTotal,
            hasComparison: hasComparison,
            average: expenses / Decimal(max(1, range.elapsedDays)),
            medianSpendingDay: medianSpendingDay,
            spendingDayCount: spendingAmounts.count,
            chartMax: chartMax
        )
    }

    // MARK: - Day groups

    /// Rolls one day's operations up by category. Every operation contributes
    /// its amount converted the same way the daily total does, so the group
    /// amounts add up to `AnalyticsDay.amount` exactly.
    static func dayGroups(
        for operations: [Operation],
        currency: Currency,
        rates: ExchangeRates
    ) -> [AnalyticsDayGroup] {
        struct Bucket {
            let title: String
            var amount: Decimal
            var count: Int
            let sample: Operation
        }

        var buckets: [String: Bucket] = [:]
        for operation in operations {
            let key: String
            if let category = operation.category {
                key = category.id.uuidString
            } else if operation.isTransfer {
                key = "transfer"
            } else {
                key = "uncategorized"
            }
            let value = rates.convert(operation.amount, from: operation.currency, to: currency) ?? 0
            if var bucket = buckets[key] {
                bucket.amount += value
                bucket.count += 1
                buckets[key] = bucket
            } else {
                // `operations` arrives newest first, so the sample is the most
                // recent operation of the group.
                buckets[key] = Bucket(
                    title: operation.displayTitle,
                    amount: value,
                    count: 1,
                    sample: operation
                )
            }
        }

        return buckets
            .map { key, bucket in
                AnalyticsDayGroup(
                    id: key,
                    title: bucket.title,
                    amount: bucket.amount,
                    count: bucket.count,
                    sample: bucket.sample
                )
            }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.title < rhs.title
            }
    }

    // MARK: - Grouping

    private static func categorySlices(
        operations: [Operation],
        previous: [Operation],
        currency: Currency,
        rates: ExchangeRates,
        hasComparison: Bool
    ) -> [AnalyticsSlice] {
        struct Meta {
            var name: String
            var symbol: String
            var color: Color
            var mandatory: Bool
        }

        var totals = [UUID: Decimal]()
        var counts = [UUID: Int]()
        var grouped = [UUID: [Operation]]()
        var meta = [UUID: Meta]()

        for operation in operations {
            let category = operation.category
            let top = category?.parent ?? category
            let id = top?.id ?? uncategorizedID
            let palette = top?.color ?? .graphite
            meta[id] = Meta(
                name: top?.displayName ?? String(localized: "analytics.uncategorized"),
                symbol: top?.iconName ?? "tag.fill",
                color: palette.color,
                mandatory: top?.isMandatory ?? false
            )
            totals[id, default: 0] += rates.convert(
                operation.amount,
                from: operation.currency,
                to: currency
            ) ?? 0
            counts[id, default: 0] += 1
            grouped[id, default: []].append(operation)
        }

        var previousTotals = [UUID: Decimal]()
        if hasComparison {
            for operation in previous where operation.kind == .expense {
                let category = operation.category
                let top = category?.parent ?? category
                let id = top?.id ?? uncategorizedID
                previousTotals[id, default: 0] += rates.convert(
                    operation.amount,
                    from: operation.currency,
                    to: currency
                ) ?? 0
            }
        }

        return totals.keys.compactMap { id -> AnalyticsSlice? in
            guard let info = meta[id], let amount = totals[id] else { return nil }
            let previousAmount = hasComparison ? (previousTotals[id] ?? 0) : nil
            let delta = previousAmount.flatMap { previousValue -> Double? in
                guard previousValue > 0 else { return nil }
                let current = NSDecimalNumber(decimal: amount).doubleValue
                let old = NSDecimalNumber(decimal: previousValue).doubleValue
                return (current - old) / old * 100
            }
            return AnalyticsSlice(
                id: id,
                name: info.name,
                symbol: info.symbol,
                color: info.color,
                amount: amount,
                operationCount: counts[id] ?? 0,
                operations: (grouped[id] ?? []).sorted {
                    if $0.date != $1.date { return $0.date > $1.date }
                    return $0.createdAt > $1.createdAt
                },
                isMandatory: info.mandatory,
                previousAmount: previousAmount,
                delta: delta
            )
        }
        .sorted { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func accountSlices(
        operations: [Operation],
        previous: [Operation],
        currency: Currency,
        rates: ExchangeRates,
        hasComparison: Bool
    ) -> [AnalyticsSlice] {
        struct Meta {
            var name: String
            var symbol: String
            var color: Color
        }

        var totals = [UUID: Decimal]()
        var counts = [UUID: Int]()
        var grouped = [UUID: [Operation]]()
        var meta = [UUID: Meta]()

        for operation in operations {
            let account = operation.account
            let id = account?.id ?? noAccountID
            let palette = account?.color ?? .graphite
            meta[id] = Meta(
                name: account?.name ?? String(localized: "analytics.no_account"),
                symbol: account?.iconName ?? "creditcard",
                color: palette.color
            )
            totals[id, default: 0] += rates.convert(
                operation.amount,
                from: operation.currency,
                to: currency
            ) ?? 0
            counts[id, default: 0] += 1
            grouped[id, default: []].append(operation)
        }

        var previousTotals = [UUID: Decimal]()
        if hasComparison {
            for operation in previous where operation.kind == .expense {
                let id = operation.account?.id ?? noAccountID
                previousTotals[id, default: 0] += rates.convert(
                    operation.amount,
                    from: operation.currency,
                    to: currency
                ) ?? 0
            }
        }

        return totals.keys.compactMap { id -> AnalyticsSlice? in
            guard let info = meta[id], let amount = totals[id] else { return nil }
            let previousAmount = hasComparison ? (previousTotals[id] ?? 0) : nil
            let delta = previousAmount.flatMap { previousValue -> Double? in
                guard previousValue > 0 else { return nil }
                let current = NSDecimalNumber(decimal: amount).doubleValue
                let old = NSDecimalNumber(decimal: previousValue).doubleValue
                return (current - old) / old * 100
            }
            return AnalyticsSlice(
                id: id,
                name: info.name,
                symbol: info.symbol,
                color: info.color,
                amount: amount,
                operationCount: counts[id] ?? 0,
                operations: (grouped[id] ?? []).sorted {
                    if $0.date != $1.date { return $0.date > $1.date }
                    return $0.createdAt > $1.createdAt
                },
                isMandatory: false,
                previousAmount: previousAmount,
                delta: delta
            )
        }
        .sorted { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Totals and heat

    static func sumExpenses(_ operations: [Operation], currency: Currency, rates: ExchangeRates) -> Decimal {
        operations
            .filter { $0.kind == .expense }
            .reduce(Decimal(0)) { total, operation in
                total + (rates.convert(operation.amount, from: operation.currency, to: currency) ?? 0)
            }
    }

    static func sumIncome(_ operations: [Operation], currency: Currency, rates: ExchangeRates) -> Decimal {
        operations
            .filter { $0.kind == .income }
            .reduce(Decimal(0)) { total, operation in
                total + (rates.convert(operation.amount, from: operation.currency, to: currency) ?? 0)
            }
    }

    static func heatLevels(_ amounts: [Decimal]) -> [Int] {
        let positive = amounts.indices.filter { amounts[$0] > 0 }
            .sorted { amounts[$0] < amounts[$1] }
        guard !positive.isEmpty else { return amounts.map { _ in 0 } }
        var levels = [Int](repeating: 0, count: amounts.count)
        for (rank, index) in positive.enumerated() {
            let level = positive.count == 1
                ? 4
                : Int((Double(rank) * 4 / Double(positive.count - 1)).rounded())
            levels[index] = min(max(level, 0), 4)
        }
        return levels
    }

    /// The five opacities the heat map steps through.
    static let heatOpacities: [Double] = [0.04, 0.09, 0.16, 0.26, 0.38]
}
