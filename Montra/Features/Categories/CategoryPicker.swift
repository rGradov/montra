import SwiftUI

/// The complete category choice, opened from the small "Ещё" chip in the
/// operation form: hierarchy, search, and the selected checkmark.
struct CategoryPickerPopover: View {
    let categories: [Category]
    @Binding var selection: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var roots: [Category] {
        categories
            .filter { $0.parent == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private func children(of root: Category) -> [Category] {
        categories
            .filter { $0.parent?.id == root.id }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private var searchResults: [Category] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return categories
            .filter { category in
                category.displayName.localizedStandardContains(trimmed)
                    || (category.parent?.displayName.localizedStandardContains(trimmed) ?? false)
            }
            .sorted { left, right in
                if left.parent?.id != right.parent?.id {
                    return (left.parent?.sortIndex ?? left.sortIndex) < (right.parent?.sortIndex ?? right.sortIndex)
                }
                return left.sortIndex < right.sortIndex
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            CapsuleSearchField(
                query: $query,
                prompt: String(localized: "common.search_categories"),
                width: 264
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(roots) { root in
                            row(root, level: 0)
                            ForEach(children(of: root)) { child in
                                row(child, level: 1)
                            }
                        }
                    } else if searchResults.isEmpty {
                        Text(String(localized: "common.no_results"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppStyle.Spacing.large)
                    } else {
                        ForEach(searchResults) { category in
                            row(category, level: 0, showsParent: true)
                        }
                    }
                }
            }
            .frame(maxHeight: 304)
        }
        .padding(AppStyle.Spacing.small + 2)
        .frame(width: 300)
        .background(AppColors.surfaceBase)
    }

    private func row(_ category: Category, level: Int, showsParent: Bool = false) -> some View {
        let isSelected = category.id == selection
        return Button {
            selection = category.id
            dismiss()
        } label: {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                if level > 0 {
                    Rectangle()
                        .fill(AppColors.borderSubtle)
                        .frame(width: 1, height: 22)
                        .padding(.leading, 8)
                }

                IconTile(symbol: category.iconName, color: category.color.tileColor, size: 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text(category.displayName)
                        .font(level == 0 ? AppStyle.Typography.body.weight(.medium) : AppStyle.Typography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if showsParent, let parent = category.parent {
                        Text(String(localized: "category.in \(parent.displayName)"))
                            .font(AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Spacer(minLength: AppStyle.Spacing.xSmall)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .padding(.horizontal, level > 0 ? 4 : AppStyle.Spacing.xSmall)
            .padding(.vertical, 5)
            .background(
                isSelected ? AppColors.fillSecondary : Color.clear,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
