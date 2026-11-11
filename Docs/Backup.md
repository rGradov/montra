# Montra backups

A backup is a single `.montra` file such as `Montra-2026-11-09-2057.montra`.
It contains accounts, categories and subcategories, transactions and both sides
of transfers, planned payments, financial periods, app settings, exchange rates
at the time of backup, and Local API switches. Restoring a backup restores the
full ledger state.

## Using backups

Open **Settings → Backup**.

| Action | Result |
|---|---|
| Save a backup | Opens a save panel with a dated filename. The last backup date appears next to the action. |
| Restore from a backup | Opens a file picker. Montra validates the file and shows what it contains, when it was created, and which app version created it. |
| Save Current State First | Backs up the current ledger to a file ending in `-before-restore.montra`. |
| Restore | Replaces the current data with the contents of the file. |

Montra validates the format version, checksum, every amount, and every record
reference before deleting current records. It rejects damaged and unrelated files
and explains the error.

## File format

The backup is human-readable JSON. Amounts are strings, dates use ISO 8601,
and identifiers are UUIDs.

```json
{
  "appBuild": "1",
  "appVersion": "1.0",
  "checksum": "9f2c9e6a…",
  "createdAt": "2026-11-09T21:03:12.480Z",
  "format": "montra.backup",
  "formatVersion": 2,
  "schemaVersion": 1,
  "payload": {
    "accounts": [
      {
        "color": "blue",
        "createdAt": "2026-10-15T09:00:00.000Z",
        "currency": "byn",
        "iconName": "creditcard.fill",
        "id": "0E6A…",
        "initialAmount": "3150",
        "isHiddenFromOverview": false,
        "isSavings": false,
        "name": "Card",
        "sortIndex": 0
      }
    ],
    "categories": [],
    "operations": [],
    "plannedOperations": [],
    "periods": [],
    "settings": {},
    "rates": {},
    "integration": {}
  }
}
```

### Envelope

| Field | Meaning |
|---|---|
| `format` | Always `montra.backup`. Montra rejects files with another value. |
| `formatVersion` | File format version, currently `2`. Montra rejects files with an unsupported newer version. |
| `schemaVersion` | SwiftData model generation. Changes with the store schema. |
| `createdAt` | Backup date in ISO 8601 with milliseconds. |
| `appVersion`, `appBuild` | Version and build that created the backup, shown in the restore sheet. |
| `checksum` | SHA-256 of the canonical JSON for `payload`, in lowercase hexadecimal. |
| `payload` | The backed-up data. |

Montra hashes `payload` encoded with sorted keys and no indentation. When reading
a file, it re-encodes the decoded payload and compares hashes. Editing an amount,
date, or reference invalidates the file.

### Payload

| Key | Contents |
|---|---|
| `accounts` | Currency, opening balance, icon, color, savings flag, Overview visibility, and sort order. |
| `categories` | Categories and subcategories with kind, color, icon, mandatory and system flags, and `parentID`. |
| `operations` | Transactions with amount, currency, date, place, coordinates, note, `accountID`, `categoryID`, and `transferID`. |
| `plannedOperations` | Recurring series, frequency, weekday mask, series boundaries, and `linkedOperationID`. |
| `periods` | Financial period start and end dates and manual adjustments. |
| `settings` | Appearance, hidden amounts, primary currency, period rule, and onboarding flags. |
| `rates` | Rate source, dates, and BYN per unit for each currency. |
| `integration` | Local API and API deletion switches. |

Amounts such as `"214.30"` and `"0.0128"` use strings to preserve decimal
precision. Dates use ISO 8601 in UTC.

### Compatibility

- New fields are optional. Decoding ignores unknown fields.
- Montra rejects newer `formatVersion` or `schemaVersion` values and asks
  the user to update the app.
- Records can appear in any order. Restore resolves references by `id`
  and links parent categories in a second pass.

## Restore sequence

1. **Validate.** Decode the file, check versions and checksum, parse every
   amount, and validate `accountID`, `categoryID`, and `parentID` references
   in transactions, plans, and categories.
2. **Replace records.** Delete current transactions, plans, accounts, categories,
   and periods. Recreate records using the original IDs, creation dates, and
   relationships. Save once and roll back the context if saving fails.
3. **Apply settings.** Restore appearance, hidden amounts, primary currency,
   the period rule, and onboarding flags immediately. If the backup contains
   accounts, Montra treats onboarding as complete, as it does on launch for
   an older store with data. Montra preserves the onboarding-started flag.
   For older backups without the flag, it defaults to true because restore
   is available from inside the app.
4. **Fill in periods.** Create missing periods around the current date using the
   restored rule. Preserve manually adjusted periods.
5. **Restore rates and API switches.** Restore a complete rate table, refresh it
   in the background if stale, and apply the Local API switches.

## Excluded data

- The **Local API token** stays on its original Mac. Another Mac uses its own
  token. The API switches are included in the backup.
- Montra rebuilds **Spotlight snapshots and system indexes**.
- Backup files are **unencrypted**. Store them where you would keep a bank
  statement, since anyone who can open the file can read amounts and notes.

## Limitations

- Restore replaces the ledger in full. Merging is unavailable.
- Open backup files through Settings. Double-clicking a `.montra` file does
  not start a restore.
- The user selects backup files and paths in the app. The Local API exposes
  ledger data, and backup file management is handled in the app.
- Each backup is a full snapshot. Very large backups may take a few seconds
  to restore, with no progress indicator.
- CSV export is separate and contains recorded transactions for spreadsheets.

## Verification

```bash
.../Montra.app/Contents/MacOS/Montra -selftest
```

The 131 checks include archive creation, decimal precision, file round trips,
detection of tampered and unrelated files, and restoration of accounts, parent
categories, transfers, plans with weekday masks and links, manually adjusted
periods, settings, rates, and API switches. They also verify that invalid backups
are rejected before deleting current data.
