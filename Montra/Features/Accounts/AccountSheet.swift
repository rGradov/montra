import SwiftData
import SwiftUI

struct AccountSheet: View {
    enum Mode {
        case create
        case edit(Account)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore

    let mode: Mode

    @State private var name: String
    @State private var currency: Currency
    @State private var initialAmountText: String
    @State private var icon: String
    @State private var color: PaletteColor
    @State private var isSavings: Bool
    @State private var isHiddenFromOverview: Bool
    @State private var isConfirmingDelete = false

    /// `startsAsSavings` lets the sidebar's "Savings" header open the sheet
    /// with the savings switch already on; the user still confirms the name.
    init(mode: Mode, startsAsSavings: Bool = false) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _currency = State(initialValue: .byn)
            _initialAmountText = State(initialValue: "")
            _icon = State(initialValue: "creditcard.fill")
            _color = State(initialValue: .blue)
            _isSavings = State(initialValue: startsAsSavings)
            _isHiddenFromOverview = State(initialValue: false)
        case .edit(let account):
            _name = State(initialValue: account.name)
            _currency = State(initialValue: account.currency)
            _initialAmountText = State(initialValue: Self.editableAmount(account.initialAmount))
            _icon = State(initialValue: account.iconName)
            _color = State(initialValue: account.color)
            _isSavings = State(initialValue: account.isSavings)
            _isHiddenFromOverview = State(initialValue: account.isHiddenFromOverview)
        }
    }

    private var editingAccount: Account? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    private var isEditing: Bool { editingAccount != nil }

    private var initialAmount: Decimal? {
        let cleaned = initialAmountText
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty { return 0 }
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        return value
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && initialAmount != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isEditing ? String(localized: "common.account") : String(localized: "account.new"),
                subtitle: isEditing ? String(localized: "account.the_accounts_currency_cant_be") : String(localized: "account.cash_card_or_crypto_wallet"),
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    preview
                    hiddenFromOverviewRow
                    nameField
                    amountField
                    currencyField
                    appearanceField
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.bottom, AppStyle.Spacing.medium)
            }
            .frame(maxHeight: 535)

            SheetFooter {
                if isEditing {
                    Button(String(localized: "common.delete")) { isConfirmingDelete = true }
                        .buttonStyle(.montra(.destructive))
                }
                Spacer(minLength: AppStyle.Spacing.small)
                Button(String(localized: "common.cancel")) { dismiss() }
                    .buttonStyle(.montra(.quiet))
                Button(isEditing ? String(localized: "common.save") : String(localized: "common.create_account")) { save() }
                    .buttonStyle(.montra(.primary))
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 470, height: 650)
        .background(AppColors.surfaceBase)
        .alert(String(localized: "common.delete_account"), isPresented: $isConfirmingDelete) {
            Button(String(localized: "common.delete"), role: .destructive) { deleteAccount() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "account.this_will_also_delete_all"))
        }
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.small) {
            IconTile(symbol: icon, color: color.tileColor, size: 44)
                .id(icon)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(name.isEmpty ? String(localized: "account.new") : name)
                    .font(AppStyle.Typography.sectionTitle)
                    .lineLimit(1)
                Text(figures: "\(currency.code) · \(settings.money(initialAmount ?? 0, currency: currency))",
                     style: AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: AppStyle.Spacing.xSmall)

            // The savings flag lives in the header, with its caption under the
            // switch. The trailing inset matches the field cards below, so this
            // switch and the hidden-account one share a single right edge.
            VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxxSmall) {
                Toggle("", isOn: $isSavings)
                    .toggleStyle(.switch)
                    .tint(AppColors.actionPrimary)
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "common.savings_account"))

                Text(String(localized: "common.savings_account"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(isSavings ? AppColors.textSecondary : AppColors.textTertiary)
                    .lineLimit(1)
            }
            .help(String(localized: "account.for_money_youre_setting_aside"))
            .padding(.trailing, AppStyle.Row.cardHorizontalPadding)
        }
        .animation(AppMotion.row, value: isSavings)
    }

    /// The second flag gets its own card the full width of a field: its caption
    /// is too long for the preview, and the switch stays on the same vertical
    /// line as the savings one above.
    private var hiddenFromOverviewRow: some View {
        HStack(alignment: .center, spacing: AppStyle.Spacing.small) {
            Image(systemName: isHiddenFromOverview ? "eye.slash" : "eye")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHiddenFromOverview ? AppColors.textSecondary : AppColors.textTertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(String(localized: "account.hide_from_overview"))
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text(String(localized: "account.stays_in_the_sidebar"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
            }

            Spacer(minLength: AppStyle.Spacing.xSmall)

            Toggle("", isOn: $isHiddenFromOverview)
                .toggleStyle(.switch)
                .tint(AppColors.actionPrimary)
                .labelsHidden()
                .accessibilityLabel(String(localized: "account.hide_from_overview"))
        }
        .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColors.fillSecondary,
            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
        }
        .help(String(localized: "account.removes_this_account_from_the"))
        .animation(AppMotion.row, value: isHiddenFromOverview)
    }

    private var nameField: some View {
        FormField(title: String(localized: "common.name")) {
            MontraTextField(placeholder: String(localized: "account.for_example_card"), text: $name)
        }
    }

    private var currencyField: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            FieldLabel(title: String(localized: "common.currency"), trailing: isEditing ? String(localized: "common.fixed") : nil)

            if isEditing {
                HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                    Text(currency.code)
                        .font(AppStyle.Typography.body.weight(.semibold))
                    Text(currency.name)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppStyle.Spacing.small)
                .frame(height: AppStyle.Control.height)
                .background(
                    AppColors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                )
            } else {
                FlowLayout(spacing: AppStyle.Spacing.xSmall, lineSpacing: AppStyle.Spacing.xSmall) {
                    ForEach(Currency.allCases) { item in
                        currencyChip(item)
                    }
                }
            }
        }
    }

    private func currencyChip(_ item: Currency) -> some View {
        let isSelected = item == currency
        return Button {
            withAnimation(AppMotion.row) { currency = item }
        } label: {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                if item.symbol != item.code {
                    Text(item.symbol)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                }
                Text(item.code)
                    .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
            .background(
                isSelected ? AppColors.surfaceRaised : AppColors.fillSecondary,
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityLabel("\(item.code), \(item.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var amountField: some View {
        FormField(title: String(localized: "common.opening_balance"), trailing: isEditing ? String(localized: "common.affects_balance") : nil) {
            HStack(spacing: AppStyle.Spacing.small) {
                TextField("0", text: $initialAmountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                ZStack(alignment: .trailing) {
                    Text(currency.symbol)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                        .id(currency)
                        .transition(.asymmetric(
                            insertion: .offset(y: 7).combined(with: .opacity),
                            removal: .offset(y: -7).combined(with: .opacity)
                        ))
                }
                .frame(width: 38, alignment: .trailing)
                .animation(AppMotion.row, value: currency)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, AppStyle.Spacing.small)
            .frame(height: 40)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
        }
    }

    /// The sheet ends with how the account looks, using the same section the
    /// category sheet draws under the same hairline.
    private var appearanceField: some View {
        GlyphAppearanceSection(icon: $icon, color: $color, catalog: AccountIconCatalog.catalog)
    }

    private func save() {
        guard let initialAmount else { return }
        let repository = AccountRepository(context: context)
        if let account = editingAccount {
            repository.update(
                account, name: name, initialAmount: initialAmount, iconName: icon, color: color,
                isSavings: isSavings, isHiddenFromOverview: isHiddenFromOverview
            )
        } else {
            repository.create(
                name: name, currency: currency, initialAmount: initialAmount, iconName: icon, color: color,
                isSavings: isSavings, isHiddenFromOverview: isHiddenFromOverview
            )
        }
        dismiss()
    }

    private func deleteAccount() {
        guard let account = editingAccount else { return }
        AccountRepository(context: context).delete(account)
        dismiss()
    }

    private static func editableAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}
