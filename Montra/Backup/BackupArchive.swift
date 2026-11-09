import CryptoKit
import Foundation

/// The file Montra writes and reads when someone saves or restores a backup.
///
/// The whole app state travels in one JSON document: accounts, categories with
/// their nesting, operations and both legs of every transfer, planned payments,
/// periods and the settings that shape the screens. Amounts are stored as
/// decimal strings, not floating-point numbers, so a restored `0.0128 BTC` stays
/// exactly what it was.
///
/// The envelope carries a format version, the app version that made it and a
/// SHA-256 of the payload. A file renamed to `.montra` from something else, a
/// truncated copy or a backup from a newer Montra is rejected with a readable
/// message instead of being half-restored.
struct MontraBackup: Codable, Equatable {
    /// Identifier of the format itself; a file without it is not a backup.
    var format: String
    var formatVersion: Int
    /// SwiftData model generation. Bumped when models change shape.
    var schemaVersion: Int
    var createdAt: Date
    var appVersion: String
    var appBuild: String
    /// Lower-case hex SHA-256 of the canonical payload encoding.
    var checksum: String
    var payload: BackupPayload

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var summary: BackupSummary { payload.summary }
}

/// Everything a person would expect to find again after a restore.
struct BackupPayload: Codable, Equatable {
    var accounts: [AccountBackup]
    var categories: [CategoryBackup]
    var operations: [OperationBackup]
    var plannedOperations: [PlannedOperationBackup]
    var periods: [PeriodBackup]
    var settings: SettingsBackup
    /// The rate table on the day of the backup. Optional so an older file
    /// without it still restores; the app simply refreshes rates afterwards.
    var rates: RatesBackup?
    /// Local API preferences. The access token is a machine secret and is
    /// deliberately not part of a backup; a new Mac gets a new one.
    var integration: IntegrationBackup?
}

struct AccountBackup: Codable, Equatable {
    var id: UUID
    var name: String
    var currency: String
    var initialAmount: String
    var isSavings: Bool
    var isHiddenFromOverview: Bool
    var iconName: String
    var color: String
    var createdAt: Date
    var sortIndex: Int
}

struct CategoryBackup: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: String
    var color: String
    var iconName: String
    var isMandatory: Bool
    var isSystem: Bool
    var sortIndex: Int
    var createdAt: Date
    /// One level of nesting: the parent's id, or nil for a top-level category.
    var parentID: UUID?
}

struct OperationBackup: Codable, Equatable {
    var id: UUID
    var kind: String
    var amount: String
    var currency: String
    var date: Date
    var place: String
    var latitude: Double?
    var longitude: Double?
    var note: String
    var createdAt: Date
    var accountID: UUID?
    var categoryID: UUID?
    var transferID: UUID?
}

struct PlannedOperationBackup: Codable, Equatable {
    var id: UUID
    var seriesID: UUID
    var kind: String
    var amount: String
    var currency: String
    var date: Date
    var place: String
    var note: String
    var createdAt: Date
    var frequency: String
    var weekdayMask: Int
    var seriesStart: Date
    var seriesEnd: Date
    var accountID: UUID?
    var categoryID: UUID?
    var linkedOperationID: UUID?
}

struct PeriodBackup: Codable, Equatable {
    var id: UUID
    var start: Date
    var end: Date
    var isManual: Bool
    var createdAt: Date
}

struct SettingsBackup: Codable, Equatable {
    var appearance: String
    var hideBalances: Bool
    var primaryCurrency: String
    var periodMode: String
    var paydayDay: Int
    var fixedLengthDays: Int
    var periodAnchor: Date
    var didSeedDemo: Bool
    var hasCompletedOnboarding: Bool
}

struct RatesBackup: Codable, Equatable {
    var source: String
    var date: Date?
    var fetchedAt: Date?
    /// Currency raw value → BYN per one unit, as a decimal string.
    var bynPerUnit: [String: String]
}

struct IntegrationBackup: Codable, Equatable {
    var enabled: Bool
    var allowDelete: Bool
}

struct BackupSummary: Equatable {
    var accounts: Int
    var categories: Int
    var operations: Int
    var plans: Int
    var periods: Int

    var records: Int { accounts + categories + operations + plans + periods }
}

extension BackupPayload {
    var summary: BackupSummary {
        BackupSummary(
            accounts: accounts.count,
            categories: categories.count,
            operations: operations.count,
            plans: plannedOperations.count,
            periods: periods.count
        )
    }
}

// MARK: - Coding

enum BackupCoding {
    static let formatIdentifier = "montra.backup"
    static let currentFormatVersion = 1
    static let currentSchemaVersion = 1

    /// Fills in the checksum so an in-memory archive always matches the bytes
    /// that will be written.
    static func seal(_ payload: BackupPayload, createdAt: Date = .now) throws -> MontraBackup {
        MontraBackup(
            format: formatIdentifier,
            formatVersion: currentFormatVersion,
            schemaVersion: currentSchemaVersion,
            createdAt: createdAt,
            appVersion: MontraBackup.appVersion,
            appBuild: MontraBackup.appBuild,
            checksum: try checksum(of: payload),
            payload: payload
        )
    }

    static func checksum(of payload: BackupPayload) throws -> String {
        let data = try encoder(pretty: false).encode(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode(_ backup: MontraBackup) throws -> Data {
        var copy = backup
        copy.checksum = try checksum(of: backup.payload)
        return try encoder(pretty: true).encode(copy)
    }

    static func decode(_ data: Data) throws -> MontraBackup {
        let decoded: MontraBackup
        do {
            decoded = try decoder().decode(MontraBackup.self, from: data)
        } catch {
            throw BackupError.notABackup
        }

        guard decoded.format == formatIdentifier else { throw BackupError.notABackup }
        guard (1...currentFormatVersion).contains(decoded.formatVersion) else {
            throw BackupError.unsupportedVersion
        }
        guard (1...currentSchemaVersion).contains(decoded.schemaVersion) else {
            throw BackupError.unsupportedVersion
        }
        guard let expected = try? checksum(of: decoded.payload),
              expected.caseInsensitiveCompare(decoded.checksum) == .orderedSame else {
            throw BackupError.corrupted
        }
        return decoded
    }

    private static func encoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(BackupDate.format(date))
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = BackupDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid backup date: \(raw)")
            }
            return date
        }
        return decoder
    }
}

/// Dates use ISO 8601 with milliseconds, which keeps two operations created in
/// the same second in the same order after a restore and stays readable when
/// someone opens the file.
enum BackupDate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func format(_ date: Date) -> String {
        withFraction.string(from: date)
    }

    static func parse(_ raw: String) -> Date? {
        withFraction.date(from: raw) ?? plain.date(from: raw)
    }
}

/// Amounts cross the file boundary as strings so no binary floating point ever
/// touches them. `NSDecimalNumber.stringValue` and the POSIX locale keep the
/// dot separator independent of the person's region.
enum BackupDecimal {
    static func text(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func value(_ text: String) throws -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw BackupError.invalidNumber
        }
        return value
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case notABackup
    case unsupportedVersion
    case corrupted
    case invalidNumber
    case unreadable(Error)
    case saveFailed(Error)
    case captureFailed(Error)
    case restoreFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notABackup:
            String(localized: "backup.error.not_a_backup")
        case .unsupportedVersion:
            String(localized: "backup.error.unsupported_version")
        case .corrupted:
            String(localized: "backup.error.corrupted")
        case .invalidNumber:
            String(localized: "backup.error.invalid_number")
        case .unreadable:
            String(localized: "backup.error.unreadable")
        case .saveFailed:
            String(localized: "backup.error.save_failed")
        case .captureFailed:
            String(localized: "backup.error.capture_failed")
        case .restoreFailed:
            String(localized: "backup.error.restore_failed")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notABackup, .corrupted, .invalidNumber:
            String(localized: "backup.error.choose_a_file_saved_by")
        case .unsupportedVersion:
            String(localized: "backup.error.update_montra_to_the_version")
        case .unreadable:
            String(localized: "backup.error.make_sure_the_file_is")
        case .saveFailed(let error), .captureFailed(let error), .restoreFailed(let error):
            error.localizedDescription
        }
    }
}
