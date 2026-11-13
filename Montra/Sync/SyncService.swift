import CloudKit
import Foundation
import SwiftData

/// What the sidebar and Settings can honestly say about iCloud.
///
/// SwiftData mirrors the store through `NSPersistentCloudKitContainer`, which
/// uploads and downloads on the system's own schedule and exposes no way to
/// force a transfer. So there is no "syncing" state: the app reports whether
/// iCloud is usable and when the ledger last changed, and that is all it claims.
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
        if case .active = self { return true }
        return false
    }

    /// `.unknown` is not an error and not a success, so it is the only state
    /// that stays neutral.
    var needsAttention: Bool {
        switch self {
        case .noAccount, .restricted, .failed, .notConfigured: true
        case .unknown, .active: false
        }
    }
}

/// Presentation for the state. Kept beside the enum so every surface shows the
/// same words, symbol and tone instead of inventing its own.
struct CloudSyncAppearance {
    let symbol: String
    let tone: AppBadge.Tone
    /// One or two words for a badge.
    let badge: String
    /// True when the state needs the person's attention. Fed from
    /// `CloudSyncState.needsAttention` so the icon and the badge can never
    /// disagree about it.
    let needsAttention: Bool
    /// A full sentence for a sheet subtitle or a Settings value.
    let sentence: String
    /// Short form that fits the 240 pt sidebar.
    let compact: String
    /// Action offered when the state is actionable.
    let action: String?
}

/// Reads iCloud availability and tracks when the ledger last changed, so the UI
/// can show the real state instead of inventing progress.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    /// The value the app uses once the container exists in the developer
    /// account and the entitlement is added. Derived from the bundle id because
    /// CloudKit containers are named `iCloud.<bundle id>`.
    nonisolated static let containerIdentifier = "iCloud.\(Bundle.main.bundleIdentifier ?? "com.example.montra")"

    /// `nil` while the first account check is still running, so nothing flashes
    /// "not connected" during launch.
    @Published private(set) var state: CloudSyncState?

    private var isEnabled = false
    private var lastSignature: StoreSignature?
    private var timer: Timer?
    private var container: ModelContainer?
    /// One in-flight check at a time. Launch, window activation and the sheet can
    /// all ask at once, and a late stale answer must not overwrite a fresh one.
    private var refreshTask: Task<Void, Never>?

    private init() {}

    var isConnected: Bool { state?.isConnected ?? false }

    var appearance: CloudSyncAppearance {
        Self.appearance(for: state)
    }

    static func appearance(for state: CloudSyncState?) -> CloudSyncAppearance {
        guard let state else {
            return CloudSyncAppearance(
                symbol: "icloud",
                tone: .neutral,
                badge: String(localized: "sync.badge_checking"),
                needsAttention: false,
                sentence: String(localized: "sync.checking"),
                compact: String(localized: "sync.compact_checking"),
                action: nil
            )
        }
        switch state {
        case .active(let lastChange):
            return CloudSyncAppearance(
                symbol: "checkmark.icloud",
                tone: .safe,
                badge: String(localized: "sync.badge_on"),
                needsAttention: false,
                sentence: lastChangeText(lastChange),
                compact: compactText(lastChange),
                action: nil
            )
        case .noAccount:
            return CloudSyncAppearance(
                symbol: "icloud.slash",
                tone: .warning,
                badge: String(localized: "sync.badge_off"),
                needsAttention: true,
                sentence: String(localized: "sync.no_account_sentence"),
                compact: String(localized: "sync.compact_no_account"),
                action: String(localized: "sync.open_icloud_settings")
            )
        case .restricted:
            return CloudSyncAppearance(
                symbol: "lock.icloud",
                tone: .warning,
                badge: String(localized: "sync.badge_off"),
                needsAttention: true,
                sentence: String(localized: "sync.restricted_sentence"),
                compact: String(localized: "sync.compact_restricted"),
                action: String(localized: "sync.open_icloud_settings")
            )
        case .unknown:
            return CloudSyncAppearance(
                symbol: "icloud",
                tone: .neutral,
                badge: String(localized: "sync.badge_unknown"),
                needsAttention: false,
                sentence: String(localized: "sync.unknown_sentence"),
                compact: String(localized: "sync.compact_unknown"),
                action: String(localized: "sync.try_again")
            )
        case .failed:
            return CloudSyncAppearance(
                symbol: "exclamationmark.icloud",
                tone: .danger,
                badge: String(localized: "sync.badge_failed"),
                needsAttention: true,
                sentence: String(localized: "sync.failed_sentence"),
                compact: String(localized: "sync.compact_failed"),
                action: String(localized: "sync.try_again")
            )
        case .notConfigured:
            return CloudSyncAppearance(
                symbol: "icloud.slash",
                tone: .neutral,
                badge: String(localized: "sync.badge_off"),
                needsAttention: true,
                sentence: String(localized: "sync.not_configured_sentence"),
                compact: String(localized: "sync.compact_off"),
                action: nil
            )
        }
    }

    /// An absolute time, because "3 min ago" was being read as a sync time while
    /// the value really describes the last edit to the ledger.
    private static func lastChangeText(_ date: Date?) -> String {
        guard let date else { return String(localized: "sync.no_changes_yet") }
        let calendar = Calendar.current
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLocalization.locale))
        if calendar.isDateInToday(date) {
            return String(localized: "sync.last_change_today \(time)")
        }
        return String(localized: "sync.last_change \(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocalization.locale)))")
    }

    private static func compactText(_ date: Date?) -> String {
        guard let date else { return String(localized: "sync.compact_on") }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLocalization.locale))
        return String(localized: "sync.compact_on_at \(time)")
    }

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
        // CloudKit decides when to transfer; polling only notices the result.
        // Two minutes is frequent enough to feel live and cheap enough to ignore.
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Turns the heartbeat off. Used by teardown and by tests; the state becomes
    /// an honest "off" rather than a permanent "checking".
    func stop() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
        state = .notConfigured
    }

    /// Re-reads the account state and notices ledger changes. Called at launch,
    /// on a timer, when the window becomes active, and from the sheet.
    func refresh() {
        guard isEnabled, refreshTask == nil else { return }
        refreshTask = Task { @MainActor in
            defer { refreshTask = nil }
            await refreshStatus()
            updateLastChange()
        }
    }

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
    /// is idle, CloudKit has delivered something from another Mac.
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
}

/// Counts rows and remembers the newest `createdAt`. Enough to notice that the
/// store gained or lost rows, without loading them. Edits to an existing row are
/// not detected, which is why the UI says "last change" and not "last sync".
struct StoreSignature: Equatable {
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
