import SwiftData
import SwiftUI

struct CategorySheet: View {
    enum Mode {
        case create(OperationKind)
        case edit(Category)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Category.sortIndex, order: .forward)]) private var categories: [Category]

    let mode: Mode

    @State private var kind: OperationKind
    @State private var name: String
    @State private var color: PaletteColor
    @State private var icon: String
    @State private var isMandatory: Bool
    @State private var parentID: UUID?
    @State private var isConfirmingDelete = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let kind):
            _kind = State(initialValue: kind)
            _name = State(initialValue: "")
            _color = State(initialValue: kind == .expense ? .orange : .green)
            _icon = State(initialValue: Self.defaultSymbol(for: kind))
            _isMandatory = State(initialValue: false)
            _parentID = State(initialValue: nil)
        case .edit(let category):
            _kind = State(initialValue: category.kind)
            _name = State(initialValue: category.displayName)
            _color = State(initialValue: category.color)
            _icon = State(initialValue: AppIconSymbol.resolved(category.iconName))
            _isMandatory = State(initialValue: category.isMandatory)
            _parentID = State(initialValue: category.parent?.id)
        }
    }

    private var editingCategory: Category? {
        if case .edit(let category) = mode { return category }
        return nil
    }

    private var isEditing: Bool { editingCategory != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rootCategories: [Category] {
        categories
            .filter { $0.kind == kind && $0.parent == nil && $0.id != editingCategory?.id }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private var hasChildren: Bool {
        guard let editingCategory else { return false }
        return categories.contains { $0.parent?.id == editingCategory.id }
    }

    private var parentName: String {
        guard let parentID,
              let parent = categories.first(where: { $0.id == parentID }) else {
            return String(localized: "common.no_parent")
        }
        return parent.displayName
    }

    private var inheritedMandatory: Bool {
        guard let parentID,
              let parent = categories.first(where: { $0.id == parentID }) else {
            return false
        }
        return parent.isMandatory
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isEditing ? String(localized: "common.category") : String(localized: "common.new_category"),
                subtitle: kind == .expense ? String(localized: "common.expense") : String(localized: "common.income_2"),
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    preview
                    typeField
                    nameField
                    parentField
                    mandatoryField
                    appearanceField
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.bottom, AppStyle.Spacing.medium)
            }
            .frame(maxHeight: 535)

            SheetFooter {
                if isEditing, editingCategory?.isSystem == false {
                    Button(String(localized: "common.delete")) { isConfirmingDelete = true }
                        .buttonStyle(.montra(.destructive))
                }
                Spacer(minLength: AppStyle.Spacing.small)
                Button(String(localized: "common.cancel")) { dismiss() }
                    .buttonStyle(.montra(.quiet))
                Button(isEditing ? String(localized: "common.save") : String(localized: "common.create")) { save() }
                    .buttonStyle(.montra(.primary))
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 470)
        .background(AppColors.surfaceBase)
        .onChange(of: kind) { oldKind, newKind in
            if newKind == .income { isMandatory = false }
            parentID = nil
            // A fresh category starts on the kind's default glyph. When the
            // kind flips, move that default with it so the one-tap row keeps a
            // selected tile; a glyph the person picked deliberately stays.
            guard !isEditing else { return }
            let previous = CategoryIcons.catalog(for: oldKind)
            let previousDefault = Self.defaultSymbol(for: oldKind)
            guard icon == previousDefault || icon == previous.emoji(for: previousDefault) else { return }
            let next = CategoryIcons.catalog(for: newKind)
            let nextDefault = Self.defaultSymbol(for: newKind)
            withAnimation(AppMotion.row) {
                icon = AppIconGlyph.isEmoji(icon) ? next.emoji(for: nextDefault) : nextDefault
            }
        }
        .alert(String(localized: "common.delete_category"), isPresented: $isConfirmingDelete) {
            Button(String(localized: "common.delete"), role: .destructive) { deleteCategory() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(hasChildren
                 ? String(localized: "category.transactions_in_this_category_will")
                 : String(localized: "category.transactions_in_this_category_will_2"))
        }
    }

    private var preview: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            IconTile(symbol: icon, color: color.tileColor, size: 44)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(name.isEmpty ? String(localized: "common.new_category") : name)
                    .font(AppStyle.Typography.sectionTitle)
                Text(previewSubtitle)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isMandatory {
                AppBadge(text: String(localized: "common.essential"), tone: .warning)
            }
        }
        .padding(.bottom, AppStyle.Spacing.xxSmall)
    }

    private var previewSubtitle: String {
        let mandatory = isMandatory || inheritedMandatory
        var text = mandatory
            ? String(localized: "common.essential_category")
            : (kind == .expense ? String(localized: "common.nonessential_category") : String(localized: "common.income_category"))
        if let parentID,
           let parent = categories.first(where: { $0.id == parentID }) {
            text += String(localized: "category.in_2 \(parent.displayName)")
        }
        return text
    }

    private var parentField: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            FieldLabel(title: String(localized: "common.parent_category"), trailing: hasChildren ? String(localized: "common.has_subcategories") : nil)

            if hasChildren {
                Text(String(localized: "category.this_category_already_has_subcategories"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if rootCategories.isEmpty {
                Text(String(localized: "category.you_can_keep_it_as"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                DropdownMenu(
                    options: [nil] + rootCategories.map(\.id),
                    selection: parentID,
                    selectionLabel: parentName,
                    optionLabel: { id in
                        guard let id,
                              let parent = categories.first(where: { $0.id == id }) else {
                            return String(localized: "common.no_parent")
                        }
                        return parent.displayName
                    },
                    fillsWidth: true,
                    onSelect: { parentID = $0 }
                )
            }

            Text(String(localized: "category.choose_a_parent_category_to"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var typeField: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            FieldLabel(title: String(localized: "common.type"), trailing: isEditing ? String(localized: "common.fixed") : nil)
            if isEditing {
                Text(kind == .expense ? String(localized: "common.expense") : String(localized: "common.income_2"))
                    .font(AppStyle.Typography.body.weight(.medium))
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .frame(height: AppStyle.Control.height)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        AppColors.fillSecondary,
                        in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    )
            } else {
                ChipGroup(
                    options: OperationKind.allCases,
                    selection: kind,
                    label: { $0 == .expense ? String(localized: "common.expense") : String(localized: "common.income_2") },
                    icon: { $0 == .expense ? "arrow.up.right" : "arrow.down.left" },
                    onSelect: { kind = $0 }
                )
            }
        }
    }

    private var nameField: some View {
        FormField(title: String(localized: "common.name")) {
            MontraTextField(placeholder: String(localized: "category.for_example_coffee"), text: $name)
        }
    }

    private var mandatoryField: some View {
        HStack(alignment: .center, spacing: AppStyle.Spacing.medium) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(String(localized: "common.essential"))
                    .font(AppStyle.Typography.body.weight(.medium))
                Text(inheritedMandatory
                     ? String(localized: "category.inherits_its_essential_status_from \(parentName)")
                     : String(localized: "category.counts_toward_essential_expenses_for"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppStyle.Spacing.small)
            if inheritedMandatory {
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
                    .toggleStyle(.montraSwitch)
                    .disabled(true)
            } else {
                Toggle("", isOn: $isMandatory)
                    .labelsHidden()
                    .toggleStyle(.montraSwitch)
                    .disabled(kind == .income)
            }
        }
        .padding(AppStyle.Spacing.medium)
        .background(
            AppColors.fillSecondary,
            in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
        )
        .opacity(kind == .income ? 0.55 : 1)
    }

    /// Like the account sheet, the form ends with how the category looks. The
    /// section is the same view accounts use, so both sheets read one way.
    private var appearanceField: some View {
        GlyphAppearanceSection(
            icon: $icon,
            color: $color,
            catalog: CategoryIcons.catalog(for: kind)
        )
    }

    private static func defaultSymbol(for kind: OperationKind) -> String {
        kind == .expense ? "fork.knife" : "banknote.fill"
    }

    private func save() {
        let repository = CategoryRepository(context: context)
        let parent = parentID.flatMap { id in categories.first { $0.id == id } }
        if let category = editingCategory {
            repository.update(
                category,
                name: name,
                color: color,
                iconName: icon,
                isMandatory: isMandatory,
                parent: parent
            )
        } else {
            repository.create(
                name: name,
                kind: kind,
                color: color,
                iconName: icon,
                isMandatory: isMandatory,
                parent: parent
            )
        }
        dismiss()
    }

    private func deleteCategory() {
        guard let category = editingCategory else { return }
        CategoryRepository(context: context).delete(category)
        dismiss()
    }
}
