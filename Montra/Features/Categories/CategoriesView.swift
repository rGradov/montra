import SwiftData
import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Category.sortIndex, order: .forward)]) private var categories: [Category]
    @Query private var operations: [Operation]

    let onNewCategory: (OperationKind) -> Void
    let onEditCategory: (Category) -> Void

    private var mandatoryCount: Int {
        categories.filter { $0.isMandatory || ($0.parent?.isMandatory ?? false) }.count
    }

    private var subtitle: String {
        var text = String(localized: "category.count \(categories.count)")
        if mandatoryCount > 0 {
            text += String(localized: "category.essential_count \(mandatoryCount)")
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                    section(title: String(localized: "common.expenses"), rows: displayRows(for: .expense), kind: .expense)
                    section(title: String(localized: "common.income"), rows: displayRows(for: .income), kind: .income)
                }
                .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                .padding(.bottom, AppStyle.Spacing.large)
            }
        }
        .background(AppColors.surfaceBase)
        .onAppear { syncHeader() }
        .onChange(of: headerKey) { _, _ in syncHeader() }
    }

    private var headerKey: String { subtitle }

    private var headerTrailing: some View {
        Button {
            onNewCategory(.expense)
        } label: {
            Label(String(localized: "common.new_category"), systemImage: "plus")
        }
        .buttonStyle(.montra(.primary))
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "navigation.categories"),
            subtitle: subtitle,
            backTitle: nil,
            onBack: nil,
            trailing: AnyView(headerTrailing)
        )
    }

    private struct CategoryDisplayRow: Identifiable {
        let category: Category
        let level: Int
        let operationCount: Int

        var id: UUID { category.id }
    }

    private func displayRows(for kind: OperationKind) -> [CategoryDisplayRow] {
        let roots = categories
            .filter { $0.kind == kind && $0.parent == nil }
            .sorted { $0.sortIndex < $1.sortIndex }

        var rows: [CategoryDisplayRow] = []
        for root in roots {
            let children = categories
                .filter { $0.parent?.id == root.id && $0.kind == kind }
                .sorted { $0.sortIndex < $1.sortIndex }
            let ownCount = operationCount(for: root)
            let total = ownCount + children.reduce(0) { $0 + operationCount(for: $1) }
            rows.append(CategoryDisplayRow(category: root, level: 0, operationCount: total))
            for child in children {
                rows.append(CategoryDisplayRow(
                    category: child,
                    level: 1,
                    operationCount: operationCount(for: child)
                ))
            }
        }
        return rows
    }

    private func section(title: String, rows: [CategoryDisplayRow], kind: OperationKind) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            SectionLabel(title: title, trailing: "\(rows.count)")

            InsetCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        InsetCardDivider()
                    }
                    CategoryRow(
                        category: row.category,
                        level: row.level,
                        operationCount: row.operationCount,
                        onOpen: { onEditCategory(row.category) },
                        onDelete: row.category.isSystem ? nil : {
                            CategoryRepository(context: context).delete(row.category)
                        }
                    )
                }
            }
        }
    }

    private func operationCount(for category: Category) -> Int {
        operations.filter { $0.category?.id == category.id }.count
    }
}

private struct CategoryRow: View {
    let category: Category
    var level: Int = 0
    let operationCount: Int
    let onOpen: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppStyle.Spacing.small) {
                if level > 0 {
                    Rectangle()
                        .fill(AppColors.borderSubtle)
                        .frame(width: 1, height: 28)
                        .padding(.leading, AppStyle.Spacing.small)
                        .padding(.trailing, AppStyle.Spacing.xxxSmall)
                }

                ListRowIcon(symbol: category.iconName, color: category.color.color)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(category.displayName)
                        .font(AppStyle.Typography.headline)
                        .lineLimit(1)
                    Text(detail)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppStyle.Spacing.small)

                Text(figures: Finance.operationsCountText(operationCount), style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.small)
            .background(isHovering ? AppColors.fillSecondaryHover.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .pointingHandOnHover()
        .contextMenu {
            Button(String(localized: "common.edit_2"), action: onOpen)
            if let onDelete {
                Divider()
                Button(String(localized: "common.delete"), role: .destructive, action: onDelete)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var detail: String {
        var parts: [String] = []
        switch category.kind {
        case .expense:
            let mandatory = category.isMandatory || (category.parent?.isMandatory ?? false)
            parts.append(mandatory ? String(localized: "common.essential") : String(localized: "common.nonessential"))
        case .income:
            parts.append(String(localized: "common.income_2"))
        }
        if let parent = category.parent {
            parts.append(String(localized: "category.in \(parent.displayName)"))
        }
        parts.append(category.isSystem ? String(localized: "common.built_in") : String(localized: "common.custom"))
        return parts.joined(separator: " · ")
    }
}
