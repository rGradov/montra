import AppKit
import Foundation
import SwiftUI

/// Reads the stores and hands the operations over as a spreadsheet. Kept out of
/// the views so the format lives in one place and can grow export options later.
@MainActor
enum CSVExporter {
    static func csv(for operations: [Operation]) -> String {
        let header = [String(localized: "common.date"), String(localized: "common.time"), String(localized: "common.type"), String(localized: "common.category"), String(localized: "common.account"), String(localized: "common.currency"), String(localized: "common.amount"), String(localized: "common.location"), String(localized: "common.note")]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = AppLocalization.locale
        dateFormatter.setLocalizedDateFormatFromTemplate("yyyyMMdd")
        let timeFormatter = DateFormatter()
        timeFormatter.locale = AppLocalization.locale
        timeFormatter.dateFormat = "HH:mm"

        var lines = [header.map(escape).joined(separator: ";")]
        for operation in operations.sorted(by: { $0.date > $1.date }) {
            let row = [
                dateFormatter.string(from: operation.date),
                timeFormatter.string(from: operation.date),
                operation.kind.title,
                operation.category?.displayName ?? "",
                operation.account?.name ?? "",
                operation.currency.code,
                NSDecimalNumber(decimal: operation.amount).stringValue,
                operation.place,
                operation.note,
            ]
            lines.append(row.map(escape).joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }

    static func export(_ operations: [Operation]) {
        let panel = NSSavePanel()
        panel.title = String(localized: "common.export_transactions")
        panel.nameFieldStringValue = "montra-operations.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "common.export")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv(for: operations).data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "export.couldnt_save_the_file")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func escape(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
