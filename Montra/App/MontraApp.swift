import AppIntents
import SwiftData
import SwiftUI

@main
struct MontraApp: App {
    private let container: ModelContainer
    private let needsOnboarding: Bool
    @StateObject private var settings: SettingsStore
    @StateObject private var integration: LocalIntegration
    @StateObject private var rates: RateStore

    @MainActor
    init() {
        AppFonts.register()
        if SelfTest.runIfRequested() { exit(0) }
        if OnboardingIntroSnapshot.renderIfRequested() { exit(0) }

        // `-preview-onboarding` runs the welcome flow on a throwaway store, so it
        // can be tried without touching real data. Used by the README and for QA.
        let previewOnboarding = CommandLine.arguments.contains("-preview-onboarding")
        // The snapshot runs render their own in-memory fixtures; opening the real
        // store here would still migrate it, so QA launches stay isolated too.
        let rendersOnly = CommandLine.arguments.contains("-snapshot")
            || CommandLine.arguments.contains("-animate-header")
        let container = previewOnboarding || rendersOnly
            ? ModelContainerFactory.make(inMemory: true)
            : ModelContainerFactory.make()
        self.container = container

        let settings: SettingsStore
        if previewOnboarding {
            let previewDefaults = UserDefaults(suiteName: "montra.preview") ?? .standard
            previewDefaults.removePersistentDomain(forName: "montra.preview")
            settings = SettingsStore(defaults: previewDefaults)
        } else {
            settings = SettingsStore()
        }
        _settings = StateObject(wrappedValue: settings)
        let rates = RateStore()
        _rates = StateObject(wrappedValue: rates)
        _integration = StateObject(wrappedValue: LocalIntegration(container: container, available: !previewOnboarding))

        // A store that already has accounts belongs to someone who has used the
        // app before the welcome flow existed: never put a first run on top of
        // their data. Once the flow has been opened, only finishing it counts —
        // see `OnboardingLaunch`.
        let accountCount = previewOnboarding
            ? 0
            : ((try? container.mainContext.fetchCount(FetchDescriptor<Account>())) ?? 0)
        needsOnboarding = previewOnboarding
            || OnboardingLaunch.needsOnboarding(accountCount: accountCount, settings: settings)

        if #available(macOS 26.0, *) {
            let isPersistent = container.configurations.contains { !$0.isStoredInMemoryOnly }
            let ledger = SpotlightLedger(
                context: container.mainContext, settings: settings, rates: rates, available: isPersistent
            )
            AppDependencyManager.shared.add(dependency: ledger)
        }

        SnapshotRunner.runIfRequested(container: container, settings: settings)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(needsOnboarding: needsOnboarding)
                .environmentObject(settings)
                .environmentObject(rates)
                .environmentObject(integration)
                .modelContainer(container)
                .onChange(of: settings.hasCompletedOnboarding, initial: true) { _, completed in
                    integration.startIfEnabled(onboardingComplete: completed)
                }
                .background(WindowConfigurator())
                .frame(minWidth: AppWindowLayout.width, maxWidth: AppWindowLayout.width,
                       minHeight: AppWindowLayout.minHeight)
        }
        .defaultSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu(String(localized: "common.integration")) {
                Button(integration.enabled ? String(localized: "app.disable_local_api") : String(localized: "app.enable_local_api")) {
                    integration.setEnabled(!integration.enabled, onboardingComplete: settings.hasCompletedOnboarding)
                }
                .disabled(!settings.hasCompletedOnboarding)

                Button(String(localized: "app.copy_api_token")) { integration.copyToken() }
                    .disabled(!integration.active)

                Toggle(String(localized: "app.allow_deletion_via_api"), isOn: $integration.allowDelete)
                    .disabled(!integration.active)

                if let failure = integration.failure {
                    Text(failure)
                } else if integration.active {
                    Text("127.0.0.1:8766")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(String(localized: "transaction.new")) {
                    NotificationCenter.default.post(name: .montraNewOperation, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(String(localized: "account.new")) {
                    NotificationCenter.default.post(name: .montraNewAccount, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Button(String(localized: "navigation.overview")) { NotificationCenter.default.post(name: .montraGoOverview, object: nil) }
                    .keyboardShortcut("1", modifiers: .command)
                Button(String(localized: "transaction.all")) { NotificationCenter.default.post(name: .montraGoOperations, object: nil) }
                    .keyboardShortcut("2", modifiers: .command)
                Button(String(localized: "navigation.categories")) { NotificationCenter.default.post(name: .montraGoCategories, object: nil) }
                    .keyboardShortcut("3", modifiers: .command)
                Button(String(localized: "navigation.analytics")) { NotificationCenter.default.post(name: .montraGoAnalytics, object: nil) }
                    .keyboardShortcut("4", modifiers: .command)
                Button(String(localized: "navigation.settings")) { NotificationCenter.default.post(name: .montraGoSettings, object: nil) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let montraNewOperation = Notification.Name("montra.newOperation")
    static let montraNewAccount = Notification.Name("montra.newAccount")
    static let montraGoOverview = Notification.Name("montra.go.overview")
    static let montraGoOperations = Notification.Name("montra.go.operations")
    static let montraGoCategories = Notification.Name("montra.go.categories")
    static let montraGoAnalytics = Notification.Name("montra.go.analytics")
    static let montraGoSettings = Notification.Name("montra.go.settings")
}

enum AppWindowLayout {
    /// The reference app keeps one width and lets only the height change, so the
    /// sidebar and the page column always hold their proportions.
    static let width: CGFloat = 980
    static let minHeight: CGFloat = 600
    static let defaultHeight: CGFloat = 700
}

/// Pins the window to the app's one width and clears the title bar, leaving the
/// traffic lights floating over the sidebar exactly as the reference does.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.resizable)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(AppColors.surfaceBase)
        window.minSize = NSSize(width: AppWindowLayout.width, height: AppWindowLayout.minHeight)
        window.maxSize = NSSize(width: AppWindowLayout.width, height: .greatestFiniteMagnitude)
        if abs(window.frame.width - AppWindowLayout.width) > 1 {
            var frame = window.frame
            let height = max(frame.height, AppWindowLayout.defaultHeight)
            frame.size = NSSize(width: AppWindowLayout.width, height: height)
            window.setFrame(frame, display: true)
        }
    }
}

enum ModelContainerFactory {
    static let schema = Schema([Account.self, Category.self, Operation.self, Period.self, PlannedOperation.self])

    static func make(inMemory: Bool = false) -> ModelContainer {
        // iCloud: switch `cloudKitDatabase` to `.private("iCloud.com.example.montra")`
        // once the container exists in the developer account and the entitlement is
        // added. See Docs/iCloud-Setup.md. The models already satisfy CloudKit's rules.
        let configuration = ModelConfiguration(
            "Montra",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupt store should not keep the app closed; fall back to memory and
            // let the user reset from Settings.
            assertionFailure(String(localized: "storage.open_error \(error.localizedDescription)"))
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
    }
}
