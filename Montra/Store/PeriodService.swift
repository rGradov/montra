import Foundation
import SwiftData

struct PeriodRule: Equatable {
    var mode: SettingsStore.PeriodMode
    var paydayDay: Int
    var fixedLengthDays: Int
    var anchor: Date
}

/// Turns the period rule into the concrete periods the app groups money by.
///
/// A financial month runs from one payday to the next, inclusive. Periods are
/// materialised as records so one month can be adjusted without touching the
/// rule, and the boundaries of its neighbours follow the edit, so the timeline
/// never overlaps or leaves a gap.
@MainActor
enum PeriodService {
    static func allPeriods(_ context: ModelContext) -> [Period] {
        (try? context.fetch(FetchDescriptor<Period>(sortBy: [SortDescriptor(\.start, order: .forward)]))) ?? []
    }

    /// Materialises enough periods around `now` to cover the app's history view,
    /// leaving manual edits alone. Safe to call on every launch.
    static func ensurePeriods(context: ModelContext, settings: SettingsStore, now: Date = .now) {
        let existing = allPeriods(context)
        let candidates = generatedPeriods(rule: settings.rule, covering: now)
        var didInsert = false

        if existing.isEmpty {
            for period in candidates {
                context.insert(period)
                didInsert = true
            }
        } else {
            for candidate in candidates where !existing.contains(where: { overlaps($0, candidate) }) {
                context.insert(candidate)
                didInsert = true
            }
        }

        if didInsert { try? context.save() }
    }

    static func currentPeriod(in periods: [Period], at date: Date = .now) -> Period? {
        periods.first { $0.contains(date) }
    }

    static func period(containing date: Date, in periods: [Period]) -> Period? {
        periods.first { $0.contains(date) }
    }

    static func sorted(_ periods: [Period]) -> [Period] {
        periods.sorted { $0.start < $1.start }
    }

    /// Moves one period's boundaries and drags its neighbours along, so the
    /// timeline stays continuous. `startDay` must not cross the previous period's
    /// start, and `endDay` must not cross the next period's end; the caller
    /// restricts the date pickers to those ranges.
    static func update(period: Period, startDay: Date, endDay: Date, context: ModelContext) {
        let calendar = Calendar.current
        let startOfStart = calendar.startOfDay(for: startDay)
        let startOfEnd = calendar.startOfDay(for: endDay)
        let clampedStart = min(startOfStart, startOfEnd)
        let clampedEnd = max(startOfStart, startOfEnd)

        let periods = sorted(allPeriods(context))
        guard let index = periods.firstIndex(where: { $0.id == period.id }) else { return }

        let newStart = clampedStart
        let newEnd = calendar.date(byAdding: .day, value: 1, to: clampedEnd)?.addingTimeInterval(-1) ?? clampedEnd

        period.start = newStart
        period.end = newEnd
        period.isManual = true

        if index > 0 {
            let previous = periods[index - 1]
            let previousEnd = newStart.addingTimeInterval(-1)
            if previousEnd > previous.start {
                previous.end = previousEnd
            }
        }
        if index + 1 < periods.count {
            let next = periods[index + 1]
            let nextStart = newEnd.addingTimeInterval(1)
            if nextStart < next.end {
                next.start = nextStart
            }
        }

        try? context.save()
    }

    /// Rebuilds every automatic period from the current rule. Periods the user
    /// adjusted by hand stay exactly where they are.
    static func regenerate(context: ModelContext, settings: SettingsStore, now: Date = .now) {
        for period in allPeriods(context) where !period.isManual {
            context.delete(period)
        }
        try? context.save()
        ensurePeriods(context: context, settings: settings, now: now)
    }

    // MARK: - Generation

    static func generatedPeriods(rule: PeriodRule, covering date: Date) -> [Period] {
        let boundaries = boundaryDates(rule: rule, covering: date)
        guard boundaries.count > 1 else { return [] }
        return (0..<(boundaries.count - 1)).map { index in
            let start = boundaries[index]
            let end = boundaries[index + 1].addingTimeInterval(-1)
            return Period(start: start, end: end)
        }
    }

    private static func boundaryDates(rule: PeriodRule, covering date: Date) -> [Date] {
        let calendar = Calendar.current
        switch rule.mode {
        case .payday:
            var boundaries: [Date] = []
            let thisMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
            for offset in -18...8 {
                guard let monthStart = calendar.date(byAdding: .month, value: offset, to: thisMonth),
                      let range = calendar.range(of: .day, in: .month, for: monthStart) else { continue }
                var components = calendar.dateComponents([.year, .month], from: monthStart)
                components.day = min(max(rule.paydayDay, 1), range.count)
                if let boundary = calendar.date(from: components) {
                    boundaries.append(calendar.startOfDay(for: boundary))
                }
            }
            return Array(Set(boundaries)).sorted()

        case .fixedDays:
            let length = max(1, rule.fixedLengthDays)
            let anchor = calendar.startOfDay(for: rule.anchor)
            let day: TimeInterval = 86_400
            var boundaries: [Date] = []
            var index = 0
            // Walk back from the anchor until the range is covered.
            while index > -400 {
                let candidate = anchor.addingTimeInterval(TimeInterval(index * length) * day)
                if candidate < date.addingTimeInterval(-TimeInterval(18 * 31 * Int(day))) { break }
                boundaries.append(candidate)
                index -= 1
            }
            index = 0
            while index < 40 {
                let candidate = anchor.addingTimeInterval(TimeInterval(index * length) * day)
                boundaries.append(candidate)
                index += 1
            }
            return Array(Set(boundaries)).sorted()
        }
    }

    private static func overlaps(_ lhs: Period, _ rhs: Period) -> Bool {
        lhs.start <= rhs.end && rhs.start <= lhs.end
    }
}
