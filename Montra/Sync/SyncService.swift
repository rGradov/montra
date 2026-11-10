import Foundation

/// The seam for iCloud. Montra writes everything through its repositories and
/// keeps every model CloudKit-safe, so turning sync on is a configuration change
/// plus a container, not a rewrite. Until then the app says so honestly.
enum CloudSyncState: Equatable {
    case notConfigured
    case ready
    case syncing
    case failed(String)

    var title: String {
        switch self {
        case .notConfigured: String(localized: "common.not_connected")
        case .ready: String(localized: "common.done")
        case .syncing: String(localized: "common.syncing")
        case .failed: String(localized: "common.error")
        }
    }

    var isConnected: Bool {
        switch self {
        case .ready, .syncing: true
        case .notConfigured, .failed: false
        }
    }
}

protocol SyncProvider {
    var identifier: String { get }
    func start() async throws
    func stop()
}

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    /// The value the app will use once the container is created in the developer
    /// account and the entitlement is added. Kept here so no code has to guess it.
    nonisolated static let containerIdentifier = "iCloud.\(Bundle.main.bundleIdentifier ?? "com.example.montra")"

    @Published private(set) var state: CloudSyncState = .notConfigured

    var isConnected: Bool { state.isConnected }

    private init() {}

    /// Called if a future build ships the entitlement and a provider. With no
    /// entitlement this reports the honest state instead of pretending.
    func start(provider: SyncProvider?) async {
        guard let provider else {
            state = .notConfigured
            return
        }
        state = .syncing
        do {
            try await provider.start()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
