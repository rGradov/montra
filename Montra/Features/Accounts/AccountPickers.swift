import SwiftUI

/// SF Symbols offered as account icons, each paired with the emoji that means
/// the same thing. The pairing is what lets the Icon/Emoji switch keep the
/// person's choice instead of resetting it to the first tile. A custom asset
/// with the same name wins over the symbol inside `IconTile`, so this list is
/// still the one place to add the user's own account artwork later.
enum AccountIconCatalog {
    struct Option: Hashable {
        let symbol: String
        let emoji: String
    }

    static let options: [Option] = [
        Option(symbol: "creditcard.fill", emoji: "💳"),
        Option(symbol: "banknote.fill", emoji: "💵"),
        Option(symbol: "building.columns.fill", emoji: "🏦"),
        Option(symbol: "wallet.pass.fill", emoji: "💰"),
        Option(symbol: "chart.line.uptrend.xyaxis", emoji: "📈"),
        Option(symbol: "bitcoinsign.circle.fill", emoji: "₿"),
        Option(symbol: "dollarsign.circle.fill", emoji: "💲"),
        Option(symbol: "eurosign.circle.fill", emoji: "💶"),
        Option(symbol: "bag.fill", emoji: "🛍️"),
        Option(symbol: "gift.fill", emoji: "🎁"),
        Option(symbol: "briefcase.fill", emoji: "💼"),
        Option(symbol: "house.fill", emoji: "🏠"),
        Option(symbol: "car.fill", emoji: "🚗"),
        Option(symbol: "airplane", emoji: "✈️"),
        Option(symbol: "globe.europe.africa.fill", emoji: "🌍"),
        Option(symbol: "lock.fill", emoji: "🔒"),
        Option(symbol: "shield.fill", emoji: "🛡️"),
        Option(symbol: "star.fill", emoji: "⭐"),
        Option(symbol: "heart.fill", emoji: "❤️"),
        Option(symbol: "pawprint.fill", emoji: "🐾"),
        Option(symbol: "gamecontroller.fill", emoji: "🎮"),
        Option(symbol: "graduationcap.fill", emoji: "🎓"),
        Option(symbol: "tram.fill", emoji: "🚆"),
        Option(symbol: "fuelpump.fill", emoji: "⛽"),
    ]

    static let symbols: [String] = options.map(\.symbol)

    /// The five tiles the sheet keeps one tap away, in both modes.
    static let favorites: [Option] = Array(options.prefix(5))

    /// The same meaning in the other mode, or the first tile when the stored
    /// glyph is outside the catalog (a custom asset, an older symbol).
    static func emoji(for glyph: String) -> String {
        options.first { $0.symbol == glyph || $0.emoji == glyph }?.emoji ?? options[0].emoji
    }

    static func symbol(for glyph: String) -> String {
        options.first { $0.symbol == glyph || $0.emoji == glyph }?.symbol ?? options[0].symbol
    }
}

enum AccountAppearanceMode: String, CaseIterable, Identifiable {
    case icon
    case emoji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: String(localized: "common.icon")
        case .emoji: String(localized: "common.emoji")
        }
    }

    var systemImage: String {
        switch self {
        case .icon: "square.grid.2x2"
        case .emoji: "face.smiling"
        }
    }
}

/// The appearance section of the account sheet: one choice of glyph (an SF
/// Symbol or an emoji), five favourites with the full list a popover away, and
/// the colour dots on the line below. Selection is stored in `icon` itself, so
/// an account has exactly one glyph field to back up and hand to the API.
struct AccountAppearancePicker: View {
    @Binding var icon: String
    @Binding var color: PaletteColor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeNamespace

    @State private var mode: AccountAppearanceMode
    @State private var isPickerPresented = false

    private let tileSize = CGSize(width: 36, height: 32)

    init(icon: Binding<String>, color: Binding<PaletteColor>) {
        _icon = icon
        _color = color
        _mode = State(initialValue: AppIconGlyph.isEmoji(icon.wrappedValue) ? .emoji : .icon)
    }

    private var favoriteGlyphs: [String] {
        AccountIconCatalog.favorites.map { mode == .icon ? $0.symbol : $0.emoji }
    }

    private var isSelectionInFavorites: Bool {
        favoriteGlyphs.contains(icon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(alignment: .center, spacing: AppStyle.Spacing.xSmall) {
                Text(String(localized: "common.appearance"))
                    .font(AppStyle.Typography.callout.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: AppStyle.Spacing.xSmall)
                modeSwitch
            }

            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                ForEach(favoriteGlyphs, id: \.self) { value in
                    glyphTile(value)
                }
                moreButton
                Spacer(minLength: 0)
            }

            HStack(spacing: AppStyle.Spacing.xSmall) {
                Text(String(localized: "common.color"))
                    .font(AppStyle.Typography.callout.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                ColorPickerRow(selection: $color)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.row, value: color)
    }

    // MARK: Mode

    private var modeSwitch: some View {
        HStack(spacing: 2) {
            ForEach(AccountAppearanceMode.allCases) { item in
                Button {
                    select(mode: item)
                } label: {
                    HStack(spacing: AppStyle.Spacing.xxSmall) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 10, weight: .medium))
                        Text(item.title)
                            .font(AppStyle.Typography.callout.weight(.medium))
                    }
                    .foregroundStyle(mode == item ? AppColors.textPrimary : AppColors.textSecondary)
                    .padding(.horizontal, AppStyle.Spacing.xSmall)
                    .frame(height: 22)
                    .background {
                        if mode == item {
                            RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                                .fill(AppColors.surfaceRaised)
                                .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
                                .matchedGeometryEffect(id: "appearance-mode", in: modeNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            AppColors.fillSecondary,
            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "common.appearance"))
    }

    private func select(mode newMode: AccountAppearanceMode) {
        guard newMode != mode else { return }
        let next = newMode == .emoji
            ? AccountIconCatalog.emoji(for: icon)
            : AccountIconCatalog.symbol(for: icon)
        isPickerPresented = false
        withAnimation(reduceMotion ? nil : AppMotion.row) {
            mode = newMode
            icon = next
        }
    }

    // MARK: Glyph tiles

    private func glyphTile(_ value: String) -> some View {
        AccountGlyphTile(value: value, isSelected: value == icon) {
            choose(value)
        }
    }

    private func choose(_ value: String) {
        isPickerPresented = false
        guard value != icon else { return }
        withAnimation(reduceMotion ? nil : AppMotion.row) {
            icon = value
        }
    }

    // MARK: Full list

    private var moreButton: some View {
        Button {
            isPickerPresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelectionInFavorites ? AppColors.textSecondary : AppColors.textPrimary)
                .frame(width: tileSize.width, height: tileSize.height)
                .background(
                    isSelectionInFavorites ? AppColors.fillSecondary : AppColors.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                        .strokeBorder(isSelectionInFavorites ? .clear : AppColors.borderStrong, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .help(String(localized: "common.more"))
        .accessibilityLabel(String(localized: "common.more"))
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            AccountGlyphPickerPanel(
                mode: mode,
                selection: icon,
                onSelect: choose,
                onClose: { isPickerPresented = false }
            )
        }
    }
}

/// One glyph in the appearance row and in the full list. A symbol takes the
/// selection tint; an emoji keeps its own colours on the same tile.
struct AccountGlyphTile: View {
    let value: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: 36, height: 32)
                .background(
                    isSelected ? AppColors.surfaceRaised : AppColors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                        .strokeBorder(isSelected ? AppColors.borderStrong : .clear, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .help(value)
        .accessibilityLabel(value)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var glyph: some View {
        if AppIconGlyph.isEmoji(value) {
            Text(value)
                .font(.system(size: 17))
        } else {
            Image(systemName: AppIconSymbol.resolved(value))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
        }
    }
}

/// The full glyph list in the popover anchored to the "…" tile. It is a view of
/// its own so the sheet's popover and the snapshot runner draw exactly one grid.
struct AccountGlyphPickerPanel: View {
    let mode: AccountAppearanceMode
    let selection: String
    let onSelect: (String) -> Void
    let onClose: () -> Void

    private let columns = Array(
        repeating: GridItem(.fixed(36), spacing: AppStyle.Spacing.xxSmallPlus),
        count: 6
    )

    private var glyphs: [String] {
        AccountIconCatalog.options.map { mode == .icon ? $0.symbol : $0.emoji }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                Text(mode == .icon
                     ? String(localized: "account.all_icons")
                     : String(localized: "account.all_emojis"))
                    .font(AppStyle.Typography.sectionTitle)
                Spacer(minLength: AppStyle.Spacing.medium)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.montra(.quiet, size: .small, width: .square))
                .accessibilityLabel(String(localized: "common.close"))
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
                ForEach(glyphs, id: \.self) { value in
                    AccountGlyphTile(value: value, isSelected: value == selection) {
                        onSelect(value)
                    }
                }
            }
        }
        .padding(AppStyle.Spacing.medium)
        .frame(width: 278)
        .background(AppColors.surfaceBase)
    }
}

struct IconPicker: View {
    struct Option {
        let symbol: String
        let title: String

        init(_ symbol: String, _ title: String? = nil) {
            self.symbol = symbol
            self.title = title ?? symbol
        }
    }

    @Binding var selection: String
    var options: [Option] = AccountIconCatalog.symbols.map { Option($0) }

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: AppStyle.Spacing.xxSmallPlus), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            ForEach(options, id: \.symbol) { option in
                let symbol = option.symbol
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == symbol ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(width: 34, height: 30)
                        .background(
                            selection == symbol ? AppColors.surfaceRaised : AppColors.fillSecondary,
                            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                .strokeBorder(selection == symbol ? AppColors.borderStrong : .clear, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
            }
        }
    }
}

struct ColorPickerRow: View {
    @Binding var selection: PaletteColor

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            ForEach(PaletteColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.tileColor)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                        }
                        .overlay {
                            if selection == color {
                                Circle()
                                    .inset(by: -3)
                                    .strokeBorder(AppColors.textPrimary, lineWidth: 2)
                            }
                        }
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}
