import SwiftUI

/// The five destinations of the port's bottom menu. The macOS sidebar keeps its
/// own list (accounts, savings, iCloud status and About are sidebar rows there);
/// these are the iOS/iPadOS roots, in the sidebar's order with Settings last.
///
/// The enum is the single source of truth for the phone tab bar and the iPad
/// glass bar, so both always agree on order, titles and symbols. `Codable` is
/// what lets a window be opened on a specific tab (`openWindow(value:)`).
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
    case overview
    case operations
    case categories
    case analytics
    case settings

    var id: String { rawValue }

    /// The page a tab shows when its stack is empty.
    var route: Route {
        switch self {
        case .overview: .overview
        case .operations: .operations
        case .categories: .categories
        case .analytics: .analytics
        case .settings: .settings
        }
    }

    var title: String {
        switch self {
        case .overview: String(localized: "navigation.overview")
        case .operations: String(localized: "transaction.all")
        case .categories: String(localized: "navigation.categories")
        case .analytics: String(localized: "navigation.analytics")
        case .settings: String(localized: "navigation.settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .operations: "list.bullet.rectangle"
        case .categories: "tag"
        case .analytics: "chart.bar"
        case .settings: "gearshape"
        }
    }

    /// The filled variant marks the selected item, so selection is never carried
    /// by tint alone (Increase Contrast flattens the material to black/white).
    var selectedSymbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .operations: "list.bullet.rectangle.fill"
        case .categories: "tag.fill"
        case .analytics: "chart.bar.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// Which tab owns a page. Accounts are pushed inside Overview and About is a
    /// sheet over Settings, so neither spends a tab slot.
    init?(route: Route) {
        switch route {
        case .overview, .account: self = .overview
        case .operations: self = .operations
        case .categories: self = .categories
        case .analytics: self = .analytics
        case .settings, .about: self = .settings
        }
    }
}
