# iOS / iPadOS Port — Code Review

- **Branch:** `codex/ios-liquid-glass`, base `bf7550f`, reviewed `bf7550f..HEAD` (`298f067` merge + follow-ups)
- **Scope:** 39 changed files (+2598/−439), 5 new files (`AppTab`, `BottomSheetHost`, `IOSAppCommands`,
  `IOSNavigationShell`, `PlatformLayout`), `AboutSheet`
- **Method:** static analysis only. No `xcodebuild`, no simulators, no parallel jobs (post-incident
  policy from `Progress.md:507`). Findings that can only be *proven* at runtime are marked
  **verify on device**.
- **Reviewer stance:** independent; this is not an integration sign-off.
- **Taste vs defect:** every P0/P1 is a defect or a contract break. P2 mixes defects with
  maintainability debt. P3 is explicitly polish, dead code or taste unless the line says "trap".

---

## Verdict

**Not merge-ready.** The architecture is sound and the macOS isolation is genuinely careful, but the
port ships three ship-blocking classes of problem: iPad layouts are selected by *device idiom*
rather than window width (so Split View / Slide Over / Stage Manager render the 1366 pt design in a
320 pt column), every popover in the app becomes a nested sheet on iPhone (including inside the
New Operation sheet), and there is **zero automated verification on iOS** — no UI-test target, no
iOS equivalent of `-selftest`. `Progress.md:188` lists that harness as an unchecked Phase-0 task.

Nothing here looks like data corruption or a crash on the happy path. The risks are behavioral and
verify-ability.

Counts: **3 P0**, **6 P1**, **8 P2**, 12 P3. Two P1s are one-line fixes.

---

## Top risks (ranked)

1. **iPad compact width is not a supported layout, though iPad multitasking is mandatory.**
2. **Popover → sheet adaptation** turns every picker into a nested modal on iPhone.
3. **A 2 600-line platform-conditional navigation refactor with no iOS test that can fail.**
4. **Header relay has no isolation between a tab root and its pushed page** — stale/crossed titles
   are plausible and the mechanism that was supposed to prevent it does nothing.
5. **Two backup paths (Mac panels / iOS exporter) were not proven to round-trip through the same
   file type**, and the iOS "save before restore" name drops the extension.

---

## P0 — must fix before merge

### P0-1. iPad Split View / Slide Over / Stage Manager use the wide-iPad layout

Branching is on `UIDevice` idiom, not on the window:

- `Montra/Platform/PlatformSupport.swift:23-37` — `isPhone` / `isPad` read `UIDevice.current.userInterfaceIdiom`.
- `Montra/Features/Navigation/IOSNavigationShell.swift:81` — shell picks `padShell` vs `phoneShell` from `isPad`.
- `Montra/Design/Forms.swift:100`, `Montra/Features/Overview/OverviewView.swift:555`,
  `Montra/Features/Onboarding/OnboardingFlowView.swift:13-28`, `Montra/Features/Accounts/AccountDetailView.swift:248`
  — layout decisions keyed on `isPhone`.

Consequences, all in configurations the project explicitly declares (`TARGETED_DEVICE_FAMILY = 1,2`,
no `UIRequiresFullScreen`):

- In iPad **Split View / Slide Over** the window can be ~320 pt wide while `isPad` stays `true`, so
  the custom `GlassTabBar` still lays out five 54–76 pt items plus captions
  (`IOSNavigationShell.swift:218-251`). At 320 pt that is ≥ 320 pt of content before padding — it
  clips. The bar has no compact fallback (`showsCaptions` reacts to Dynamic Type only,
  `IOSNavigationShell.swift:226`).
- `AccountOverviewRow` keeps the share % (`OverviewView.swift:555`), keeps two trailing figures, and
  keeps the iPad typography in a phone-width column.
- `SheetContentFrame` returns `nil` for iPad (`Forms.swift:100`), so sheet content falls back to
  `maxWidth: .infinity` inside a 320 pt form sheet.

This is exactly what `Docs/Research-iPadOS-Features.md:304-320` ("let iPad resize… reflow on width
rather than assuming one column set", plus the mandatory multitasking/orientation note) and
pitfall 15 warned about.

**Fix:** introduce one width concept — `@Environment(\.horizontalSizeClass)` (or a `ViewThatFits` /
`GeometryReader` threshold) — and use it for every layout branch. Keep a device-idiom check only
where hardware is genuinely different (none of these are). Concretely: `IOSNavigationShell` should
use the *system* `TabView` shell when `horizontalSizeClass == .compact` (an iPad in Slide Over gets
the phone bar, which is what the system does), and the custom glass bar only at regular width.
`isPhone` should become `isCompactWidth` and be `@Environment`-driven, not a static read
(`PlatformSupport.swift:23` is also non-reactive: Stage Manager resizes never re-evaluate it).

### P0-2. Every popover becomes a nested sheet on iPhone

No `.presentationCompactAdaptation` exists anywhere in the tree (verified by grep). On iPhone a
`.popover` with default adaptation presents as a **sheet**, and these popovers are presented from
*inside* sheets or from the primary create flow:

| Site | What it is |
|---|---|
| `Montra/Features/Operations/OperationSheet.swift:690` | category picker inside New Operation |
| `Montra/Design/Forms.swift:267-270` | `PopoverMenu` (account/sort/scope menus in the sheet) |
| `Montra/Design/Forms.swift:364-370` | date/time picker inside New Operation |
| `Montra/Design/Components.swift:866` | `PopoverMenu` used by screens |
| `Montra/Design/GlyphAppearancePicker.swift:222` | icon/colour picker |
| `Montra/Features/Onboarding/OnboardingFlowView.swift:374` | account-style picker |

So on iPhone the core "create an operation" screen stacks *sheet → sheet* for the category, the date
and each account selector — each a full modal over the form the user is still filling in, and each
requiring its own dismissal. That is the HIG "one sheet at a time" rule that the team's own research called
out (`Docs/Research-iPadOS-Features.md:737-739`) and that the port's `BottomSheetHost` contract
otherwise respects.

**Fix:** one shared modifier (e.g. `func montraMenuPopover()` in `Forms.swift`) that applies
`.presentationCompactAdaptation(.popover)` on iOS, and use it at the six sites. Popovers stay
anchored menus on every iPhone size; iPads keep native popovers.

**Verify on device** — the visual severity depends on how the adapted sheets size themselves, but
the modality is certain.

### P0-3. No automated iOS verification exists, and the branch cannot be regression-checked

- `Montra/Snapshot/SelfTest.swift:1` is `#if os(macOS)`; `SnapshotRunner.swift` and
  `OnboardingIntroSnapshot.swift` likewise. The `-selftest` 182-check suite proves nothing about iOS.
- No UI-test target: no `MontraUITests` directory, `Montra.xcodeproj/xcshareddata/xcschemes` contains
  only `Montra.xcscheme`. `Progress.md:188` ("Add a `MontraUITests` UI-test target … with 5–6 smoke
  flows") is still `[ ]`, and `Progress.md:353-367` depends on it.
- `AGENTS.md` step 5 requires `ALL CHECKS PASSED` from `-selftest`; that check is now
  macOS-only, so "all checks passed" is silently weaker than it was before this branch.

The port's only iOS evidence is screenshots (`Progress.md:499-501`) plus a debug-only window probe
(`IOSNavigationShell.swift:98-123`). Screenshots cannot detect a wrong navigation stack, a sheet that
presents the wrong content, or a backup that will not re-import.

**Fix (minimum bar):** a UI-test target with: launch → 5 tabs; re-tap a tab with a pushed page;
Settings → About sheet; New Operation → category picker; Backup export → import round trip;
onboarding finish. Plus a Debug `-iostest` launch argument that runs the arithmetic half of
`SelfTest` on iOS (the suite is pure SwiftData/Swift logic — it is gated only by its `import AppKit`).

---

## P1 — must fix

### P1-1. Sheet content width is read from the *screen*, not from the sheet

`Montra/Design/Forms.swift:99-107`:

```swift
let scene = UIApplication.shared.connectedScenes…
let width = scene?.screen.bounds.width ?? 0
```

`UIScreen.bounds` reports the **display**, not the presented sheet. On iPhone it is the device's
native (portrait) bounds, it does not track the window, and it is not invalidated by rotation; even
on a build where it did rotate it would still describe the screen rather than the sheet. Every
iPhone sheet is therefore forced to a hard-coded `.frame(width: screenWidth)` (`Forms.swift:83-89`)
instead of the width SwiftUI actually offers.

Failure modes: iPhone landscape (sheet ~874 pt wide, content locked to ~393 pt, centred with two
blank bands), Split View / Stage Manager, and any future external display. The comment at
`Forms.swift:96-97` claims "a rotating phone picks up the new width on the next layout pass" — the
value is not observed by anything, so there is no invalidation either.

**Fix:** drop `phoneWidth` entirely and use the container:

```swift
content
    .containerRelativeFrame(.horizontal)
    .frame(maxHeight: .infinity)
```

or a `GeometryReader` inside the sheet. If a minimum is needed, `.frame(minWidth:)` on the content
plus the system's own sizing. Delete `SheetContentFrame.phoneWidth` and the `AppPlatform.isPhone`
branch (`Forms.swift:100`) — the sheet already knows its width.

**Verify on device** (landscape iPhone, and iPad in Split View).

### P1-2. "Re-tap the lit tab to pop" is unreachable on iPhone

`Montra/App/AppModel.swift:131-138` implements the re-tap contract, and the doc comment promises it.
The iPad bar calls it unconditionally (`IOSNavigationShell.swift:165`), so iPad works. On iPhone the
only caller is the `TabView` selection binding (`IOSNavigationShell.swift:138-143`), and SwiftUI does
not write to a selection binding when the selection value is unchanged — so the `selectedTab == tab`
branch never runs on iPhone.

Result: tapping the active tab on iPhone does nothing (SwiftUI documents no pop-to-root on re-tap,
and the system bar is not observed by this code), while the same gesture pops on iPad. This is a
behavioral difference between the two shells that the code claims not to have.

**Fix:** a same-tab tap cannot be observed through the system `Tab` selection binding, so pick one:
(a) drop the re-tap promise and the branch (`AppModel.swift:128-138`) and let iPhone behave the way
the system bar behaves; or (b) implement pop-to-root explicitly on iPhone (e.g. an iOS 18+ `TabView`
with the root content carrying its own re-tap handling) and document why the two shells differ. Do
not leave a comment stating a contract one platform cannot execute.

### P1-3. The `DockedHeader` relay provides no isolation; a tab root can keep a pushed page's title

`Montra/Features/Navigation/IOSNavigationShell.swift:26-48` claims the per-render `@StateObject`
prevents "a pushed page's title leaking back into the tab root's header". It cannot: both the root
`DockedHeader` (line 178) and the pushed one (line 187) forward from the **same** `DetailHeaderHost`
(the per-tab host at line 175), and screens write into that host through the environment
(`OverviewView.swift:125`, `AccountDetailView.swift:195`). The `display` object is a copy of a copy.

Two concrete consequences:

1. When Overview pushes an account, `AccountDetailView.syncHeader()` overwrites the tab host, so the
   root header underneath renders the account title too. On pop, the root's re-sync depends on
   `.onAppear` re-firing after a `NavigationStack` pop (`OverviewView.swift:99-101`). If it does not
   (this differs by OS version and is exactly the sort of thing that must not be assumed), the
   Overview header keeps showing the account name until `headerKey` happens to change. **Verify on
   device: push account detail, swipe back, read the header.**
2. `forward` is invoked from `.onReceive(source.$config)` (line 37) and writes `display.config`
   inside the view-update pass. That is the standard "Publishing changes from within view updates"
   pattern: it will emit runtime warnings and can drop an animation frame.

**Fix:** give the pushed page its own host and stop copying. In `TabHeaderStore`, keep
`rootHost` and `pushHost` per tab; inject `pushHost` into `destinationContent` at
`IOSNavigationShell.swift:185-193`, and clear it when the path empties. Then `DockedHeader` becomes
`SharedDetailHeader(host: showsBack ? pushHost : rootHost)` with no `@StateObject` and no
`onReceive` — the root's title is physically untouched while a page is pushed, which is what the
design wanted.

### P1-4. iOS "save before restore" filename has no `.montra` extension

`Montra/Features/Settings/BackupRestoreSheet.swift:274`:

```swift
exportFileName = "Montra-\(currentStamp())-before-restore"
```

versus the macOS path immediately below (line 277) which appends `BackupFile.fileExtension`. The
`fileExporter` may or may not append the type's preferred extension depending on the destination
provider; if it does not, the user gets an extension-less `…-before-restore` file whose type cannot
be inferred, and `fileImporter` (filtered to `BackupFile.contentType`,
`SettingsView.swift:103`) will show it greyed out. A "save your data first" affordance that produces
a file the app cannot re-open is the worst possible failure.

**Fix:** `"Montra-\(currentStamp())-before-restore.\(BackupFile.fileExtension)"`, matching line 277.
Additionally assert in a UI test that export → import of that exact file succeeds.

### P1-5. A new feature ("Duplicate operation") was added without the mandated release work

`Montra/Features/Operations/OperationsView.swift:829-843` adds `duplicate(_:)`, wired to a new
context-menu item at `OperationsView.swift:960-970` under a new key `common.duplicate`
(`Localizable.xcstrings`). This is not port work:

- `AGENTS.md` requires every behavior change / screen change to be represented in
  `Montra/Integration/LedgerAPI.swift` + `Docs/Local-API.md` and exposed in `mcp/server.py`, to be
  covered by `-selftest`, and to pass `Scripts/audit-feature-sync.py --require-dmg`. Duplicate is a
  data-creating action; it appears in none of them (`Montra/Integration/` is untouched by this diff).
- It also lands on **macOS** (the context menu is not gated), which contradicts `Progress.md:125-127`
  ("macOS behavior and visuals must not change") and the stated scope of an iOS port.
- `Docs/Feature-Inventory.md`, `README.md` and `Scripts/feature-sync-allowlist.txt` are unchanged.

**Fix:** either remove Duplicate from this branch, or split it into its own change that does the API,
MCP, self-test, inventory and audit work. Note that `AGENTS.md` also requires two languages —
that part was done (12 string units, en + ru — all new keys verified present).

### P1-6. macOS behavior drift is plausible but unproven

The rebase claims macOS parity; two shared-code changes can move Mac pixels or affordances:

- `OverviewView.swift:608-616` adds a **context menu** (right-click) to every account row on macOS.
  New macOS affordance, not requested.
- `OverviewView.swift:815-818` adds `.fixedSize(horizontal: true, vertical: false)` to `CurrencyChip`
  in shared code — the Mac row can no longer compress its chips.

Checked and safe (iOS-gated): `AccountDetailView.swift:369` and `OperationCompactRow.swift:20-30`
(`.switch` → `.touchCheckbox`), `DetailHeader.swift:159-172` (`shellBottomRoom`) and the
`ViewThatFits` block (`DetailHeader.swift:36-46`).

**Fix:** the snapshot diff must be re-run from the same worktree before and after *this* merge and
reviewed by eye, not summarised as "clock text only". The previous comparison
(`Progress.md:455`) predates both builders' merges. Anything beyond the demo clock rows is a
regression.

---

## P2 — should fix

### P2-1. `BottomSheetHost` is bypassed by `DeleteOperationsSheet`
`AppRootView.swift:540` is the only place `BottomSheetHost` is applied. But `OperationsView.swift:399`
and `AccountDetailView.swift:144` present `DeleteOperationsSheet` themselves through their own
`.sheet(item:)`, so it gets no detents, no drag indicator and no iPad form sizing — the one sheet the
centralisation contract missed. Same for the restore sheet, which re-implements the chrome by hand
(`SettingsView.swift:926-945`) instead of reusing `BottomSheetHost`.

**Fix:** make `BottomSheetHost` take a `sheet:`-free variant
(`func bottomSheetChrome(detents:)`) and apply it at both extra sites; or lift delete-confirmation
into `AppModel.sheet` as an `AppSheet` case.

### P2-2. The touch checkbox loses its accessible name, and one instance is 22 pt
`Montra/Design/Components.swift:921-951` (`TouchCheckboxStyle.makeBody`) renders only the box and
**ignores `configuration.label`**. Callers that put their text in the Toggle label lose it for
VoiceOver:
- `OperationsView.swift:617-635` passes `Text("common.select_all")` as the label, which is discarded,
  then re-adds a sibling `Text` at `OperationsView.swift:709-724` that is not part of the control.
  The select-all toggle is an unnamed button announcing only "on/off".
- `AccountDetailView.swift:366` (the savings toggle) and `TouchCheckboxStyle` generally: no label at
  all.

Also, the select-all toggle gets no `SelectionToggleTouchTarget` (`OperationsView.swift:709-724`),
so its target is 22×22 while the per-row boxes are grown to 44 pt
(`OperationsView.swift:994-1002`).

**Fix:** in `TouchCheckboxStyle.makeBody`, append
`.accessibilityLabel(Text(configuration.label))` (or `.accessibilityRepresentation { Toggle(...) }`),
and add the touch-target modifier at the select-all site.

### P2-3. iPad keeps every visited tab mounted, including a hidden Analytics page and its window recognizer
`IOSNavigationShell.swift:147-158` keeps visited tabs alive with `.opacity(0)`; that is a deliberate
trade (scroll position), but:
- every mounted tab re-evaluates its `@Query`-driven body on every store mutation, so a write costs
  2–5 screen recomputations instead of one; `@Query private var operations` exists in
  `AppRootView.swift:12`, `OperationsView`, `AnalyticsView`, `AboutContent`. Measure before merging.
- `AnalyticsView.swift:339-350` installs a **window-wide** `UITapGestureRecognizer` while its day
  popup is open (`AnalyticsView.swift:2354-2432`). If the user switches tabs with the popup open, the
  hidden Analytics page keeps `isActive == true`, the recognizer stays on the window, and the first
  tap anywhere in the app also dismisses that invisible popup. Harmless but stateful; the view never
  learns it disappeared.

**Fix:** dismiss the popup on `.onDisappear` (or subscribe to `scenePhase`), and consider unmounting
non-visible tabs beyond a small LRU.

### P2-4. Two sources of navigation truth, and `apply` replaces stacks instead of pushing
`AppModel` keeps both `route` (line 77) and `tabPaths` (line 86), with `setPath` rewriting `route`
only when the tab is selected (`AppModel.swift:121-126`). On iOS nothing renders from `route`:
`AppRootView.swift:225-229` builds every page from `AppTab.route` or the path. So `route` is dead
state that five methods keep in sync, and `apply` (line 156-170) **replaces** `tabPaths[.overview]`
with a single element rather than appending — fine today because only one page deep, but it silently
drops any future deeper stack, and it is the reason `push`/`popToRoot` were written and then never
used.

**Fix:** pick one. Either `route` stays authoritative and `tabPaths` is derived, or (better for iOS)
`route` is macOS-only behind `#if os(macOS)` and iOS reads the path. Delete `push`/`popToRoot` if
`open` is the only entry point.

### P2-5. CSV temp file is never cleaned up
`Montra/Store/CSVExporter.swift:40-45` writes a fixed `montra-operations.csv` into
`FileManager.default.temporaryDirectory`; `SettingsView.swift:481-490` hands it to the share sheet
and forgets it. Every export overwrites the previous file (so no unbounded growth), but it is
world-readable in the app container until the system purges tmp, and the share sheet may still be
reading it if a later export rewrites it.

**Fix:** unique name per export, delete in `onDismiss`/after the activity completes; or write into
`FileManager.default.urls(for: .cachesDirectory…)`.

### P2-6. Sheet-to-sheet replacement is untested on iOS
`AppRootView.swift:558-564`: `PlanActionSheet`'s callback assigns `app.sheet = .newOperation(...)`
while a sheet is presented. `.sheet(item:)` with a changed identity re-presents; on iOS this can
drop the presentation or animate a full dismiss/present cycle. macOS tolerated it. **Verify on
device**; if it misbehaves, dismiss first (the pattern already used at
`AppRootView.swift:584-590` for the onboarding replay).

### P2-7. `.medium` detents on sheets that have a pinned footer
`BottomSheetHost.swift:32-42` gives `.transferDetails`, `.planActions`, `.periods`, `.iCloud` a
`.medium` detent while those sheets carry a fixed `SheetFooter` outside their ScrollView
(e.g. `PeriodsSheet.swift:80-90`). At `.medium` on a short phone (or with large Dynamic Type) the
header + scroll body + footer exceed the detent and something is squeezed. `.presentationContentInteraction(.scrolls)`
(line 27) means the scroll view absorbs the shortfall, so the footer may end up partially pushed out
before the user drags up.

**Fix:** either `.large` only, or `.fraction`/`.height` values derived from content, and verify with
`UICTContentSizeCategoryAccessibilityXXXL`.

### P2-8. Backup decode runs on the main actor
`SettingsView.swift:452-478` reads and decodes the whole `.montra` JSON synchronously inside the
`fileImporter` completion, and `BackupService` is `@MainActor` (`BackupService.swift:7`). A large
backup blocks the UI and the security-scoped scope stays open while it does. Acceptable at today's
data sizes; worth a `Task.detached`/`nonisolated` decode if the archive grows.

---

## P3 — suggestions, dead code and nits

**Dead code / traps**
1. `AppModel.push` (`AppModel.swift:141-148`) and `popToRoot` (`:150-152`) have no call sites (verified
   by grep). Delete.
2. `BackupFile` iOS stubs return `nil` and no-op silently: `BackupFile.swift:103-125` (iOS branch:
   `export` 114, `chooseArchive` 118, `confirmSave` 122, `presentError` 124). `presentError`
   swallowing errors is a footgun; make the whole `#else` block macOS-absent rather than compiling
   no-ops, and drop `makeDocument` (`:108`) which duplicates `document(for:)` (`:35-37`).
3. `TabHeaderStore.host(for:)` (`IOSNavigationShell.swift:16-18`) returns a **fresh** `DetailHeaderHost`
   on the `??` path — silently unshared if the dictionary ever misses. Force-index instead.
4. `AboutSheet.swift:10-11` declares `settings` and `rates` it never reads (`AboutContent` owns its own).
5. `AppPlatform.supportsTouchBar` / `supportsWindowChrome` (`PlatformSupport.swift:45-48`) are unused.
6. `hiddenSidebarAccountID` (`AppRootView.swift:33,353,367`) has no consumer on iOS; the hero flight
   sets it for a sidebar that does not exist.
7. `SettingsView.onOpenAbout` is unused on macOS (`SettingsView.swift:564-590` hides the row for
   `AppPlatform.isMac`), yet every call site must pass it.
8. `QAFixtures` prints in `IOSNavigationShell.swift:107,120` — fine under `DEBUG`, but tag them with a
   common `MONTRA-QA` prefix for grep-ability (they already mostly are).

**Docs / consistency**
9. `Progress.md:167` names `MountraDocument.swift`; the file is `Montra/Backup/BackupDocument.swift`.
10. `Docs/iCloud-Setup.md:64` has an over-long line from the edit ("…(and vice versa) using the same
    Apple ID. If it does not appear, verify that both devices use the").
11. `Progress.md` claims "all nine sheets flexible" but `DeleteOperationsSheet` alone has no detents
    (P2-1) — document the exception or fix it.
12. `Route.sidebarSection` (`AppModel.swift:15-18`) maps `.operations → .overview` while
    `AppTab(route:)` (`AppTab.swift:64-72`) maps `.operations → .operations`. Two deliberate but
    contradictory taxonomies with no comment tying them together; a future reader will "fix" one.

**Polish / taste**
13. Onboarding intro scale (`OnboardingIntroView.swift:78-90`) starts at 1 and jumps when
    `onGeometryChange` delivers the size on iPad, after the timeline has begun. Read the container
    size before the first frame (or animate `artworkScale`) so the first change is not a jump.
14. Onboarding step transitions run inside the new `ScrollView` (`OnboardingFlowView.swift:246-270`)
    without `.scrollClipDisabled()`, so the blur/fade transition is clipped at the content bounds.
15. `IOSAppCommands.swift:18` uses `@Environment(\.openWindow)` inside `Commands`. `@FocusedValue`
    (line 17) definitely works there; environment delivery to `Commands` is an area where behaviour
    has changed across releases. **Verify** ⌘⌥N opens a window on iPad before relying on it; the safe
    alternative is a focused value carrying the action.
16. The iOS About group shows the version twice (`SettingsView.swift:564-584`: the About row's value
    and the "Version" row). Small duplication on a short screen.
17. `AnalyticsView.swift:351-356` implements Escape-to-dismiss with a zero-size, `.opacity(0)` Button
    in a `.background` — it works, but a `.hidden()`-style focusable button is a smell next to the
    UIKit catcher that already exists two lines up. Consider an `onKeyPress(.escape)` (iOS 17+).
18. `SettingsView.swift:156-194` reproduces `controlRow`'s padding by hand for the compact appearance
    row instead of adding an alignment parameter to `controlRow`.
19. `Untracked Docs/prototypes/{README.md,analytics.html,generate-data.py}` are present in the working
    tree. They are unrelated to the port and must not ride along in the merge commit.

**Style**
20. `IOSNavigationShell.swift:174-196` builds every page inside a `VStack` that duplicates four lines
    (`DockedHeader` + content + frame + background + toolbar). Extract a `tabPage(showsBack:)` helper.
21. `Forms.swift:512` (`NSEvent`) and `Components.swift:792` (`NSCursor`) use AppKit types with **no
    `import AppKit`** — they compile only because `import SwiftUI` transitively re-exports AppKit on
    macOS. The code is correctly `#if os(macOS)`-gated, but the missing import defeats the team's own
    "grep gate for `import AppKit` outside `#if os(macOS)`" mitigation (`Progress.md:339`) and breaks
    silently if that transitive export ever changes. Add the import inside the existing gate.

---

## Architecture assessment

**Good bones.** The split the plan promised is real: `AppRootView` keeps the macOS `HStack` sidebar
shell verbatim (`AppRootView.swift:195-220`) and the iOS shell is a sibling branch, not a rewrite.
The single `screen(_ route:)` switch (`:459-533`) is the best decision in the diff — both platforms
render pages from one function, so a screen cannot drift between them. `Material`/`AppStyle` tokens
are untouched, AppKit is genuinely isolated (`PlatformSupport.swift`, `Forms.swift`, `BackupFile`,
`CSVExporter`, `SettingsStore`, `LocalIntegration` all import AppKit only under `#if os(macOS)`;
`AnalyticsView`, `CapsuleSearchField`, `OnboardingHero` likewise — checked file by file), and the
`platformHelp` / `platformExitCommand` / `platformPointerHover` shims (`PlatformSupport.swift:136-174`)
keep shared screens free of `#if` noise.

**Where it weakens.** The port encodes *device* into layout instead of *width* (P0-1), and it
centralised sheet chrome in `BottomSheetHost` but not the *presentation*, so two sheets escape it
(P2-1). The navigation model has an iOS half (`tabPaths`) bolted onto a macOS half (`route`) that iOS
no longer renders (P2-4). The header relay is an abstraction that does not abstract (P1-3). None of
these are hard to fix; all of them are the kind of thing that becomes permanent if merged.

**Contract compliance:** the `SidebarAccountFramesKey` contract is honoured
(`OverviewView.swift:629-646` publishes, `AppRootView.swift:101` consumes, name and meaning
preserved). The sheet-flexibility contract is honoured by all nine sheets' frames but leaks at
`DeleteOperationsSheet`'s presentation. The backup contract is *nearly* honoured — same
`BackupService`, same `BackupCoding`, one shared `BackupDocument` — with the extension bug at P1-4.

**Process compliance:** `AGENTS.md` is partially met. Localization is complete for new keys (6 keys
× en/ru = 12 string units, verified). Backup format/schema unchanged (good). Local API/MCP untouched
(good for the port, but violated by the new Duplicate action, P1-5). `-selftest`/audit were run on the
merged branch (`Progress.md:494-498`) but the audit cannot see iOS-only code paths. `MARKETING_VERSION`
untouched. No README/Feature-Inventory update (Phase 5, still pending).

---

## What is good

- macOS isolation is disciplined and verifiable: every `import AppKit` is inside `#if os(macOS)`, and
  the iOS-only files (`BottomSheetHost`, `IOSNavigationShell`, `IOSAppCommands`) are wrapped whole.
- `AppTab` as the single source of order/title/symbol for both bars (`AppTab.swift:30-60`), including
  **filled** symbols for selection so state is not carried by tint alone (`:50-60`) — the right call
  for Increase Contrast.
- iPad bar accessibility is real: 44 pt minimum target, `.isSelected` trait, `accessibilityHidden` on
  non-selected pages, Dynamic Type caps, captions dropped at accessibility sizes
  (`IOSNavigationShell.swift:211-297`).
- No custom `presentationBackground` anywhere, deliberately (`BottomSheetHost.swift:5-8`) — exactly
  what the research asked for.
- `AboutContent` extraction (`AboutView.swift:39-86`) means the Mac page and the iOS sheet cannot
  disagree about version or totals. Same for `AboutMetrics` (`:202-207`).
- `Screen`-level typography fixes (`minimumScaleFactor`, `lineLimit`) are applied to the *content*,
  not by shrinking type globally, and are platform-gated where the Mac must not move.
- Security-scoped URL handling is correct (`SettingsView.swift:457-459`), and the importer is
  filtered to the app's UTType.
- The QA fixture store deliberately mirrors `SnapshotRunner` (`QAFixtures.swift:96-198`) so macOS
  snapshots and iOS screenshots are comparable — that is what makes the visual evidence meaningful.
- `PrivacyInfo.xcprivacy` gains the file-timestamp reason (`C617.1`) alongside `UserDefaults`
  (`CA92.1`), which matches what the code actually touches.

---

## Verification gaps — what a reviewer must demand

Nothing below is covered by an automated check today. Each is a silent-regression candidate.

**Must be demonstrated before merge (manual or UI test):**
1. iPhone **landscape** and iPad **Split View / Slide Over / Stage Manager** at ~320 pt width:
   custom bar, Overview rows, all nine sheets. (P0-1, P1-1)
2. iPhone: New Operation → category picker → account picker → date picker. Confirm no nested sheets
   (P0-2). Same for the sort/scope menus on Operations.
3. Push account detail → swipe back: the Overview header must read "Overview" (P1-3).
4. Settings → Save backup → **re-import that exact file** → restore. Repeat from the restore
   confirmation's "save first" path (P1-4). Check the file appears enabled in the picker.
5. Re-tap the active tab on iPhone and on iPad; document the intended difference (P1-2).
6. Multi-window: two windows on different tabs, edit in one, confirm the other updates and that both
   share one container (the debug probe at `IOSNavigationShell.swift:98-109` counts scenes but does
   not assert data sharing).
7. macOS: fresh before/after snapshot pair from the same worktree, diffed by eye — not just clock
   text. Pay attention to account rows (new context menu, P1-6) and currency chips.
8. `-selftest` (macOS, 182) + `Scripts/audit-feature-sync.py` on the merge commit; note in the report
   that neither exercises iOS.

**Should be added as ongoing checks:**
9. An iOS UI-test target (P0-3). Suggested 6 cases: tabs, re-tap, About sheet, new-operation picker,
   backup round-trip, onboarding finish.
10. A `-iostest` launch argument that runs the arithmetic half of `SelfTest` on iOS.
11. Dynamic Type `UICTContentSizeCategoryAccessibilityXXXL` + Reduce Transparency + Increase Contrast
    pass on the iPad bar and every sheet.
12. VoiceOver pass on the iPad bar and the select-all control (P2-2).
13. Reduce Motion pass over the intro, hero flight and sheet detents.
14. Localization smoke: launch in `ru` and `en` and confirm no raw keys appear (all 6 new keys are
    present; older keys are out of scope for this review).

---

## Merge-readiness checklist

| # | Gate | Status |
|---|---|---|
| 1 | P0-1 width/idiom branching fixed | ❌ blocks |
| 2 | P0-2 popovers no longer adapt to sheets on iPhone | ❌ blocks |
| 3 | P0-3 iOS verification harness (UI test + iOS self-test path) | ❌ blocks |
| 4 | P1-1 sheet width from container, not `UIScreen` | ❌ |
| 5 | P1-3 header host split, no publish-during-update | ❌ |
| 6 | P1-4 backup filename extension | ❌ (one line) |
| 7 | P1-5 Duplicate split out or fully released per `AGENTS.md` | ❌ |
| 8 | P1-6 macOS snapshot diff reviewed (not just "clock text") | ⚠ unproven |
| 9 | P1-2 re-tap contract either works or is documented per platform | ⚠ |
| 10 | P2-1 delete/restore sheets through the central chrome | ⚠ |
| 11 | P2-2 checkbox accessibility label + 44 pt | ⚠ |
| 12 | Localization complete (6 keys × en/ru) | ✅ verified statically |
| 13 | Backup format/schema unchanged | ✅ |
| 14 | Local API / MCP untouched | ✅ (but see P1-5) |
| 15 | Privacy manifest reasons | ✅ |
| 16 | AppKit fully gated | ✅ verified file by file |
| 17 | `-selftest` 182 on macOS | ✅ per `Progress.md:494` (re-run on final HEAD) |
| 18 | Audit 6/0 | ✅ per `Progress.md:495` (re-run with `--require-dmg` at release) |
| 19 | README / Feature Inventory / DMG / PR evidence | ❌ Phase 5, pending |
| 20 | Untracked `Docs/prototypes/*` excluded from the commit | ⚠ |

**Bottom line:** fix the three P0s and the two one-line P1s (P1-1, P1-4), then this is a
straightforward merge. The remaining P1/P2 work is small and local; the architecture does not need
to change, but the *width* concept and the *header host* ownership do.
