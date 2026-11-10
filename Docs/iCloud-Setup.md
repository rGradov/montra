# Setting up iCloud

Montra has the prerequisites for iCloud sync. Follow these steps to enable it.

## Existing setup

1. **CloudKit-compatible models.** Every attribute has a default, relationships
   are optional with declared inverses, and the models use no `@Attribute(.unique)`.
2. **Single container factory.** `ModelContainerFactory` in
   `Montra/App/MontraApp.swift` creates the model container.
3. **Repository writes.** Sync hooks belong in `AccountRepository`,
   `OperationRepository`, `CategoryRepository`, and `PeriodService`.
4. **Status and UI.** `SyncService` exposes `CloudSyncState`. The sidebar shows
   that iCloud is disconnected and Settings includes an explanatory sheet.
5. **Entitlements template.** See `Docs/Montra.entitlements`.
6. **Separate settings store.** `SettingsStore` uses `UserDefaults`. To sync
   settings, switch it to `NSUbiquitousKeyValueStore` and call `synchronize()`.

## Steps

1. In your Apple Developer account, go to **Certificates, Identifiers & Profiles**
   → **iCloud Containers** and create `iCloud.com.vladrudenua.montra`. If you use
   another domain, update `SyncService.containerIdentifier` and the entitlements.
2. Under **Signing & Capabilities** for the Montra target, add **iCloud**. Enable
   CloudKit and select `iCloud.com.vladrudenua.montra`. Xcode can create
   `Montra.entitlements`, or you can copy the template and set the target's
   `CODE_SIGN_ENTITLEMENTS` to the copied file. Signing the iCloud entitlement
   requires a development team.

   ```bash
   cp Docs/Montra.entitlements Montra/Montra.entitlements
   ```

3. In `ModelContainerFactory.make()` in `Montra/App/MontraApp.swift`, replace
   `cloudKitDatabase: .none` with the following. This is the only code change
   required to enable sync.

   ```swift
   cloudKitDatabase: .private(SyncService.containerIdentifier)
   ```

4. Run the app with the container enabled. SwiftData creates records in the
   development environment. Inspect them in **CloudKit Console → Database**,
   then deploy the schema to production before distributing the build.
5. To replace the default `.notConfigured` status with live status, pass a
   provider. A `CloudKitProvider: SyncProvider` can use an
   `NSPersistentCloudKitContainer`-style setup to track status and retries for
   the SwiftData container already configured for CloudKit.

   ```swift
   await SyncService.shared.start(provider: CloudKitProvider())
   ```

6. Create a transaction on one Mac and check for it on another device using
   the same Apple ID. If it does not appear, verify that both devices use the
   same container and that you deployed the schema. Filter Console.app by
   `CloudKit` and `Montra`.

## Limitations

- CloudKit does not support unique constraints, and the models use none.
- Transfers and conflict merging have no custom sync handling. Concurrent
  edits follow SwiftData's last-write-wins behavior.
- Each device seeds demo data independently. Clear the demo data on one device
  when enabling sync.
