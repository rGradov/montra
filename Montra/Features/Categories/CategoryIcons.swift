/// The category glyphs the sheet offers, in the same shape as the account
/// catalog: an SF Symbol, the emoji that means the same thing, and the name the
/// tile shows on hover. Categories reuse the account symbols that are not
/// already featured here, so both pickers speak one visual language.
enum CategoryIcons {
    static let options: [GlyphOption] = {
        let featured: [GlyphOption] = [
            .init(symbol: "heart.circle.fill", emoji: "❤️", title: String(localized: "category.icon.charity")),
            .init(symbol: "cat.fill", emoji: "🐱", title: String(localized: "category.icon.cat")),
            .init(symbol: "dog.fill", emoji: "🐶", title: String(localized: "category.icon.dog")),
            .init(symbol: "pawprint.fill", emoji: "🐾", title: String(localized: "category.icon.pets")),
            .init(symbol: "cart.fill", emoji: "🛒", title: String(localized: "category.starter.food")),
            .init(symbol: "basket.fill", emoji: "🧺", title: String(localized: "category.icon.groceries")),
            .init(symbol: "fork.knife", emoji: "🍴", title: String(localized: "category.starter.restaurants")),
            .init(symbol: "cup.and.saucer.fill", emoji: "☕", title: String(localized: "category.icon.caf")),

            .init(symbol: "house.fill", emoji: "🏠", title: String(localized: "category.starter.housing")),
            .init(symbol: "lightbulb.fill", emoji: "💡", title: String(localized: "category.icon.electricity")),
            .init(symbol: "drop.fill", emoji: "💧", title: String(localized: "category.icon.water")),
            .init(symbol: "wifi", emoji: "📶", title: String(localized: "category.icon.phone_and_internet")),
            .init(symbol: "bus.fill", emoji: "🚌", title: String(localized: "category.icon.bus")),
            .init(symbol: "tram.fill", emoji: "🚆", title: String(localized: "category.icon.public_transport")),
            .init(symbol: "car.side.fill", emoji: "🚕", title: String(localized: "category.icon.taxi")),
            .init(symbol: "bicycle", emoji: "🚲", title: String(localized: "category.icon.bicycle")),

            .init(symbol: "cross.case.fill", emoji: "🏥", title: String(localized: "category.starter.health")),
            .init(symbol: "pills.fill", emoji: "💊", title: String(localized: "category.icon.pharmacy")),
            .init(symbol: "dumbbell.fill", emoji: "🏋️", title: String(localized: "category.icon.fitness")),
            .init(symbol: "sparkles", emoji: "✨", title: String(localized: "category.icon.personal_care")),
            .init(symbol: "scissors", emoji: "✂️", title: String(localized: "category.icon.hair_salon")),
            .init(symbol: "bag.fill", emoji: "🛍️", title: String(localized: "category.starter.shopping")),
            .init(symbol: "tshirt.fill", emoji: "👕", title: String(localized: "category.icon.clothing")),
            .init(symbol: "laptopcomputer", emoji: "💻", title: String(localized: "category.icon.tech_and_freelancing")),

            .init(symbol: "smoke.fill", emoji: "🚬", title: String(localized: "category.icon.smoking")),
            .init(symbol: "repeat.circle.fill", emoji: "🔄", title: String(localized: "category.starter.subscriptions")),
            .init(symbol: "gift.fill", emoji: "🎁", title: String(localized: "category.starter.gifts")),
            .init(symbol: "gamecontroller.fill", emoji: "🎮", title: String(localized: "category.icon.games")),
            .init(symbol: "ticket.fill", emoji: "🎫", title: String(localized: "category.icon.tickets")),
            .init(symbol: "book.fill", emoji: "📖", title: String(localized: "category.icon.books")),
            .init(symbol: "banknote.fill", emoji: "💵", title: String(localized: "category.starter.salary")),
            .init(symbol: "chart.line.uptrend.xyaxis", emoji: "📈", title: String(localized: "category.starter.investments")),

            .init(symbol: "tag.fill", emoji: "🏷️", title: String(localized: "category.icon.tag")),
            .init(symbol: "ellipsis.circle.fill", emoji: "💬", title: String(localized: "category.starter.other")),
        ]
        let featuredSymbols = Set(featured.map(\.symbol))
        let featuredEmojis = Set(featured.map(\.emoji))
        // The account catalog adds glyphs a category may still want, without
        // repeating a symbol or emoji the featured list already offers: one
        // emoji must always map back to exactly one symbol when the mode flips.
        let shared = AccountIconCatalog.options
            .filter { !featuredSymbols.contains($0.symbol) && !featuredEmojis.contains($0.emoji) }
            .map { option in
                GlyphOption(symbol: option.symbol, emoji: option.emoji, title: sharedTitles[option.symbol])
            }
        return featured + shared
    }()

    /// The account glyphs categories may also use, named so a category tile
    /// never falls back to the raw symbol name in its tooltip or VoiceOver.
    private static let sharedTitles: [String: String] = [
        "creditcard.fill": String(localized: "category.icon.card"),
        "building.columns.fill": String(localized: "category.icon.bank"),
        "wallet.pass.fill": String(localized: "category.icon.wallet"),
        "bitcoinsign.circle.fill": String(localized: "category.icon.crypto"),
        "dollarsign.circle.fill": String(localized: "category.icon.dollar"),
        "eurosign.circle.fill": String(localized: "category.icon.euro"),
        "briefcase.fill": String(localized: "category.icon.work"),
        "car.fill": String(localized: "category.icon.car"),
        "airplane": String(localized: "category.icon.travel"),
        "globe.europe.africa.fill": String(localized: "category.icon.world"),
        "lock.fill": String(localized: "category.icon.savings"),
        "shield.fill": String(localized: "category.icon.insurance"),
        "star.fill": String(localized: "category.icon.favorites"),
        "graduationcap.fill": String(localized: "category.icon.education"),
        "fuelpump.fill": String(localized: "category.icon.fuel"),
    ]

    /// The five most common glyphs one tap away, per kind. The full catalog
    /// stays a "…" away in the same popover as accounts.
    static func favorites(for kind: OperationKind) -> [GlyphOption] {
        let symbols: [String] = switch kind {
        case .expense:
            ["cart.fill", "basket.fill", "fork.knife", "cup.and.saucer.fill", "house.fill"]
        case .income:
            ["banknote.fill", "chart.line.uptrend.xyaxis", "gift.fill", "laptopcomputer", "briefcase.fill"]
        }
        return symbols.compactMap { symbol in options.first { $0.symbol == symbol } }
    }

    static func catalog(for kind: OperationKind) -> GlyphCatalog {
        GlyphCatalog(options: options, favorites: favorites(for: kind))
    }
}
