import Foundation
import SwiftData

@MainActor
struct PlanRepository {
    let context: ModelContext

    @discardableResult
    func create(
        kind: OperationKind,
        amount: Decimal,
        account: Account,
        category: Category?,
        date: Date,
        place: String,
        note: String,
        frequency: PlanFrequency,
        weekdays: Set<Int>,
        end: Date,
        seriesID: UUID = UUID(),
        saveImmediately: Bool = true
    ) -> [PlannedOperation] {
        let dates = PlanSchedule.dates(
            start: date,
            end: end,
            frequency: frequency,
            weekdays: weekdays
        )
        guard !dates.isEmpty else { return [] }

        let plans = dates.map { dueDate in
            PlannedOperation(
                seriesID: seriesID,
                kind: kind,
                amount: amount,
                currency: account.currency,
                date: dueDate,
                place: place.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                frequency: frequency,
                weekdays: weekdays,
                seriesStart: date,
                seriesEnd: end,
                account: account,
                category: category
            )
        }
        for plan in plans { context.insert(plan) }
        if saveImmediately { try? context.save() }
        return plans
    }

    func delete(_ plan: PlannedOperation) {
        context.delete(plan)
        try? context.save()
    }

    func deleteSeries(_ plan: PlannedOperation) {
        let seriesID = plan.seriesID
        let all = (try? context.fetch(FetchDescriptor<PlannedOperation>())) ?? []
        for item in all where item.seriesID == seriesID {
            context.delete(item)
        }
        try? context.save()
    }

    func link(_ plan: PlannedOperation, to operation: Operation) {
        plan.linkedOperationID = operation.id
        try? context.save()
    }
}
