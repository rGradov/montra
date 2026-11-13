import SwiftUI
import UniformTypeIdentifiers

/// Bridges the in-memory `.montra` archive to SwiftUI's document pickers. The
/// Mac keeps its AppKit panels; iOS and iPadOS use this document with
/// `fileExporter` / `fileImporter`, so both platforms read and write exactly the
/// same JSON format through `BackupArchive`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [BackupFile.contentType] }
    static var writableContentTypes: [UTType] { [BackupFile.contentType] }

    var backup: MontraBackup

    init(backup: MontraBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backup = try BackupCoding.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BackupCoding.encode(backup))
    }
}
