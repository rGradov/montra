import Combine
import Network
import Security
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class LocalIntegration: ObservableObject {
    private static let enabledKey = "montra.integration.enabled"
    private static let deleteKey = "montra.integration.allowDeletion"
    private static let legacyAccountDeleteKey = "montra.integration.allowAccountDeletion"
    private static let legacyEntryDeleteKey = "montra.integration.allowEntryDeletion"

    @Published private(set) var enabled: Bool
    @Published private(set) var active = false
    @Published private(set) var failure: String?
    @Published var allowDelete: Bool {
        didSet { defaults.set(allowDelete, forKey: Self.deleteKey) }
    }

    private let defaults: UserDefaults
    private let ledger: LedgerAPI
    let available: Bool
    private var server: LocalHTTPServer?
    private var generation = UUID()
    private var token: String?

    init(container: ModelContainer, available: Bool, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.available = available
            && AppPlatform.supportsLocalIntegration
            && container.configurations.allSatisfy { !$0.isStoredInMemoryOnly }
        enabled = self.available && defaults.bool(forKey: Self.enabledKey)
        // A legacy grant can carry over only if it covered every deletion command.
        allowDelete = (defaults.object(forKey: Self.deleteKey) as? Bool)
            ?? (defaults.bool(forKey: Self.legacyAccountDeleteKey) && defaults.bool(forKey: Self.legacyEntryDeleteKey))
        ledger = LedgerAPI(context: container.mainContext)
    }

    func startIfEnabled(onboardingComplete: Bool) {
        guard onboardingComplete else { stop(); return }
        guard enabled, available, server == nil else { return }
        do {
            let token = try LocalAPIToken.loadOrCreate()
            let server = try LocalHTTPServer()
            let generation = UUID()
            self.generation = generation
            self.server = server
            self.token = token
            failure = nil
            server.start(token: token) { [weak self] state in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    switch state {
                    case .ready:
                        self.active = true
                    case .failed, .waiting:
                        self.stop()
                        self.failure = String(localized: "integration.port_8766_is_unavailable_turn")
                    default:
                        break
                    }
                }
            } handle: { [weak self] body, reply in
                Task { @MainActor in
                    guard let self, self.generation == generation, self.active else {
                        reply(HTTPReply(status: 503, error: "The Montra API is unavailable."))
                        return
                    }
                    reply(Self.respond(
                        body, ledger: self.ledger, allowDelete: self.allowDelete
                    ))
                }
            }
        } catch {
            stop()
            failure = String(localized: "integration.couldnt_start_the_api_or")
        }
    }

    func setEnabled(_ value: Bool, onboardingComplete: Bool) {
        guard available else { return }
        enabled = value
        defaults.set(value, forKey: Self.enabledKey)
        if value { startIfEnabled(onboardingComplete: onboardingComplete) }
        else { stop(); failure = nil }
    }

    func copyToken() {
        guard active, let token else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        #else
        UIPasteboard.general.string = token
        #endif
    }

    /// Restores the switches that travel in a backup. The access token does not:
    /// it belongs to this Mac, and an existing one keeps working after a restore.
    func applyBackup(enabled: Bool, allowDelete: Bool, onboardingComplete: Bool) {
        guard available else { return }
        self.allowDelete = allowDelete
        setEnabled(enabled, onboardingComplete: onboardingComplete)
    }

    private func stop() {
        generation = UUID()
        active = false
        server?.stop()
        server = nil
        token = nil
    }

    static func respond(_ body: Data, ledger: LedgerAPI, allowDelete: Bool) -> HTTPReply {
        do {
            return HTTPReply(status: 200, body: try ledger.execute(body, allowDelete: allowDelete))
        } catch let error as LedgerError {
            return HTTPReply(status: error.status, error: error.message)
        } catch is DecodingError {
            return HTTPReply(status: 400, error: "Invalid command or field type. Check the API documentation.")
        } catch {
            return HTTPReply(status: 500, error: "SwiftData could not complete the request.")
        }
    }
}

private enum LocalAPIToken {
    private static let directory: URL = {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Montra/LocalAPI", isDirectory: true)
        #else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montra/LocalAPI", isDirectory: true)
        #endif
    }()

    static func loadOrCreate() throws -> String {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let folder = try files.attributesOfItem(atPath: directory.path)
        guard folder[.type] as? FileAttributeType == .typeDirectory,
              (folder[.posixPermissions] as? Int) == 0o700 else { throw LedgerError("Unsafe token directory permissions.") }

        let url = directory.appendingPathComponent("token")
        if files.fileExists(atPath: url.path) {
            let info = try files.attributesOfItem(atPath: url.path)
            guard info[.type] as? FileAttributeType == .typeRegular,
                  (info[.posixPermissions] as? Int) == 0o600,
                  (info[.size] as? Int) == 64 else { throw LedgerError("Unsafe token file.") }
            let token = try String(contentsOf: url, encoding: .ascii)
            guard token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw LedgerError("Invalid API token.")
            }
            return token
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw LedgerError("Could not generate the API token.") }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try Data(token.utf8).write(to: url, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }
}
