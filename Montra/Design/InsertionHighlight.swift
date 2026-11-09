import SwiftUI

/// Remembers which rows just appeared, so a row can announce itself for a moment
/// after it is created. Only real insertions count: changing a filter or opening
/// a page does not flash the whole list.
@MainActor
final class NewRowHighlighter: ObservableObject {
    @Published private(set) var highlighted: Set<UUID> = []

    private var known: Set<UUID> = []
    private var hasStarted = false
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func track(_ ids: [UUID]) {
        let current = Set(ids)
        defer { known = current }

        guard hasStarted else {
            hasStarted = true
            return
        }

        let inserted = current.subtracting(known)
        // One or two rows are a person adding something. A burst is the demo
        // data or a reset, and flashing the whole list for that reads as noise.
        guard !inserted.isEmpty, inserted.count <= 3 else { return }

        highlighted.formUnion(inserted)
        for id in inserted {
            tasks[id]?.cancel()
            tasks[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled, let self else { return }
                _ = withAnimation(AppMotion.highlight) { self.highlighted.remove(id) }
                self.tasks[id] = nil
            }
        }
    }

    func isNew(_ id: UUID) -> Bool {
        highlighted.contains(id)
    }

    deinit {
        for task in tasks.values { task.cancel() }
    }
}

/// The insertion itself: a short drop from above, a touch of scale and blur, so
/// a new card settles into the list instead of snapping into place.
private struct RowRevealModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: (1 - progress) * -7)
            .scaleEffect(0.985 + 0.015 * progress, anchor: .top)
            .blur(radius: (1 - progress) * 1.2)
    }
}

extension AnyTransition {
    static var rowReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: RowRevealModifier(progress: 0),
                identity: RowRevealModifier(progress: 1)
            ),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }
}
