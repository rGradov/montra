#if os(iOS)
import SwiftUI
import UIKit

/// Identifier of the app's one window group, so a second window can be opened
/// on any tab (`openWindow(id:value:)`) without a second scene definition.
enum AppSceneID {
    static let main = "main"
}

// MARK: - Commands

/// The iPad menu bar and hardware keyboard. They act on the focused window's
/// `AppModel`, never on a global notification bus: with several windows open a
/// notification would drive whichever scene happens to answer it.
struct IOSAppCommands: Commands {
    @FocusedValue(\.appModel) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "transaction.new")) {
                app?.present(.newOperation(OperationSource(account: nil, kind: nil)))
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(app == nil)

            Button(String(localized: "account.new")) {
                app?.present(.newAccount(isSavings: false))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(app == nil)

            Divider()

            Button(String(localized: "common.new_window")) {
                openWindow(id: AppSceneID.main, value: app?.selectedTab ?? .overview)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!AppPlatform.isPad || app == nil)
        }

        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "navigation.settings")) { app?.open(.settings) }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(app == nil)
        }

        CommandMenu(String(localized: "navigation.menu")) {
            Button(String(localized: "navigation.overview")) { app?.selectTab(.overview) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(app == nil)
            Button(String(localized: "transaction.all")) { app?.selectTab(.operations) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(app == nil)
            Button(String(localized: "navigation.categories")) { app?.selectTab(.categories) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(app == nil)
            Button(String(localized: "navigation.analytics")) { app?.selectTab(.analytics) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(app == nil)
            Button(String(localized: "navigation.settings")) { app?.selectTab(.settings) }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(app == nil)

            Divider()

            Button(String(localized: "common.about")) { app?.present(.about) }
                .disabled(app == nil)
        }
    }
}

// MARK: - Focused window model

struct FocusedAppModelKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    /// The focused window's navigation model, so commands stay per-window.
    var appModel: AppModel? {
        get { self[FocusedAppModelKey.self] }
        set { self[FocusedAppModelKey.self] = newValue }
    }
}

// MARK: - Share sheet

/// The system share sheet for the CSV export. iOS has no save panel, so the
/// temporary file `CSVExporter` writes is handed over here.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file waiting for the share sheet.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
#endif
