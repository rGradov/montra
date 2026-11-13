# Setting up iCloud for Montra

This is the operator runbook for the shipped iCloud setup. It records the real
identifiers, the account roles, and the rules that are easy to get wrong.

## What is enabled

| Item | Value |
|---|---|
| Bundle id | `app.finance.montra` |
| Team | `97S3QGCCV4` (Uladzislau Rudzenia, Individual, paid) |
| iCloud container | `iCloud.app.finance.montra` |
| Capabilities on the App ID | iCloud with CloudKit, Push Notifications |
| Sync mechanism | SwiftData's built-in CloudKit mirroring (`ModelConfiguration.cloudKitDatabase = .private(container)`) |
| Entitlements | `Montra/Montra.entitlements` (Debug, Development environment) and `Montra/Montra-DeveloperID.entitlements` (Release, Production), selected by `CODE_SIGN_ENTITLEMENTS` |
| Team setting | `DEVELOPMENT_TEAM` lives in `Montra.local.xcconfig`, which is gitignored |

`ModelContainerFactory` keeps `cloudKitDatabase: .none` for in-memory stores, so
`-selftest`, `-snapshot`, `-preview-onboarding` and the onboarding replay never
touch the network.

## Accounts and roles

The team has two users, and this matters because Apple gates Developer ID
certificates to the Account Holder only:

| Apple ID | Role |
|---|---|
| `mainrudenua@gmail.com` | Account Holder, Admin |
| `rudenua.dev@gmail.com` | App Manager |

The App Manager can edit App IDs, capabilities and metadata, but cannot create
Developer ID certificates — from Xcode or from an App Store Connect API key.
Apple's message is literally *"This operation can only be performed by the
Account Holder"*, and API keys do not get around it, because key roles top out
at Admin.

## Creating a Developer ID certificate

1. Generate a CSR on the Mac that will sign, in Keychain Access → Certificate
   Assistant → Request a Certificate from a Certificate Authority. The private
   key never leaves that Mac; a certificate built from another machine's CSR is
   useless without exporting a `.p12`.
2. Sign in to the developer portal as the **Account Holder**.
3. Certificates, Identifiers & Profiles → Certificates → `+` → Software →
   Developer ID → **Developer ID Application** → upload the CSR → Download.
4. Double-click the downloaded `.cer`; it lands in the login keychain and pairs
   with the key.
5. Verify:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

Certificates named **`… Managed`** in the portal are cloud-managed: Apple keeps
the key and signs through Xcode's Organizer workflow. They never appear in
`find-identity` and cannot be used by `Scripts/make-dmg.sh`.

## Local development build

A Debug build needs a Mac App Development profile, because CloudKit creates its
schema in the **development** environment and a production container stays empty
until a schema is deployed. Two identifiers matter, and they are different on
Apple Silicon:

| Purpose | Identifier |
|---|---|
| Hardware UUID | `system_profiler SPHardwareDataType` → `Hardware UUID` |
| Provisioning UDID (the one profiles actually contain) | `00008103-…` form, shown in the Xcode error or in Devices |

Register the provisioning UDID, not the hardware UUID. Then:

```bash
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Development: …" \
  PROVISIONING_PROFILE="<profile uuid>" build
```

Confirm the signature carries iCloud and push:

```bash
codesign -d --entitlements :- build/DerivedData-debug/Build/Products/Debug/Montra.app
```

Expected keys: `com.apple.developer.icloud-container-identifiers`,
`com.apple.developer.icloud-services`, `com.apple.developer.icloud-container-environment`,
`com.apple.developer.aps-environment`. Note the push key is
`com.apple.developer.aps-environment` on macOS, not iOS's `aps-environment`.

## Shipping: schema and Developer ID

1. Run a Debug build until CloudKit reports
   `Successfully set up CloudKit integration for store`. This creates the
   development schema.
2. Deploy that schema to production in CloudKit Console **before** packaging.
   A Developer ID build talks to production and sees nothing until then.
3. Create the Developer ID provisioning profile that carries iCloud and push,
   and sign the DMG with it (`Scripts/make-dmg.sh <tag> --distribute`).
   Notarization additionally needs
   `xcrun notarytool store-credentials montra-notary --apple-id … --team-id 97S3QGCCV4 --password <app-specific password>`.

## Schema rule that cannot be undone

After the first production deploy, CloudKit schemas are additive only: record
types and fields cannot be renamed or deleted. Before that deploy, settle every
model and attribute name. Afterwards, only add fields, with in-code migration.
Apple's own suggestion for multi-version coexistence is a `version` attribute on
each entity.

## What the app reports, and why

SwiftData mirrors through `NSPersistentCloudKitContainer`, which transfers on the
system's schedule (Apple: "generally … within about a minute") and exposes no
public "sync now" or progress API. So Montra reports:

- the iCloud account state from `CKContainer.accountStatus`, and
- the last time the ledger changed, taken from a cheap store signature.

It deliberately does not show a "syncing…" state, because nothing in the public
API can back that claim. `SyncService.flush()` saves a pending context at quit;
it cannot push an upload.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `No profiles for '<bundle id>' were found` | Automatic signing has no profile; pass `-allowProvisioningUpdates` or use a manual profile |
| `Device "…" isn't registered` | The hardware UUID was registered instead of the `00008103-…` provisioning UDID |
| `This operation can only be performed by the Account Holder` | The session or API key belongs to the App Manager |
| CloudKit set up but no records on another Mac | Schema not deployed to production, or the other Mac uses a different Apple Account |
| Sidebar says "Sign in to iCloud" | No Apple Account signed in on this Mac; CloudKit cannot prompt for one |
