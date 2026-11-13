import SwiftUI

#if DEBUG
/// Debug-only launch switches used by the screenshot harness and the UI tests.
/// They seed an in-memory store, so a QA launch can never touch real data.
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

    static var sheet: AppSheet? {
        switch value(after: "-qa-sheet") {
        case "new-operation": return .newOperation(OperationSource(account: nil, kind: nil))
        case "new-account": return .newAccount(isSavings: false)
        case "new-category": return .newCategory(.expense)
        case "periods": return .periods
        case "icloud": return .iCloud
        default: return nil
        }
    }

    /// Resolves the requested page after the demo store exists, so an account
    /// route can point at a real demo account.
    static func route(accounts: [Account]) -> Route? {
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

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
