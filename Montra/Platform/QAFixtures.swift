import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

#if DEBUG
/// Debug-only launch switches used by the screenshot harness and the UI tests.
/// They seed an in-memory store, so a QA launch can never touch real data.
///
/// The fixture deliberately mirrors `SnapshotRunner`'s macOS store — the same
/// accounts, operations, coffee subcategory, two recurring plans and two demo
/// transfers, with the same preview rates — so a macOS snapshot and an iOS
/// screenshot of the same screen show the same figures.
enum QAFixtures {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isEnabled: Bool { arguments.contains("-qa-demo") }

    static var appearance: SettingsStore.Appearance? {
        guard let value = value(after: "-qa-appearance") else { return nil }
        switch value {
        case "light": return .light
        case "dark": return .dark
        default: return .auto
        }
    }

    static var routeName: String? { value(after: "-qa-route") }

    /// `-qa-about` opens About on its own. On iOS/iPadOS that is the About sheet
    /// over Settings; on macOS it is the About page.
    static var isAboutRequested: Bool { arguments.contains("-qa-about") }

    static var sheet: AppSheet? {
        if isAboutRequested { return .about }
        switch value(after: "-qa-sheet") {
        case "new-operation": return .newOperation(OperationSource(account: nil, kind: nil))
        case "new-account": return .newAccount(isSavings: false)
        case "new-category": return .newCategory(.expense)
        case "periods": return .periods
        case "icloud": return .iCloud
        case "about": return .about
        default: return nil
        }
    }

    /// Opens a second window on another tab at launch, so multi-window (shared
    /// `ModelContainer`, per-window navigation state) can be checked without a
    /// pointer.
    static var opensExtraWindow: Bool { arguments.contains("-qa-second-window") }

    /// `-qa-sheet restore` is the restore confirmation, which needs a decoded
    /// backup rather than an `AppSheet`; the Settings screen builds one from the
    /// demo store.
    static var presentsRestoreSheet: Bool {
        value(after: "-qa-sheet") == "restore"
    }

    /// Resolves the requested page after the demo store exists, so an account
    /// route can point at a real demo account.
    static func route(accounts: [Account]) -> Route? {
        if isAboutRequested { return .about }
        switch routeName {
        case "overview": return .overview
        case "operations": return .operations
        case "categories": return .categories
        case "analytics": return .analytics
        case "settings": return .settings
        case "about": return .about
        case "account":
            guard let account = accounts.first else { return .overview }
            return .account(account.id)
        default:
            return nil
        }
    }

    /// `-qa-orientation landscape` asks for a landscape window through the
    /// supported geometry-update API, so rotated screens can be captured on a
    /// simulator, where there is no rotation control.
    #if os(iOS)
    static var orientationMask: UIInterfaceOrientationMask? {
        guard let value = value(after: "-qa-orientation") else { return nil }
        switch value {
        case "landscape": return .landscapeRight
        case "portrait": return .portrait
        default: return nil
        }
    }
    #endif

    // MARK: - Store

    /// Seeds the demo store: the app's bootstrap and demo month, then the exact
    /// extra rows `SnapshotRunner` adds for the macOS fixtures.
    @MainActor
    static func seedStore(_ context: ModelContext, settings: SettingsStore) {
        settings.primaryCurrency = .byn
        SeedData.bootstrap(context: context, settings: settings)
        SeedData.seedDemo(context: context, settings: settings)

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if let food = categories.first(where: { $0.starterCategory == .food && $0.kind == .expense }) {
            _ = CategoryRepository(context: context).create(
                name: String(localized: "demo.coffee"),
                kind: .expense,
                color: .orange,
                iconName: "cup.and.saucer.fill",
                isMandatory: false,
                parent: food
            )
        }

        let accounts = (try? context.fetch(
            FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex)])
        )) ?? []

        // Two recurring plans: one overdue and one upcoming, so the plan rows,
        // the missed/upcoming filters and their actions are all visible.
        if let cash = accounts.first(where: { $0.currency == .byn }),
           let housing = categories.first(where: { $0.starterCategory == .housing && $0.kind == .expense }) {
            let today = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .year, value: 1, to: today) ?? today
            if let missedStart = Calendar.current.date(byAdding: .day, value: -1, to: today) {
                _ = PlanRepository(context: context).create(
                    kind: .expense,
                    amount: 700,
                    account: cash,
                    category: housing,
                    date: missedStart.addingTimeInterval(10 * 3600),
                    place: String(localized: "demo.landlord"),
                    note: String(localized: "demo.rent"),
                    frequency: .month,
                    weekdays: [],
                    end: end
                )
            }
            if let upcomingStart = Calendar.current.date(byAdding: .day, value: 1, to: today) {
                _ = PlanRepository(context: context).create(
                    kind: .expense,
                    amount: 700,
                    account: cash,
                    category: housing,
                    date: upcomingStart.addingTimeInterval(10 * 3600),
                    place: String(localized: "demo.landlord"),
                    note: String(localized: "demo.rent"),
                    frequency: .month,
                    weekdays: [],
                    end: end
                )
            }
        }

        // One transfer between currencies, so the read-only transfer detail and
        // the cross-currency rows are visible.
        if let source = accounts.first(where: { $0.currency == .byn }),
           let destination = accounts.first(where: { $0.currency == .eur }) {
            _ = TransferRepository(context: context).create(
                from: source,
                to: destination,
                sent: 100,
                received: 30
            )
        }

        // A transfer into the savings account, so Analytics shows it as savings
        // rather than spending.
        if let cash = accounts.first(where: { $0.currency == .byn && !$0.isSavings }),
           let savings = accounts.first(where: { $0.isSavings }) {
            _ = TransferRepository(context: context).create(
                from: cash,
                to: savings,
                sent: 100,
                received: Decimal(100) / Decimal(227_358)
            )
        }
    }

    /// The same rate table the macOS snapshots render with, so converted figures
    /// match across platforms without a network round trip.
    @MainActor
    static func makeRates() -> RateStore {
        RateStore(preview: ExchangeRates(
            bynPerUnit: [
                .byn: 1,
                .usd: 3.0010,
                .eur: 3.3460,
                .usdc: 3.0034,
                .usdt: 2.9963,
                .btc: 227_358,
                .eth: 6_705,
            ],
            date: Calendar.current.date(byAdding: .day, value: -1, to: .now),
            fetchedAt: .now,
            source: .nbrb
        ))
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
