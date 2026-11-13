# Sync mechanism research

Question: Montra must sync its ledger across the owner's Macs automatically,
with no manual step, using the owner's iCloud account. Which mechanism, and what
does each one cost in this codebase?

Scope: architecture choice only. Signing, entitlements and release steps live in
`icloud-plan.md`.

## 1. Constraints that decide the answer

From the app:

| Constraint | Reality in Montra |
|---|---|
| Data volume | One person's ledger: thousands of rows at most, five entity types |
| Write pattern | Append-mostly; edits and deletes are rare; no collaborative editing |
| Offline | Must work fully offline, with sync catching up later |
| No iCloud account | Must keep working, without blocking writes |
| Existing schema | `Account`, `Category`, `Operation`, `Period`, `PlannedOperation`; `Decimal` money, `UUID` ids, enums stored as raw strings |
| Write path | Already funnelled through repositories, one `ModelContainer` |
| Distribution | Notarized Developer ID DMG, not the App Store |

From Apple (verified, section 4 has the sources):

- SwiftData's automatic sync is `NSPersistentCloudKitContainer` from Core Data.
- It requires the iCloud capability **and** Background Modes with remote
  notifications; sync happens in system background tasks, usually within about
  a minute, with silent pushes.
- The CloudKit schema is **additive only** once promoted to production: record
  types and fields cannot be renamed or deleted.
- No unique constraints, all relationships optional, all relationships must
  declare an inverse, and the `.deny` delete rule is unsupported.

## 2. Options

| Option | What we write | Conflict control | Sync status visibility | Effort |
|---|---|---|---|---|
| **A. SwiftData + CloudKit** (`cloudKitDatabase: .private(id)`) | Container switch, entitlements, two relationship inverses, status UI | Apple's, per field, last write wins; no hooks | None official; inferred from History + `CKContainer.accountStatus` | Small |
| **B. `CKSyncEngine` + SwiftData** | A full sync layer: `CKRecord` mapping for 5 entities, change tokens, tombstones, batching, retry, conflict rules | Full | Full: sent/fetched events, accurate timestamps | Large |
| **C. Core Data rewrite** | Replace SwiftData with Core Data + `NSPersistentCloudKitContainer` | Same as A, plus `NSPersistentCloudKitContainer` event notifications | Good: event stream per import/export | Very large |
| **D. iCloud Drive file sync** | Copy the SQLite store into a ubiquity container | None: whole-file conflicts, last writer wins at file level, silent data loss | Filesystem only | Small but wrong |
| **E. Own server** | Accounts, API, auth, migrations | Full | Full | Very large, plus operations |

Option D is listed only to be rejected: syncing a live SQLite file through
iCloud Drive loses data whenever both Macs are awake, and the failure is
invisible.

## 3. Recommendation

**Option A: SwiftData's built-in CloudKit mirroring.**

Reasons:

1. The data is small and append-mostly, so per-field last-write-wins is a
   tolerable conflict policy. It is bad for shared documents, fine for a
   personal ledger where two people never type into the same row at once.
2. It is the only option with effectively no sync code. Options B and C move the
   hard parts — record mapping, tombstones, ordering, retry, batching — into our
   codebase, where they would need their own tests and would still be worse than
   Apple's implementation.
3. It gives the "automatic" behaviour the owner asked for: no button, no timer,
   no manual step, roughly a minute of latency.
4. The schema is already CloudKit-shaped: defaults everywhere, optional
   relationships, raw-string enums, no unique constraints. `Decimal`, `UUID`,
   `Date`, `String`, `Int`, `Bool` and `Double?` are all mirrored by Core Data.

What we knowingly give up:

- No custom conflict resolution. Two edits to the same row resolve by last
  write, without a hook to intervene.
- No honest "syncing" indicator. SwiftData exposes no CloudKit events, so the UI
  can report the account state and the time of the last import, not "uploading
  3 records now".
- Field names and types freeze at the first production deploy. Every future
  model change must be additive, with in-code migration.
- `.montra` restore while sync is on needs an explicit policy (plan Phase 2b).

`CKSyncEngine` stays the right answer only if Montra later needs CloudKit
sharing (a household ledger), a web client, or per-record conflict UI.

## 4. Verified Apple facts and what they cost us

### 4.1 How SwiftData syncs

> "SwiftData uses the [`NSPersistentCloudKitContainer`] class from Core Data to
> handle CloudKit synchronization."

> "SwiftData requires two separate capabilities to perform automatic iCloud
> sync: the iCloud capability … and the Background Modes capability, which lets
> your app receive remote notifications from CloudKit."

Cost: B9 in the plan is mandatory, not optional. Without Background Modes +
remote notifications, other Macs learn about changes late.

> "By default, SwiftData inspects your app's `Entitlements.plist` file to
> determine which CloudKit container to use, and selects the first identifier it
> finds in that file."

Cost: adding the entitlement alone switches sync on. Phase 1 must keep
`cloudKitDatabase: .none` explicitly so the app does not start syncing as a side
effect of signing.

### 4.2 Model rules

| Rule | Our status |
|---|---|
| No unique constraints | We have none |
| All relationships optional | We comply |
| All relationships have an inverse | **Broken**: `PlannedOperation.account` and `.category` have none |
| `.deny` delete rule unsupported | We use `.cascade` and `.nullify`, both fine |
| `Undefined` and `Object ID` attribute types unsupported | Not used |
| Entities in a configuration cannot relate across configurations | One configuration |

Mirrored attribute types include `Integer 16/32/64`, `Double`, `Float`,
`Boolean`, `Date`, `Decimal`, `UUID`, `URI`, `String`, `Binary Data` and
`Transformable`. Money as `Decimal` is therefore supported.

Cost: Phase 2a adds the two inverses. Nothing else in the schema blocks sync.

### 4.3 Schema is additive only

> "After you promote a schema to production, the record types and their fields
> are immutable and exist for all time. You can add new record types, and
> additional fields to existing record types, but you can't modify or delete
> existing record types."

Cost, and it is the biggest long-term constraint in the plan:

- Never rename an attribute or change its type after the first production
  deploy. Add a new field, migrate in code, keep the old one.
- A rename today, before production, is free. A rename after has no recovery
  except a new container and a new store, which means the user's data starts
  over.
- Apple suggests including a `version` attribute from the outset if multiple app
  versions must coexist. For a single-user app that updates as a whole, this is
  optional; the immutable-name rule is not.

### 4.4 Conflict and timing behaviour

> "Core Data uploads the change to CloudKit before sending it to the user's other
> devices… Generally, you can expect data to synchronize a local change within
> about a minute of the change."

There is no documented conflict API in the SwiftData sync article; the merge is
performed by Core Data's mirroring with the persistent container's merge policy,
which SwiftData does not expose. Plan for last-write-wins and design around it:
do not put two independently editable copies of the same fact in the schema.

### 4.5 `CKSyncEngine`, for the record

Available since macOS 14. It requires the CloudKit and Remote notifications
entitlements, it makes us persist its opaque state, it asks us for batches of
record zone changes (≤ 250 records per request), and it must not be used for the
public database. It is a better fit than hand-written `CKRecord` code, and a
worse fit than built-in mirroring for this app.

## 5. What this changes in `icloud-plan.md`

1. **Status honesty.** Replace "lastSyncedAt from sync events" with: account
   status from `CKContainer.accountStatus`, plus the time of the last local
   import observed through SwiftData's History API (macOS 15, which is our
   deployment target). No "syncing" verb in the UI; say "updated 3 minutes ago"
   instead of pretending to know about in-flight uploads.
2. **Reconcile pass.** On the first import after launch, dedupe the two things
   the app generates locally: starter categories and materialized `Period` rows.
   History tells us an import happened; a business-key comparison decides what
   to merge. Without this, the second Mac doubles them.
3. **Schema freeze discipline.** Add to the release checklist: after the first
   production schema deploy, no attribute may be renamed or retyped; new fields
   only, with in-code migration.
4. **Two inverses before the switch**, as already planned.
5. **No unique constraints**, so every dedupe rule is a fetch-and-merge in code,
   not a schema guarantee.

## 6. Open questions

1. Do we accept last-write-wins for edits made on two Macs? For a personal
   ledger the realistic worst case is losing one edited note or amount.
2. If the owner ever wants a shared household ledger, `CKSyncEngine` + CloudKit
   sharing becomes the path, and it is a different project.
3. Does the first production schema deploy happen before or after the settings
   entity from Phase 3? Whatever ships first freezes the names it contains, so
   it is worth adding the settings entity before that deploy rather than after.

## 7. Sources

- [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Mirroring a Core Data store with CloudKit](https://developer.apple.com/documentation/coredata/mirroring-a-core-data-store-with-cloudkit)
- [Creating a Core Data Model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)
- [Setting Up Core Data with CloudKit](https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit)
- [Syncing a Core Data Store with CloudKit](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit)
- [Reading CloudKit Records for Core Data](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data)
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9)
- [HistoryProviding](https://developer.apple.com/documentation/swiftdata/historyproviding)
- [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
