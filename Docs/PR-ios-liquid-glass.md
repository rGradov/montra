# Montra for iPhone and iPad — Liquid Glass port

Base branch: `codex/new-operation-sheet` · Head branch: `codex/ios-liquid-glass`

## What changed

- **One universal app.** The existing `Montra` target now also builds for
  iPhone and iPad (iOS/iPadOS 26+), sharing the same SwiftData store, models,
  repositories, backups and tests as the Mac. macOS 15+ is unchanged.
- **Navigation.** The sidebar becomes five destinations: Overview,
  Transactions, Categories, Analytics and **Settings** (rightmost).
  - iPhone: native `TabView` with the system Liquid Glass tab bar.
  - iPad: a custom bottom bar built with `GlassEffectContainer` +
    `glassEffect(.regular.interactive())`. iPadOS has no system bottom tab bar
    (its `TabView` is at the top and can become a sidebar), and the brief asks
    for the bottom menu, so this is a deliberate product choice. The bar keeps
    44 pt targets, Dynamic Type, VoiceOver labels/selected traits and a pointer
    hover state.
- **Settings & About.** Local API is hidden on iOS (it stays macOS-only). The
  About row in Settings opens `AboutSheet` as a bottom sheet; replay-onboarding
  works from it. Backup/restore uses `fileExporter`/`fileImporter`; CSV uses the
  system share sheet.
- **Sheets.** Every form is a bottom sheet with detents, a drag indicator and
  iPad form sizing. Popovers stay anchored on iPhone instead of stacking
  sheets. No custom `presentationBackground` (iOS 26 supplies the material).
- **Onboarding and animations.** Mori intro, soundtrack, glow, sparkles,
  transitions and the account hero flight are preserved. Geometry adapts to
  phone/iPad/window width; the hero flight lands on the first Overview account
  card, with the fade fallback.
- **iPadOS.** Multi-window (⌥⌘N), menu-bar/hardware shortcuts (⌘1…⌘5, ⌘N, ⇧⌘N,
  ⌘,), pointer hover, context menus, Stage Manager/Split View resizing and all
  four orientations. Window width (not device idiom) selects the compact shell.
- **iCloud.** The seam is preserved: entitlements, `SyncService`, the iCloud
  sheet and `cloudKitDatabase: .none` stay as they were. Sync is still a
  documented configuration change, not enabled.
- **App Store prep.** Opaque 1024 icon, privacy manifest (UserDefaults/file
  metadata), export-compliance key, localised location purpose string, iOS
  entitlements with CloudKit only (no unused APNs/KVS), all iPad orientations,
  launch screen and multi-scene manifest.

## Screenshots — same fixture data on macOS, iPhone and iPad

| Overview | Analytics |
|---|---|
| ![Overview](Docs/screenshots/ios-port/compare-overview.png) | ![Analytics](Docs/screenshots/ios-port/compare-analytics.png) |

| Settings | About |
|---|---|
| ![Settings](Docs/screenshots/ios-port/compare-settings.png) | ![About](Docs/screenshots/ios-port/compare-about.png) |

| New operation | Onboarding |
|---|---|
| ![New operation](Docs/screenshots/ios-port/compare-new-operation.png) | ![Onboarding](Docs/screenshots/ios-port/compare-onboarding.png) |

## Verification

- macOS Debug build; `-selftest` → **ALL CHECKS PASSED** (182).
- iOS build for the iPhone and iPad simulators; iPhone light/dark, ru/en,
  onboarding, sheets, Settings/About, multi-window and accessibility probes.
- iOS data-layer check: `simctl launch ... -iostest` →
  **ALL IOS CHECKS PASSED** (money, periods, transfers, `.montra` encode/decode,
  CSV, settings, onboarding launch rules).
- Synchronization audit: `python3 Scripts/audit-feature-sync.py --require-dmg`
  → **7 passed, 0 failures**.
- Local QA DMG: `build/Montra-1.0-ios-liquid-glass.dmg` (12.2 MB, ad-hoc signed;
  not notarized and not for distribution).
- Evidence script: `Scripts/ios-port-evidence.sh` renders the comparison set
  above; raw captures are in `build/evidence-raw/`.
- Reviews: `Docs/iOS-Code-Review.md` (static code review) and
  `Docs/iOS-AppStore-Review.md` (App Store/HIG review). Their P0 findings were
  fixed; remaining items are listed below.

## Known follow-ups (not hidden)

- No XCUITest target yet. UI interaction (tab re-tap, swipe-back, sheet
  drag-dismiss, file pickers) was verified visually/state-level, not by taps.
- Dynamic Type at accessibility XXXL still truncates some toolbar labels and
  chips; the money figures use fixed-size rounded numerals.
- Privacy policy and Support URLs are not in the app yet — they must be provided
  and added to Settings/About.
- New Account keeps a lower blank band on a tall sheet; Periods scrolls under
  its pinned footer. Both are cosmetic.
- No screenshot at iPad Split View/Slide Over width; the shell now switches to
  the compact bar by width, but a manual Stage Manager check is recommended.
- Release/Archive signing was not exercised: the iOS entitlements are prepared,
  but the App ID capabilities and App Store profile must be set up in the
  developer account. The Mac entitlements file remains local (git-ignored) as
  before.
- The Appearance picker now draws iOS-shaped thumbnails; the Mac keeps its
  window sketch.

## Manual checks

1. On iPhone, open Settings → About and confirm the bottom sheet, then
   “Replay onboarding” (sheet dismisses and the flow starts).
2. On iPad, drag the window to a narrow Split View width and confirm the shell
   switches to the phone tab bar; open a new window with ⌥⌘N.
3. On both, open New Operation and a picker; the picker stays anchored, not a
   second sheet. Switch Light/Dark and confirm the selected tab is legible.
4. On the Mac, confirm the sidebar, About page, sheets and `-selftest` are
   unchanged, and open the DMG.

## Developer account / App Store Connect

- App ID `app.finance.montra`: enable iOS, iCloud/CloudKit and the container
  `iCloud.app.finance.montra`; do not create a second App ID. Leave Push and
  KVS off.
- One universal App Store record (iPhone, iPad, Mac), Finance, 4+, privacy
  answers “Data Not Collected”.
- Privacy policy and Support URLs; 6.9" iPhone and 13" iPad screenshots
  (the comparison images above are 1320×2868 and 2048×2732 source captures).
- Team `97S3QGCCV4`, distribution certificate and App Store profile. The local
  DMG is ad-hoc and only for QA.

## Review follow-up (November 14)

User review of the first iPhone sheets and iPad bar:

- **No Cancel in iOS sheets.** The header X and the drag indicator close the
  sheet; the primary action now spans the sheet width with horizontal padding.
  Destructive actions stack above it. The Mac keeps its desktop footers.
- **Periods hint removed on iOS.** Done is full width; macOS keeps the hint.
- **Analytics day is a bottom sheet on iOS.** Tapping a heat-map cell presents
  a medium/large sheet with the day's category groups and amount; macOS keeps
  the anchored popup.
- **iPad bar is one glass platter.** The five per-item glass capsules are now
  one `GlassEffectContainer` platter with an accent selection fill; the iPhone
  keeps the native system tab bar.
- **Static Liquid Glass audit:** `Docs/iOS-Liquid-Glass-Audit.md`. Its P0 is the
  iPad platter fix above. The proposed Overview quick-add FAB, onboarding
  glass and Operations chrome remain follow-ups; the audit also rejects
  glass-on-glass sheets, cards and close buttons.

| New Operation: before / after | Periods: before / after |
|---|---|
| ![Operation](Docs/screenshots/ios-port/feedback-operation-before-after.png) | ![Periods](Docs/screenshots/ios-port/feedback-periods-before-after.png) |

| iPad bar: before / after | Analytics day sheet |
|---|---|
| ![iPad bar](Docs/screenshots/ios-port/feedback-ipad-bar-before-after.png) | ![Analytics sheet](Docs/screenshots/ios-port/feedback-analytics-sheet.png) |

Verification for this follow-up: iOS build and iPhone/iPad captures; iOS
`-iostest` **ALL IOS CHECKS PASSED**; macOS build + `-selftest` **182**.
