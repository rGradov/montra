# iPadOS 26/27 Feature Research for the Montra iOS/iPadOS Port

Research date: 2026-11-13. Target: iOS/iPadOS 26 + 27, built with Xcode 27 / iOS 27 SDK.

Audience: whoever writes the implementation plan. Scope: which iPadOS 26/27 capabilities Montra
should adopt, in priority order, with the exact API, its availability, and how it maps onto
Montra's existing screens (sidebar → tabs, sheets, accounts, analytics, onboarding).

---

## 0. Ground truth about this workspace

Checked before writing anything, because it changes the plan:

| Fact | Value | Why it matters |
|---|---|---|
| Xcode | 27.0 (27A266a) | iOS 27 SDK is installed; every API below was verified against it |
| iOS SDK | 27.0 | — |
| `IPHONEOS_DEPLOYMENT_TARGET` | **26.0** (already set) | All iOS 26 Liquid Glass APIs are usable **without** `#available`; only 26.x/27.0 additions need guards |
| `TARGETED_DEVICE_FAMILY` | `1,2` | iPhone + iPad already declared |
| `SUPPORTED_PLATFORMS` | `iphoneos iphonesimulator macosx` | iOS/iPadOS already a build target |
| Existing nav | `Montra/Features/Sidebar/SidebarView.swift`: Overview, Accounts, Savings, Categories, Analytics, Settings, About + iCloud status row | Maps almost 1:1 to iPad sidebar (see P0-1) |
| Existing sheets | `OperationSheet`, `AccountSheet`, `CategorySheet`, `PeriodsSheet`, `BackupRestoreSheet`, `ICloudSheet`, `DeleteOperationsSheet`, `PlanActionSheet`, `TransferDetailSheet` | Each is a candidate for detents/sizing (P0-3) |
| Charts | `Montra/Features/Analytics/AnalyticsPaceChart.swift` uses Swift Charts | Selection/popover is a real upgrade (P1-6) |
| Spotlight / Intents | `Integration/SpotlightEntities.swift`, `SpotlightLedger.swift`, `SpotlightActions.swift`, gated on `#available(macOS 26.0, *)` | Already App Intents-based; extend to iOS rather than rebuild (P1-7) |
| Local API server | `Integration/LocalHTTPServer.swift`, `NWListener` bound to `127.0.0.1:8766` | **Loopback only** → no Local Network permission; still must be excluded from the iOS target |
| Entitlements | `iCloud.app.finance.montra` + CloudKit + `aps-environment` | Push entitlement on iOS needs a real purpose or it is review noise (P0-5) |
| macOS-only window code | `WindowConfigurator` (`NSViewRepresentable`), `.windowStyle(.hiddenTitleBar)`, fixed 980pt width via `AppWindowLayout` | Must not compile into the iOS target (P0-4) |
| Existing shortcuts | `⌘N` new transaction, `⇧⌘N` new account, `⌘1…⌘4`, `⌘,`, all posted through `NotificationCenter` | On iPad these must move to `commands` + a router, not `NotificationCenter` (P1-4) |

**Verification method.** API names, signatures and availability were read out of the installed
iOS 27 SDK interface (`iPhoneOS27.0.sdk/.../SwiftUI.swiftinterface`, `SwiftUICore`, `Charts`,
`WidgetKit`, `AppIntents`), not from blog posts. Behavioural rules come from WWDC transcripts and
HIG pages. Where something is my judgement rather than a documented rule, it is marked
**Judgement**. Anything I could not verify is called out explicitly.

---

## 1. The two decisions everything else hangs off

### Decision A — navigation: the system will not put a tab bar at the bottom on iPad

This is the single most important finding, so it goes first.

Apple's HIG, iPadOS section of *Tab bars*:

> "The system displays a tab bar near the top of the screen. You can choose to have the tab bar
> appear as a fixed element, or with a button that converts it to a sidebar."

And for iOS:

> "A tab bar floats above content at the bottom of the screen. Its items rest on a Liquid Glass
> background that allows content beneath to peek through."

The documentation for `TabViewStyle.sidebarAdaptable` says the same thing in API terms:

> "iPadOS displays a top tab bar that can adapt into a sidebar. iOS displays a bottom tab bar."

I checked whether an API exists to override this. It does not:

- `AdaptableTabBarPlacement` has exactly three members: `.automatic`, `.tabBar`, `.sidebar`. There
  is no `.bottom`.
- `defaultAdaptableTabBarPlacement(_:)` (iOS 18.0+) only works on iPadOS **and only** in the
  `sidebarAdaptable` style, and it chooses between *sidebar* and *tab bar*, not between top and bottom.
- `defaultTabBarPlacement(_:)` (iOS 27.0+) is explicitly a no-op on iPadOS. Its own documentation:
  "On iPadOS (where the bar is adaptable), this modifier has no effect."
- `TabViewStyle.tabBarOnly` (iOS 18.0+) removes the sidebar-conversion button. It does not move the
  bar down.

**So:** a bottom Liquid Glass bar on iPad is only achievable as a *custom control you draw
yourself* with `glassEffect`. That yields genuine Liquid Glass material (it is the same system
material, not a fake blur), but it is not a `TabView` tab bar, and it will not get the system's tab
bar behaviours (sidebar morphing, tab customization, search-tab field replacement, minimize-on-scroll,
automatic iPad-orientation handling).

**Recommendation:**
- **P0 — ship the native `TabView`.** Use `.tabViewStyle(.sidebarAdaptable)` on iPad: top floating
  glass tab bar that morphs into a sidebar. This is *also* the most faithful port of Montra's
  macOS sidebar — on iPad the user gets an actual sidebar with the same section list, and on iPhone
  they get the bottom glass tab bar. It is HIG-recommended, and the "convert to sidebar" affordance
  is the canonical iPad pattern.
- **P1 — optional custom bottom glass bar**, behind a build flag, if the product genuinely wants
  visual parity with the desktop-derived design on iPad. Full recipe in P1-1, with the trade-offs
  spelled out. Do not ship both at once.

### Decision B — how many tabs

HIG: "Avoid overflow tabs… limit scenarios where this can happen", "Include tab labels", "Don't
disable or hide tab bar buttons". Montra has 8 sidebar destinations (Overview, Accounts, Savings,
Categories, Analytics, Settings, About, iCloud status).

- Keep **5** primary tabs: Overview, Accounts, Categories, Analytics, Settings.
- **Savings accounts** stay inside Accounts (they are accounts with a flag, and `SidebarView`
  already groups them under "Accounts"/"Savings" section labels) — **Judgement**, but it protects the
  tab count.
- **About** belongs in Settings.
- **iCloud status** belongs in Settings, surfaced as a status row; it is state, not a destination.
  (`SidebarView` already renders it as an accessory row, so this is a small move.)
- Add **search** as `Tab(role: .search)` (see P0-1) rather than spending a tab slot.

---

## 2. P0 — must use for a faithful port / HIG compliance

### P0-1. Root navigation with `TabView` + `Tab`, and the Liquid Glass tab bar for free

**API**

```swift
TabView(selection: $route) {
    Tab("Overview", systemImage: "chart.pie", value: Route.overview) { OverviewView() }
    Tab("Accounts", systemImage: "creditcard", value: Route.accounts) { AccountsView() }
    Tab("Categories", systemImage: "square.grid.2x2", value: Route.categories) { CategoriesView() }
    Tab("Analytics", systemImage: "chart.bar.xaxis", value: Route.analytics) { AnalyticsView() }
    Tab("Settings", systemImage: "gearshape", value: Route.settings) { SettingsView() }
    Tab(value: Route.search, role: .search) { SearchResultsView() }   // iOS 18.0+
}
.tabViewStyle(.sidebarAdaptable)                      // iOS 18.0+
.tabBarMinimizeBehavior(.onScrollDown)                // iOS 26.0+, iPhone bottom bar only
.searchable(text: $query)                             // pairs with the .search tab
```

- `Tab(_:systemImage:value:content:)` / `Tab(role:)` — **iOS 18.0+**. With a selection-based
  `TabView`, the search tab needs its own value: `Tab(value: Route.search, role: .search) { … }`
  (`init(value:role:content:)`); the value-less `Tab(role: .search) { … }` form only fits a
  non-selection `TabView`.
- `TabRole.search` — **iOS 18.0+**; `TabRole.prominent` — **iOS 27.0+** (see P2-1)
- `TabViewStyle.sidebarAdaptable` / `.tabBarOnly` — **iOS 18.0+**
- `tabBarMinimizeBehavior(_:)` + `TabBarMinimizeBehavior` (`.automatic`, `.onScrollDown`,
  `.onScrollUp`, `.never`) — **iOS 26.0+**; the three explicit values are iOS-only
- `Tab.badge(_:)` — iOS 18.0+
- `TabViewCustomization` — **iOS 18.0+** (P2-2)

**Montra application.** Replaces `SidebarView` as the root container while keeping the same
destinations and the same `Route` enum. On iPhone the tab bar is a bottom floating glass bar with
morphing selection — this is the Liquid Glass the design brief asks for, rendered by the system. On
iPad the bar sits at the top and gains a sidebar-conversion button, which is a *better* port of the
desktop sidebar than a bottom bar would be. `tabBarMinimizeBehavior(.onScrollDown)` suits the long
Overview/Operations lists.

Selected-tab state should be a plain `Route` in `@SceneStorage` so iPad windows restore independently
(see P1-2).

**Sources**
- https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable
- https://developer.apple.com/documentation/swiftui/tabviewstyle/tabbaronly
- https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
- https://developer.apple.com/documentation/swiftui/tabrole/search
- https://developer.apple.com/design/human-interface-guidelines/tab-bars
- https://developer.apple.com/videos/play/wwdc2025/208/ ("Elevate the design of your iPad app")
- https://developer.apple.com/videos/play/wwdc2025/323/ ("Build a SwiftUI app with the new design")

---

### P0-2. Liquid Glass primitives (`glassEffect`, `GlassEffectContainer`) for every non-system surface

This is the API set that makes the design brief's "bottom Liquid Glass tab/menu" and "glass forms"
possible, and it is also what you use for any surface the system does not draw for you.

**API**

```swift
Text("+").padding()
    .glassEffect(.regular.interactive(), in: .capsule)   // iOS 26.0+

GlassEffectContainer(spacing: 20) {                        // iOS 26.0+
    HStack {
        Button("Overview") { }.glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("overview", in: ns)
        Button("Accounts") { }.glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("accounts", in: ns)
    }
}
```

- `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View` — **iOS/iPadOS 26.0+**, `visionOS` unavailable
- `Glass`: `.regular`, `.clear`, `.identity`, `.tint(_ color: Color?)`, `.interactive(_ isEnabled: Bool = true)` — **26.0+**
- `GlassEffectContainer(spacing: CGFloat? = nil, content:)` — **26.0+**
- `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)` (`.matchedGeometry`, `.materialize`, `.identity`) — **26.0+**
- `ConcentricRectangle` shape + `.containerConcentric` corner — **26.0+** (keeps a custom bar's
  corner radius concentric with the sheet/window corner; HIG asks for exactly this on custom toolbar
  components)
- `scrollEdgeEffectStyle(_:for:)` with `ScrollEdgeEffectStyle.soft` / `.hard` — **26.0+**
- `backgroundExtensionEffect()` — **26.0+**
- `safeAreaInset(edge:)` — long-standing; the correct way to mount a floating bar over scrolling content

**Rules the design must follow** (from *Meet Liquid Glass*, not optional polish):

- Glass is for the **navigation layer that floats above content**. Do not glass the content layer —
  no glass on balance cards, transaction rows, chart cards. "Making it Liquid Glass would make it
  compete with other elements and muddy the hierarchy."
- **Never glass on glass.** Stacking produces the "cluttered and confusing" result Apple calls out.
  If something must sit on glass (e.g. a label in the bottom bar), use fills, transparency and
  vibrancy instead of a second material.
- **`.regular` almost everywhere.** `.clear` is only legitimate when *all three* hold: over
  media-rich content, the content layer tolerates a dimming layer, and the content above it is bold
  and bright. Montra has no media-rich content — **use `.regular` only. Never mix the two variants.**
- **Tint sparingly, for one primary action.** Tinting every element destroys the hierarchy. Montra's
  candidate for the single tint is the "New operation" affordance.
- Avoid content intersecting glass in **steady state** (fresh launch): inset content or scale it.
- In a `GlassEffectContainer`, keep neighbouring glass in the **same** container — "glass can not
  sample other glass", so separate containers give inconsistent rendering. This is the difference
  between a good-looking bar and a visibly wrong one.

**Montra application.** Every sheet chrome, the custom bottom bar (P1-1), the onboarding hero's
floating controls, and any floating "add" button on Overview. Because the deployment target is
already 26.0, no `#available` guards are needed for any of this.

**Sources**
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/documentation/swiftui/glass
- https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
- https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)
- https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()
- https://developer.apple.com/documentation/swiftui/concentricrectangle
- https://developer.apple.com/videos/play/wwdc2025/219/ ("Meet Liquid Glass")

---

### P0-3. Sheet modernization — this is a *deletion* task as much as an adoption task

**API**

```swift
.sheet(item: $editingOperation) { op in
    OperationSheet(op: op)
        .presentationDetents([.medium, .large])              // iOS 16.0+
        .presentationSizing(.form)                           // iOS 18.0+
        .presentationCornerRadius(28)                         // iOS 16.4+
        .presentationDragIndicator(.visible)                  // iOS 16.0+
        .presentationCompactAdaptation(.sheet)                // iPhone: force sheet over popover
}
```

- `presentationDetents(_:)` / `presentationDetents(_:selection:)` — **iOS 16.0+**
- `PresentationDetent`: `.medium`, `.large`, `.fraction(_:)`, `.height(_:)` — iOS 16.0+
- `presentationSizing(_:)` + `PresentationSizing` (`.form`, `.page`, `.fitted`,
  `.fitted(horizontal:vertical:)`, `.sticky(horizontal:vertical:)`) — **iOS 18.0+**
- `presentationCornerRadius(_:)`, `presentationDragIndicator(_:)`, `presentationBackground(_:)`,
  `presentationBackgroundInteraction(_:)`, `presentationContentInteraction(_:)`,
  `presentationCompactAdaptation(_:)` — iOS 16.0–16.4+
- `matchedTransitionSource(id:in:)` + `navigationTransition(.zoom(...))` — **iOS 18.0+** (sheet
  morphs out of the control that presented it)

**The important iOS 26 behaviour change.** From *Build a SwiftUI app with the new design*:

> "On iOS 26, partial height sheets are inset by default with a Liquid Glass background. At smaller
> heights, the bottom edges pull in… When transitioning to a full height sheet, the glass background
> gradually transitions, becoming opaque and anchoring to the edge of the screen. If you've used the
> `presentationBackground` modifier to apply a custom background to your sheets, consider removing
> that and let the new material shine."

So the correct port of `OperationSheet`, `AccountSheet`, `CategorySheet`, `PeriodsSheet`,
`BackupRestoreSheet`, `ICloudSheet`, `DeleteOperationsSheet`, `PlanActionSheet` and
`TransferDetailSheet` is:

1. **Delete** any custom background/`presentationBackground` and any hard-coded sheet corner radius
   the macOS design used — they will fight the new material.
2. Give each sheet **explicit detents** matched to its content: `OperationSheet` `.large` (a full
   form); `PeriodsSheet` `.medium, .large`; `DeleteOperationsSheet` `.height(…)` or `.medium`;
   `AboutView`/`ICloudSheet` `.medium`.
3. On iPad use `.presentationSizing(.form)` for the form sheets so they present as a centred card
   rather than a stretched page (see Risks: iPad sheets are form sheets at regular width).
4. Give the presenting control a zoom transition so the sheet appears to grow out of it — the new
   design's default feel, and cheap to adopt.

HIG also constrains these: one sheet at a time from the main interface; if an action inside a sheet
needs another sheet, close the first; if you show Done, always offer Cancel (or Back). Check
`OperationSheet`'s flow against that.

**Sources**
- https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)
- https://developer.apple.com/documentation/swiftui/presentationsizing
- https://developer.apple.com/documentation/swiftui/view/presentationbackground(_:)
- https://developer.apple.com/documentation/swiftui/view/presentationcornerradius(_:)
- https://developer.apple.com/design/human-interface-guidelines/sheets
- https://developer.apple.com/videos/play/wwdc2025/323/

---

### P0-4. Window/scene cleanup: remove the macOS window plumbing, let iPad resize

**API**

```swift
WindowGroup {
    AppRootView(...)
}
.windowResizability(.contentMinSize)      // iOS 17.0+
.defaultSize(width: 900, height: 700)     // iOS 17.0+
```

- `WindowGroup` — iOS 14.0+
- `scene.windowResizability(_:)` — **iOS 17.0+** (`WindowResizability`: `.automatic`,
  `.contentSize`, `.contentMinSize`)
- `scene.defaultSize(_:)` / `defaultSize(width:height:)` — **iOS 17.0+**
- `openWindow` environment action (`OpenWindowAction`) — iOS 16.0+ (P1-2)
- **`Window` scene: not available on iOS.** Verified in the iOS 27 SDK: `SwiftUI.Window` is
  `@available(macOS 13.0, visionOS 26.0, *)` with `@available(iOS, unavailable)`. Use `WindowGroup`.
- **`defaultWindowPlacement(_:)`: not available on iOS** (macOS 15 / visionOS 2 only). Do not plan
  iPad window placement around it.

**Montra application.** `AppWindowLayout` pins the window to 980pt wide and `WindowConfigurator`
drives `NSWindow` directly; both are AppKit and must be `#if os(macOS)`. On iPad, iPadOS 26 gives
apps a resizable window with window controls automatically — a fixed 980pt width would fight it and
look broken in Split View and Stage Manager. Replace with `.windowResizability(.contentMinSize)`
plus a sensible `.defaultSize`, and make the Overview/Analytics layouts reflow on width rather than
assuming one column set.

**Orientation requirement.** iPad apps must declare all four orientations in
`UISupportedInterfaceOrientations~ipad`. Omitting one, or shipping `UIRequiresFullScreen`, is what
trips App Store validation and the iPad multitasking expectations.

**`UIRequiresFullScreen` is deprecated in iOS 26.0** (verified in the SDK docs: "iOS 9.0
DEPRECATED@26.0; iPadOS 9.0 DEPRECATED@26.0") and its documentation now actively says: "In iPadOS 26
and later, support multitasking and dynamic resizing to make your iPad app flexible." Do **not** add
it to opt out of resizing.

**Sources**
- https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)
- https://developer.apple.com/documentation/swiftui/scene/defaultsize(_:)
- https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen
- https://developer.apple.com/videos/play/wwdc2025/208/

---

### P0-5. App Store / privacy compliance for the iOS target

Concrete checklist, all of it verifiable:

1. **`PrivacyInfo.xcprivacy`** in the iOS bundle: `NSPrivacyCollectedDataTypes` (Montra collects
   nothing off-device — the ledger is local + the user's own CloudKit), `NSPrivacyTracking` = false,
   `NSPrivacyTrackingDomains` empty, `NSPrivacyAccessedAPITypes` for each required-reason API the
   app actually calls. `UserDefaults` alone forces `NSPrivacyAccessedAPICategoryUserDefaults` —
   and `SettingsStore` uses `UserDefaults`, so this applies.
2. **No location usage strings.** Montra has no location code; do not add
   `NSLocationWhenInUseUsageDescription` "just in case" — an unused purpose string is review noise.
3. **No Local Network permission.** `LocalHTTPServer` sets
   `parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8766)`, i.e. loopback
   only, which does not trigger the Local Network prompt and needs no
   `NSLocalNetworkUsageDescription`/`NSBonjourServices`. Regardless: the server, `LedgerAPI`, and the
   MCP integration are a desktop affordance; **exclude them from the iOS target** rather than port
   them (an iOS app's listener also dies on suspension, so it would not work anyway).
4. **CloudKit entitlements.** `iCloud.app.finance.montra` + `CloudKit` port cleanly. The
   `aps-environment` entitlement is a *push* capability — Montra does not use remote push, so drop it
   from the iOS configuration unless `SyncService` actually registers for remote notifications.
5. **Data collection disclosure.** If the app is local-only and iCloud-synced through the user's own
   account, the App Privacy answers are "Data Not Collected" — worth confirming against
   `Docs/iCloud-Setup.md` before submission, because CloudKit private database is *not* collection by
   the developer.
6. **Single 1024×1024 icon.** One App Store icon, no `@2x`/`@3x` variants, no transparent alpha.
   Xcode 27's asset catalog handles the variants. Montra's `Design/Brand.swift` should drive the
   glyph so the icon and in-app identity match.
7. **Launch screen.** `UILaunchScreen` in Info.plist (no storyboard needed). Without it the app
   letterboxes at a legacy size.
8. **Minimum functionality (App Store Review 4.2).** A finance tracker with real persistence,
   analytics and backup is comfortably above the bar; nothing to do, but do not ship a build where
   the only working path is onboarding.
9. **Custom tab bar (if P1-1 ships).** HIG does not forbid custom navigation, but it forbids tab
   bars used for actions, hidden tab bar buttons, and silent overflow. A custom bottom bar that
   behaves like a tab bar (persistent, labelled, 44pt targets, no overflow, no disabled items) is
   defensible; one that doubles as an action bar is not. There is **no** "Liquid Glass adoption"
   review requirement — adopting Xcode 26+ SDKs gets the new look automatically.

**Sources**
- https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/design/human-interface-guidelines/tab-bars

---

### P0-6. Accessibility floor (it is mostly free, but two things are on you)

The material handles three settings automatically. From *Meet Liquid Glass*:

> "Reduced Transparency makes Liquid Glass frostier and obscures more of the content behind it.
> Increased contrast makes elements predominantly black or white and highlights them with a
> contrasting border, and Reduced Motion decreases the intensity of some effects and disables any
> elastic properties for the material. These are available automatically whenever you use the new
> material."

Two things you must do yourself:

1. **Never encode meaning in glass, tint or translucency alone.** `Design/Theme.swift`,
   `ListRowIcon.swift` and `OperationDisplay.swift` already use color/icon pairs for income vs
   expense — keep that pairing in the tab bar and sheets. With Increase Contrast the material goes
   black/white, so a tint-only signal disappears.
2. **Dynamic Type.** Audit for fixed point sizes. Use semantic fonts (`.body`, `.headline`) and
   `@ScaledMetric` for the bottom bar's height/padding; a glass bar with hard-coded 44pt height and
   `.caption2` labels will clip at accessibility sizes. If a custom bar must cap growth, use
   `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` deliberately, not accidentally.
3. **VoiceOver.** Custom glass buttons need `.accessibilityLabel`, and a selected tab needs the
   `.isSelected` trait; `accessibilityElement(children: .combine)` on bar items so the icon+label
   read as one control. `SidebarView` already does label composition well (`"\(account.name), …"`) —
   carry that over.

`@Environment(\.accessibilityReduceTransparency)`, `\.accessibilityReduceMotion`,
`\.accessibilityDifferentiateWithoutColor` and `\.dynamicTypeSize` are all available if a custom
surface needs to branch. Prefer not branching — the material already adapts.

**Sources**
- https://developer.apple.com/videos/play/wwdc2025/219/
- https://developer.apple.com/design/human-interface-guidelines/tab-bars
- https://developer.apple.com/videos/play/wwdc2026/220/ ("Refine accessibility for custom controls")

---

## 3. P1 — should use, clear user value

### P1-1. A genuinely-Liquid-Glass *custom* bottom bar (only if the design demands it on iPad)

Because the system won't do it (Decision A), here is the only correct way to build it.

```swift
struct GlassTabBar: View {
    @Namespace private var ns
    @Binding var selection: Route

    var body: some View {
        GlassEffectContainer(spacing: 8) {                    // ONE container for all items
            HStack(spacing: 4) {
                ForEach(Route.tabbable) { route in
                    Button { selection = route } label: {
                        Label(route.title, systemImage: route.symbol)
                            .labelStyle(.iconOnly)            // iPad: icons, per HIG regular width
                            .frame(width: 56, height: 44)      // ≥44pt target
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        selection == route ? .regular.tint(.accentColor).interactive()
                                           : .regular.interactive(),
                        in: .capsule
                    )
                    .glassEffectID(route, in: ns)
                    .accessibilityAddTraits(selection == route ? [.isSelected] : [])
                }
            }
            .padding(6)
        }
        .padding(.horizontal, 16)
    }
}

// Mount it over content so lists scroll underneath, and keep text legible under it:
content
    .safeAreaInset(edge: .bottom) { GlassTabBar(selection: $selection) }
    .scrollEdgeEffectStyle(.hard, for: .bottom)               // iOS 26.0+
```

Notes that decide whether this looks native or broken:
- **One** `GlassEffectContainer` for the whole bar (glass cannot sample glass across containers).
- `.interactive()` on tappable items only; it is what produces the tap/scale/shimmer response.
- `.regular`, never `.clear`, and don't stack another material on top of the bar.
- `ConcentricRectangle` with the `.containerConcentric` corner if the bar is pinned to a sheet/window
  corner, so radii stay concentric (HIG requirement for custom bar components).
- Hide the real tab bar with `.toolbar(.hidden, for: .tabBar)` on the tab contents, or use a plain
  `ZStack` root instead of `TabView` — but then you lose `Tab(role: .search)` integration and the
  system's search field.
- Re-implement what `TabView` gave you: keyboard `⌘1…⌘5`, VoiceOver `.isSelected`, iPad pointer
  hover, Dynamic Type, and split-view/Stage Manager safe-area changes.

**Trade-offs to accept explicitly** (this is why it is P1, not P0): no sidebar morph, no tab
customization, no minimize-on-scroll, no search-tab field replacement, no automatic
top-bar/title/focus-scope behaviour, and it diverges from the platform pattern users know on iPad.
**Judgement:** ship native `TabView` first, then decide with a real iPad build in hand.

**Sources:** as P0-2, plus https://developer.apple.com/design/human-interface-guidelines/tab-bars

---

### P1-2. Secondary windows for account detail (iPad only, multi-window)

**API**

```swift
// Scene
WindowGroup(id: "account", for: UUID.self) { $accountID in
    AccountDetailView(accountID: accountID)
}
.defaultSize(width: 520, height: 640)          // iOS 17.0+
.windowResizability(.contentMinSize)           // iOS 17.0+

// Opening
@Environment(\.openWindow) private var openWindow   // iOS 16.0+
openWindow(id: "account", value: account.id)
```

- One `ModelContainer` shared: attach `.modelContainer(container)` at each scene root, sharing the
  instance built in `MontraApp.init()`. Do not build a second container — two containers on one store
  file is the classic SwiftData corruption/duplicate-schema trap.
- `@Query` reads per scene; SwiftData notifies across scenes on the same container automatically.
- State restoration: `@SceneStorage` for the selected route/window payload; `scenePhase` for flush
  and analytics.
- `NSUserActivity` / handoff is optional; skip unless continuity is requested.

**Montra application.** Account detail (`AccountDetailView`) is the ideal second window: users
compare an account against Overview or Analytics. Also good for `TransferDetailSheet` on iPad.
Wire the *existing* sheet to open a window instead when `horizontalSizeClass == .regular`:
`.sheet` on iPhone, `openWindow` on iPad. Note that `Window` scene and
`defaultWindowPlacement` are **unavailable on iOS** — do not use them.

**Sources**
- https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow
- https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)
- https://developer.apple.com/documentation/swiftui/scene/defaultsize(_:)
- https://developer.apple.com/videos/play/wwdc2025/208/

---

### P1-3. Hardware keyboard: real `commands` on iPad, replacing the `NotificationCenter` bus

**API**

```swift
.commands {
    CommandGroup(replacing: .newItem) {
        Button("New operation") { router.newOperation() }
            .keyboardShortcut("n", modifiers: .command)      // existing behaviour, kept
    }
    CommandMenu("Go") {
        Button("Overview") { router.select(.overview) }.keyboardShortcut("1")
        // …
    }
}
```

- `commands` / `CommandGroup` / `CommandMenu` — long-standing; on iPadOS 26 **every** app gets a
  menu bar (reveal by pointer to the top edge or swipe down), so `commands` is now a first-class iPad
  surface, not a Mac-only nicety.
- `keyboardShortcut(_:modifiers:)` on views — iOS 15+; on `Scene` too.
- `FocusState` / `.focused(_:)` — iOS 15+; `.focusable(_:interactions:)` for custom focusable
  regions; `.focusSection` for arrow-key navigation between columns.
- `ToolbarItem(placement: .keyboard)` (**verified present in the iOS SDK**) for the keyboard
  accessory bar — useful for the amount field in `OperationSheet` (prev/next/Done).
- **iOS 27 additions worth knowing:** `visibilityPriority(_:)` on toolbar content (keep Undo/Redo
  visible when the resizable window gets narrow) and `ToolbarOverflowMenu` (force low-frequency
  actions into the overflow rather than letting them crowd the bar). Both are iOS 27.0+, so
  `#available`.

**Montra application.** The eight existing shortcuts (`⌘N`, `⇧⌘N`, `⌘1…⌘4`, `⌘,`) currently post
`Notification.Name`s. Port them to a `FocusedValue`/router so they work per-window on iPad — with
multiple windows, a global notification would act on whichever scene posts last. Keep `⌘N` as the
one shortcut users will actually use, and add `⌘F` for the search tab.

**Sources**
- https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:)
- https://developer.apple.com/documentation/swiftui/view/focusable(_:interactions:)
- https://developer.apple.com/videos/play/wwdc2025/208/ (iPad menu bar)
- https://developer.apple.com/videos/play/wwdc2026/269/ (visibilityPriority, ToolbarOverflowMenu)

---

### P1-4. Pointer polish: `hoverEffect` (not `pointerStyle`)

- `hoverEffect(_:isEnabled:)` — **iOS 18.0+**, macOS unavailable. iOS 26 gives the *new* highlight: a
  liquid glass platter that materialises over the hovered control and refracts what's beneath it
  (WWDC25/208). `.hoverEffect(.automatic)` on rows/cards is enough; `.highlight`/`.lift` are the
  stock variants, and `HoverEffectGroup` coordinates a set of controls.
- **`pointerStyle` does not exist on iOS.** Verified: it appears only in the macOS SwiftUI
  interface. Do not plan custom pointer shapes for iPad.
- Secondary click: iPadOS maps a trackpad/mouse right-click to the same `contextMenu` path
  (`.contextMenu` / `contextMenu(forSelectionType:)`), so existing long-press menus come along free.

**Montra application.** `hoverEffect(.automatic)` on transaction rows and account rows; the platter
does the visual work and matches the glass bar. No custom pointer cursors.

**Sources**
- https://developer.apple.com/documentation/swiftui/view/hovereffect(_:)
- https://developer.apple.com/videos/play/wwdc2025/208/

---

### P1-5. Drag & drop, multi-select, share/import/export

- `draggable(_:)` / `dropDestination(for:action:isTargeted:)` + `Transferable` — iOS 16.0+.
  Montra's natural transferables: an `Operation` (drag a row onto a category in the Categories tab to
  re-categorise), and an `Account` (drag into another window). Make `Operation` a `Transferable`
  via a `Codable` representation.
- Multi-select: `List(selection:)` with `Set<UUID>` + `EditMode`, or the iOS 16 `List(selection:)`
  two-way binding. This is the correct replacement for `DeleteOperationsSheet` on iPad: select many,
  delete once. Keep the sheet for iPhone.
- `ShareLink` — iOS 16.0+: share an analytics report or an account statement as CSV/PDF.
- `fileExporter` / `fileImporter` — iOS 14.0+: `BackupRestoreSheet` already produces a `.montra`
  archive; on iOS these map to the Files app and should replace any macOS `NSSavePanel` logic.
- iOS 27 adds **reorderable container** APIs beyond `List` (List *and* `LazyVGrid`), plus the
  item-binding pattern for `confirmationDialog`/`alert` (WWDC26/269). Useful if account or category
  ordering becomes user-editable.

**Sources**
- https://developer.apple.com/documentation/swiftui/view/draggable(_:)
- https://developer.apple.com/documentation/swiftui/view/dropdestination(for:action:istargeted:)
- https://developer.apple.com/documentation/swiftui/sharelink
- https://developer.apple.com/videos/play/wwdc2026/271/ ("Code-along: Build powerful drag and drop in SwiftUI")

---

### P1-6. Swift Charts: selection and popovers in Analytics

**API** (verified in the iOS 27 `Charts` interface): `chartXSelection(value: Binding<P?>)`,
`chartXSelection(range:)`, `chartYSelection(value:)`, `chartYSelection(range:)`, plus
`chartOverlay`/`chartBackground` for hit-testing and `.chartGesture`. `chartXSelection` is iOS 16.0+.

**Montra application.** `AnalyticsPaceChart` becomes interactive on iPad: drag across the pace line,
show a floating annotation/popover with the date and amount, and let the Overview cards follow the
selection. On iPad the pointer makes this genuinely useful; on iPhone it is a touch scrub. Keep the
existing static rendering as the accessibility fallback (`accessibilityLabel` describing the trend)
because a selection-driven chart is not VoiceOver-navigable by default.

**Sources**
- https://developer.apple.com/documentation/charts
- https://developer.apple.com/documentation/swiftui/view/chartoverlay(alignment:content:)

---

### P1-7. App Intents, Shortcuts, Siri and Spotlight for "new operation"

Montra already has App Intents (`SpotlightActions`, `SpotlightEntities`, `SpotlightLedger`) — port
them rather than reinventing:

- `AppIntent` + `AppShortcutsProvider` — iOS 16.0+; `AppShortcut` exposes phrases with no user setup.
  This is how "Hey Siri, add an expense to Montra" and the Shortcuts app action work.
- `IndexedEntity` — **iOS 18.0+**, the modern way to feed Spotlight from App Intents (replaces
  hand-rolled `CSSearchableItem` indexing). Montra's `SpotlightLedger` should move to
  `IndexedEntity`/`IndexedEntityQuery` so tapping a Spotlight result opens the right account or
  operation.
- Donation: `IntentDonationManager` / `donate()` so Siri surfaces "new operation" at the right time
  of day. WWDC26/343 and /345 cover the current best practice; /295 covers testing with
  `AppIntentsTesting`.
- Deep link the intent result into the tab router (`openURL`/`onOpenURL` → `Route`).

**Judgement:** this is high value for a finance app (quick capture is the main mobile use case) and
low cost because the intents exist. Do it before widgets.

**Sources**
- https://developer.apple.com/documentation/appintents/indexedentity
- https://developer.apple.com/videos/play/wwdc2026/345/ ("Discover new capabilities in the App Intents framework")
- https://developer.apple.com/videos/play/wwdc2026/343/ ("Explore advanced App Intents features for Siri")
- https://developer.apple.com/videos/play/wwdc2026/310/ ("What's new in Shortcuts")

---

### P1-8. Widgets and Control Center

- **WidgetKit** home screen + lock screen widgets: iOS 14+/16+; `WidgetKit foundations` (WWDC26/277)
  is the current reference. Best Montra widgets: (a) *Balance* (small/medium, per account), (b)
  *This month* (spend vs budget), (c) lock-screen accessory (balance or "remaining this month").
  Widgets read SwiftData through a shared App Group container or an App Intents-backed snapshot —
  decide storage early, because a widget cannot read the app's private container.
- **`ControlWidget`** — **iOS 18.0+** (verified: declared in the SwiftUI module,
  `ControlWidgetConfiguration`/`StaticControlConfiguration`/`AppIntentControlConfiguration`). A
  Control Center "New operation" toggle/button that opens `OperationSheet` is a genuinely nice
  iPadOS 26 surface. Requires an `AppIntent`, which P1-7 gives you.
- **StandBy** is iPhone-only and lock-screen based — **P3** for a finance app.

**Sources**
- https://developer.apple.com/documentation/widgetkit
- https://developer.apple.com/documentation/swiftui/controlwidget
- https://developer.apple.com/videos/play/wwdc2026/277/ ("WidgetKit foundations")

---

## 4. P2 — nice to have, low cost

| # | Capability | API + availability | Montra fit |
|---|---|---|---|
| P2-1 | Prominent tab treatment | `Tab(role: .prominent)` — **iOS 27.0+** (verified). Doc: "provides prominent visual treatment to one of the tabs in supported tab bars. Only one tab can receive the prominent treatment. When there are no tabs with an explicit `.prominent` role, then a `.search` role tab may receive the prominent visual treatment by default." | Tempting for "New operation", but HIG says a tab bar is for **navigation, not actions**, and only one tab can be prominent — if you use it for `+` you cannot also use it for search. **Judgement: skip in v1**; keep `+` as a toolbar primary action. Revisit only if the tab bar becomes the product's identity. |
| P2-2 | User-customisable tabs | `TabViewCustomization` (iOS 18.0+), `.tabViewCustomization(_:)`, `.customizationBehavior(_:for:)`, `.defaultVisibility(_:for:)` | With 8 sections, letting iPad users pin Categories/Savings into the bar is a real win and is the HIG-blessed answer to "too many sections". Needs `Codable` persistence. |
| P2-3 | Bottom accessory (iPhone) | `tabViewBottomAccessory { }` — **iOS 26.0+**, iPhone-oriented; read `\.tabViewBottomAccessoryPlacement` to adapt when it collapses | A "quick add" row above the bottom bar on iPhone (e.g. amount field + save). Nice, but overlaps P1-7's intent-based quick capture. |
| P2-4 | Glass morph from control → sheet | `glassEffectID` + `glassEffectTransition(.matchedGeometry)`, combined with `matchedTransitionSource`/`navigationTransition(.zoom)` | Make the "New operation" button *become* the sheet. Polish, cheap once detents exist. |
| P2-5 | Content extension under bars | `backgroundExtensionEffect()` — iOS 26.0+ | Analytics heat map and Overview hero can bleed under the glass bar/top bar — this is the modifier that makes it look intentional instead of clipped. |
| P2-6 | Search tab + field behaviour | `Tab(role: .search)` (iOS 18.0+), `.searchable`, `searchToolbarBehavior(_:)` (iOS 26.0+) | On iPad/Mac, selecting the search tab replaces the tab bar area with a search field. Gives global search over operations/accounts without a tab slot. |
| P2-7 | Menu bar refinements | `labelStyle(.titleAndIcon)` on menu items (iOS 27.0+; iPad menu bars now show a *minimal* icon set by default), `visibilityPriority(_:)`, `ToolbarOverflowMenu` | Keeps Montra's `Integration` menu discoverable without cluttering a resizable iPad menu bar. |
| P2-8 | Inactive-window dimming | `\.appearsActive` environment value — **iOS 27.0+** | iPad shows inactive windows with dimmed icons/text automatically; custom chrome (the glass bar) must opt in by dimming when `appearsActive == false`, or it looks "live" while the window is not. Small, but the omission is visible on iPad. |
| P2-9 | Scribble in text fields | Automatic for `TextField` — no API | Amount/notes fields get Apple Pencil handwriting for free. Just don't build a custom text input that bypasses `TextField`. |

**Sources**
- https://developer.apple.com/documentation/swiftui/tabrole/prominent
- https://developer.apple.com/documentation/swiftui/tabviewcustomization
- https://developer.apple.com/videos/play/wwdc2026/269/
- https://developer.apple.com/videos/play/wwdc2026/292/ ("Design intuitive search experiences")

---

## 5. P3 — skip, with reasons

| Capability | Why skip |
|---|---|
| **PencilKit** (`PKCanvasView`) | No drawing domain in a ledger. Scribble (free, P2-9) covers the actual Pencil use case. WWDC26/203 is a great session, irrelevant here. |
| **Live Activities / Dynamic Island** | Designed for ongoing, time-bounded events. A budget tracker has no live session; an "operation in progress" activity would be noise and would be rejected as inappropriate use. |
| **StandBy** | iPhone-only and glance-oriented; the lock-screen widget (P1-8) covers the same need better. |
| **`pointerStyle`** | Not available on iOS — verified absent from the iOS SwiftUI interface (macOS only). |
| **`Window` scene / `defaultWindowPlacement`** | Not available on iOS (macOS/visionOS only). `WindowGroup` + `windowResizability` is the iPad path. |
| **visionOS / spatial** | Out of scope for the port. |
| **Porting `LocalHTTPServer` + MCP to iOS** | Loopback-only server is a desktop integration; iOS suspends the listener, and shipping an unused local API server on iOS is pure review risk. Keep macOS-only. |
| **Bottom-tab-bar via size-class hacks** (e.g. forcing `.compact` horizontal size class to make `TabView` render bottom on iPad) | Unsupported and fragile: it changes layout semantics the whole app then inherits, and it can regress with OS updates. If a bottom bar is required, build it honestly (P1-1). |
| **Custom `presentationBackground` glass for sheets** | Counterproductive on iOS 26: the system already gives sheets the inset Liquid Glass material, and a custom background suppresses it. |
| **External display support** | No clear Montra use case; add only if "present the dashboard on a projector" becomes a request. |

---

## 6. Risks and pitfalls

**Navigation**
1. **No bottom tab bar on iPad, by design.** `AdaptableTabBarPlacement` has no `.bottom`, and
   `defaultTabBarPlacement(_:)` is documented as a no-op on iPadOS. Any plan that assumes a system
   bottom bar on iPad will not compile into the expected result. Budget for P1-1 if the design
   insists.
2. **A custom bottom bar is not a tab bar.** It loses sidebar morphing, tab customization,
   minimize-on-scroll, search-tab field replacement, and system focus/keyboard ordering. It also must
   re-implement `⌘1…⌘5`, `.isSelected`, hover, and Dynamic Type. It is the highest-effort,
   highest-regression item in this report — **do not** start there.
3. **Overflow.** 8 destinations will not fit. Resolve the information architecture (Decision B)
   before writing view code, not after.
4. `tabBarMinimizeBehavior` explicit values are **iOS-only** (`.onScrollDown/.onScrollUp/.never` are
   marked unavailable on macOS/tvOS/watchOS/visionOS); `.automatic` is the portable one.

**Liquid Glass**
5. **Glass on glass** is the most common way this design fails. Bottom bar + sheet with its own
   material + a glass FAB = three stacked materials. Pick one floating layer per surface.
6. **`.clear` is wrong for Montra.** It needs media-rich content underneath and a dimming layer to
   stay legible; there is no such content in a ledger. Mixing `.regular` and `.clear` is explicitly
   called out as something never to do.
7. **Glass can't sample glass across containers** — nearby glass in different `GlassEffectContainer`s
   renders inconsistently. Use one container per floating cluster.
8. **Reduce Transparency changes the look substantially** (frostier, more obscuring) — verify the
   bottom bar and sheets with it on, and again with Increase Contrast (black/white + border).
9. **Tint everything = hierarchy gone.** One tinted element, maximum (the primary add action).

**Sheets**
10. **iPad regular width presents sheets as form sheets**, not bottom sheets; `presentationDetents`
    matters most in compact. Decide per sheet: `.presentationSizing(.form)` for iPad cards, and
    verify drag-dismiss still makes sense at regular width.
11. **Delete existing custom sheet backgrounds** when adopting iOS 26 — they suppress the new
    material and will look like a bug next to system sheets.
12. **One sheet at a time** (HIG). Check `OperationSheet` → `CategorySheet`/`AccountSheet` chains:
    close the first before presenting the second.

**Windows / scenes**
13. **`Window` and `defaultWindowPlacement` are not on iOS.** Verified in the SDK. Many blog posts
    assume otherwise.
14. **One `ModelContainer`.** A second container over the same store is the classic SwiftData bug;
    share the instance from `MontraApp.init()` into every scene.
15. **Remove the fixed 980pt width and `WindowConfigurator`** from the iOS target or Split View and
    Stage Manager break.

**Availability / platform**
16. **Deployment target is already 26.0**, so iOS 26 APIs need no guards — but anything marked 27.0
    (`TabRole.prominent`, `defaultTabBarPlacement`, `visibilityPriority`, `ToolbarOverflowMenu`,
    `appearsActive`) **does** need `#available(iOS 27.0, *)`.
17. **`hoverEffect` is unavailable on macOS** in the iOS-flavoured API and `pointerStyle` is
    unavailable on iOS — don't write one shared modifier that assumes either.
18. **`UIRequiresFullScreen` is deprecated as of 26.0** — adding it to force a full-screen iPad app
    is both deprecated and against the iPadOS 26 direction.

**Review**
19. An unused `aps-environment` entitlement, an unused purpose string, or a shipped-but-idle local
    server are the three most likely review questions for this port.
20. A custom bottom bar that is also the action bar conflicts with "use a tab bar to support
    navigation, not to provide actions".

---

## 7. Testing / QA on the simulator (and what differs from macOS)

Montra currently verifies behaviour with an in-process `-selftest` plus a `SnapshotRunner` that
renders SwiftUI views and uses `screencapture`/`NSView`. **That harness does not port**: there is no
AppKit, no `screencapture -R`, and no reliable way to rasterise a live window from inside the app on
iOS. Plan a parallel iOS path.

**Baseline commands** (verified against this machine: Xcode 27, iPad Pro 13-inch (M5) and iPhone 17
Pro Max simulators present):

```bash
# Discover / boot
xcrun simctl list devices available
xcrun simctl boot "iPad Pro 13-inch (M5)"

# Install + launch, capturing stdout
xcrun simctl install booted <path>/Montra.app
xcrun simctl launch --console-pty booted app.finance.montra

# Screenshots (replaces screencapture)
xcrun simctl io booted screenshot /tmp/montra-ipad.png

# Environment overrides for accessibility passes
xcrun simctl launch booted app.finance.montra
#   then Settings > Accessibility, or use XCUITest launch arguments:
#   -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
#   -AppleLanguages (ru)  -AppleLocale ru_RU     (localization: ru/en are in Localizable.xcstrings)
```

**UI tests** (XCTest / XCUITest):
- `XCUIApplication()`, `launchArguments`, `launchEnvironment` for deterministic fixtures — reuse the
  `-snapshot` / in-memory container idea from `MontraApp.init()` so tests never touch the real store.
- `performAccessibilityAudit()` catches contrast, hit-target and Dynamic Type issues automatically;
  this is the cheapest way to validate the custom glass bar.
- Prefer `accessibilityIdentifier` over label strings, since labels are localized (ru/en).
- Multi-window and Stage Manager scenarios are best verified by hand on a simulator/iPad: resize the
  window, rotate, enter Split View, and confirm the glass bar keeps its insets and that content does
  not clip under it.

**What "native" looks like when you verify** (vs the macOS build): the tab bar floats and morphs on
selection; a partial sheet is inset with glass and its bottom corners pull in; scrolling under a bar
produces an edge effect rather than a hard line; hovering a row with a trackpad produces a platter
highlight. If any of those is missing, a custom background or a missing modifier is usually the cause.

**Sources**
- https://developer.apple.com/documentation/xcode/testing
- https://developer.apple.com/documentation/xctest
- https://developer.apple.com/videos/play/wwdc2026/260/ ("Get the most out of Device Hub")

---

## 8. Coverage check against the requested topics

| Requested area | Where |
|---|---|
| 1. Liquid Glass SwiftUI APIs (glassEffect, containers, tabs, toolbars, sheets, search, custom bars) | P0-1, P0-2, P0-3, P1-1, P2-4, P2-6 |
| 2. Where the iPad tab bar appears; bottom placement; official pattern; HIG-acceptable custom approach | §1 Decision A, P0-1, P1-1, Risks 1–4 |
| 3. Multi-window / Stage Manager / scenes / shared SwiftData / restoration | P0-4, P1-2, Risks 13–15 |
| 4. iPad productivity: keyboard, focus, pointer, context menus, menu bar, accessory, drag & drop, multi-select, share/import/export | P1-3, P1-4, P1-5 |
| 5. Apple Pencil & touch: Scribble, PencilKit, targets, secondary click | P2-9, P3 (PencilKit), P0-6 (targets), P1-4 (secondary click) |
| 6. Widgets, Control Center, App Intents/Shortcuts/Siri, Spotlight, Live Activities | P1-7, P1-8, P3 (Live Activities, StandBy) |
| 7. Swift Charts selection/popovers | P1-6 |
| 8. Review & HIG requirements (privacy manifest, permissions, iCloud, disclosures, icons, launch, orientations, multitasking) | P0-4, P0-5, Risks 19–20 |
| 9. Accessibility incl. how Liquid Glass handles Reduce Transparency etc. | P0-6, P2-8 |
| 10. Simulator testing/QA, native-vs-macOS verification | §7 |

---

## 9. Suggested implementation order

1. **P0-4 + P0-1 skeleton**: strip macOS window code from the iOS target, stand up `TabView` with
   five tabs + search, confirm top bar on iPad / bottom bar on iPhone. This is a day, and it de-risks
   everything (it tells you immediately whether the design needs P1-1 at all).
2. **P0-3 sheets**: delete custom backgrounds, add detents/sizing per sheet, add zoom transitions.
3. **P0-2 glass on the remaining custom surfaces** (FAB, hero controls), obeying the layering rules.
4. **P0-5 + P0-6**: privacy manifest, entitlements, icon/launch/orientations, then the accessibility
   audit pass.
5. **P1-3 + P1-7**: keyboard/commands router, then App Intents + Spotlight. Highest user value per
   line of code.
6. **P1-2 windows**, then P1-6 charts, P1-5 drag/drop + multi-select, P1-8 widgets.
7. Only now decide on **P1-1** (custom bottom bar) with a build in hand.

---

## 10. Sources

Apple documentation (all verified to resolve):
- Liquid Glass: [glassEffect](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) · [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) · [Glass](https://developer.apple.com/documentation/swiftui/glass) · [glassEffectID](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)) · [scrollEdgeEffectStyle](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)) · [backgroundExtensionEffect](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()) · [ConcentricRectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle)
- Navigation: [sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable) · [tabBarOnly](https://developer.apple.com/documentation/swiftui/tabviewstyle/tabbaronly) · [tabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)) · [TabRole.search](https://developer.apple.com/documentation/swiftui/tabrole/search) · [TabRole.prominent](https://developer.apple.com/documentation/swiftui/tabrole/prominent) · [defaultAdaptableTabBarPlacement](https://developer.apple.com/documentation/swiftui/view/defaultadaptabletabbarplacement(_:)) · [defaultTabBarPlacement](https://developer.apple.com/documentation/swiftui/view/defaulttabbarplacement(_:)) · [TabViewCustomization](https://developer.apple.com/documentation/swiftui/tabviewcustomization)
- Sheets: [presentationDetents](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)) · [PresentationSizing](https://developer.apple.com/documentation/swiftui/presentationsizing) · [presentationBackground](https://developer.apple.com/documentation/swiftui/view/presentationbackground(_:)) · [presentationCornerRadius](https://developer.apple.com/documentation/swiftui/view/presentationcornerradius(_:))
- Scenes/input/data: [windowResizability](https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)) · [defaultSize](https://developer.apple.com/documentation/swiftui/scene/defaultsize(_:)) · [openWindow](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow) · [keyboardShortcut](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:)) · [focusable](https://developer.apple.com/documentation/swiftui/view/focusable(_:interactions:)) · [hoverEffect](https://developer.apple.com/documentation/swiftui/view/hovereffect(_:)) · [draggable](https://developer.apple.com/documentation/swiftui/view/draggable(_:)) · [dropDestination](https://developer.apple.com/documentation/swiftui/view/dropdestination(for:action:istargeted:)) · [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink) · [Charts](https://developer.apple.com/documentation/charts) · [WidgetKit](https://developer.apple.com/documentation/widgetkit) · [ControlWidget](https://developer.apple.com/documentation/swiftui/controlwidget) · [IndexedEntity](https://developer.apple.com/documentation/appintents/indexedentity)
- Review/plist: [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) · [Required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) · [UIRequiresFullScreen (deprecated 26.0)](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen) · [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Human Interface Guidelines:
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) · [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) · [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)

WWDC sessions:
- [WWDC25/219 — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25/323 — Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [WWDC25/208 — Elevate the design of your iPad app](https://developer.apple.com/videos/play/wwdc2025/208/)
- [WWDC25/356 — Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [WWDC26/269 — What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)
- [WWDC26/277 — WidgetKit foundations](https://developer.apple.com/videos/play/wwdc2026/277/)
- [WWDC26/345 — Discover new capabilities in the App Intents framework](https://developer.apple.com/videos/play/wwdc2026/345/)
- [WWDC26/343 — Explore advanced App Intents features for Siri and Apple Intelligence](https://developer.apple.com/videos/play/wwdc2026/343/)
- [WWDC26/310 — What's new in Shortcuts](https://developer.apple.com/videos/play/wwdc2026/310/)
- [WWDC26/292 — Design intuitive search experiences](https://developer.apple.com/videos/play/wwdc2026/292/)
- [WWDC26/271 — Code-along: Build powerful drag and drop in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/271/)
- [WWDC26/274 — What's new in SwiftData](https://developer.apple.com/videos/play/wwdc2026/274/)
- [WWDC26/220 — Refine accessibility for custom controls](https://developer.apple.com/videos/play/wwdc2026/220/)

### Confidence notes

- **Verified in the installed iOS 27 SDK** (signature + availability): every API name, modifier
  signature and `@available` version in §2–§4. Notably: `TabRole.prominent` is iOS **27.0**;
  `Window` scene and `defaultWindowPlacement` are **unavailable on iOS**; `pointerStyle` is
  **macOS-only**; `tabViewBottomAccessory` is iOS **26.0**; `AdaptableTabBarPlacement` has **no**
  bottom case.
- **Verified via HIG text**: iPad tab bar "near the top", iOS tab bar bottom, tab bars are for
  navigation not actions, one sheet at a time.
- **Verified via WWDC transcripts**: sheet inset/material behaviour on iOS 26, remove custom
  `presentationBackground`, glass-on-glass prohibition, `.regular` vs `.clear` conditions, automatic
  Reduce Transparency / Increase Contrast / Reduce Motion handling, iPad menu bar, new pointer
  highlight.
- **Judgement, flagged inline**: 5-tab information architecture, keeping Savings inside Accounts,
  deferring `TabRole.prominent`, and the P1-1 "build native first" sequencing.
- **Not verified**: the exact visual result of combining a custom `safeAreaInset` bar with
  `.toolbar(.hidden, for: .tabBar)` inside a `TabView` — worth a 30-minute spike before committing
  to P1-1.
