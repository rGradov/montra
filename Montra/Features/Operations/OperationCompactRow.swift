import SwiftUI

/// An operation as one card: category, when and where, amount. Shared by the
/// account page so a row looks the same wherever it appears.
struct OperationCompactRow: View {
    let operation: Operation
    var isNew: Bool = false
    let masked: Bool
    let onOpen: () -> Void
    var isSelectable: Bool = false
    var isSelected: Bool = false
    var onToggle: () -> Void = {}
    var animatesHover = true

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            if isSelectable {
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .tint(AppColors.actionPrimary)
                    .accessibilityLabel(String(localized: "common.select_transaction"))
            }

            Button(action: onOpen) {
                HStack(spacing: AppStyle.Spacing.small) {
                    IconTile(
                        symbol: operation.displayIcon,
                        color: operation.displayColor
                    )

                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                        Text(operation.displayTitle)
                            .font(AppStyle.Typography.headline)
                            .lineLimit(1)
                        Text(figures: detail, style: AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                    .frame(minHeight: 32, alignment: .leading)

                    Spacer(minLength: AppStyle.Spacing.small)

                    Text(operation.amountText(masked: masked))
                        .font(AppStyle.Typography.headline.numbers)
                        .monospacedDigit()
                        .foregroundStyle(operation.kind == .income ? AppColors.statusSafeText : AppColors.textPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
        }
        .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.small)
        .background {
            let shape = RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
            ZStack {
                shape.fill(isNew ? AppColors.fillSecondaryHover : (isHovering ? AppColors.fillSecondaryHover : AppColors.fillSecondary))
                NewRowVeil(isNew: isNew, cornerRadius: AppStyle.Radius.lg)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                .strokeBorder(isNew ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: 0.5)
        }
        .onHover { isHovering = $0 }
        .animation(animatesHover ? .easeOut(duration: 0.12) : nil, value: isHovering)
        .animation(AppMotion.highlight, value: isNew)
        .contextMenu {
            Button(operation.isTransfer ? String(localized: "common.open_transfer") : String(localized: "common.edit_2"), action: onOpen)
        }
    }

    private var detail: String {
        var parts = [AppDate.dayMonthTime.string(from: operation.date)]
        if !operation.place.isEmpty { parts.append(operation.place) }
        if !operation.note.isEmpty { parts.append(operation.note) }
        return parts.joined(separator: " · ")
    }
}
