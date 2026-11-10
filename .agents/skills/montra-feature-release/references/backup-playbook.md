# Backup playbook

A `.montra` backup is a JSON document with a `MontraBackup` envelope and
`BackupPayload`. The envelope contains the format, schema and app versions,
and the payload's SHA-256 hash. The payload contains accounts, categories,
transactions, plans, periods, settings, exchange rates, and Local API settings.
Amounts are decimal strings and dates use ISO 8601 with milliseconds.

- `Montra/Backup/BackupArchive.swift` defines structures and encoding.
- `Montra/Backup/BackupService.swift` handles capture, restore, applying settings,
  and reference validation.
- `Montra/Backup/BackupFile.swift` handles file panels and the `.montra` extension.
- `Montra/Features/Settings/BackupRestoreSheet.swift` confirms restore and applies
  restored rates and API settings.
- `Montra/Snapshot/SelfTest.swift` contains backup checks.

## 1. New model fields

The following example adds `isPinned` to an account.

### Model

```swift
@Model
final class Account {
    // ...
    var isPinned: Bool = false

    init(
        // ...
        isPinned: Bool = false,
        // ...
    ) {
        // ...
        self.isPinned = isPinned
    }
}
```

Give the property a default so SwiftData can migrate existing stores.

### Format

```swift
struct AccountBackup: Codable, Equatable {
    // ...
    /// Older files without the flag restore it as false.
    var isPinned: Bool?
}
```

The synthesized `JSONDecoder` logic treats a missing optional field as `nil`.
Restore supplies the default. A missing required field fails decoding.

### Capture

```swift
private extension AccountBackup {
    init(_ account: Account) {
        self.init(
            // ...
            isPinned: account.isPinned
        )
    }
}
```

### Restore

```swift
let account = Account(
    // ...
    isPinned: row.isPinned ?? false
)
```

If the field is a `UUID` reference, validate it in `PreparedPayload` before
deleting current records.

### Versions

```swift
enum BackupCoding {
    static let currentFormatVersion = 2   // Payload changed
    static let currentSchemaVersion = 2   // Model gained a stored property
}
```

- New releases read older formats within `1...current` using optional fields.
- Older releases report that Montra needs an update when they see a newer
  `formatVersion`.
- If an existing field changes meaning, bump both versions and document migration.

### Self-test

Add the check to the existing backup block in `SelfTest.swift` and reuse its fixtures.

```swift
let pinned = Account(
    name: "Pinned", currency: .byn, initialAmount: 10,
    iconName: "creditcard.fill", color: .blue
)
pinned.isPinned = true
backupContext.insert(pinned)

// After capture
check(
    archive.payload.accounts.first { $0.id == pinned.id }?.isPinned == true,
    "backup captured the pinned flag"
)

// After restore
let restoredPinned = accounts.first { $0.id == pinned.id }
check(restoredPinned?.isPinned == true, "backup restored the pinned flag")
```

Check that the value appears in the payload, survives encoding and decoding, and
restores into a new context.

## 2. New settings

```swift
// SettingsStore.swift
@Published var showCents: Bool {
    didSet { defaults.set(showCents, forKey: Key.showCents) }
}
```

```swift
// BackupArchive.swift
struct SettingsBackup: Codable, Equatable {
    // ...
    var showCents: Bool?
}
```

```swift
// BackupService.swift — capture
private extension SettingsBackup {
    init(_ settings: SettingsStore) {
        self.init(
            // ...
            showCents: settings.showCents
        )
    }
}
```

```swift
// BackupService.swift — restore
private static func apply(_ backup: SettingsBackup, hasAccounts: Bool, to settings: SettingsStore) {
    // ...
    settings.showCents = backup.showCents ?? true
}
```

The restore fallback must match the default in `SettingsStore.init` so older
backups preserve the intended behavior. `lastBackupAt` is a machine-specific
timestamp recorded in the allowlist and excluded from `SettingsBackup`.

## 3. State outside SwiftData

Examples include the rate table and Local API settings.

1. Add runtime values to `BackupService.Environment`.
2. Add an optional section to `BackupPayload`, such as `RatesBackup?` or
   `IntegrationBackup?`.
3. Populate it in `BackupService.capture`.
4. Return the values through `BackupService.RestoreReport`.
5. Apply them in `BackupRestoreSheet.performRestore`.
6. Reuse `LocalIntegration.applyBackup` or `RateStore.applyBackup` where applicable.
7. Update both capture callers, `SettingsView.backupEnvironment` and
   `BackupRestoreSheet.environment`.

Exclude secrets such as the API token. Each Mac generates its own token.

## 4. New entities

1. Add an optional array to `BackupPayload`, for example
   `var tags: [TagBackup]?`. Decode older files with `?? []`.
2. Add a count such as `tags: Int` to `BackupSummary` and include it in `records`.
3. Fetch and sort consistently in `capture`, then map with `TagBackup.init`.
4. Create and insert records in dependency order in `restore.insert`.
5. Validate foreign keys in `PreparedPayload` before deleting anything.
6. Delete dependent entities before their parents in `deleteAll`.
7. Add a count row and localization key in `BackupRestoreSheet`.
8. Add a fixture, capture and restore checks, and reference assertions to `SelfTest`.
9. Add a persistence scenario to `Docs/Feature-Inventory.md`.

Use two passes for relationships, as with category parents. Insert the records,
then link them by ID so file order does not affect restore.

## 5. Reference validation

`PreparedPayload` checks that each category parent exists and does not reference
itself, and that the accounts and categories referenced by transactions and
plans exist. Validate new relationships there and throw `BackupError.corrupted`
before deleting records.

## 6. Older files

- A missing optional field decodes to `nil` and uses the restore default.
- A file with `formatVersion 1` passes `1...currentFormatVersion` when current is `2`.
- An older app returns `unsupportedVersion` for a newer format.
- An invalid checksum returns `corrupted` before restore changes data.
- Let the encoder compute checksums and keep validation enabled.

## 7. Checklist

- [ ] Model field with a default.
- [ ] Optional field in `*Backup`.
- [ ] Capture extension.
- [ ] Restore `insert` with a default.
- [ ] `PreparedPayload` check for references.
- [ ] Update `currentFormatVersion` and `currentSchemaVersion` as applicable.
- [ ] `BackupSummary` and UI count for a new entity.
- [ ] Assertion in `SelfTest.swift`.
- [ ] `-selftest` reports `ALL CHECKS PASSED`.
- [ ] Backup checks pass in `python3 Scripts/audit-feature-sync.py`.
- [ ] Manual round trip if the format changed.
