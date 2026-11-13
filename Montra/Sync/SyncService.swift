import CloudKit
import Foundation
import SwiftData

/// What the sidebar and Settings can honestly say about iCloud.
///
/// SwiftData mirrors the store through `NSPersistentCloudKitContainer`, which
/// uploads and downloads on the system's own schedule and exposes no way to
/// force a transfer. So there is no "sync now" state: the app can report
/// whether iCloud is usable and when it last saw the ledger change, and that is
/// all it pretends to know.
enum CloudSyncState: Equatable {
    /// No iCloud capability in this build, or sync was switched off.
    case notConfigured
    /// The person is not signed in to iCloud on this Mac.
    case noAccount
    /// iCloud is restricted, typically by a managed Mac.
    case restricted
    /// The account state could not be determined.
    case unknown
    /// iCloud is usable; the date is the last time the ledger changed.
    case active(lastChange: Date?)
    case failed(String)

    var isConnected: Bool {
        switch self {
        case .active: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .notConfigured: String(localized: "common.not_connected")
        case .noAccount: String(localized: "sync.no_icloud_account")
        case .restricted: String(localized: "sync.icloud_restricted")
        case .unknown: String(localized: "sync.icloud_unknown")
        case .active(let date):
            if let date { String(localized: "sync.updated \(SyncService.relativeText(for: date))") }
            else { String(localized: "sync.active") }
        case .failed: String(localized: "common.error")
        }
    }
}

/// Reads iCloud availability and tracks when the ledger last changed, so the
/// UI can show "updated 3 minutes ago" instead of inventing a sync progress.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    /// The value the app uses once the container exists in the developer
    /// account and the entitlement is added. Derived from the bundle id because
    /// CloudKit containers are named `iCloud.<bundle id>`.
    nonisolated static let containerIdentifier = "iCloud.\(Bundle.main.bundleIdentifier ?? "com.example.montra")"

    @Published private(set) var state: CloudSyncState = .notConfigured

    /// Set when the store is in memory: tests and snapshots must stay offline.
    private var isEnabled = false
    private var lastSignature: StoreSignature?
    private var timer: Timer?

    private init() {}

    var isConnected: Bool { state.isConnected }

    /// Starts the heartbeat. `inMemory` keeps everything off so `-selftest` and
    /// the snapshot runs never touch the network.
    func start(container: ModelContainer, inMemory: Bool) {
        guard !inMemory else {
            state = .notConfigured
            return
        }
        isEnabled = true
        self.container = container
        refresh()
        timer?.invalidate()
        // CloudKit itself decides when to transfer; polling only notices the
        // result. Two minutes is frequent enough to feel live and cheap enough
        // to ignore.
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
        state = .notConfigured
    }

    /// Re-reads the account state and notices ledger changes. Called at launch,
    /// on a timer, when the window becomes active, and before the app quits.
    func refresh() {
        guard isEnabled else { return }
        Task { @MainActor in
            await refreshStatus()
            updateLastChange()
        }
    }

    private var container: ModelContainer?

    private func refreshStatus() async {
        do {
            let status = try await CKContainer(identifier: Self.containerIdentifier).accountStatus()
            switch status {
            case .available:
                if case .active = state { return }
                state = .active(lastChange: lastSignature?.date)
            case .noAccount:
                state = .noAccount
            case .restricted:
                state = .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                state = .unknown
            @unknown default:
                state = .unknown
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// A cheap fingerprint of the ledger. When it changes while the app itself
    /// is idle, CloudKit has just delivered something from another Mac.
    private func updateLastChange() {
        guard let context = container?.mainContext else { return }
        let signature = StoreSignature(context: context)
        guard signature != lastSignature else { return }
        lastSignature = signature
        if case .active = state {
            state = .active(lastChange: signature.date)
        }
    }

    /// Called before the app terminates. SwiftData saves on every write, so this
    /// only catches a context that was edited but not yet committed. It cannot
    /// force an upload: CloudKit decides when to transfer.
    func flush() {
        guard isEnabled, let context = container?.mainContext else { return }
        if context.hasChanges {
            try? context.save()
        }
    }

    /// Shown in the sidebar, the Settings row and the explanation sheet.
    nonisolated static func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// Counts rows and remembers the newest `createdAt`, which is enough to notice
/// that the store changed without loading the rows themselves.
private struct StoreSignature: Equatable {
    let operations: Int
    let accounts: Int
    let categories: Int
    let periods: Int
    let planned: Int
    let newestCreatedAt: Date?

    var date: Date? { newestCreatedAt }

    init(context: ModelContext) {
        operations = (try? context.fetchCount(FetchDescriptor<Operation>())) ?? 0
        accounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        categories = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        periods = (try? context.fetchCount(FetchDescriptor<Period>())) ?? 0
        planned = (try? context.fetchCount(FetchDescriptor<PlannedOperation>())) ?? 0

        var descriptor = FetchDescriptor<Operation>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        newestCreatedAt = (try? context.fetch(descriptor))?.first?.createdAt
    }
}
