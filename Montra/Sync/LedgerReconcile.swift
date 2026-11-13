import Foundation
import SwiftData

/// Merges the two kinds of row that every Mac creates on its own before CloudKit
/// delivers the ledger. Without this, a second Mac ends up with two sets of
/// starter categories and two sets of the same month's periods: same names, same
/// dates, different identities.
///
/// Deliberately narrow. It only touches rows the app itself generates — system
/// categories and materialised periods — so a user's own duplicate-looking
/// categories are never merged behind their back.
@MainActor
enum LedgerReconcile {
    struct Result: Equatable {
        var categories = 0
        var periods = 0
        var isEmpty: Bool { categories == 0 && periods == 0 }
    }

    @discardableResult
    static func run(context: ModelContext) -> Result {
        var result = Result()
        result.categories = mergeSystemCategories(context: context)
        result.periods = mergePeriods(context: context)
        if !result.isEmpty {
            try? context.save()
        }
        return result
    }

    /// Keeps one starter category per (kind, name), moves its operations over and
    /// deletes the duplicates.
    private static func mergeSystemCategories(context: ModelContext) -> Int {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let system = categories.filter { $0.isSystem && $0.parent == nil }

        var groups: [String: [Category]] = [:]
        for category in system {
            groups["\(category.kindRaw)|\(category.name)", default: []].append(category)
        }

        var removed = 0
        for (_, group) in groups where group.count > 1 {
            // Oldest wins, with a stable tie-break so two Macs agree on the
            // survivor instead of each keeping its own copy.
            let ordered = group.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let survivor = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                for operation in duplicate.operations ?? [] {
                    operation.category = survivor
                }
                for child in duplicate.children ?? [] {
                    child.parent = survivor
                }
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    /// Keeps one period per exact date range. A hand-edited period wins, because
    /// regenerating would otherwise discard the person's own boundary.
    private static func mergePeriods(context: ModelContext) -> Int {
        let periods = (try? context.fetch(FetchDescriptor<Period>())) ?? []
        var groups: [String: [Period]] = [:]
        for period in periods {
            let start = Int(period.start.timeIntervalSince1970)
            let end = Int(period.end.timeIntervalSince1970)
            groups["\(start)|\(end)", default: []].append(period)
        }

        var removed = 0
        for (_, group) in groups where group.count > 1 {
            let ordered = group.sorted {
                if $0.isManual != $1.isManual { return $0.isManual }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let survivor = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                // Nothing points at a period, so the extra row is simply dropped.
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }
}
