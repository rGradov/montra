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
    case newAccount
    case editAccount(Account)
    case newCategory(OperationKind)
    case editCategory(Category)
    case periods
    case iCloud

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
        case .newAccount:
            "new-account"
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
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: Route
    @Published var sheet: AppSheet?

    init(route: Route = .overview) {
        self.route = route
    }

    func open(_ route: Route) {
        withAnimation(AppMotion.route) { self.route = route }
    }

    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }
}
