import SwiftData
import SwiftUI

/// One operation captured as display data before anything is deleted, so the
/// confirmation and the success screen never touch a deleted model.
struct DeleteOperationItem: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let amountText: String
    let icon: String
    let color: Color
    let isIncome: Bool
}

extension DeleteOperationItem {
    init(operation: Operation, masked: Bool) {
        var parts = [
            operation.account?.name ?? String(localized: "common.no_account"),
            AppDate.dayMonthTime.string(from: operation.date),
        ]
        if !operation.place.isEmpty { parts.append(operation.place) }

        self.init(
            id: operation.id,
            title: operation.displayTitle,
            detail: parts.joined(separator: " · "),
            amountText: operation.amountText(masked: masked),
            icon: operation.displayIcon,
            color: operation.displayColor,
            isIncome: operation.kind == .income
        )
    }
}

/// Everything the confirmation and success screens need, captured before any
/// model is deleted. Both the All Operations page and an account use it.
struct DeleteRequest: Identifiable {
    let id = UUID()
    let items: [DeleteOperationItem]
    let totalText: String

    @MainActor
    static func make(
        operations: [Operation],
        settings: SettingsStore,
        rates: RateStore,
        context: ModelContext
    ) -> DeleteRequest? {
        var seen = Set<UUID>()
        let unique = expandTransfers(
            operations.filter { seen.insert($0.id).inserted },
            context: context
        )
        guard !unique.isEmpty else { return nil }

        let total = rates.total(of: unique, to: settings.primaryCurrency)
        return DeleteRequest(
            items: unique.map { DeleteOperationItem(operation: $0, masked: settings.hideBalances) },
            totalText: settings.money(
                total,
                currency: settings.primaryCurrency,
                sign: total == 0 ? .none : .always
            )
        )
    }

    /// Deleting one leg of a transfer must delete the other leg too, otherwise
    /// the two accounts would disagree about where the money went.
    private static func expandTransfers(
        _ operations: [Operation],
        context: ModelContext
    ) -> [Operation] {
        let transferIDs = Set(operations.compactMap(\.transferID))
        guard !transferIDs.isEmpty else { return operations }

        let all = (try? context.fetch(FetchDescriptor<Operation>())) ?? []
        var result = operations
        var seen = Set(result.map(\.id))
        for operation in all where operation.transferID.map(transferIDs.contains) == true {
            if seen.insert(operation.id).inserted { result.append(operation) }
        }
        return result
    }
}

/// The two-step removal flow: first a list of exactly what will go, then a short
/// completion screen with an animated checkmark. Mirrors the reference's
/// "Move selected files to Trash?" sheet and its celebration.
struct DeleteOperationsSheet: View {
    let items: [DeleteOperationItem]
    let totalText: String
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .confirm
    @State private var elapsed: Double = 0

    private enum Phase {
        case confirm
        case success
    }

    private var title: String {
        items.count == 1 ? String(localized: "common.delete_transaction") : String(localized: "transaction.delete.delete_selected_transactions")
    }

    private var message: String {
        let base = items.count == 1
            ? String(localized: "transaction.delete.this_transaction_will_be_removed")
            : String(localized: "transaction.delete.these_transactions_will_be_removed")
        if items.contains(where: { $0.title == String(localized: "transaction.transfer") }) {
            return base + String(localized: "transaction.delete.both_sides_of_the_transfer")
        }
        return base
    }

    var body: some View {
        ZStack {
            if phase == .confirm {
                confirm
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                DeleteSuccessView(
                    totalText: totalText,
                    count: items.count,
                    elapsed: elapsed,
                    onDone: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .frame(width: 540, height: 600)
        .background(AppColors.surfaceBase)
        .animation(.easeInOut(duration: 0.35), value: phase)
    }

    private var confirm: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                    Text(title)
                        .font(AppStyle.Typography.pageTitle)
                    Text(message)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScrollView {
                    LazyVStack(spacing: AppStyle.Spacing.xSmall) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(AppStyle.Spacing.large)

            footer
        }
        .frame(width: 540, height: 600)
        .background(AppColors.surfaceBase)
    }

    private func row(_ item: DeleteOperationItem) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            ListRowIcon(symbol: item.icon, color: item.color, frameSize: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(AppStyle.Typography.headline)
                    .lineLimit(1)
                Text(item.detail)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            Text(item.amountText)
                .font(AppStyle.Typography.headline.numbers)
                .foregroundStyle(item.isIncome ? AppColors.statusSafeText : AppColors.textPrimary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, AppStyle.Spacing.small)
        .padding(.vertical, AppStyle.Spacing.xSmall)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .fill(AppColors.surfaceRaised)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 0.5)

            HStack(spacing: AppStyle.Spacing.small) {
                Text(String(localized: "transaction.delete.to_be_deleted \(items.count) \(totalText)"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: AppStyle.Spacing.small)

                Button(String(localized: "common.cancel")) { dismiss() }
                    .buttonStyle(.montra(.secondary))
                    .keyboardShortcut(.cancelAction)

                Button(String(localized: "transaction.delete.delete \(items.count)")) { performDelete() }
                    .buttonStyle(.montra(.destructive))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, AppStyle.Spacing.large)
            .padding(.vertical, AppStyle.Spacing.small + 2)
        }
        .background(AppColors.surfaceBase)
    }

    private func performDelete() {
        let start = Date()
        onDelete()
        elapsed = Date().timeIntervalSince(start)
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = .success
        }
    }
}

/// The completion card: a drawn checkmark, the amount that left the journal, how
/// many operations it was, and a single way out.
struct DeleteSuccessView: View {
    let totalText: String
    let count: Int
    let elapsed: Double
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentVisible = false

    private var timeText: String {
        if elapsed < 0.1 { return String(localized: "common.instantly") }
        let value = MoneyFormat.number(Decimal(elapsed), fractionDigits: 1)
        return String(localized: "transaction.delete.finished_in_s \(value)")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: AppStyle.Spacing.large)

            DeleteSuccessCheckmark()

            Text(totalText)
                .font(AppStyle.Typography.display.numbers)
                .monospacedDigit()
                .padding(.top, AppStyle.Spacing.large)

            Text(String(localized: "transaction.delete.removed_from_history"))
                .font(AppStyle.Typography.sectionTitle)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, AppStyle.Spacing.xxSmall)

            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11, weight: .semibold))
                Text(Finance.operationsCountText(count))
            }
            .font(AppStyle.Typography.callout)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
            .background(AppColors.surfaceRaised, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
            }
            .padding(.top, AppStyle.Spacing.small)

            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.statusCheckText)
                Text(timeText)
                    .font(AppStyle.Typography.body.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.top, AppStyle.Spacing.small)

            Spacer(minLength: AppStyle.Spacing.large)

            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                Text(String(localized: "transaction.delete.deleted_transactions_cant_be_restored"))
            }
            .font(AppStyle.Typography.callout)
            .foregroundStyle(AppColors.textTertiary)

            Button(String(localized: "common.done"), action: onDone)
                .buttonStyle(.montra(.primary, size: .large, width: .fixed(280)))
                .keyboardShortcut(.defaultAction)
                .padding(.top, AppStyle.Spacing.small + 2)
                .padding(.bottom, AppStyle.Spacing.large)
        }
        .padding(.horizontal, AppStyle.Spacing.large)
        .frame(width: 540, height: 600)
        .background(AppColors.surfaceBase)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 10)
        .onAppear {
            guard !reduceMotion else {
                contentVisible = true
                return
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.12)) {
                contentVisible = true
            }
        }
    }
}

private struct DeleteSuccessCheckmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.textPrimary, lineWidth: 5)

            DeleteCheckmarkShape()
                .trim(from: 0, to: progress)
                .stroke(
                    AppColors.textPrimary,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
                .padding(22)
        }
        .frame(width: 88, height: 88)
        .scaleEffect(appeared ? 1 : 0.78)
        .onAppear {
            guard !reduceMotion else {
                progress = 1
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.55).delay(0.1)) {
                progress = 1
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DeleteCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.26))
        return path
    }
}
