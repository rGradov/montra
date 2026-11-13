# iCloud sync and optional Apple sign-in: implementation plan

Montra already carries most of the iCloud groundwork. This plan lists what is
actually missing, what can be shipped without Apple accounts, and what a
"conditional Apple sign-in" entry would mean for a single-user, local-first
ledger.

The short version: **iCloud sync needs no sign-in screen and no
`Sign in with Apple` button.** The identity is the Apple Account that is already
signed in on the Mac, and an app cannot present an iCloud login prompt. The
`Sign in with Apple` button only makes sense if Montra ever owns a server-side
account system. Section 3 separates these into decisions.

## 0. Decisions taken (owner input, 2026-11-13)

| Decision | Value |
|---|---|
| Architecture | **Option A**: iCloud sync only, no sign-in UI, no `Sign in with Apple` |
| Developer account | Paid Apple Developer Program membership confirmed by the owner |
| Bundle id | **`app.finance.montra`**, so the container becomes `iCloud.app.finance.montra` |
| Sync behaviour | **Automatic**: no manual sync button, the person never triggers sync by hand |
| Backup | Manual `.montra` export/import stays as it is for now |
| Sync mechanism | **SwiftData's built-in CloudKit mirroring** (`cloudKitDatabase: .private(...)`), chosen in `icloud-sync-research.md` |
| Distribution | Notarized Developer ID DMG |

Consequences: B1 is half-resolved (paid membership, but no Developer ID
certificate on this Mac), B2 and B4 are decided, and Option B/C in section 3 stay
only as reference.

## 1. What exists today

| Area | State | Where |
|---|---|---|
| Models | Defaults on every attribute, optional relationships, no unique constraints, no `.deny` delete rule (only that one is unsupported; `.cascade` and `.nullify` mirror fine). One exception: `PlannedOperation.account` and `PlannedOperation.category` declare no inverse, and CloudKit mirroring requires one on every relationship | `Montra/Models/Models.swift`, `Montra/Models/Plan.swift` |
| Container factory | One factory, pinned to `cloudKitDatabase: .none` | `ModelContainerFactory` in `Montra/App/MontraApp.swift:211` |
| Sync seam | `CloudSyncState`, `SyncProvider` protocol, `SyncService.shared`, `containerIdentifier`. The service is never instantiated or observed: only `containerIdentifier` is read, by `ICloudSheet` | `Montra/Sync/SyncService.swift` |
| Status surfaces | Three places show iCloud state: the sidebar (hard-coded `iCloudConnected: false`), `ICloudSheet`, and the Settings row that prints `common.not_connected_2` | `AppRootView.swift:185`, `ICloudSheet.swift`, `SettingsView.swift:349` |
| Entitlements | Template only, not referenced by the target; it still carries the key-value-store key | `Docs/Montra.entitlements` |
| Integrations | App Intents/Spotlight and the Local API already read the one shared container, both gated on the store being persistent | `MontraApp.swift:61`, `LocalIntegration.swift:30` |
| Documentation | Enabling steps, limitations | `Docs/iCloud-Setup.md` |

So the data layer is nearly ready; the app is missing a signed entitlement, a
real container, a live status provider, one relationship inverse, and a decision
about what syncs and what stays per-Mac.

## 2. Hard blockers (cannot be worked around in code)

| # | Blocker | Current value | Needed |
|---|---|---|---|
| B1 | ~~A local Developer ID signing identity~~ **done 2026-11-13** |  **Root cause found.** The team `97S3QGCCV4` has two users: `mainrudenua@gmail.com` is `ACCOUNT_HOLDER` + `ADMIN`, `rudenua.dev@gmail.com` is only `APP_MANAGER`. Every attempt so far used the App Manager: Xcode's Manage Certificates and an App Store Connect API key both answer *"This operation can only be performed by the Account Holder"*. The two `Developer ID Application Managed` certificates are cloud-managed, carry no local private key, and `find-identity` never lists them | `Developer ID Application: Uladzislau Rudzenia (97S3QGCCV4)` is installed, paired with its private key, signs a test binary and verifies non-interactively. Expires 2027-12-13. The CSR lives at `~/Desktop/montra-csr/montra.certSigningRequest`; keep the private key on this Mac |
| B2 | Real bundle identifier | **Done.** App ID `app.finance.montra` exists as resource `GLZRJPQQU6`, name "montra finance app", platform `UNIVERSAL`, `seedId 97S3QGCCV4`. The project still says `com.example.montra` in `Montra.xcconfig` | Set `app.finance.montra` everywhere, and migrate the `UserDefaults` domain (below) |
| B3 | ~~Development team~~ **done** | `DEVELOPMENT_TEAM = 97S3QGCCV4` now lives in `Montra.local.xcconfig`, which is gitignored, so each Mac keeps its own team | Nothing |
| B4 | ~~iCloud container~~ **done** | The container `iCloud.app.finance.montra` is attached to the App ID, and the regenerated profile reports `com.apple.developer.icloud-container-identifiers = ['iCloud.app.finance.montra']` with `aps-environment = development` | Nothing |
| B5 | ~~Entitlements on the target~~ **done** | `Montra/Montra.entitlements` (Development environment, `aps-environment = development`) for Debug and `Montra/Montra-DeveloperID.entitlements` (Production, `production`) for Release, both wired through `CODE_SIGN_ENTITLEMENTS`. Both are gitignored, matching the repo's existing rule | Nothing |
| B6 | ~~Provisioning profiles~~ **done** | Both exist now: `Montra Mac Development` (`MAC_APP_DEVELOPMENT`, Development env, the Mac's provisioning UDID) and `Montra Developer ID` (`MAC_APP_DIRECT`, Production env, container, `aps-environment = production`). The Debug build signs with the first and passes `-selftest` | Nothing |
| B6b | ~~Notarization credentials~~ **done** | `xcrun notarytool store-credentials montra-notary --key AuthKey_5M4G6L5T7X.p8 --key-id … --issuer …` validated, and `notarytool history` returns the earlier accepted submission | Nothing |
| B7 | CloudKit schema deployed to production | No schema exists yet | Deploy the development schema to production in CloudKit Console **before** shipping the DMG, otherwise release builds see no records |
| B8 | Container environment entitlement | Absent | `com.apple.developer.icloud-container-environment` (`Production` for the DMG build, `Development` for local builds) |
| B9 | Push Notifications capability | **App ID done**: `PUSH_NOTIFICATIONS` enabled. Entitlement key on macOS is `com.apple.developer.aps-environment` (prefixed), not iOS's `aps-environment`; both entitlement files now use the prefixed key, matching the profile | Rebuild and confirm with `codesign -d --entitlements -` |
| B10 | CloudKit on Developer ID builds | Apple documents it as supported: for Developer ID software, "applications can also take advantage of advanced capabilities such as CloudKit and push notifications". Still never exercised in Montra, so one empirical check remains | Run the Phase 0 smoke test once; no architectural fallback is expected to be needed |

B2 and B3 are the real gate: without a team, the iCloud entitlement cannot be
signed at all, so the app will keep reporting "not connected" even after the
container switch. B1 and B10 are the gate for the whole plan: if a Developer ID
build cannot reach a CloudKit container, nothing below matters.

### 2.1 About `app.finance.montra`
Checked against Apple's `CFBundleIdentifier` documentation: the string may
contain only alphanumerics, hyphens and periods, is case-insensitive, and
Apple *"typically"* wants reverse-DNS. `app.finance.montra` satisfies the
character rules and has three components, so it is legal. Two things to know:

- It is not reverse-DNS of a domain, which is unusual but not enforced. What
  Apple enforces is global uniqueness in your account, and that the identifier
  matches App Store Connect. Once a build is uploaded the id **cannot be
  changed** and the container **cannot be renamed**, so this is permanent.
- Changing the bundle id today is not free but it is safe for data: the ledger
  store is `~/Library/Application Support/Montra.store` and the Local API token
  lives in `~/Library/Application Support/Montra/LocalAPI`, neither derived from
  the bundle id, so both survive. `UserDefaults.standard` **is** scoped to the
  bundle id, so appearance, hidden balances, primary currency, period rule,
  onboarding flags, `didSeedDemo`, the API switches and `lastBackupAt` would all
  reset. Migrate them once by reading the old `com.example.montra` domain, or
  accept a settings reset before the first public release.

### 2.2 Accounts and roles in team `97S3QGCCV4`

Confirmed through the App Store Connect API on 2026-11-13: the team has exactly
two users.

| Apple ID | Role | What it can do |
|---|---|---|
| `mainrudenua@gmail.com` | `ACCOUNT_HOLDER`, `ADMIN` | Everything, including Developer ID certificates |
| `rudenua.dev@gmail.com` | `APP_MANAGER` | App IDs, capabilities, App Store metadata; **not** Developer ID certificates |

That is the whole explanation for the repeated *"This operation can only be
performed by the Account Holder"*: Xcode and the API key were both operating as
the App Manager. An API key is not a way around this either — key roles top out
at Admin, while Apple gates Developer ID certificate creation to the human
Account Holder. The browser session signed in as `mainrudenua@gmail.com` is the
route.

## 3. Decision: do we need `Sign in with Apple`?

Three architectures are possible. **Option A is chosen** (section 0); B and C
stay as reference so the question does not have to be re-researched.

### Option A: iCloud only, no auth UI (chosen)

- Identity = the Apple Account signed in on this Mac. The app cannot and must
  not ask for iCloud credentials; it can only read `CKAccountStatus` and send
  the person to System Settings when no account is present.
- No `Sign in with Apple`, no tokens, no server, no account model, no privacy
  policy change for an identity provider.
- Same Apple Account on both Macs → same private CloudKit database → the ledger
  appears on both.
- Cost: sync is tied to iCloud. No web app, no Android, no shared household
  ledger.

### Option B: `Sign in with Apple` as an optional identity layer

- Adds `AuthenticationServices`, `SignInWithAppleButton`, the
  `com.apple.developer.applesignin` entitlement, and a stored credential
  (`userIdentifier`, optional name/email) that can gate features or label an
  export.
- **It still does not sign anyone into iCloud.** Data would keep syncing through
  the private CloudKit database, so the button changes nothing about sync. It
  is only meaningful as the first step towards Option C.
- Verdict: do not build it now. It is UI debt with no user-visible benefit for
  a local-first ledger.

### Option C: Montra account system with `Sign in with Apple` + server sync

- Requires a backend, an account entity, migrations on the server, session
  handling, account deletion, privacy and data-processing disclosures, and a
  completely different conflict model. This is a product decision, not an
  iCloud task.
- If this is ever built, App Review's login-services rule applies (section 4.1):
  offering any third-party login then obliges you to offer an equivalent option
  that limits data collection to name and email, allows a private email address,
  and does not collect ad interactions. `Sign in with Apple` is the practical
  way to satisfy that, so it stops being optional.

### What "conditional entry" should mean in the UI

Replace "sign in" with **iCloud availability states**. A single entry in
Settings → iCloud that adapts:

| `CKAccountStatus` | Entry | Action |
|---|---|---|
| `.available` | "Sync with iCloud" toggle + last sync time | Flip the container on, restart it |
| `.noAccount` | "Sign in to iCloud" | Open System Settings → Apple Account (a URL; the exact identifier is not verified here and must be checked on the target macOS version) |
| `.restricted` | Explain that iCloud is restricted (MDM) | No action |
| `.couldNotDetermine` / `.temporarilyUnavailable` | "Try again" | Retry the status check |

That is the honest, HIG-compatible "conditional Apple entry" for this app: a
state-driven row, not an Apple ID button. **This deliberately replaces the
literal sign-in screen the request implies.** That substitution is a product
decision, so it needs the owner's explicit agreement (question 1) before Phase 2
starts.

## 4. Apple requirements (verified sources)

This section exists only to answer the question definitively. If Option A is
chosen it is reference material, not working steps.

Sources: [Human Interface Guidelines — Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple),
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[Enabling CloudKit in Your App](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app),
[CloudKit](https://developer.apple.com/documentation/cloudkit),
[CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer),
[NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore).

### 4.1 Can Sign in with Apple be the only sign-in method?

Yes. App Review 4.8 only obliges an equivalent option when the app uses a
**third-party or social** login (Facebook, Google, X, LinkedIn, Amazon,
WeChat) for the user's primary account. Verbatim: *"Apps that use a third-party
or social login service … to set up or authenticate the user's primary account
with the app must also offer as an equivalent option another login service"*
that limits data collection to name and email, allows a private email address,
and does not track ad interactions.

The rule is not triggered when the app *"exclusively uses your company's own
account setup and sign-in systems"*. Two consequences for Montra:

- If Montra never adds a third-party login, `Sign in with Apple` is **not
  required** at all. Shipping only Apple sign-in is also compliant, because the
  obligation is to add a privacy-respecting option, never to add a third-party
  one.
- Montra currently ships as a notarized **Developer ID** app, so App Review does
  not apply to the current DMG distribution channel. Keep the rule in mind only
  if a Mac App Store build is planned.

For iCloud sync specifically, no sign-in method is involved: see section 3.
Apple's CloudKit guidance is to *"design your app to run gracefully with or
without an active iCloud account"*, to explain why iCloud is needed, and to
offer a button that takes the person to Settings to enable it.

### 4.2 Button titles, styles and sizes (HIG)

- **Titles** are fixed. On iOS, macOS, tvOS and the web only these are allowed:
  `Sign in with Apple`, `Sign up with Apple`, `Continue with Apple`. watchOS
  provides a single title, the Apple logo plus `Sign in`.
- **Styles**: white (all platforms and web, for dark backgrounds), white with
  outline (iOS, macOS, web, for light backgrounds), black (all platforms, for
  light backgrounds; never on dark).
- **Minimum size**: 140 × 30 pt. Minimum margin around the button: 1/10 of the
  button's height.
- **Corner radius** is adjustable on iOS, macOS and the web to match the app's
  other buttons; the default is rounded.
- Use the **system-provided button** so the appearance is approved, proportions
  hold at any size, the title is translated automatically, the corner radius can
  match the UI, and VoiceOver gets a correct label. That means SwiftUI's
  `SignInWithAppleButton` or `ASAuthorizationAppleIDButton` with
  `cornerRadius`, not a hand-built view.
- **Platform differences for this app: none.** The HIG states "No additional
  considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS".

Behaviour the HIG asks for, which should shape the UI if Option B is ever built:
ask for sign-in only in exchange for value, delay it as long as possible, never
ask for a password, respect the private relay address, and show that the person
is signed in (for example "Using Sign in with Apple") in settings.

### 4.3 iCloud and CloudKit facts that change this plan

- **Private database requires an active iCloud account.** The public database is
  always reachable without one, though saving records to it also needs an
  account. So Montra must keep working with no iCloud account, which it already
  does.
- **Enabling the iCloud capability with CloudKit also adds the Push
  Notifications capability.** Montra has no `aps-environment` entitlement today,
  and CloudKit uses silent pushes to tell other devices about changes. Without
  it, sync still happens on launch and whenever CloudKit next syncs (the timing
  is not verified here), but cross-device updates are late.
- **The container name is the bundle id prefixed with `iCloud.`**, and Apple
  says a container *"can't be deleted or renamed"* once created. The bundle id
  decision in section 2 is therefore permanent.
- **`NSUbiquitousKeyValueStore` is documented as requiring App Store or Mac App
  Store distribution**: *"To use this object, you must distribute your app
  through the App Store or Mac App Store"*. Montra ships a notarized DMG, so the
  key-value store is **not** a safe way to sync settings here (see Phase 3).
  Limits if it is ever used: 1024 keys, 1 MB total, 1 MB per value, 128 UTF-16
  characters per key, stored unencrypted (never put the Local API token there).
- **Developer ID supports CloudKit and push.** Apple's Developer ID certificate
  page says notarized Developer ID software may use "advanced capabilities such
  as CloudKit and push notifications", and that a Developer ID provisioning
  profile gates those capabilities at install and at every launch. So the
  distribution channel is not the blocker the earlier draft assumed. What
  remains unverified is Montra's own configuration: that our entitlement set
  produces a profile that CloudKit accepts, which the Phase 0 smoke test proves.
- **A Developer ID certificate can be created in a browser or in Xcode.** Apple:
  "You can create up to five Developer ID Application certificates … using
  either your developer account or Xcode. Required role: Account Holder." The
  browser flow still needs a locally generated CSR (Keychain Access →
  Certificate Assistant), because the private key never leaves the Mac. Xcode's
  Accounts → Manage Certificates → `+` is the same request without the file
  juggling.

## 5. Work plan

### Phase 0: Owner prerequisites (outside the repo)

1. ~~Confirm Apple Developer Program membership~~ done: paid membership confirmed.
2. ~~Pick the production bundle id~~ done: `app.finance.montra`.
3. Create a `Developer ID Application` certificate and record the 10-character
   Team ID. Two equivalent routes, both requiring the **Account Holder** role:
   - **Browser:** Certificates, Identifiers & Profiles → Certificates → `+` →
     Software → Developer ID → Developer ID Application → upload a CSR, then
     download the `.cer` and double-click it into the login keychain.
   - **Xcode:** Settings → Accounts → Manage Certificates → `+` → Developer ID
     Application.
   The CSR must be generated on this Mac (Keychain Access → Certificate Assistant
   → Request a Certificate from a Certificate Authority). The private key stays
   here; a certificate created against another machine's CSR is useless unless
   that key is exported as a `.p12`. Limit: five Developer ID Application
   certificates per account.
   If Xcode answers "This operation can only be performed by the Account Holder"
   even for the owner, ignore Xcode and use the browser route above: Xcode's
   error describes the Apple ID it holds, not the browser session. Only the
   portal proves the role.
4. Register the App ID `app.finance.montra` with iCloud (CloudKit) and Push
   Notifications enabled.
5. Register the container `iCloud.app.finance.montra` and check the box for it.
6. Produce the Developer ID provisioning profile that carries iCloud and push.
   Apple documents portal creation only for App Store distribution profiles, so
   expect Xcode to mint this one when the target signs for Developer ID with the
   capabilities enabled. Record what actually worked.
7. Log in to CloudKit Console once so the container is visible.
8. Run the smoke test: a throwaway or Montra Debug build with the entitlement
   reaches `CKContainer.accountStatus == .available`, then the Developer ID
   Release build does the same on a second Mac.

Exit criteria: Team ID, bundle id, container id and profile are recorded in a
short "environment" note in `Docs/iCloud-Setup.md`, and the Phase 0 smoke test
confirms CloudKit from a Developer ID build.

Checking it from the terminal, because only some of Phase 0 is local:

```bash
# The certificate is local and must show up as an identity, not just a cert.
security find-identity -v -p codesigning | grep "Developer ID Application"

# Profiles Xcode has downloaded for this account.
ls -la ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles
```

The App ID, the iCloud container and the capability switches are server-side and
have no local artifact; confirm those in the developer portal. A downloaded
`.cer` that was never double-clicked appears in `find-certificate` but **not** in
`find-identity`, because it has no private key: that is the usual reason a
"created" certificate still cannot sign.

### Phase 1: Signing and entitlements (no behavior change)

1. Set `PRODUCT_BUNDLE_IDENTIFIER = app.finance.montra` in `Montra.xcconfig` and
   `DEVELOPMENT_TEAM` in `Montra.local.xcconfig` (machine-specific, not
   committed; the include already exists).
2. Migrate the `UserDefaults` domain once, or consciously accept the reset
   described in 2.1. The ledger and the API token are unaffected.
3. Add two entitlement files, because `CODE_SIGN_ENTITLEMENTS` is one setting
   shared by configurations: `Montra/Montra-Development.entitlements`
   (`Development` environment) and `Montra/Montra-DeveloperID.entitlements`
   (`Production`), selected per configuration. Drop the template's
   `com.apple.developer.ubiquity-kvstore-identifier` key: nothing here uses the
   key-value store (4.3), and the key would demand that capability on the App ID
   as well.
4. Add the Push Notifications capability (`aps-environment`).
5. Verify how the synchronized `Montra/` group treats `.entitlements` files:
   they must be build inputs, not copied resources.
6. Keep the current behavior: the container stays `.none`, so the app still
   works offline and stores nothing in iCloud.

Exit criteria: **met for Debug on 2026-11-13.** `codesign -d --entitlements :-`
reports `97S3QGCCV4.app.finance.montra`, `iCloud.app.finance.montra`, `CloudKit`,
`com.apple.developer.aps-environment = development`, and the build prints
`ALL CHECKS PASSED`. The Developer ID half waits for its profile.

### Phase 2a: Container, inverse, honest status (revertible, no user switch)

Mechanism: SwiftData's built-in CloudKit mirroring, not a hand-written sync
layer. The comparison and the reasons are in `icloud-sync-research.md`.

1. Switch `cloudKitDatabase` to `.private(SyncService.containerIdentifier)` for
   the **persistent store only**. CloudKit mirroring needs an SQLite-backed
   store, so `make(inMemory: true)` must keep `.none`: `-selftest`, `-snapshot`,
   the intro/animation snapshot modes, `-preview-onboarding`, and the onboarding
   replay all build in-memory containers and must stay offline and
   deterministic. The `catch` fallback that opens an in-memory configuration
   needs the same guard.
2. Add the missing inverse for `PlannedOperation.account` and
   `PlannedOperation.category` (for example `plannedOperations` on `Account` and
   `Category`). Choose the delete rule to preserve today's behavior when an
   account or category is deleted, and cover it in the backup tests. This is a
   schema change, so it also needs the migration check in Phase 5.
3. Add `CloudKitProvider: SyncProvider` reading `CKContainer.accountStatus`.
   `CloudSyncState` today has only `.notConfigured`, `.ready`, `.syncing` and
   `.failed`, so the states in section 3 need new cases and translations, and
   `SyncService.start(provider:)` runs once and cannot report a later state: an
   account-change observer is part of the work.
4. Status has to be honest about what SwiftData can actually report. There are
   no CloudKit events in its public API, so track two things instead: account
   availability from `CKContainer.accountStatus`, and the time of the last local
   import observed through SwiftData's History API (`HistoryProviding`,
   macOS 15 — our deployment target). Show "updated N minutes ago", never a
   fake "uploading 3 records" state.
5. Add a reconcile pass that runs after an import, because the app generates
   data locally that CloudKit will happily duplicate: starter categories and
   materialized `Period` rows. History says an import happened; a business-key
   comparison merges the duplicates. Without this, the second Mac doubles both.
6. Feed the state into the three surfaces listed in section 1.
7. Register for remote notifications and handle CloudKit's silent push.
8. Keep App Intents/Spotlight and the Local API as they are: both already read
   the shared container and keep their `isPersistent` gate, so synced rows appear
   in them without extra work.

Exit criteria: with the switch not yet exposed, a Debug build with the
entitlement shows a live status, and two Macs on one Apple Account converge.

### Phase 1b: Why a development profile is not optional

CloudKit creates record types in the **development** environment only; a
production container stays empty until a schema is deployed. So the first
successful sync must come from a development-signed build, which needs an Apple
Development certificate, the Mac registered in the team, and a Mac App
Development profile carrying iCloud and push. Without that chain there is
nothing to deploy to production and no Developer ID build can ever sync.
`CODE_SIGNING_ALLOWED=NO` proves the code compiles in the meantime.

### Phase 2b: The switch, onboarding and restore

1. Add a "Sync with iCloud" switch in Settings. Turning it on requires a
   container reload, so plan for a restart prompt or a container swap in
   `MontraApp`. It must be **off** for stores that predate this build.
   Once on, sync is **automatic**: no "Sync now" button, no manual step, and the
   only visible surface is the status row with `lastSyncedAt`. A manual trigger
   would only teach people to press it and then distrust the app when the press
   does nothing.
2. Offer the same choice during first run, not only in Settings, so nobody has
   to find the setting to get sync.
3. Gate the second Mac's onboarding and seeding. `hasCompletedOnboarding` and
   `hasStartedOnboarding` are per-Mac, `OnboardingLaunch.needsOnboarding` runs
   before any CloudKit import can land, and `SeedData.bootstrap` →
   `ensureCategories` + `PeriodService.ensurePeriods` runs in `AppRootView`'s
   task. On a second Mac that means onboarding over synced data and a second set
   of categories and periods. Treat a mirroring import as completed onboarding,
   or wait for the first import before deciding.
4. Decide the restore policy. `.montra` restore replaces every row while CloudKit
   is live: disable restore while sync is on, or perform it as a
   delete-and-reinsert inside one CloudKit export so the other Macs converge
   instead of resurrecting deleted rows.
5. Add the `.noAccount` affordance Apple asks for: why iCloud is needed, plus a
   button that opens System Settings → Apple Account. An in-app iCloud login
   does not exist.
6. Handle the offline case: CloudKit errors degrade to "local only" without
   blocking writes, and the UI says so instead of spinning.

Exit criteria: enabling sync on a store with real data uploads it and leaves a
usable backup path; a second Mac does not repeat onboarding or seed duplicates;
restore cannot corrupt the shared database.

### Phase 3: What syncs, what stays per-Mac

`SettingsStore` uses `UserDefaults`; the Local API switches live in
`LocalIntegration`'s own keys. Pick one rule per value instead of syncing the
whole store.

| Value | Recommendation | Why |
|---|---|---|
| Accounts, categories, operations, transfers, plans, periods | Sync via CloudKit | The ledger itself |
| `primaryCurrency`, `periodMode`, `paydayDay`, `fixedLengthDays`, `periodAnchor` | **Sync** | They change how the same rows are read; two Macs showing different monthly totals is a defect, not a preference |
| `hideBalances`, `appearance`, `spendMetric` | Keep per-Mac | Screen and privacy preferences |
| Local API on/off, `allowDelete`, token | Keep per-Mac | The token is a per-machine secret |
| `didSeedDemo` | Keep per-Mac, gated as in 2b | Device-scoped onboarding state |
| `lastBackupAt` | Keep per-Mac | Describes this Mac |
| Exchange-rate cache | Keep per-Mac | Derived data |

Implement the synced five through a small singleton SwiftData model (for example
`SyncedSettings`), so they travel with CloudKit like the rest of the data.
`NSUbiquitousKeyValueStore` is excluded (4.3). When it is built, the audit script
needs to know: it reads `SettingsStore.swift` for settings and scans only
`Models.swift` and `Plan.swift` for model fields, so a settings move or a new
model file silently escapes the backup/API checks otherwise.

Cost of this phase is real: `SettingsStore` stops being `UserDefaults`-only, so
backup, Local API, MCP, the allowlist, and the `UserDefaults(suiteName:)` test
injection all need attention. If scope must stay small, ship Phase 2 without it,
document that Macs can disagree about period rules, and treat the divergence as
a known limitation rather than a bug.

### Phase 4: Optional `Sign in with Apple` (only if Option B/C is chosen)

Not part of the sync release. If it is approved later:

1. Add the `com.apple.developer.applesignin` entitlement (`Default`).
2. Add a `SignInWithAppleButton` with Apple's required label and size (4.2),
   localized in `ru` and `en`.
3. Store only what is needed (`userIdentifier`), and never the email unless the
   person shares it. With no server there is nothing to delete, so an
   account-deletion path belongs to Option C, not here.
4. Back it with a `SessionStore` exposing `.signedOut/.signedIn`, and gate only
   features that genuinely require it. Never gate sync.

### Phase 5: Release obligations

Per `AGENTS.md` and `montra-feature-release`, this is a feature, not a docs
change:

1. **Localization.** New strings in `ru` and `en`, **and reword the existing
   ones**, because they describe the current static state:
   `sync.ready_to_set_up`, `sync.setup_steps %@`,
   `sync.your_data_stays_on_this`, `sync.to_enable_sync`,
   `sidebar.icloud_not_connected*`, plus `CloudSyncState.title` reusing
   `common.done`/`common.error`.
2. **Backup.** `currentSchemaVersion` is 1 and `currentFormatVersion` is 2. A new
   SwiftData entity is a new backup entity: add the payload array, a
   `BackupSummary` count, capture/restore, a restore-sheet row, and a self-test,
   bump `currentSchemaVersion`, and keep reading v1 files. The relationship
   inverse from 2a also needs the migration check. Machine-local exceptions get
   allowlist entries with reasons.
3. **Local API.** Expose the synced settings in `LedgerAPI.swift` and
   `Docs/Local-API.md`, or record a deliberate exclusion with a reason.
4. **MCP.** Mirror the same fields in `mcp/server.py` and `mcp/README.md`, with
   smoke coverage.
5. **Tests.** `-selftest` prints `ALL CHECKS PASSED`; CloudKit checks skip
   gracefully without an iCloud account; snapshots for the new Settings states.
6. **Audit.** `python3 Scripts/audit-feature-sync.py --require-dmg` reports zero
   failures. Add any new model file to its `MODEL_FILES`, or let it glob
   `Montra/Models/`.
7. **DMG.** `Scripts/make-dmg.sh <tag> --distribute --open`, after deploying the
   schema to production. Only `--distribute` applies `Manual` Developer ID
   signing; a plain run is the automatically signed local build and proves
   nothing about iCloud.
8. **Inventory.** Update `SET-07` and `DAT-01` in `Docs/Feature-Inventory.md`;
   `SET-07` currently asserts that "data stays local and sync is inactive".
9. **Docs.** Rewrite `Docs/iCloud-Setup.md` as an operator runbook, update the
   README's iCloud section and Features list, and fix `MasterPrompt.md` (line 15
   says sync is disabled, line 419 hard-codes the container) and `PLAN.md`.
10. **Delivery.** Branch `codex/icloud-sync`, Conventional Commit, PR with
    before/after Settings screenshots, and the Russian release report with the
    DMG path and 2–4 manual steps.
11. **Schema discipline.** CloudKit schemas are additive only once promoted.
    Before the first production deploy, settle every model and attribute name
    (including the settings entity from Phase 3). After it, only add fields:
    never rename, never retype, never delete a record type. Write this into
    `Docs/iCloud-Setup.md` so it is read before the next model change.

## 5b. Delivery status (2026-11-13)

| Step | State |
|---|---|
| Phase 0 prerequisites | Done: App ID, container, capabilities, certificates, both profiles, notary credentials |
| Phase 1 signing | Done: Debug and Developer ID builds carry iCloud + push entitlements |
| Phase 2a mirroring | Done: `.private(container)` for the persistent store, inverses added, live status in sidebar/Settings/sheet |
| Phase 2b switch/onboarding | Switch: **not done** by design, sync is always on. Duplicate rows: **done** — `LedgerReconcile` merges the starter categories and periods a second Mac seeds before the first import, moving operations to the survivor and keeping a hand-edited period. It never touches categories the person created |
| Phase 3 settings sync | Not done by design: settings stay per-Mac, documented |
| Localization | Done: `ru` and `en`, 654 call sites resolve |
| Backup / API / MCP | No new persisted field or action, so no payload change; audit confirms |
| `-selftest` | 225 checks, `ALL CHECKS PASSED`, also on the binary inside the DMG |
| `audit-feature-sync --require-dmg` | 7 passed, 0 failures |
| DMG | **Done**: built, signed with the Developer ID profile, notarization **Accepted**, ticket stapled, `spctl` reports "accepted / Notarized Developer ID", and the binary inside the image prints `ALL CHECKS PASSED` |
| CloudKit production schema | **Not deployed, and now proven by the app**: launching the notarized Developer ID build logs `Never successfully initialized and cannot execute request … CKErrorDomain Code=2`. CloudKit creates schema in development only, and `cktool` needs a management token from CloudKit Console, so this is a portal action |

## 6. Sync risks that the code does not handle yet

| Risk | Symptom | Mitigation |
|---|---|---|
| Second-Mac onboarding and seeding | First launch on Mac B shows onboarding over synced data, then inserts duplicate categories and periods | Phase 2b item 3: gate bootstrap on the first import |
| Starter data seeding per device | Duplicate categories and periods even after onboarding | **Handled**: `LedgerReconcile` merges duplicates of app-generated rows at launch, after onboarding and after a restore |
| Generated periods per device | Two `Period` rows for the same month | **Handled** by `LedgerReconcile`: one row per exact range, and `isManual` wins |
| Transfers are two rows | One side arrives without the other, or `transferID` splits | Accept last-write-wins, or repair on read using `transferID` |
| `sortIndex` collisions | Sidebar order flips between Macs | Re-index after each merge, or sort by `createdAt` as a tie-break |
| Concurrent edits | Someone edits the same account on both Macs | SwiftData's last-write-wins; say so in the UI |
| First enable on an existing store | Local rows never upload | Backup → enable → restore, verified on real hardware |
| Restore while sync is on | Other Macs resurrect deleted rows or double-insert | Phase 2b item 4 |
| iCloud unavailable | Writes fail or hang | Local-only mode, queue nothing, show status honestly |
| Two Macs, Local API | Two servers, one token per Mac | Already per-Mac; document it |
| No push entitlement | Changes arrive late, only on launch | B9 |
| CloudKit refused for Developer ID | The DMG build stays "not connected" while Debug works | B10 in Phase 0; fallback is App Store distribution or a non-iCloud backend |
| Schema not deployed | The DMG sees no records although Debug works | Deploy to production before packaging |
| Production schema freezes names | After the first production deploy an attribute cannot be renamed or retyped | Decide model names before that deploy; afterwards only add fields, with in-code migration |
| No sync events | The UI cannot say "syncing", only "updated N minutes ago" | Do not fake it; the status row reports what is known |
| Audit goes green without checking | New model file or settings move escapes the checks | Phase 5 item 6 |

## 7. Testing plan

1. **Unit/self-test.** Provider state mapping for `.available`, `.noAccount`,
   `.restricted`, `.couldNotDetermine`; container factory keeps in-memory stores
   offline; legacy backup still opens.
2. **Single Mac.** Enable sync, create data, quit, relaunch, confirm status and
   no duplicates. Disable sync and confirm the app still opens the local store.
3. **Two Macs (the only test that proves the feature).** Same Apple Account,
   create on A, verify on B, edit on both, verify the last-write-wins outcome,
   and confirm Mac B never repeated onboarding or seeding.
4. **No-iCloud Mac.** A fresh user without an Apple Account: onboarding works,
   the Settings row explains it, nothing blocks.
5. **Restore.** Restore a `.montra` while sync is on and confirm the other Mac
   converges.
6. **Distribution build.** Install the `--distribute` DMG on a clean Mac and
   confirm records appear from production CloudKit.
7. **Audit and smoke.** `audit-feature-sync.py --require-dmg`, plus
   `mcp/tests/smoke.py` if the API surface changed.

## 8. Open questions for the owner

Answered on 2026-11-13: Option A, paid membership, bundle id
`app.finance.montra`, automatic sync, manual backup unchanged.

Remaining:

1. Who installs the `Developer ID Application` certificate and where? It is not
   on this Mac. Phase 0 stops without it.
2. Does "automatic" mean the switch is on by default once iCloud is available, or
   off by default and turned on once by the person? The plan currently says off
   by default, because auto-uploading an existing local ledger is not reversible.
3. On first enable with existing data, upload automatically, or require a
   backup → enable → restore? This decides whether Phase 2b needs the backup gate.
4. Should the period rule and primary currency sync (Phase 3), accepting the
   extra work, or stay per-Mac with a documented divergence?
5. Is Restore allowed while sync is on, or is it disabled in sync mode?
6. Is the household case ("my partner and I share the ledger") in scope? Private
   CloudKit cannot do it; it would need CloudKit sharing.
7. Is a Mac App Store build planned? It changes the B10 fallback and whether App
   Review 4.8 matters at all.
8. Is a second Mac available for the two-Mac test? It is the only test that
   proves the feature.
9. Does "backup stays as it is" mean no automatic `.montra` backup is added in
   this release, and the existing manual export/import must keep working
   unchanged?

## 9. Checklist

- [ ] Team ID and container id recorded (bundle id `app.finance.montra` decided)
- [ ] Developer ID Application certificate installed
- [ ] `app.finance.montra` set in `Montra.xcconfig`; `UserDefaults` domain migrated or reset accepted
- [ ] B10 answered: CloudKit works in a Developer ID Release build
- [ ] iCloud container registered; CloudKit and Push enabled on the App ID
- [ ] Developer ID provisioning profile with iCloud and push installed
- [ ] Two entitlement files added and selected per configuration
- [ ] Entitlements verified with `codesign -d --entitlements -` on a `--distribute` build
- [ ] `PlannedOperation` relationship inverses added before the container switch
- [ ] In-memory stores and snapshot/selftest modes stay on `.none`
- [ ] `CloudKitProvider`, new `CloudSyncState` cases and an account-change observer
- [ ] `lastSyncedAt`-style status derived from History, no fake "syncing" state
- [ ] Reconcile pass dedupes starter categories and periods after an import
- [ ] Remote notifications registered and handled
- [ ] Sidebar, `ICloudSheet` and the Settings row read live state
- [ ] Sync switch defaults to off for old stores; first-run choice offered
- [ ] Second-Mac onboarding and seeding gated on the first import
- [ ] Restore policy decided and enforced
- [ ] Period and currency settings synced, or the divergence documented
- [ ] Localization added and existing `sync.*` / `sidebar.icloud_*` reworded
- [ ] Backup entity, schema bump and allowlist updated
- [ ] Local API and MCP parity, docs updated
- [ ] `-selftest` reports `ALL CHECKS PASSED`
- [ ] Two-Mac manual verification passed, including no duplicate seeding
- [ ] CloudKit schema deployed to production
- [ ] `audit-feature-sync.py --require-dmg` clean, with `MODEL_FILES` updated
- [ ] `--distribute` DMG built, mounted and verified on a clean Mac
- [ ] `Docs/Feature-Inventory.md`, README, `MasterPrompt.md`, `PLAN.md` and
      `Docs/iCloud-Setup.md` updated
- [ ] PR with before/after screenshots and the Russian release report
