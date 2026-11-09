import SwiftUI

/// One day's operations, newest day first. The header reads "Сегодня"/"Вчера"
/// and falls back to a localized calendar date.
struct OperationDaySection: Identifiable {
    let day: Date
    let title: String
    let operations: [Operation]

    var id: Date { day }

    static func sections(
        from operations: [Operation],
        calendar: Calendar = .current
    ) -> [OperationDaySection] {
        let grouped = Dictionary(grouping: operations) { operation in
            calendar.startOfDay(for: operation.date)
        }

        return grouped.keys.sorted(by: >).map { day in
            let dayOperations = (grouped[day] ?? []).sorted { $0.date > $1.date }
            return OperationDaySection(
                day: day,
                title: title(for: day, calendar: calendar),
                operations: dayOperations
            )
        }
    }

    static func title(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "date.today") }
        if calendar.isDateInYesterday(day) { return String(localized: "date.yesterday") }
        if calendar.isDateInTomorrow(day) { return String(localized: "date.tomorrow") }

        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: .now)
        return (sameYear ? monthFormatter : yearFormatter).string(from: day)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter
    }()
}

/// A quiet, sticky day header above that day's cards.
struct OperationDateHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppStyle.Typography.body.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppStyle.Spacing.xxSmall)
            .padding(.top, AppStyle.Spacing.xSmall)
            .padding(.bottom, AppStyle.Spacing.xxSmall)
            .background(AppColors.surfaceBase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A mixed list row: a real operation or a future planned payment.
enum TransactionEntry: Identifiable {
    case operation(Operation)
    case plan(PlannedOperation)

    var id: String {
        switch self {
        case .operation(let operation): "operation-\(operation.id.uuidString)"
        case .plan(let plan): "plan-\(plan.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .operation(let operation): operation.date
        case .plan(let plan): plan.date
        }
    }
}

/// Day sections that can hold both facts and future plans.
struct TransactionDaySection: Identifiable {
    let day: Date
    let title: String
    let entries: [TransactionEntry]

    var id: Date { day }

    static func sections(
        from entries: [TransactionEntry],
        ascending: Bool = false,
        calendar: Calendar = .current
    ) -> [TransactionDaySection] {
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.date)
        }

        let days = grouped.keys.sorted(by: ascending ? (<) : (>))
        return days.map { day in
            let dayEntries = (grouped[day] ?? []).sorted { left, right in
                ascending ? left.date < right.date : left.date > right.date
            }
            return TransactionDaySection(
                day: day,
                title: OperationDaySection.title(for: day, calendar: calendar),
                entries: dayEntries
            )
        }
    }
}
