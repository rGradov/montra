import SwiftUI

/// One glyph choice: an SF Symbol and the emoji that means the same thing. The
/// pairing is what lets the Icon/Emoji switch keep the person's choice instead
/// of resetting it to the first tile. A custom asset with the same name wins
/// over the symbol inside `IconTile`, so the catalog stays the one place to add
/// the user's own artwork later.
struct GlyphOption: Hashable {
    let symbol: String
    let emoji: String
    /// The localized name used in tooltips and accessibility labels. Account
    /// tiles leave it out and fall back to the glyph itself.
    var title: String?

    init(symbol: String, emoji: String, title: String? = nil) {
        self.symbol = symbol
        self.emoji = emoji
        self.title = title
    }
}

/// The glyphs one sheet offers: the full list behind "…" and the five tiles the
/// row keeps one tap away. Accounts and categories each supply their own
/// catalog; the picker and the stored `icon` string stay shared.
struct GlyphCatalog {
    var options: [GlyphOption]
    var favorites: [GlyphOption]

    /// The same meaning in the other mode, or the first tile when the stored
    /// glyph is outside the catalog (a custom asset, an older symbol).
    func emoji(for glyph: String) -> String {
        options.first { $0.symbol == glyph || $0.emoji == glyph }?.emoji ?? options[0].emoji
    }

    func symbol(for glyph: String) -> String {
        options.first { $0.symbol == glyph || $0.emoji == glyph }?.symbol ?? options[0].symbol
    }

    /// The tile's localized name, or the glyph itself when the catalog entry
    /// has no title of its own.
    func title(for value: String) -> String {
        options.first { $0.symbol == value || $0.emoji == value }?.title ?? value
    }
}

enum GlyphAppearanceMode: String, CaseIterable, Identifiable {
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

/// The appearance section of a sheet: one choice of glyph (an SF Symbol or an
/// emoji), five favourites with the full list a popover away, and the colour
/// dots on the line below. Selection is stored in `icon` itself, so an account
/// or a category has exactly one glyph field to back up and hand to the API.
struct GlyphAppearancePicker: View {
    @Binding var icon: String
    @Binding var color: PaletteColor
    let catalog: GlyphCatalog

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeNamespace

    @State private var mode: GlyphAppearanceMode
    @State private var isPickerPresented = false

    init(icon: Binding<String>, color: Binding<PaletteColor>, catalog: GlyphCatalog) {
        _icon = icon
        _color = color
        self.catalog = catalog
        _mode = State(initialValue: AppIconGlyph.isEmoji(icon.wrappedValue) ? .emoji : .icon)
    }

    private var favoriteGlyphs: [String] {
        catalog.favorites.map { mode == .icon ? $0.symbol : $0.emoji }
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
            ForEach(GlyphAppearanceMode.allCases) { item in
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

    private func select(mode newMode: GlyphAppearanceMode) {
        guard newMode != mode else { return }
        let next = newMode == .emoji
            ? catalog.emoji(for: icon)
            : catalog.symbol(for: icon)
        isPickerPresented = false
        withAnimation(reduceMotion ? nil : AppMotion.row) {
            mode = newMode
            icon = next
        }
    }

    // MARK: Glyph tiles

    private func glyphTile(_ value: String) -> some View {
        GlyphTile(value: value, title: catalog.title(for: value), isSelected: value == icon) {
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
                .frame(width: GlyphTile.size.width, height: GlyphTile.size.height)
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
        .platformHelp(String(localized: "common.more"))
        .accessibilityLabel(String(localized: "common.more"))
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            GlyphPickerPanel(
                mode: mode,
                catalog: catalog,
                selection: icon,
                onSelect: choose,
                onClose: { isPickerPresented = false }
            )
        }
    }
}

/// The hairline and the picker together, so every sheet ends its form the same
/// way: a rule separates "what the record is" from "how it is drawn".
struct GlyphAppearanceSection: View {
    @Binding var icon: String
    @Binding var color: PaletteColor
    let catalog: GlyphCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 0.5)
            GlyphAppearancePicker(icon: $icon, color: $color, catalog: catalog)
        }
        .padding(.top, AppStyle.Spacing.xxSmall)
    }
}

/// One glyph in the appearance row and in the full list. A symbol takes the
/// selection tint; an emoji keeps its own colours on the same tile.
struct GlyphTile: View {
    static let size = CGSize(width: 36, height: 32)

    let value: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: Self.size.width, height: Self.size.height)
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
        .platformHelp(title)
        .accessibilityLabel(title)
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
struct GlyphPickerPanel: View {
    let mode: GlyphAppearanceMode
    let catalog: GlyphCatalog
    let selection: String
    let onSelect: (String) -> Void
    let onClose: () -> Void

    private let columns = Array(
        repeating: GridItem(.fixed(36), spacing: AppStyle.Spacing.xxSmallPlus),
        count: 6
    )

    private var glyphs: [String] {
        catalog.options.map { mode == .icon ? $0.symbol : $0.emoji }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                Text(mode == .icon
                     ? String(localized: "appearance.all_icons")
                     : String(localized: "appearance.all_emojis"))
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
                    GlyphTile(value: value, title: catalog.title(for: value), isSelected: value == selection) {
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

struct ColorPickerRow: View {
    @Binding var selection: PaletteColor

    var body: some View {
        #if os(iOS)
        // Ten swatches in one row are wider than a phone's form column, so they
        // wrap onto a second line instead of running off the sheet.
        FlowLayout(spacing: AppStyle.Spacing.xSmall, lineSpacing: AppStyle.Spacing.xxSmall) {
            swatches
        }
        #else
        HStack(spacing: AppStyle.Spacing.xSmall) {
            swatches
            Spacer(minLength: 0)
        }
        #endif
    }

    @ViewBuilder
    private var swatches: some View {
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
            .platformHelp(color.title)
            .accessibilityLabel(color.title)
            .accessibilityAddTraits(selection == color ? .isSelected : [])
        }
    }
}
