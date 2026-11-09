enum CategoryIcons {
    static let options: [IconPicker.Option] = {
        let featured: [IconPicker.Option] = [
            .init("heart.circle.fill", String(localized: "category.icon.charity")),
            .init("cat.fill", String(localized: "category.icon.cat")),
            .init("dog.fill", String(localized: "category.icon.dog")),
            .init("pawprint.fill", String(localized: "category.icon.pets")),
            .init("cart.fill", String(localized: "category.starter.food")),
            .init("basket.fill", String(localized: "category.icon.groceries")),
            .init("fork.knife", String(localized: "category.starter.restaurants")),
            .init("cup.and.saucer.fill", String(localized: "category.icon.caf")),

            .init("house.fill", String(localized: "category.starter.housing")),
            .init("lightbulb.fill", String(localized: "category.icon.electricity")),
            .init("drop.fill", String(localized: "category.icon.water")),
            .init("wifi", String(localized: "category.icon.phone_and_internet")),
            .init("bus.fill", String(localized: "category.icon.bus")),
            .init("tram.fill", String(localized: "category.icon.public_transport")),
            .init("car.side.fill", String(localized: "category.icon.taxi")),
            .init("bicycle", String(localized: "category.icon.bicycle")),

            .init("cross.case.fill", String(localized: "category.starter.health")),
            .init("pills.fill", String(localized: "category.icon.pharmacy")),
            .init("dumbbell.fill", String(localized: "category.icon.fitness")),
            .init("sparkles", String(localized: "category.icon.personal_care")),
            .init("scissors", String(localized: "category.icon.hair_salon")),
            .init("bag.fill", String(localized: "category.starter.shopping")),
            .init("tshirt.fill", String(localized: "category.icon.clothing")),
            .init("laptopcomputer", String(localized: "category.icon.tech_and_freelancing")),

            .init("smoke.fill", String(localized: "category.icon.smoking")),
            .init("repeat.circle.fill", String(localized: "category.starter.subscriptions")),
            .init("gift.fill", String(localized: "category.starter.gifts")),
            .init("gamecontroller.fill", String(localized: "category.icon.games")),
            .init("ticket.fill", String(localized: "category.icon.tickets")),
            .init("book.fill", String(localized: "category.icon.books")),
            .init("banknote.fill", String(localized: "category.starter.salary")),
            .init("chart.line.uptrend.xyaxis", String(localized: "category.starter.investments")),

            .init("tag.fill", String(localized: "category.icon.tag")),
            .init("ellipsis.circle.fill", String(localized: "category.starter.other")),
        ]
        let featuredSymbols = Set(featured.map(\.symbol))
        return featured + AccountIconCatalog.symbols
            .filter { !featuredSymbols.contains($0) }
            .map { IconPicker.Option($0) }
    }()
}
