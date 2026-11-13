# Montra iOS / iPadOS port — progress log

Status: **Phase 0 complete — multiplatform build green, both simulators launch**
Started: 2026-11-13
Branch: `codex/ios-liquid-glass` (created from `codex/new-operation-sheet` @ `a77d61e`)
Owner: main agent + Builder A + Builder B + three critics

This file is the single source of truth for the port. It records the baseline,
the decisions, the work split, the verification plan, what is blocked on the
Apple Developer account, and the evidence produced. Update it after every phase.

---

## 0. Task

Port the macOS Montra app to iOS and iPadOS 26+ with Liquid Glass while keeping
the existing macOS app intact:

- the sidebar's navigation moves into a **bottom Liquid Glass menu** on iPhone
  and iPad;
- every popup/form opens as a **bottom sheet**;
- the rightmost navigation item is **Settings**; Settings contains an
  **About** row that opens **About** in a bottom sheet;
- the whole existing logic is preserved, including the iCloud seam;
- onboarding, all screens, all animations (Mori intro, hero flight, blur/fade
  transitions) stay;
- iPadOS features that fit the product are used;
- the result is verified by a functional critic, a code-review critic and an
  App Store / HIG critic, with simulator evidence and a screenshot comparison
  (macOS vs iOS vs iPadOS), then packaged and delivered as a PR or a local PR
  description.

Not a new repository. The port lives on one branch in `rGradov/montra`.

---

## 1. Baseline (before any change)

| Item | Value |
|---|---|
| App | Montra 1.0 (1), macOS 15.0+, SwiftUI + SwiftData |
| Sources | 70 Swift files, ~25 600 lines |
| Xcode | 27.0 (27A266a), macOS 27 SDK, iOS 27 SDK |
| Simulators | iOS 26.1 and iOS 27.0; iPhone 17 Pro, iPad Pro 13-inch (M5), iPad (A16) |
| Target platform | macOS only (`SDKROOT = macosx`, `MACOSX_DEPLOYMENT_TARGET = 15.0`) |
| Localization | `Localizable.xcstrings`: 689 keys, source language `ru`, `en` required |
| Tests | no test target; launch-time `-selftest` (182 checks, 1337-line Swift file) |
| Snapshots | `-snapshot <dir>` renders every macOS screen; `-preview-onboarding` |
| iCloud | `Montra/Montra.entitlements` (git-ignored) has iCloud container `iCloud.app.finance.montra` + APNs; `SyncService` is a documented seam; `cloudKitDatabase: .none` |
| Local API | 127.0.0.1:8766 + MCP proxy, macOS feature |
| Backups | `.montra` JSON, format v2, schema v1 |
| Uncommitted work on base branch | `Montra.xcodeproj/project.pbxproj`: signing config (team `97S3QGCCV4`, bundle id `app.finance.montra`, entitlements); untracked `Docs/prototypes/*` (another task — not committed here) |
| GitHub | `origin https://github.com/rGradov/montra.git`; `gh` not installed |

macOS baseline: build OK with `CODE_SIGNING_ALLOWED=NO` (the local signing config has no CLI profile); `-selftest` → `ALL CHECKS PASSED` (182); audit → 7 passed; snapshots → `build/snaps-baseline/`. Plain `xcodebuild` needs either `-allowProvisioningUpdates` or signing disabled. See §11.

---

## 2. Decisions

1. **No new repository.** One codebase, one branch
   `codex/ios-liquid-glass`, one universal App Store app with bundle id
   `app.finance.montra` (team `97S3QGCCV4`). A second app id would split the
   data model, backups and the iCloud container, and would double review work
   for no gain.
2. **One multiplatform target.** The existing `Montra` target gains the iOS and
   iPadOS destinations (`SUPPORTED_PLATFORMS`, `TARGETED_DEVICE_FAMILY = 1,2`,
   `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `MACOSX_DEPLOYMENT_TARGET = 15.0`
   unchanged). Shared code stays shared; `#if os(...)` is used only where the
   platforms genuinely differ. This is less risky than a second target with
   duplicated file membership, and keeps the synchronized source folder.
3. **Minimum iOS/iPadOS 26.0.** Liquid Glass (`glassEffect`,
   `TabBarMinimizeBehavior`, `presentationSizing`) and the iPadOS 26 behaviors
   need iOS 26. Supporting iOS 18 would mean two visual systems and would
   contradict the brief. macOS minimum stays 15.0.
4. **Tab map (the sidebar, flattened):**
   | Tab | Contains |
   |---|---|
   | Overview | accounts, savings, balance, periods, recent operations, account detail (push) |
   | Transactions | all operations, planned operations, plan actions, delete |
   | Categories | categories + subcategories |
   | Analytics | analytics |
   | Settings (rightmost) | general, integration, periods, rates, backup, data, **About row** |
   Accounts and savings stay reachable from Overview (and from a "Accounts" section
   inside it), because 10+ accounts cannot be tabs. About and iCloud are not
   tabs: About opens a bottom sheet from Settings; iCloud keeps its sheet.
5. **iPhone navigation**: native `TabView` (real Liquid Glass tab bar, tab
   minimize behavior, system accessibility) with one `NavigationStack` per tab.
   Screens keep their own `PageHeader`; the system navigation bar is hidden, so
   the visual language does not change. **iPad navigation**: research (see
   `Docs/Research-iPadOS-Features.md`) confirmed there is **no supported way** to
   put a `TabView` bar at the bottom on iPadOS — the system puts it at the top
   (optionally becoming a sidebar). The brief explicitly asks for the bottom
   menu on iPad, so iPad gets a custom bottom bar built with
   `GlassEffectContainer` + `glassEffect(.regular.interactive())` (real Liquid
   Glass material, same item order and accessibility as the iPhone bar). The
   HIG trade-off (no top bar/sidebar morph) is documented and will be shown to
   the reviewer; a native top-bar/sidebar variant can replace it behind a flag
   if the product prefers HIG over the brief. iPhone keeps the native bar.
6. **All modals become bottom sheets on iOS/iPadOS**: one central
   `BottomSheetHost` in the shell applies `presentationDetents`,
   `presentationDragIndicator(.visible)`, corner radius, `.presentationSizing(.form)`
   on iPad and keyboard-safe scrolling to every `AppSheet`; each sheet's fixed
   desktop frame becomes flexible on iOS. iOS 26 gives partial sheets the new
   inset Liquid Glass material, so no custom `presentationBackground` is added
   (it would suppress the system material). Popovers inside controls keep their
   native iPad behavior (popover on regular width, sheet on compact).
7. **Settings is the rightmost tab; About is a row inside Settings** and opens
   `AboutSheet` (identity, version, totals, capabilities, replay onboarding).
   The macOS About page stays exactly as it is.
8. **Onboarding is fully preserved**: welcome, account step, optional first
   expense, celebration, Mori intro with sound, glow, sparkles, blur/fade and
   the account hero flight. Geometry becomes adaptive (iPhone padding 24,
   iPad/mac 48; form width clamps to the container). The hero flight lands on
   the first account card inside Overview on iOS/iPadOS; if a frame is missing
   (e.g. Reduce Motion), it falls back to today's fade. No tab bar during
   onboarding.
9. **iCloud is preserved, not extended.** The entitlements, `SyncService`
   states, `ICloudSheet`, container identifier and `cloudKitDatabase: .none`
   stay as they are on both platforms. Enabling sync remains the documented
   one-line change. The port installs the iOS side of the same container; the
   developer-account work is listed in §10. Settings remain in `UserDefaults`
   exactly as now (the documented future `NSUbiquitousKeyValueStore` migration
   is out of scope).
10. **macOS behavior and visuals must not change.** Every macOS snapshot is
    compared before/after; `-selftest` must stay `ALL CHECKS PASSED`; the
    synchronization audit and DMG gate stay green.
11. **Local API / MCP / Touch Bar stay macOS-only.** An iPhone/iPad app cannot
    expose a useful localhost server to other apps and background listening is
    restricted. The code is preserved and the iOS Settings omits the
    integration group (documented). No Local API/MCP changes are expected, so
    `LedgerAPI.swift`, `mcp/server.py`, `Docs/Local-API.md` and smoke tests
    remain untouched unless the audit says otherwise.
12. **Files and sharing**: backups keep the `.montra` format and version;
    macOS keeps `NSSavePanel`/`NSOpenPanel`; iOS uses SwiftUI
    `fileExporter`/`fileImporter` and the share sheet for CSV. No new persisted
    fields, so no backup schema/API change.
13. **Platform truth**: only iOS/macOS APIs available in this SDK are used
    (verified against `SwiftUI.swiftinterface`); iOS 27-only APIs are behind
    `#available` and never required for the 26.0 target.

---

## 3. Target architecture

```
MontraApp (App)
 ├─ macOS: WindowGroup + .windowStyle(.hiddenTitleBar) + .commands + WindowConfigurator
 │         AppRootView = SidebarView | detail (unchanged shell)
 └─ iOS/iPadOS: WindowGroup + (no commands) + Scene phase handling
           RootView
             ├─ OnboardingFlowView (full screen, tab bar hidden)
             ├─ AppShell (tabs)
             │    ├─ iPhone: TabView(selection:) { Tab(...) }  [Liquid Glass]
             │    └─ iPad:   ZStack { content; GlassTabBar }     [glassEffect]
             ├─ sheet(item: $app.sheet) → BottomSheetHost
             ├─ onboarding replay overlay (full-screen cover)
             └─ account hero flight overlay
```

New shared layer:

```
Montra/Platform/
  PlatformSupport.swift      // cross-platform colors, appearance, pointer/help,
                             // platform flags, safe values
  MountraDocument.swift      // FileDocument for .montra (iOS exporter/importer)
  QAFixtures.swift           // deterministic demo data + launch-argument router
```

The macOS-only files (`MontraTouchBar.swift`, `SnapshotRunner.swift`,
`SelfTest.swift`, `OnboardingIntroSnapshot.swift`, `MontraApp` window commands)
are compiled under `#if os(macOS)`; nothing is deleted.

---

## 4. Work plan

Status key: `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked.

### Phase 0 — baseline and safety net (main agent)

- [ ] Write this file; record the baseline state.
- [ ] Create `codex/ios-liquid-glass`; first commit contains the previous
      signing configuration (needed for iOS) + this plan.
- [ ] Baseline: macOS Debug build, `-selftest`, `-snapshot build/snaps-baseline`,
      audit; save outputs.
- [ ] Add a `MontraUITests` UI-test target + scheme test action (verification
      harness) with 5–6 smoke flows.
- [ ] Multiplatform project configuration (destinations, Info.plist keys, iOS
      app icon entries, iOS entitlements, orientations, launch screen).
- [ ] Platform shims and mechanical compile enablement:
      colors/appearance/pointer/help, gate AppKit-only files, split `MontraApp`
      scene, extract demo fixtures, gate `BackupFile`/`CSVExporter` panels,
      cross-platform font registration.
- [ ] Make the target build and launch on iPhone and iPad simulators with a
      temporary native tab shell.
- [ ] Verify macOS build + snapshots are unchanged after the scaffolding.

### Phase 1 — Builder A: Liquid Glass shell, navigation, Settings/About, sheets

- [ ] `AppRootView` split into a macOS shell (unchanged) and an iOS shell.
- [ ] `AppModel`: `AppTab`, per-tab `NavigationStack` paths, tab selection,
      deep links (`montraGo*` notifications), `Route` compatibility.
- [ ] iPhone native `TabView` with 5 tabs, Liquid Glass, minimize behavior,
      accessibility labels/selected traits, hide system nav bar.
- [ ] iPad `GlassTabBar` (custom, bottom, glassEffect) with the same items,
      safe-area handling, landscape/portrait, Stage Manager resize.
- [ ] `SettingsView` iOS adaptation: rightmost tab, About row, sections,
      flexible widths; About sheet; replay onboarding cover.
- [ ] Central `BottomSheetHost` for all `AppSheet`s: detents, drag indicator,
      corner radius, keyboard avoidance, sheet-over-sheet (backup restore).
- [ ] iPad shell features: multi-window (`WindowGroup`, openWindow), keyboard
      shortcuts (⌘1…⌘5, ⌘N, ⌘,), pointer hover, context menus on tabs.
- [ ] QA launch router (`-qa-*`) + screenshots helper; UI tests for shell.
- [ ] Localization keys for new shell strings (ru/en).
- [ ] Builds green on macOS + iPhone + iPad; no macOS snapshot change.

### Phase 2 — Builder B: onboarding, screens, files, system surfaces, iPad content

- [ ] Onboarding: adaptive geometry, iPhone/iPad layout, keyboard avoidance,
      Mori intro, sound, hero flight destination, Reduce Motion fallback,
      replay from About, no tab bar.
- [ ] Screens: Overview, Operations, Categories, Analytics, Accounts/account
      detail, Transfers — safe areas, scroll, touch targets, width-adaptive
      layouts, no clipped content, landscape, Dynamic Type where the design
      allows.
- [ ] iPad content features: context menus, hover/pointer, drag & drop where
      it earns its place, share sheet for CSV/backup, adaptive columns.
- [ ] Backup/restore: `fileImporter`/`fileExporter` + confirmation UX; macOS
      panels unchanged; `.montra` compatibility.
- [ ] CSV export via share sheet; location permission handling on iOS.
- [ ] Spotlight/App Intents availability on iOS; Local API gated to macOS.
- [ ] Localization for every new string (ru/en).
- [ ] Builds green on all three platforms; macOS snapshots unchanged.

### Phase 3 — Integration and self-review (main agent)

- [ ] Merge both workstreams, resolve shared-file conflicts, run all builds.
- [ ] macOS: self-test, snapshots (diff), audit.
- [ ] iOS/iPad: launch, screenshots of Onboarding, Overview, Operations,
      Categories, Analytics, Settings, About sheet, new-operation sheet.
- [ ] Native behavior comparison (tab bar glass, sheet detents, swipe back,
      keyboard, orientation, Stage Manager).

### Phase 4 — Critics

- [ ] **Functional critic** — launches the app in all three simulators, runs
      the test suite, exercises every tab/sheet/onboarding path, compares with
      macOS, reports pass/fail and evidence.
- [ ] **Code-review critic** — reviews the full diff: architecture, dead code,
      platform gating, maintainability, macOS regressions, Swift/SwiftData
      correctness.
- [ ] **App Store / HIG critic** — checks Apple HIG and App Store Review
      Guidelines for a finance app: custom tab bar, touch targets, Dynamic
      Type, VoiceOver, privacy manifest, location string, icon, launch screen,
      iPad multitasking/orientations, iCloud/CloudKit entitlements, no private
      APIs, data-collection answers, onboarding quality, minimum
      functionality, screenshots.

### Phase 5 — Release evidence

- [ ] Fix all critic findings.
- [ ] Re-run self-test, audit, snapshots, UI tests.
- [ ] Build the DMG (`Scripts/make-dmg.sh ios-liquid-glass --open`) and re-run
      the audit with `--require-dmg`.
- [ ] Screenshot set: macOS / iPhone / iPad for the same screens + the About
      sheet, under `Docs/screenshots/ios-port/`.
- [ ] README + Feature Inventory + Docs (platform support, iCloud admin steps,
      iOS file flows).
- [ ] PR: push the branch and open a PR if credentials allow; otherwise produce
      `Docs/PR-ios-liquid-glass.md` with the same content and screenshots.
- [ ] Final report in Russian (feature, tests, audit, DMG, PR, manual steps).

---

## 5. File ownership (for parallel builders)

Main agent owns: `Progress.md`, `Montra.xcodeproj/project.pbxproj` (the initial
multiplatform setup and the UI-test target), `Montra/Platform/*`,
`Montra/App/MontraApp.swift`, `Montra/Design/Theme.swift`,
`Montra/Design/Components.swift` platform shims, macOS-only file gating,
`Scripts/*` if needed, `Docs/*` (except the research report), `README.md`.

**Builder A** (shell): `Montra/App/AppRootView.swift`,
`Montra/App/AppModel.swift`, new `Montra/Features/Navigation/*`,
`Montra/Features/Sidebar/*` (macOS side only if needed),
`Montra/Features/Settings/SettingsView.swift`,
`Montra/Features/About/*`, `MontraUITests/*` shell cases, new
`Montra/Design/Glass*.swift`. Must not edit Builder B's files or
`Montra/Platform/*`.

**Builder B** (screens): `Montra/Features/Onboarding/*`,
`Montra/Features/Overview/*`, `Operations/*`, `Categories/*`, `Analytics/*`,
`Accounts/*`, `Transfers/*`, `Montra/Features/Settings/{BackupRestoreSheet,
ICloudSheet,PeriodsSheet}.swift`, `Montra/Backup/*`,
`Montra/Store/CSVExporter.swift`, `Montra/Store/LocationProvider.swift`,
`Montra/Integration/*`, `Montra/Design/{Forms,DateTimePicker,
GlyphAppearancePicker,CapsuleSearchField,DetailHeader}.swift`,
`MontraUITests/*` content cases. Must not edit Builder A's files or
`Montra/Platform/*`.

**Contracts between them**

- `SidebarAccountFramesKey` keeps its name and meaning; Overview cards on iOS
  publish their frames under it so the existing hero-flight code in
  `AppRootView` finds its target.
- Builder A wraps every `AppSheet` in `BottomSheetHost`; Builder B makes sheet
  content flexible (no fixed width/height on iOS) and keyboard-safe.
- Backup: the macOS panels stay in `BackupFile`; the iOS file
  exporter/importer is wired in `SettingsView` (A) around the existing
  `BackupService` capture/read (B).
- CSV: `CSVExporter.csv(for:)` stays the format source (B); Settings (A) asks
  for a temporary file URL and shares it.
- New localized strings are added by the builder that introduces them; both
  languages.

---

## 6. What must not change

- `.montra` backup JSON, schema version, restore semantics, old-file
  compatibility (no new persisted fields are planned).
- Local API payloads, actions, token handling, MCP tool parity, docs.
- SwiftData models, repositories, period arithmetic, currency conversion,
  onboarding logic and seed data.
- iCloud container identity and the "not configured" honest state.
- macOS window size/pinning, sidebar, About page, sheet frames, snapshot
  fixtures, keyboard shortcuts and Touch Bar.
- `MARKETING_VERSION` (stays 1.0; DMG tag distinguishes the build).

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Multiplatform conversion breaks the macOS build | One commit per change; macOS build + selftest + snapshot diff after each phase; `#if os(...)` instead of rewrites |
| AppKit leaks into shared files | Compile for iPhone simulator early and often; a grep gate for `import AppKit` outside `#if os(macOS)` |
| iPad tab bar is top-only | Verify in iPad simulator first; fall back to the custom bottom glass bar (same material, same items) |
| Fixed-width desktop sheets clip on iPhone | Central `BottomSheetHost` + flexible frames; screenshot each sheet at 3 sizes |
| Onboarding hero flight breaks (no sidebar on iOS) | Overview publishes the account card frame under the existing preference key; fade fallback when unavailable |
| Touch targets < 44 pt (desktop is 24–30 pt) | Platform-specific control heights in the design system; critic audit with XCUITest/measurement |
| iOS device signing / iCloud entitlement failures | Simulator first; document the developer-account steps; device/App Store build is a separate gate |
| Parallel builders touch the same files | Strict file ownership in §5; main agent resolves and reviews |
| GitHub PR impossible (no `gh`) | Push with git if credentials exist; otherwise a local PR markdown + screenshots and a clear note |
| Local API expected on iOS | Explicitly out of scope, hidden with a note; macOS unchanged |

---

## 8. Verification plan

1. **Builds**: macOS Debug, iPhone 17 Pro simulator (iOS 26.1), iPad Pro
   13-inch (iOS 27.0), plus an iPad Air 11-inch for size checks.
2. **Logic**: macOS `-selftest` → `ALL CHECKS PASSED`; backup round-trip
   unchanged; `python3 Scripts/audit-feature-sync.py` → zero failures.
3. **Visual**: `-snapshot build/snaps-after` for macOS diffed against
   `build/snaps-baseline`; iPhone/iPad screenshots via `simctl` for the same
   screens and the same demo fixtures.
4. **Interaction**: XCUITest smoke suite (tabs, Settings → About, account
   detail, new operation, onboarding finish, iPad keyboard shortcut) +
   functional critic working in the simulators.
5. **Native behavior**: split view/Stage Manager resize, orientation, swipe
   back, sheet detents/drag, keyboard avoidance, Dynamic Type, Reduce
   Motion/Transparency, VoiceOver order.
6. **App Store**: App Store / HIG critic report, all P0 findings fixed.
7. **Release**: DMG built and mounted; audit with `--require-dmg`; PR/evidence.

---

## 9. Evidence index

To be filled during Phase 5:

- `Docs/screenshots/ios-port/overview-{macos,ios,ipados}.png`
- `Docs/screenshots/ios-port/settings-{macos,ios,ipados}.png`
- `Docs/screenshots/ios-port/about-ios-ipados.png`
- `Docs/screenshots/ios-port/onboarding-ios-ipados.png`
- `Docs/Research-iPadOS-Features.md`
- `build/snaps-baseline/`, `build/snaps-after/`
- DMG path, PR URL

---

## 10. Needed from the Apple Developer account / App Store Connect

The port builds and runs in simulators without these; they are needed for a
device build and an App Store submission. Please confirm/do these when the port
reaches release:

1. **Universal app id.** `app.finance.montra` is used for macOS and iOS. If the
   iOS platform was not added to this App ID, enable it in Certificates,
   Identifiers & Profiles.
2. **iCloud / CloudKit + Push Notifications** enabled for the App ID, and the
   container `iCloud.app.finance.montra` present (the entitlements already
   reference it; `Docs/iCloud-Setup.md` still mentions an older identifier and
   will be corrected). Sync stays disabled in code, but the entitlement must be
   valid for distribution.
3. **App Store Connect app record**: one universal record (iPhone, iPad, Mac) or
   a new iOS record if the Mac app is already live and you prefer separate
   listings; tell me which.
4. **Signing**: team `97S3QGCCV4`; an Apple Distribution certificate and an
   App Store provisioning profile (or automatic signing) for the iOS
   destination.
5. **Privacy answers**: the app collects no analytics; location is used only to
   fill the payment place; backups and CSV leave the app only when the person
   taps save/share. A `PrivacyInfo.xcprivacy` will be added for required-reason
   APIs (`UserDefaults`, file timestamps) and the App Store critic will list the
   exact declarations.
6. **App Store screenshots** for iPhone 6.9" and iPad 13" (generated from the
   same fixtures during Phase 5).

Local API / MCP remains a macOS feature; nothing is needed for it on iOS.

---

## 11. Progress log

### 2026-11-13 — Phase 0

- Baseline captured: macOS build, `-selftest` 182/182, audit 7/7, 49 baseline
  snapshots, existing DMG `Montra-1.0-new-operation.dmg`.
- Branch `codex/ios-liquid-glass` created; signing configuration and this plan
  committed.
- Target converted to one multiplatform target: iOS/iPadOS 26.0, macOS 15.0,
  `TARGETED_DEVICE_FAMILY = 1,2`, all-four iPad orientations, launch screen,
  scene manifest, indirect input, iOS 1024 app icon, location string.
- Platform layer added (`Montra/Platform/PlatformSupport.swift`): dynamic
  colours, `PlatformImage`, asset lookup, `platformHelp`,
  `platformExitCommand`, pointer hover, appearance, platform flags.
- AppKit isolated: Touch Bar, window configurator, snapshot runner, `-selftest`,
  onboarding snapshot runner, AppKit panels, `NSCursor`, `NSEvent` monitors,
  pasteboard and `NSApplication` are macOS-only; the iOS build compiles.
- iOS/iPadOS launch verified in the iPhone 17 Pro (iOS 26.1) and iPad Air 13"
  (iOS 26.1) simulators; the Mori onboarding intro renders on both.
- Baseline introspection: snapshot differences after the foundation are only
  the time-stamped demo transfer rows (23:05 → 23:18), no layout change.
- iPadOS research completed: `Docs/Research-iPadOS-Features.md` (56 sources,
  SDK-verified). Key decisions: no system bottom bar on iPad → custom bottom
  glass bar per the brief; native `TabView` on iPhone; sheet detents and no
  custom sheet background; Local API stays macOS-only; `UIRequiresFullScreen`
  is deprecated and not used; privacy manifest added.
- Known state: the iOS shell is still the temporary bottom strip in
  `AppRootView` (Builder A replaces it); the macOS shell is untouched.
- Builder A (navigation, Settings/About, sheets, iPad shell features) and
  Builder B (onboarding, screens, file/system flows) are running in parallel
  worktrees `build/wt-nav` (`codex/ios-nav`) and `build/wt-screens`
  (`codex/ios-screens`), both branched from the foundation commit.
- Verified bundle metadata: iPhone + iPad orientations, scene manifest with
  `UIApplicationSupportsMultipleScenes = true`, generated launch screen, 1024
  icon, privacy manifest in the bundle, location usage string. Replaced the
  iOS icon with an opaque `icon_ios_1024.png` (the macOS icon keeps its alpha)
  so App Store validation cannot reject it for transparency.
- Known macOS snapshot caveat: the demo transfers use `.now`, so their clock
  text changes between runs; that is the only expected diff.
### 2026-11-14 — builder interim

- Builder B (screens) interim: the nine B-owned sheets now use one flexible
  frame (macOS keeps exact fixed sizes; iOS fills the sheet, pinned
  header/footer, scrolling + keyboard-safe); Overview publishes account-card
  frames under `SidebarAccountFramesKey` for the hero flight; macOS build and
  `-selftest` green, iPhone/iPad builds green, audit 6/0 with the expected
  no-DMG warning.
- Builder B found two issues in Builder A's `SettingsView`: the macOS
  Integration group is still visible on iOS, and the appearance thumbnails
  overlap their labels. Both were relayed to Builder A with screenshot
  evidence.
- Contract confirmed: Builder A's `BottomSheetHost` adds
  `.presentationSizing(.form)` on iPad and content-appropriate iPhone detents
  so B's flexible sheets do not leave a blank gap; no custom
  `presentationBackground`.
- Snapshot caveat: `build/snaps-baseline` was captured on 2026-11-13; the demo
  fixtures use `.now`, so after midnight the committed baseline no longer
  matches. Compare fresh before/after pairs from the same worktree and verify
  layout, not clock text.
- Builder B merged into `codex/ios-liquid-glass` (merge commit `23e2352`,
  source `6c59991`): onboarding adaptation, shared-header wrapping, content
  screen fixes, all nine sheets flexible on iOS, iOS Analytics popup dismissal,
  context menus, `common.duplicate` localization. macOS snapshot diff was
  limited to demo clock text and one sparkle phase before the merge.
- Builder A still running. `SettingsView` findings and the sheet-detent
  contract were relayed to it.
- Merged branch verified: macOS build, `-selftest` 182/ALL CHECKS PASSED, iPhone
  build, audit 6 passed / 0 failures (DMG-freshness warning only).
- Privacy manifest now declares UserDefaults (`CA92.1`) and file metadata
  (`C617.1`) — the two required-reason categories the app actually uses.
- Pending App Store prep after the shell merge: a tracked iOS entitlements file
  without the unused `aps-environment`; iCloud/CloudKit capability for the
  universal App ID; final DMG signing strategy.
- Builder A merged (merge `298f067`, source `6c79112`): native iPhone TabView,
  custom iPad Liquid Glass bottom bar, per-tab NavigationStacks, About sheet,
  Settings iOS pass, central BottomSheetHost, iPad multi-window and commands,
  QA fixtures mirroring the macOS snapshot data, 5 new localization keys.
- Integration verified on the merged branch: macOS build + `-selftest` 182,
  iPhone/iPad builds, audit 6/0. Builder A's two P0 concerns (fixed-width
  sheets and phone overflow) were artifacts of its pre-merge worktree; after
  the merge, Periods/New Account/About/Settings render correctly on iPhone and
  iPad, and Overview fits with no clipping.
- Evidence captured for integration: `build/check/iphone-{overview,settings,
  periods,newaccount,about,onboarding}.png`, `build/check/ipad-{overview,
  settings,periods,about}.png` (ignored).
- Next: functional / code / App Store critics.
