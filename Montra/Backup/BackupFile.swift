import AppKit
import Foundation
import UniformTypeIdentifiers

/// The file-level half of backups: the save and open panels, the `.montra`
/// extension and the small confirmations around them. Kept apart from
/// `BackupService` so the archive logic never depends on AppKit.
@MainActor
enum BackupFile {
    static let fileExtension = "montra"

    /// A dynamic type for the extension. It gives the panels both the filter and
    /// the default extension without an Info.plist declaration, because the app
    /// is not a document-based one and backups are opened from Settings.
    static var contentType: UTType {
        UTType(filenameExtension: fileExtension, conformingTo: .data) ?? .data
    }

    /// "Montra-2026-11-09-2057.montra" — sorts by date and never overwrites the
    /// previous copy by accident.
    static func suggestedName(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Montra-\(formatter.string(from: now)).\(fileExtension)"
    }

    // MARK: - Panels

    /// Shows the save panel and writes the archive. Returns nil when the person
    /// cancels, and throws when the file cannot be written.
    static func export(_ backup: MontraBackup, suggestedName name: String? = nil) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = String(localized: "backup.save_title")
        panel.nameFieldStringValue = name ?? suggestedName()
        panel.allowedContentTypes = [contentType]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = String(localized: "backup.save_action")

        guard panel.runModal() == .OK, var url = panel.url else { return nil }
        if url.pathExtension.isEmpty { url.appendPathExtension(fileExtension) }
        try BackupService.write(backup, to: url)
        return url
    }

    /// Shows the open panel and decodes the chosen archive. Returns nil when the
    /// person cancels, and throws when the file is not a valid backup.
    static func chooseArchive() throws -> (backup: MontraBackup, url: URL)? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "backup.open_title")
        panel.allowedContentTypes = [contentType]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "backup.open_action")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (try BackupService.read(from: url), url)
    }

    // MARK: - Feedback

    static func confirmSave(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "backup.saved_title")
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
        let sizeText = size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        alert.informativeText = [url.lastPathComponent, sizeText].compactMap { $0 }.joined(separator: " · ")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "backup.show_in_finder"))
        alert.addButton(withTitle: String(localized: "common.close"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func presentError(_ error: Error, title: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title ?? String(localized: "backup.error.title")
        alert.informativeText = [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "common.ok"))
        alert.runModal()
    }
}
