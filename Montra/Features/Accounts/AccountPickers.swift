import SwiftUI

/// The account glyphs, paired with the emoji that means the same thing through
/// the shared `GlyphOption` type. A custom asset with the same name wins over
/// the symbol inside `IconTile`.
enum AccountIconCatalog {
    static let options: [GlyphOption] = [
        GlyphOption(symbol: "creditcard.fill", emoji: "💳"),
        GlyphOption(symbol: "banknote.fill", emoji: "💵"),
        GlyphOption(symbol: "building.columns.fill", emoji: "🏦"),
        GlyphOption(symbol: "wallet.pass.fill", emoji: "💰"),
        GlyphOption(symbol: "chart.line.uptrend.xyaxis", emoji: "📈"),
        GlyphOption(symbol: "bitcoinsign.circle.fill", emoji: "₿"),
        GlyphOption(symbol: "dollarsign.circle.fill", emoji: "💲"),
        GlyphOption(symbol: "eurosign.circle.fill", emoji: "💶"),
        GlyphOption(symbol: "bag.fill", emoji: "🛍️"),
        GlyphOption(symbol: "gift.fill", emoji: "🎁"),
        GlyphOption(symbol: "briefcase.fill", emoji: "💼"),
        GlyphOption(symbol: "house.fill", emoji: "🏠"),
        GlyphOption(symbol: "car.fill", emoji: "🚗"),
        GlyphOption(symbol: "airplane", emoji: "✈️"),
        GlyphOption(symbol: "globe.europe.africa.fill", emoji: "🌍"),
        GlyphOption(symbol: "lock.fill", emoji: "🔒"),
        GlyphOption(symbol: "shield.fill", emoji: "🛡️"),
        GlyphOption(symbol: "star.fill", emoji: "⭐"),
        GlyphOption(symbol: "heart.fill", emoji: "❤️"),
        GlyphOption(symbol: "pawprint.fill", emoji: "🐾"),
        GlyphOption(symbol: "gamecontroller.fill", emoji: "🎮"),
        GlyphOption(symbol: "graduationcap.fill", emoji: "🎓"),
        GlyphOption(symbol: "tram.fill", emoji: "🚆"),
        GlyphOption(symbol: "fuelpump.fill", emoji: "⛽"),
    ]

    static let symbols: [String] = options.map(\.symbol)

    /// The five tiles the account sheet keeps one tap away, in both modes. The
    /// rest of the catalog stays behind "…".
    static let catalog = GlyphCatalog(options: options, favorites: Array(options.prefix(5)))
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
                .platformHelp(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
            }
        }
    }
}
