# Montra iOS / iPadOS — App Store & HIG Review

- **Branch:** `codex/ios-liquid-glass` @ `c34e02b` — "fix(ios): anchor popovers, size sheets by container and isolate headers"
- **Reviewed artifacts:** `build/DerivedData-final-ios/Build/Products/Debug-iphonesimulator/Montra.app` (iOS), `build/DerivedData-final/Build/Products/Debug/Montra.app` (macOS), screenshots in `build/check2/`, `build/check/`, `build/wt-nav/build/evidence/`, `build/wt-screens/build/evidence/`
- **Method:** static analysis only — `plutil`, `sips`, `assetutil`, `codesign`, `grep`, file reads, Pillow pixel measurement. **No** `xcodebuild`, **no** simulator runs, **no** parallel jobs (post-incident policy, `Progress.md:507`). Nothing was edited except this file.
- **Reviewer stance:** independent. This is not an integration sign-off and not a rubber stamp. Where a claim could only be proven at runtime it is marked **verify on device**.
- **Both builds are `Debug`.** All bundle evidence below is from a Debug simulator product. A Release/Archive build has never been analysed on this branch (see §F).

---

## Verdict

# NOT READY

Three ship blockers, ten must-fixes, and a release-signing configuration that cannot currently produce a distribution build.

The port is architecturally careful and the HIG work is real — the iPhone shell is a genuine system `TabView`, sheet chrome is centralised, popovers no longer stack modals, the width-vs-idiom bug from the code review is fixed, and the privacy manifest is honest. But it ships one **visible accessibility failure in its primary navigation control**, a **pervasive sub-44 pt control geometry inherited from the desktop design system**, and **platform-wrong copy and developer instructions in the shipping UI**. None of these is a crash; all of them are what a reviewer or a customer sees in the first ten minutes.

| Severity | Count |
|---|---|
| P0 — blocks submission | 3 |
| P1 — must fix before submission | 10 |
| P2 — should fix | 13 |
| Checklist rows | 77 (20 ❌, 18 ⚠️, 39 ✅/—/❓) |

---

## Checklist

Status key: ✅ pass · ⚠️ pass with caveats · ❌ fail · ❓ unprovable statically (needs device/portal) · — not applicable.

### 1. Navigation

| # | Item | Status | Evidence |
|---|---|---|---|
| 1.1 | iPhone: native `TabView`, 5 tabs, Settings rightmost | ✅ | `IOSNavigationShell.swift:136-145`; `AppTab.swift:10-16` (order ends `.settings`); `build/check2/iphone-overview.png` |
| 1.2 | Tab bar used for navigation only, no actions in the bar | ✅ | `IOSNavigationShell.swift:267-310` — five destination buttons, nothing else |
| 1.3 | Persistent, labelled, no overflow / hidden / disabled items | ✅ | 5 items, all enabled, labels always present on iPhone (system bar) |
| 1.4 | ≥44 pt targets | ✅ (bar) | iPhone system bar; iPad `minHeight` 44 / `minWidth` 54 (`IOSNavigationShell.swift:232-245, 284`) |
| 1.5 | Selection state is legible | ❌ **P0-1** | Light appearance: measured **1.32:1** for the selected label (worst case 1.09:1) — detail below |
| 1.6 | Selection not conveyed by colour alone | ⚠️ | iPad bar: filled symbol + accent + glass pill (`AppTab.swift:50-60`) ✅. iPhone: system bar tints with the app accent only; the glass pill is the sole non-colour cue and it is also near-background in light mode |
| 1.7 | Safe areas respected | ✅ | iPad `safeAreaInset(edge: .bottom)` + `.scrollEdgeEffectStyle(.hard, for: .bottom)` (`IOSNavigationShell.swift:171-178`); `build/check2/ipad-overview.png` |
| 1.8 | VoiceOver labels / traits / order | ⚠️ | iPad: label + `.isButton` + `.isSelected` (`:297-300`) but announced as "button", never "tab, *n* of 5"; system bar on iPhone ✅ |
| 1.9 | Dynamic Type on the bar | ⚠️ | Captions drop at accessibility sizes by design (`:240`), target survives (`:244-247`). Between `xxLarge` and `accessibility1` captions still show with `minimumScaleFactor(0.7)` → ~9 pt (`:279-281`) |
| 1.10 | Shell follows **window width**, not device idiom | ✅ | `IOSNavigationShell.swift:90` — `AppPlatform.isPhone \|\| sizeClass == .compact`; validated by `ipad-second-window.png` existing and `Progress.md:524` |
| 1.11 | No system bottom tab bar exists on iPadOS (custom bar is a product decision, documented) | ⚠️ | `Docs/Research-iPadOS-Features.md:41-85`; `Progress.md:92-99`. Defensible per HIG (custom navigation is allowed; it must not hide items, act as an action bar, or overflow — it does none of those). The cost is the lost top-bar/sidebar idiom, lost bar minimisation, and lost system tab semantics |
| 1.12 | Residual device-idiom branches | ⚠️ | `OnboardingFlowView.swift:16,24,785` still branch on `isPhone`/`isPad` (gutters 24/48, artwork 184/148). At a 320 pt iPad Slide Over the 48 pt gutter eats 30 % of the width |

### 2. Sheets

| # | Item | Status | Evidence |
|---|---|---|---|
| 2.1 | Detents + drag indicator on every sheet | ⚠️ | `BottomSheetHost.swift:23-41` ✅, but `DeleteOperationsSheet` never goes through it: `OperationsView.swift:399`, `AccountDetailView.swift:144` present their own `.sheet(item:)`. Restore sheet re-implements chrome by hand (`SettingsView.swift:926-931`) |
| 2.2 | iPad form sizing | ✅ | `BottomSheetHost.swift:16-20` `.presentationSizing(.form)` at regular width |
| 2.3 | One sheet at a time | ⚠️ | `AppRootView.swift:558-566` — `PlanActionSheet` assigns `app.sheet = .newOperation(…)` while presented. Identity changes mid-presentation; iOS may drop or double-animate. **verify on device** |
| 2.4 | Popovers stay anchored, not nested sheets | ✅ | `PlatformSupport.swift:154-160` `montraPopoverContent()`; six call sites updated; `Progress.md:521-523` |
| 2.5 | No custom `presentationBackground` | ✅ | Absent tree-wide; documented in `BottomSheetHost.swift:5-8` |
| 2.6 | Sheet width from the sheet, not `UIScreen` | ✅ | `Forms.swift:67-88` `containerRelativeFrame(.horizontal)`; `UIScreen` no longer read |
| 2.7 | Sheet content fits its detent (no clip / blank band) | ❌ **P1-3** | `build/check2/iphone-newaccount.png` — ~143 pt empty band between the colour row and the footer; `build/check2/iphone-periods.png` — "Selected period" card clipped by the pinned footer, ~50 pt dead band under the footer. `.periods` is in the `[.medium, .large]` set (`BottomSheetHost.swift:39`) |
| 2.8 | Dismiss affordances | ✅ | Drag indicator, sheet swipe, explicit `SheetHeader` close button |

### 3. Accessibility

| # | Item | Status | Evidence |
|---|---|---|---|
| 3.1 | 44×44 pt touch targets | ❌ **P0-2** | 28 pt dropdowns/steppers, 32 pt text & date fields, 24 pt menu rows, 38×22 switch, 22×22 checkbox, 13 pt info button — full audit below |
| 3.2 | Dynamic Type: text scales | ⚠️ | `Theme.swift:265-270` `Font.custom("Onest", size:, relativeTo: .body)` — but **every** style scales by the `.body` ratio, so captions over-grow relative to their layout |
| 3.3 | Dynamic Type: figures scale | ❌ | `Theme.swift:160-163` `.numbers` = `.system(size:)` (fixed). At XXXL the amounts stay small while labels grow — `ipad-a11y-xxxl-contrast.png` |
| 3.4 | Dynamic Type: layout holds at XXXL | ❌ **P1-1** | Same screenshot: "Удали…" / "Новая…" truncated toolbar labels; filter chips clip descenders |
| 3.5 | VoiceOver: every control has a name | ❌ **P1-4** | `Components.swift:921-951` `TouchCheckboxStyle` ignores `configuration.label` — a labelled `Toggle` with this style announces only "on/off". `InfoButton` (`Components.swift:851-866`) is a 13 pt glyph |
| 3.6 | VoiceOver: hidden UI is not reachable | ❌ **P1-5** | `AppRootView.swift:52-56` hides the shell with `.opacity(0)` + `allowsHitTesting(false)` — no `.accessibilityHidden`. During onboarding VoiceOver can swipe into the invisible tab bar and screens |
| 3.7 | Colour-only meaning | ⚠️ | Badges pair text + tone (`Обязательная`, `Доход`) ✅; the balance bar (`build/check2/iphone-overview.png`) encodes category shares as unlabelled colour segments — length carries magnitude, colour carries nothing readable |
| 3.8 | Reduce Motion | ✅ | 28 sites; intro skipped (`AppRootView.swift:238-241`), hero flight falls back to fade (`Progress.md:113-115`) |
| 3.9 | Reduce Transparency | ✅ | Relies on the system material, which the platform adapts (`Docs/Research-iPadOS-Features.md:376-386`) — correct per WWDC guidance |
| 3.10 | Increase Contrast | ❌ | No `\.accessibilityContrast` / `colorSchemeContrast` branch anywhere; custom tokens are static hex pairs. Consequence is worst in light appearance (P0-1) |
| 3.11 | Hardware keyboard | ⚠️ | `IOSAppCommands.swift:40` disables every command when `!isPad` — ⌘1…⌘5, ⌘N, ⌘, do nothing on an iPhone with a keyboard |
| 3.12 | Landscape | ✅ | `iphone-landscape-overview.png`; bar is the system floating capsule, content scrolls under it |

### 4. Bundle & review metadata

| # | Item | Status | Evidence |
|---|---|---|---|
| 4.1 | iPhone orientations (portrait + both landscape, no upside-down) | ✅ | `Info.plist` `UISupportedInterfaceOrientations~iphone`; `project.pbxproj:216` |
| 4.2 | iPad all four orientations | ✅ | `…~ipad`; `project.pbxproj:216` |
| 4.3 | Scene manifest + multiple scenes | ✅ | `UIApplicationSupportsMultipleScenes = true`; `WindowGroup(id:for: AppTab.self)` `MontraApp.swift:175-177` |
| 4.4 | Launch screen | ⚠️ | `UILaunchScreen` is an empty dict (`project.pbxproj:212-213`). Valid and non-letterboxing, but a blank flash — no brand, no colour |
| 4.5 | Display name / version | ✅ | `Montra` / 1.0 (1) |
| 4.6 | Category | ⚠️ | `LSApplicationCategoryType = public.app-category.finance` is a **macOS** key; iOS reads the category from App Store Connect only |
| 4.7 | Privacy manifest present and complete | ✅ | `PrivacyInfo.xcprivacy` in the bundle root: `UserDefaults/CA92.1`, `FileTimestamp/C617.1`, `NSPrivacyTracking=false`, empty domains, empty collected-data. Scanned for the other categories the manifest would need — SystemBootTime (no `systemUptime`), DiskSpace (no volume-capacity call), ActiveKeyboard (no `UIKeyboard`/`activeInputModes`) — none are used |
| 4.8 | Location purpose string, correctly localised | ⚠️ **P1-6** | Both `NSLocationWhenInUseUsageDescription` and the legacy `NSLocationUsageDescription` are set; only the **legacy** key is localised (`en.lproj`/`ru.lproj` `InfoPlist.strings`) — the key iOS actually reads is English-only |
| 4.9 | 1024 icon, opaque, no alpha | ✅ | `icon_ios_1024.png` RGB, no alpha channel; `Assets.car` rendition `Opaque: true`, 1024×1024. Generated 120/152 PNGs carry an alpha channel with extrema (255,255) |
| 4.10 | No `UIRequiresFullScreen` | ✅ | Absent |
| 4.11 | iPad multitasking | ✅ declaration / ⚠️ evidence | No `UIRequiresFullScreen`, all orientations, compact-width shell. No screenshot at Split View/Slide Over width exists |
| 4.12 | Export compliance key | ❌ **P1-7** | `ITSAppUsesNonExemptEncryption` absent from `Info.plist` and the project |
| 4.13 | No private APIs | ✅ | Public SwiftUI/SwiftData/UIKit/Charts/AppIntents only; `Scene.requestGeometryUpdate` is public (DEBUG-gated QA path) |

### 5. Privacy & data

| # | Item | Status | Evidence |
|---|---|---|---|
| 5.1 | No tracking | ✅ | `NSPrivacyTracking=false`; no ATT prompt, no ad SDK, no SPM dependencies (`project.pbxproj` has 0 package references) |
| 5.2 | No off-device collection | ✅ | Local SwiftData store; only outbound traffic is two HTTPS GETs for rates (`ExchangeRates.swift:75,78` — `api.nbrb.by`, `cdn.jsdelivr.net`). No account, no analytics |
| 5.3 | CloudKit private, sync off | ✅ | `MontraApp.swift:293-298` `cloudKitDatabase: .none` |
| 5.4 | Local API / MCP / Touch Bar inert on iOS | ✅ | `PlatformSupport.swift:42`; `LocalIntegration.swift:32-46` (`available` false ⇒ `startIfEnabled` returns immediately); Settings group gated `SettingsView.swift:56-60` |
| 5.5 | Declared entitlements match what ships | ❌ **P0-3** | `Montra/Montra.entitlements` carries `aps-environment` for every SDK including iOS; no push code exists |
| 5.6 | Privacy policy / support reachable in-app | ❌ **P1-8** | No link in Settings or About — ASC requires the URLs; finance apps are expected to surface them |
| 5.7 | App Privacy answers match the binary | ✅ ready to declare | "Data Not Collected", no tracking |

### 6. iCloud

| # | Item | Status | Evidence |
|---|---|---|---|
| 6.1 | Container + `cloudKitDatabase: .none` | ✅ | `iCloud.app.finance.montra`; `MontraApp.swift:293-298` |
| 6.2 | Honest UI (no fake "synced") | ✅ | `ICloudSheet.swift:69-80` — "Not connected" badge, "your data stays on this device" |
| 6.3 | No developer instructions in shipping UI | ❌ **P1-2** | `ICloudSheet.swift:41-47` renders `sync.setup_steps` verbatim: "1. Create the container … 2. Add the entitlement from Docs/Montra.entitlements. 3. Set cloudKitDatabase in ModelContainerFactory to .private(…)." |
| 6.4 | No wrong-platform hardware named | ❌ **P1-2** | `sync.your_data_stays_on_this` = "Your data stays on this **Mac** for now." / "…на этом **Mac**." rendered by `ICloudSheet.swift:74` on iPhone |
| 6.5 | Entitlement set is minimal | ⚠️ | `Docs/Montra.entitlements` also declares `ubiquity-kvstore-identifier`; no `NSUbiquitousKeyValueStore` call exists anywhere |

### 7. Minimum functionality & completeness

| # | Item | Status | Evidence |
|---|---|---|---|
| 7.1 | Onboarding | ✅ | `iphone-onboarding-no-tabbar.png` — welcome, no tab bar; account step, first-expense step, Mori intro; replay from About |
| 7.2 | Persistence | ✅ | SwiftData, 5 models (`MontraApp.swift:287`) |
| 7.3 | Analytics | ✅ | Analytics tab, Charts, day popup |
| 7.4 | Backup / restore / CSV | ✅ (logic) | `fileExporter`/`fileImporter` filtered to the app's UTType (`SettingsView.swift:93-113`); CSV via share sheet. Round-trip unproven — **verify on device** |
| 7.5 | No placeholder or demo content on a real install | ✅ | `SeedData.bootstrap` seeds categories + periods only (`SeedData.swift:48-53`); demo rows are opt-in and `QAFixtures` is `#if DEBUG` |
| 7.6 | No unfinished feature visible to a customer | ❌ | The iCloud sheet is the exception (6.3) |

### 8. App Store Connect readiness

| # | Item | Status | Evidence |
|---|---|---|---|
| 8.1 | Universal record decision | ❓ | One App ID `app.finance.montra` + one container ⇒ universal record strongly preferred (`Progress.md:61-65`) |
| 8.2 | 6.9" iPhone screenshot | ✅ exists | 1320×2868 (`build/check2/iphone-*.png`) — exactly the 6.9" size |
| 8.3 | 13" iPad screenshot | ✅ exists | 2048×2732 (`build/check2/ipad-overview.png`) |
| 8.4 | Screenshot localisation | ⚠️ | Russian only; the en localization has no screenshots |
| 8.5 | Age rating | ❓ | No UGC, no ads, no purchases ⇒ 4+ |
| 8.6 | Review notes for the custom iPad bar | ❌ | Not written (`Docs/` has no review-notes file) |
| 8.7 | Export compliance answer | ❌ | Same as 4.12 |

### 9. Visual / UX (from screenshots)

| # | Item | Status | Evidence |
|---|---|---|---|
| 9.1 | iPad Settings width | ✅ | `platformReadableWidth()` clamp at `SettingsView.swift:63`, 760 pt max (`PlatformLayout.swift:9-15`) |
| 9.2 | Truncation at default text size | ❌ **P2** | `build/check2/iphone-overview.png` — Savings row subtitle "BTC · 1 операция · накопите…" |
| 9.3 | Tab bar legibility | ❌ **P0-1** | Light appearance: selected label 1.09:1 |
| 9.4 | macOS metaphors on iOS | ❌ **P1-9** | Appearance picker thumbnails are 64×44 macOS windows with red/yellow/green traffic lights and a sidebar (`SettingsView.swift:793-900`, `MiniWindow`), shown at `build/wt-nav/build/evidence/iphone-settings-light.png` / `iphone-periods.png` |
| 9.5 | Dark / light contrast overall | ⚠️ | Dark is good; light content is good; only the system-accent surface fails (9.3) |
| 9.6 | Vertical rhythm above the title | ⚠️ | ~50 pt of dead space between the status bar and every page title (`check2/iphone-overview.png`, `iphone-settings-light.png`) — reads as a layout leftover from the Mac window |
| 9.7 | Sheet blank bands | ❌ **P1-3** | 2.7 |

---

## P0 — blocks submission

### P0-1. The selected tab is unreadable in Light appearance (measured 1.32:1, worst case 1.09:1)

The app supports Auto/Light/Dark. In Light, the iPhone system tab bar draws the selected item with the app's global accent, which is the **original macOS accent, never adapted for iOS**: `AccentColor.colorset` is one universal colour `(0.925, 0.918, 0.996)` ≈ `#ECEAFF`, wired in by `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` (`project.pbxproj:192,235` → `NSAccentColorName`). Confirmed in the shipped catalog: `assetutil --info Assets.car` reports `AccentColor … Color components [0.925, 0.918, 0.996, 1], Idiom universal` — a single rendition, no light/dark variant.

Measured on `build/wt-nav/build/evidence/iphone-settings-light.png` (tab bar region; builder-worktree screenshot — the accent asset and the shipped `Assets.car` are identical at `c34e02b`, so the defect is present in `DerivedData-final-ios` too):

| Sample | Relative luminance | Contrast |
|---|---|---|
| Selected label "Настройки" ink `#E1DEF0` on pill `#FCFBF8` | 0.721 / 0.965 | **1.32:1** |
| Worst-case ink-to-local-background inside the label | 0.745 / 0.813 | **1.09:1** |
| Unselected label "Категории" on the bar | 0.010 / 0.965 | 17.04:1 |

HIG > Accessibility > *Color and contrast*; WCAG 2.1 SC 1.4.3 requires 4.5:1 for text and SC 1.4.11 requires 3:1 for UI components. 1.09:1 is not "low", it is invisible — in the screenshot the selected item is the *least* legible thing in the bar. This is the app's primary navigation state indicator, on the platform's primary device class.

It also breaks the app's own selection contract: the iPad bar marks selection with a filled symbol **and** `AppColors.accent` (blue, `Theme.swift:45`), which is fine; the iPhone bar relies on the system accent alone, so the two shells disagree and only one is legible.

**Fix:** give the accent a proper light appearance (`AccentColor` → `AppColors.accent`, `#0A6ED1` light / `#4C9EEA` dark, with an `Increase Contrast` variant), or apply a root `.tint(AppColors.accent)` on iOS. Re-shoot Light at the same fixtures.

### P0-2. Touch targets are 22–32 pt across the whole form surface

Every interactive control still uses the desktop design system's heights. `AppStyle.Control.height = 28` (`Theme.swift:105-107`) and the field defaults were never given an iOS variant:

| Control | Height | File | Used by |
|---|---|---|---|
| `DropdownMenu` (period rule, sort, scope, currency) | **28 pt** | `Forms.swift:203` | Settings, Operations, Periods sheet |
| `NumberStepper` (payday day, period length) | **28 pt** | `Forms.swift:440` | Settings, Periods sheet, New Operation |
| `MontraTextField` (name, place, notes) | **32 pt** | `Forms.swift:146` | Account/Category/Operation sheets, onboarding |
| `DatePickerField` | **32 pt** | `Forms.swift:328` | New Operation, Plan |
| `PopoverMenu` **rows** (the anchored menu on iPhone) | **24 pt** | `Forms.swift:268` | every picker's menu |
| `MontraSwitchStyle` | **38 × 22 pt** | `Components.swift:825` | ~10 Settings/About rows |
| `TouchCheckboxStyle` | **22 × 22 pt** | `Components.swift:944` | select-all (`OperationsView.swift:617-636`, no touch-target modifier at all); row checkboxes are 22 × 44 via `SelectionToggleTouchTarget` (`OperationsView.swift:969-977`) |
| `InfoButton` | **~13 × 13 pt** (11 pt glyph, no padding) | `Components.swift:861` | Settings row headers |

HIG > Layout > Best practices: interactive elements need a **44 × 44 pt** target. `Progress.md:343` lists exactly this risk ("Touch targets < 44 pt (desktop is 24–30 pt) → Platform-specific control heights in the design system"); the mitigation was not implemented for these tokens. In a data-entry finance app the stepper, the date field and the picker rows are the most-used controls in the app.

The anchored-popover case is the sharpest: `montraPopoverContent()` (correctly) keeps the menu a popover on iPhone, but its rows are 24 pt — a menu of 24 pt rows on a phone is a mis-tap generator, and it is the *new* behaviour introduced by the popover fix.

**Fix:** one iOS control height (44 pt) in the design tokens, `minHeight: 44` on the popover rows, `contentShape` padding on the switch/checkbox/info button, and tap-to-toggle on the whole `toggleRow`. Then re-measure.

### P0-3. The distribution build cannot be signed as configured

`CODE_SIGN_ENTITLEMENTS = Montra/Montra.entitlements` applies to **all** SDKs (`project.pbxproj:193,236`), and that file requests `com.apple.developer.aps-environment = development` (`plutil -p Montra/Montra.entitlements`). The app contains no push registration — the entitlement is a leftover from the shared macOS configuration (`Progress.md:49`, and the port's own research says to drop it: `Docs/Research-iPadOS-Features.md:351-355`).

An iOS App Store profile will not carry `aps-environment` unless Push Notifications is enabled on the App ID, so `xcodebuild archive`/upload fails with the classic "Provisioning profile doesn't include the aps-environment entitlement". This is a release blocker, not a review finding — and it is invisible today because every build so far is an unsigned/ad-hoc simulator product (`codesign -dv` on the .app: `adhoc, linker-signed`, `TeamIdentifier=not set`, no `embedded.mobileprovision`).

Secondary: `Montra/Montra.entitlements` is **git-ignored** (not in `git ls-files`). A fresh clone cannot build; `Docs/Montra.entitlements` is a different, also-unused file (`ubiquity-kvstore-identifier`, no APNs).

**Fix:** see §E, step 1–3.

---

## P1 — must fix before submission

### P1-1. Dynamic Type breaks the layout at accessibility sizes
`build/wt-nav/build/evidence/ipad-a11y-xxxl-contrast.png` (iPad, `UICTContentSizeCategoryAccessibilityXXXL`): the toolbar reads "**Удали…**" and "**Новая…**" — the two primary actions are truncated; the "Планы / Пропущенные / Будущие" chip row clips its descenders. Text scales (`relativeTo: .body`, `Theme.swift:268`) but rows, chips and buttons keep fixed heights — and every money figure uses `.numbers` = `.system(size:)`, which does **not** scale (`Theme.swift:160-163`), so at XXXL the amounts stay small while their labels grow. HIG > Accessibility > *Dynamic Type*. Fix: allow the toolbar to collapse to icon-only at accessibility sizes, let chips wrap, stop capping heights on text rows, and scale the `.numbers` styles relative to a text style.

### P1-2. The iOS UI still speaks macOS — and shows developer instructions
Three surfaces render text written for the Mac, on iPhone and iPad:

| Surface | Rendered text | Source |
|---|---|---|
| Onboarding privacy note (first run, every user) | "Your data stays on this **Mac**. You can enable iCloud later." / "Данные остаются на этом **Mac**…" | `OnboardingFlowView.swift:452`, key `onboarding.your_data_stays_on_this` |
| New Account → "Hide from Overview" caption | "The account stays in the **sidebar** and on its own page" / "…в **сайдбаре**…" | `AccountSheet.swift:168`, key `account.stays_in_the_sidebar` — visible in `build/check2/iphone-newaccount.png` |
| iCloud sheet | "Your data stays on this **Mac** for now." | `ICloudSheet.swift:74`, key `sync.your_data_stays_on_this` |

And the iCloud sheet prints setup instructions meant for the developer: "1. Create the container iCloud.app.finance.montra in the developer account. 2. Add the entitlement from Docs/Montra.entitlements. 3. Set cloudKitDatabase in ModelContainerFactory to .private(…)." (`ICloudSheet.swift:41-47`, `sync.setup_steps`). A customer cannot do any of that; a reviewer reads it as an unfinished feature (Guideline 2.1 App Completeness). Note the port already fixed this pattern for About (`AboutView.swift:162-168` branches to "this device") — the fix just was not applied here.

Also `OverviewView.swift:334` — the "all accounts hidden" empty state says accounts "can still be opened from the **sidebar**".

**Fix:** platform-branch these four strings; on iOS hide the "To enable sync" block entirely and state only that sync is off.

### P1-3. Sheet content does not fit the detent it is given
- `check2/iphone-newaccount.png`: ~143 pt of empty space between the colour row and the pinned footer — the "blank band" the port set out to remove.
- `check2/iphone-periods.png`: the "Selected period" card is cut mid-row by the footer hairline, and the sheet ends with a rounded bottom edge and ~50 pt of dead space below the footer.

`.periods` is in the `[.medium, .large]` set (`BottomSheetHost.swift:39-41`) while carrying a pinned `SheetFooter` outside its `ScrollView` — the exact P2-7 risk the code review raised (`Docs/iOS-Code-Review.md:342-351`). HIG > Sheets: a partial-height sheet should size to its content; content should not be clipped by chrome. **Fix:** `.large` (or content-derived `.height`) for sheets with pinned footers, and verify at XXXL. **verify on device** — the dead band under the footer is not explainable from the code alone.

### P1-4. `TouchCheckboxStyle` has no accessible name
`Components.swift:921-951` renders only the box and never uses `configuration.label`; it sets only `accessibilityValue`. Any `Toggle("…", isOn:)` with this style announces "on/off" with no name. The select-all control shows the consequence precisely: the toggle is created with the label `common.select_all` (`OperationsView.swift:617-636`), that label is discarded by the style, and the visible text is then re-added as a **sibling** `Text` that is not part of the control (`OperationsView.swift:704-720`) — so VoiceOver reads an unnamed switch followed by a stray label. Carried over unfixed from the code review (`Docs/iOS-Code-Review.md:279-295`). HIG > Accessibility > *VoiceOver*. **Fix:** `.accessibilityLabel(Text(configuration.label))` inside `makeBody`.

### P1-5. VoiceOver can enter the app behind the onboarding overlay
`AppRootView.swift:52-56` hides the shell with `.opacity(0)` + `.allowsHitTesting(!showsOnboarding)` and no `.accessibilityHidden(showsOnboarding)`. Opacity does not remove a view from the accessibility tree, so on first launch a VoiceOver user can focus the invisible tab bar and page content. The iPad shell gets this right for inactive tabs (`IOSNavigationShell.swift:163`) — the onboarding overlay does not. **Fix:** one modifier.

### P1-6. The location purpose string iOS actually reads is not localised
`NSLocationWhenInUseUsageDescription` and the legacy `NSLocationUsageDescription` are both set (`project.pbxproj:205-206,248-249`). `en.lproj/InfoPlist.strings` and `ru.lproj/InfoPlist.strings` localise **only the legacy key**. iOS 8+ reads the when-in-use key, so a Russian user sees the English alert. CoreLocation is genuinely used (`Montra/Store/LocationProvider.swift` — one reading → reverse geocode → fills the payment place), so the string must stay and must be localised. Guideline 5.1.1(ii) (purpose strings must be clear and accurate). **Fix:** move the translations to `NSLocationWhenInUseUsageDescription` and delete the legacy key.

### P1-7. Export compliance is unanswered
`ITSAppUsesNonExemptEncryption` is absent from `Info.plist` and the project, so every upload triggers the ASC questionnaire. The app uses HTTPS (`URLSession`) and SHA-256 for backup/API integrity (`BackupArchive.swift:204`, `LedgerAPI.swift:217`) — no non-exempt encryption. **Fix:** set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`.

### P1-8. No privacy policy or support entry point in the app
About lists capabilities but no privacy policy, terms or support contact (`AboutView.swift:125-153`). Guideline **5.1.1(i)** requires the privacy-policy link both in the App Store Connect metadata **and inside the app in an easily accessible manner**; Support URL is likewise a mandatory ASC field. For a finance app the absence is both a review risk and a credibility problem. HIG > Settings expects these affordances in a settings surface.

### P1-9. The appearance picker shows macOS windows on iOS
`SettingsView.swift:793-900` (`MiniWindow`) draws a 64×44 miniature of the **Mac** app — sidebar and red/yellow/green traffic lights — to represent Light/Dark. Visible in `iphone-settings-light.png`, `iphone-periods.png`, and in the final-build comparison montage `Docs/screenshots/ios-port/compare-settings.png` (both the iPhone and iPad panels show the traffic lights). On iOS this is a metaphor for chrome the platform does not have. HIG > Settings / platform conventions; it also reads as an unported asset. **Fix:** an iOS-shaped thumbnail (rounded-rect app surface, no traffic lights), or a segmented control.

### P1-10. Entitlements over-declare iCloud
`Docs/Montra.entitlements` declares `com.apple.developer.ubiquity-kvstore-identifier`; nothing in the tree calls `NSUbiquitousKeyValueStore` (settings are `UserDefaults`, `SettingsStore.swift:85`). Keep only what ships: iCloud/CloudKit + the container. This also simplifies the App ID capability set (see §E).

---

## P2 — recommendations

1. **`DeleteOperationsSheet` bypasses the sheet chrome.** `OperationsView.swift:399` and `AccountDetailView.swift:144` present it directly, so it has no detents, no drag indicator and no iPad form sizing. Lift it into `AppModel.sheet` or apply a chrome-only modifier (carried over from `Docs/iOS-Code-Review.md:268-277`).
2. **Sheet-to-sheet swap in the plan flow.** `AppRootView.swift:558-566` replaces `AppModel.sheet` while a sheet is visible. Prefer dismiss-then-present, as the onboarding replay already does (`AppRootView.swift:584-590`).
3. **Savings row truncates at default size.** "BTC · 1 операция · накопите…" in `check2/iphone-overview.png` — the subtitle should wrap to two lines or drop the kind suffix on compact widths.
4. **The balance bar has no label.** Colour-only segments with no legend or `accessibilityLabel` on the overview bar. Add a composed label ("Spending by category, 5 accounts") and per-segment accessibility elements.
5. **iPad bar semantics.** Announce "*n* of 5" and the tab role in the label (e.g. `"\(tab.title), вкладка \(index+1) из 5"`), and consider `.accessibilityElement(children: .contain)` grouping so VoiceOver rotor navigation matches a system tab bar.
6. **iPad bar does not minimise.** The system bar supports `tabBarMinimizeBehavior(.onScrollDown)`; the custom bar permanently occupies ~65 pt. Either adopt the behaviour or document that it does not.
7. **Empty `UILaunchScreen`.** A blank flash on every cold start. Give it the app background colour (or a launch image) — HIG > Launching.
8. **~50 pt dead space above every page title.** Consistent across iPhone/iPad screenshots; the Mac header rhythm was not compressed for touch. Tighten `DockedHeader`'s top inset.
9. **`settings.access_for_other_apps_on`, `common.local_api`, `app.*_local_api`** remain in the string catalog though unreachable on iOS — fine for a shared catalog, but they make the localisation audit noisier.
10. **Hardware keyboard on iPhone.** `IOSAppCommands.swift:40` disables all commands off-iPad; the shortcuts are harmless on a phone with a keyboard.
11. **iOS 26.0 deployment target.** Valid, but it excludes every device that cannot run iOS 26. Document the decision in the listing (HIG > Platform support) — it is a product trade-off, not a defect.
12. **`LSApplicationCategoryType` in `Info.plist`** is a macOS key; keep it for the Mac build but do not treat it as the iOS category.
13. **iPad: the last Settings row sits under the floating bar.** In the final-build montage `Docs/screenshots/ios-port/compare-settings.png` the destructive "Удалить все данные" row is drawn beneath the custom bar. Either the scroll content is mid-scroll or the bottom safe-area inset does not reserve the bar's full height — confirm the inset (`IOSNavigationShell.swift:171-178`) and that the last row can be scrolled clear of the glass. The same check applies to the iPhone shell.

---

## E. What the developer must do in the Apple Developer portal / App Store Connect

Nothing below can be done from this branch.

### Apple Developer portal → Certificates, Identifiers & Profiles

1. **App ID `app.finance.montra`.** Confirm the `ios` platform is enabled on the existing identifier (universal/multipurpose ID). If the ID was created for macOS only, enable iOS — do **not** create a second App ID: a second bundle ID means a second iCloud container and a second data model.
2. **iCloud capability.** Enable iCloud on the App ID with **CloudKit** checked and the container `iCloud.app.finance.montra` associated. If the container does not exist: *iCloud Containers → +* → `iCloud.app.finance.montra`. Choose deliberately: a container identifier cannot be renamed, and deleting one destroys the data in it.
3. **Push Notifications: leave disabled** — unless the product now wants APNs. In that case enable the capability *and* add remote-notification code, otherwise the entitlement is dead weight.
4. **Key-value storage: leave disabled** unless `NSUbiquitousKeyValueStore` is actually adopted (it is not).
5. **Certificates & profiles.** An Apple Distribution certificate and an App Store provisioning profile for `app.finance.montra` (iOS), or automatic signing under team `97S3QGCCV4`. Keep the team: `Docs/Montra.entitlements` resolves `$(TeamIdentifierPrefix)` against it, and a team change would invalidate the existing macOS distribution identity.
6. **App Store Connect API key** (optional) if the release is to be automated.

### Repository changes required before the first archive

1. Create `Montra/Montra-iOS.entitlements` containing only:
   - `com.apple.developer.icloud-container-identifiers` = `["iCloud.app.finance.montra"]`
   - `com.apple.developer.icloud-services` = `["CloudKit"]`
2. Wire it per-SDK in **both** configurations: `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` and `[sdk=iphonesimulator*]` → the iOS file; keep `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = Montra/Montra.entitlements`.
3. **Track the entitlements file in git.** `Montra/Montra.entitlements` is currently ignored; no one else can build the branch.
4. Delete the unused `ubiquity-kvstore-identifier` from the macOS file, or adopt the API.
5. Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`.
6. Move the `NSLocation*` translations onto `NSLocationWhenInUseUsageDescription`; drop the legacy key.

### App Store Connect

1. **Record strategy — universal record (recommended).** Keep one app record for `app.finance.montra` with iOS, iPadOS and macOS platforms so the iCloud container, backup format and data model stay shared (`Progress.md:61-65`). If a macOS record already exists, add the iOS platform to it; the bundle ID must not change. If a separate iOS record were created it would need a different bundle ID, which would fracture the container and the `Docs/iCloud-Setup.md` story — not recommended.
2. **Build number.** If 1.0 (1) was ever uploaded for macOS under the same record, give the iOS build a distinct `CURRENT_PROJECT_VERSION` (CFBundleVersion is unique per platform, but bumping avoids confusion); `MARKETING_VERSION` stays 1.0 until a version change is requested.
3. **App information.** Primary language **Russian** (matches `CFBundleDevelopmentRegion = ru`); secondary English (the en localization is complete — 694 keys, 0 missing locales). Category: **Finance** (primary), Productivity optional. Content rights and age rating: no UGC, no ads, no purchases ⇒ **4+**.
4. **App Privacy.** "Data Not Collected"; no tracking. Keep the policy consistent with the only network traffic: two HTTPS GETs for exchange rates (`api.nbrb.by`, `cdn.jsdelivr.net`) that carry no user data. Location is used on-device only, stored in the user's own operation — not collected by the developer.
5. **Privacy policy URL and Support URL** — both mandatory fields, and both should also be reachable in-app (P1-8).
6. **Screenshots.** 6.9" iPhone (1320×2868) and 13" iPad (2048×2732) already exist in `build/check2/`. Add an English set if English is offered, and re-shoot after the P0-1 fix — every Light screenshot currently shows the broken selection.
7. **Export compliance.** Answer "No" (or rely on the new plist key): HTTPS + SHA-256 only; no proprietary or non-exempt cryptography.
8. **Review notes** (Guideline 2.1 / 2.3) must state:
   - the app has **no account and no server**; a reviewer can complete onboarding and use everything offline;
   - **iCloud sync is intentionally off** (`cloudKitDatabase: .none`); the entitlement exists for a planned release;
   - **location** is requested only when the reviewer taps the place field, to fill a payment place; denying it changes nothing else;
   - the **iPad bottom bar is a deliberate custom control**, because iPadOS 26 has no system bottom tab bar (the system offers only top bar / sidebar) and the product spec requires the bottom menu; it is persistent, labelled, 44 pt, never disabled, never overflows — a screenshot plus this paragraph is the defence;
   - **Local API / MCP / Touch Bar are macOS-only** and absent from the iOS UI; nothing on iOS listens on a port;
   - first launch starts with onboarding; no demo data is seeded.
9. **TestFlight on physical hardware** before submission — every artifact in this review is a Debug simulator product.

---

## F. What this review could not prove

1. **Release/Archive build.** Both analysed bundles are `Debug` (`DerivedData-final-ios`, `-iphonesimulator`, `CFBundleSupportedPlatforms = iPhoneSimulator`, ad-hoc signed). Release-only issues (optimiser, asset thinning, `#if DEBUG` stripping) are unverified.
2. **Signed-device entitlements.** The simulator binary carries no entitlements at all, so the actual provisioning result of P0-3 can only be observed at archive time.
3. **iPad Split View / Slide Over at ~320 pt.** The code branches on `horizontalSizeClass` correctly, but no screenshot at that width exists; `ipad-second-window.png` is a full-size window.
4. **VoiceOver order and announcement** on both bars, on the select-all control, and behind the onboarding overlay.
5. **Backup export → import round-trip** on iOS (`.montra` through Files), and the CSV share sheet.
6. **Sheet behaviour on device**: the ~50 pt dead band under the Periods footer (P1-3) and the plan→new-operation sheet swap (P2-2).
7. **Reduce Transparency / Increase Contrast on a real device** — only the XXXL + contrast screenshot exists, and it is from the builder's worktree, not from `DerivedData-final-ios`.
8. **Localization smoke in `en`.** No English screenshot of a full screen exists; `iphone-settings-en.png` was not reviewed here.

---

## G. Evidence index

| Artifact | Used for |
|---|---|
| `build/DerivedData-final-ios/.../Montra.app/Info.plist` | orientations, scenes, launch screen, purpose strings, icon keys, version |
| `…/PrivacyInfo.xcprivacy` | privacy manifest reasons |
| `…/Assets.car` (`assetutil --info`) | `AccentColor` (P0-1), `AppIcon` opacity |
| `…/en.lproj`, `…/ru.lproj/InfoPlist.strings` | P1-6 |
| `build/DerivedData-final/.../Montra.app` + `codesign` | shared entitlement story, no signed entitlements |
| `Montra/Montra.entitlements`, `Docs/Montra.entitlements`, `project.pbxproj:193,236` | P0-3, P1-10 |
| `Montra/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` | P0-1 root cause |
| `build/check2/iphone-overview.png` | tab bar, nav, truncation, safe areas |
| `build/check2/ipad-overview.png` | custom glass bar, iPad layout |
| `build/check2/iphone-newaccount.png` | sheet band, sidebar copy, control sizes |
| `build/check2/iphone-periods.png` | sheet clip, macOS thumbnails, 28 pt controls |
| `build/wt-nav/build/evidence/iphone-settings-light.png` | **P0-1 contrast**, macOS thumbnails, light mode |
| `build/wt-nav/build/evidence/ipad-a11y-xxxl-contrast.png` | **P1-1** Dynamic Type |
| `build/wt-nav/build/evidence/iphone-landscape-overview.png` | landscape, system floating bar |
| `build/wt-nav/build/evidence/iphone-onboarding-no-tabbar.png` | onboarding, no tab bar |
| `Docs/screenshots/ios-port/compare-settings.png` | final-build macOS/iPhone/iPad montage: P1-9 on final artifacts, iPad bar selection (blue), last-row occlusion (P2-13) |
| `Montra/Features/Navigation/{AppTab,BottomSheetHost,IOSNavigationShell}.swift` | navigation, sheets, accessibility traits |
| `Montra/Design/{Theme,Forms,Components}.swift` | P0-2 control heights, Dynamic Type fonts |
| `Montra/App/{MontraApp,AppRootView}.swift` | scenes, sheets, onboarding overlay |
| `Montra/Features/Settings/{SettingsView,ICloudSheet}.swift` | P1-2, P1-9, P1-8 |
| `Montra/Store/LocationProvider.swift` | location is genuinely used |
| `Montra/Integration/LocalIntegration.swift`, `Montra/Platform/PlatformSupport.swift` | macOS-only integration inert on iOS |
| `Docs/Research-iPadOS-Features.md`, `Docs/iOS-Code-Review.md`, `Progress.md` | prior decisions and carried-over findings |

### Guidelines cited

- App Store Review Guidelines: **2.1** App Completeness, **2.3** Accurate Metadata, **4.0** Design, **4.2** Minimum Functionality, **5.1.1(i)(ii)** Privacy — policies and purpose strings, **5.1.2** Data Use and Sharing, **2.5.1** public APIs. <https://developer.apple.com/app-store/review/guidelines/>
- HIG > Components > Navigation and search > **Tab bars** — <https://developer.apple.com/design/human-interface-guidelines/tab-bars>
- HIG > Components > Presentation > **Sheets** and **Popovers** — <https://developer.apple.com/design/human-interface-guidelines/sheets>
- HIG > Foundations > **Accessibility** (Color and contrast, Dynamic Type, VoiceOver, Reduce Motion) — <https://developer.apple.com/design/human-interface-guidelines/accessibility>
- HIG > Foundations > **Layout** (44×44 pt targets) — <https://developer.apple.com/design/human-interface-guidelines/layout>
- HIG > Patterns > **Multitasking**, **Launching**, **Onboarding**, **Settings** — <https://developer.apple.com/design/human-interface-guidelines/multitasking>
- HIG > Foundations > **App icons** — <https://developer.apple.com/design/human-interface-guidelines/app-icons>
