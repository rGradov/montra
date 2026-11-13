import SwiftData
import SwiftUI

enum Route: Hashable {
    case overview
    case operations
    case categories
    case analytics
    case settings
    case about
    case account(UUID)

    /// Which sidebar row a route belongs to. Accounts and the full operations
    /// list are subpages of Overview, so they keep Overview lit.
    var sidebarSection: Route? {
        switch self {
        case .account, .operations: .overview
        default: self
        }
    }
}

struct OperationSource {
    var account: Account?
    var kind: OperationKind?
    /// Set when the sheet is opened to turn a planned occurrence into a fact.
    var planned: PlannedOperation?
}

enum AppSheet: Identifiable {
    case newOperation(OperationSource)
    case editOperation(Operation)
    case transferDetails(UUID)
    case planActions(UUID)
    /// `isSavings` starts the create sheet with the savings switch already on,
    /// so the sidebar's "Savings" header can add straight into its group.
    case newAccount(isSavings: Bool)
    case editAccount(Account)
    case newCategory(OperationKind)
    case editCategory(Category)
    case periods
    case iCloud
    /// iOS/iPadOS show About as a bottom sheet from Settings. The macOS About
    /// page is a sidebar destination and keeps its route.
    case about

    var id: String {
        switch self {
        case .newOperation(let source):
            "new-operation-\(source.account?.id.uuidString ?? "any")-\(source.kind?.rawValue ?? "any")-\(source.planned?.id.uuidString ?? "none")"
        case .editOperation(let operation):
            "edit-operation-\(operation.id)"
        case .transferDetails(let transferID):
            "transfer-details-\(transferID)"
        case .planActions(let planID):
            "plan-actions-\(planID)"
        case .newAccount(let isSavings):
            "new-account-\(isSavings)"
        case .editAccount(let account):
            "edit-account-\(account.id)"
        case .newCategory(let kind):
            "new-category-\(kind.rawValue)"
        case .editCategory(let category):
            "edit-category-\(category.id)"
        case .periods:
            "periods"
        case .iCloud:
            "icloud"
        case .about:
            "about"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: Route
    @Published var sheet: AppSheet?

    #if os(iOS)
    /// The lit bottom-menu item. On macOS `route` stays the single source of
    /// truth and this is never read.
    @Published var selectedTab: AppTab
    /// One stack per tab, so switching tabs keeps the pushed page and the
    /// scroll position of the tab you left.
    @Published var tabPaths: [AppTab: [Route]]
    #endif

    init(route: Route = .overview) {
        self.route = route
        #if os(iOS)
        self.selectedTab = AppTab(route: route) ?? .overview
        var paths: [AppTab: [Route]] = [:]
        if case .account = route { paths[.overview] = [route] }
        self.tabPaths = paths
        // About is a sheet over Settings on iOS; a launch route of `.about`
        // (the QA screenshot flag) opens it.
        if route == .about { self.sheet = .about }
        #endif
    }

    func open(_ route: Route) {
        #if os(iOS)
        withAnimation(AppMotion.route) { apply(route) }
        #else
        withAnimation(AppMotion.route) { self.route = route }
        #endif
    }

    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    #if os(iOS)
    // MARK: - Tab navigation (iOS / iPadOS)

    func path(for tab: AppTab) -> [Route] {
        tabPaths[tab] ?? []
    }

    func setPath(_ path: [Route], for tab: AppTab) {
        tabPaths[tab] = path
        if selectedTab == tab {
            route = path.last ?? tab.route
        }
    }

    /// A tap on a bottom-menu item. Re-tapping the lit tab pops its stack to the
    /// root, which is what a system tab bar does; the stack of every other tab
    /// is left alone.
    func selectTab(_ tab: AppTab) {
        if selectedTab == tab {
            if !path(for: tab).isEmpty { setPath([], for: tab) }
            return
        }
        selectedTab = tab
        route = path(for: tab).last ?? tab.route
    }

    /// Pushes a page inside its tab (account detail inside Overview).
    func push(_ route: Route) {
        guard let tab = AppTab(route: route) else { return }
        selectedTab = tab
        var path = path(for: tab)
        if path.last != route { path.append(route) }
        setPath(path, for: tab)
        self.route = route
    }

    func popToRoot(_ tab: AppTab) {
        setPath([], for: tab)
    }

    /// Keeps `route`, the lit tab and the stacks consistent for a page opened by
    /// a command, a deep link or the onboarding finish.
    private func apply(_ route: Route) {
        self.route = route
        guard let tab = AppTab(route: route) else { return }
        selectedTab = tab
        switch route {
        case .account:
            tabPaths[.overview] = [route]
        case .about:
            tabPaths[.settings] = []
            sheet = .about
        default:
            tabPaths[tab] = []
        }
    }
    #endif
}
