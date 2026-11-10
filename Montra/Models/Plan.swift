import Foundation
import SwiftData

/// How often a planned payment repeats. Week is the only frequency with an
/// extra choice (which weekdays to include).
enum PlanFrequency: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: String(localized: "schedule.day")
        case .week: String(localized: "schedule.week")
        case .month: String(localized: "schedule.month")
        case .year: String(localized: "schedule.year")
        }
    }

    var adverb: String {
        switch self {
        case .day: String(localized: "schedule.daily")
        case .week: String(localized: "schedule.weekly")
        case .month: String(localized: "schedule.monthly")
        case .year: String(localized: "schedule.yearly")
        }
    }
}

/// Weekdays use `Calendar` numbering (Sunday = 1), displayed Monday first.
enum PlanWeekday: Int, CaseIterable, Identifiable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var short: String { Self.calendar.shortWeekdaySymbols[rawValue - 1].capitalized(with: AppLocalization.locale) }

    var full: String { Self.calendar.weekdaySymbols[rawValue - 1].capitalized(with: AppLocalization.locale) }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLocalization.locale
        return calendar
    }()

    static func mask(for weekdays: Set<Int>) -> Int {
        weekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    static func weekdays(from mask: Int) -> Set<Int> {
        Set(PlanWeekday.allCases.map(\.rawValue).filter { mask & (1 << ($0 - 1)) != 0 })
    }
}

/// Builds the actual due dates for a plan. The first occurrence is the plan's
/// start date (or the next selected weekday for a weekly plan); the last is on
/// or before `end`, inclusive by day. Times come from the start date.
enum PlanSchedule {
    static let maxOccurrences = 1000

    static func dates(
        start: Date,
        end: Date,
        frequency: PlanFrequency,
        weekdays: Set<Int>,
        calendar: Calendar = .current
    ) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard endDay >= startDay else { return [] }

        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        let hour = time.hour ?? 0
        let minute = time.minute ?? 0
        let second = time.second ?? 0

        func atTime(_ day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: second, of: day) ?? day
        }

        var dates: [Date] = []

        switch frequency {
        case .day:
            var day = startDay
            while day <= endDay, dates.count < maxOccurrences {
                dates.append(atTime(day))
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            }

        case .week:
            let selected = weekdays.isEmpty
                ? [calendar.component(.weekday, from: start)]
                : Array(weekdays)
            var day = startDay
            while day <= endDay, dates.count < maxOccurrences {
                if selected.contains(calendar.component(.weekday, from: day)) {
                    dates.append(atTime(day))
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            }

        case .month:
            let startParts = calendar.dateComponents([.year, .month, .day], from: start)
            var offset = 0
            while dates.count < maxOccurrences {
                guard let monthBase = calendar.date(from: DateComponents(
                    year: startParts.year,
                    month: (startParts.month ?? 1) + offset,
                    day: 1
                )) else { break }

                let monthLength = calendar.range(of: .day, in: .month, for: monthBase)?.count ?? 28
                let day = min(startParts.day ?? 1, monthLength)
                guard let occurrence = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: monthBase),
                    month: calendar.component(.month, from: monthBase),
                    day: day,
                    hour: hour,
                    minute: minute,
                    second: second
                )) else { break }

                if calendar.startOfDay(for: occurrence) > endDay { break }
                dates.append(occurrence)
                offset += 1
            }

        case .year:
            let startParts = calendar.dateComponents([.year, .month, .day], from: start)
            var offset = 0
            while dates.count < maxOccurrences {
                guard let monthBase = calendar.date(from: DateComponents(
                    year: (startParts.year ?? 2000) + offset,
                    month: startParts.month,
                    day: 1
                )) else { break }

                let monthLength = calendar.range(of: .day, in: .month, for: monthBase)?.count ?? 28
                let day = min(startParts.day ?? 1, monthLength)
                guard let occurrence = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: monthBase),
                    month: startParts.month,
                    day: day,
                    hour: hour,
                    minute: minute,
                    second: second
                )) else { break }

                if calendar.startOfDay(for: occurrence) > endDay { break }
                dates.append(occurrence)
                offset += 1
            }
        }

        return dates
    }
}

/// How far ahead the "Upcoming" lists look. Two years covers rent, utilities
/// and yearly renewals; further out the list stops being a plan and becomes a
/// wish.
enum PlanHorizon {
    static let years = 2

    static func limit(from date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: years, to: calendar.startOfDay(for: date)) ?? date
    }
}

/// One due payment of a recurring plan. Occurrences are generated up front so
/// every date can be linked, moved or deleted individually; none of them is an
/// actual `Operation` and none affects balances until it is saved as a fact.
@Model
final class PlannedOperation {
    var id: UUID = UUID()
    var seriesID: UUID = UUID()
    var kindRaw: String = OperationKind.expense.rawValue
    var amount: Decimal = 0
    var currencyRaw: String = Currency.byn.rawValue
    var date: Date = Date()
    var place: String = ""
    var note: String = ""
    var createdAt: Date = Date()
    var frequencyRaw: String = PlanFrequency.month.rawValue
    var weekdayMask: Int = 0
    var seriesStart: Date = Date()
    var seriesEnd: Date = Date()
    var account: Account?
    var category: Category?
    var linkedOperationID: UUID?

    init(
        seriesID: UUID,
        kind: OperationKind,
        amount: Decimal,
        currency: Currency,
        date: Date,
        place: String = "",
        note: String = "",
        frequency: PlanFrequency,
        weekdays: Set<Int>,
        seriesStart: Date,
        seriesEnd: Date,
        account: Account?,
        category: Category?
    ) {
        self.id = UUID()
        self.seriesID = seriesID
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currencyRaw = currency.rawValue
        self.date = date
        self.place = place
        self.note = note
        self.createdAt = .now
        self.frequencyRaw = frequency.rawValue
        self.weekdayMask = PlanWeekday.mask(for: weekdays)
        self.seriesStart = seriesStart
        self.seriesEnd = seriesEnd
        self.account = account
        self.category = category
    }

    var kind: OperationKind {
        get { OperationKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .byn }
        set { currencyRaw = newValue.rawValue }
    }

    var frequency: PlanFrequency {
        get { PlanFrequency(rawValue: frequencyRaw) ?? .month }
        set { frequencyRaw = newValue.rawValue }
    }

    var weekdays: Set<Int> { PlanWeekday.weekdays(from: weekdayMask) }

    var isLinked: Bool { linkedOperationID != nil }

    var isMissed: Bool {
        !isLinked && date < Calendar.current.startOfDay(for: .now)
    }

    var isUpcoming: Bool {
        !isLinked && date >= Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        !isLinked && Calendar.current.isDateInToday(date)
    }

    var signedAmount: Decimal {
        kind == .income ? amount : -amount
    }

    var weekdaySummary: String {
        PlanWeekday.allCases
            .filter { weekdays.contains($0.rawValue) }
            .map(\.short)
            .joined(separator: ", ")
    }
}
