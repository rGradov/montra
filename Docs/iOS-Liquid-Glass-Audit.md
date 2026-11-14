# iOS / iPadOS Liquid Glass audit

Static audit of where Montra uses real Liquid Glass, where it paints its own
opaque chrome instead, and which additional places would genuinely benefit.
Read-only: no `xcodebuild`, no simulators, no rendering. Evidence is the source
plus the existing captures in `Docs/screenshots/ios-port/`, `build/check2/` and
`build/check4/`.

Line numbers are from the working tree at the time of writing; the tree was being
edited while this was written. Cite the symbol names given (they are stable) if a
number has moved.

Verdict in one paragraph: the port uses Liquid Glass **once** — the iPad bottom
bar — and the iPhone tab bar for free. Everything else (page header, every
sheet, every card, every control) is an opaque custom surface. That is mostly
*correct*: Liquid Glass belongs to the navigation layer that floats over moving
content, and most of Montra is a content layer. There are only **three** places
left where glass is both legitimate and visible, and one of them is a fix to the
glass we already ship. Glassing the dozen candidates I reject in §5.1 would
produce exactly the "glass demo" the brief warns about.

---

## 1. Inventory: what is real glass today

### 1.1 Real Liquid Glass (two glass surfaces, one scroll edge)

| Surface | Where | Notes |
|---|---|---|
| iPhone bottom tab bar | `Montra/Features/Navigation/IOSNavigationShell.swift:136-145` (`TabView`/`Tab`, `.tabBarMinimizeBehavior(.onScrollDown)` at `:144`) | System-drawn. Nothing to add; replacing it with custom glass would be a regression. |
| iPad bottom bar | `IOSNavigationShell.swift:156-179` (mount) and `:225-311` (`GlassTabBar`) | `GlassEffectContainer(spacing: 4)` at `:254`, one `glassEffect(.regular…)` capsule per item at `:289-294`, `glassEffectID` at `:295`, selected item tinted `accent.opacity(0.16)` at `:291`. |
| iPad bottom scroll edge | `IOSNavigationShell.swift:178` `.scrollEdgeEffectStyle(.hard, for: .bottom)` | Correct: content passing under the custom bar gets a defined edge. |

There is no `Material`, `ultraThinMaterial` or `.thin` anywhere in the app
(`grep` finds none), and no `presentationBackground` (`BottomSheetHost.swift:4-8`
says so explicitly, deliberately). `glassEffect` appears in exactly one file.

### 1.2 Opaque custom surfaces (the rest)

| Surface | Where | Kept opaque deliberately? |
|---|---|---|
| Page header (title, subtitle, back row, trailing actions) | `Montra/Design/DetailHeader.swift:27-52`, opaque fill at `:51` | **Yes — see §7.** It is a large-title area, not a control bar. |
| Shell / page backgrounds | `IOSNavigationShell.swift:97,193,206`; `OverviewView.swift:99`; `OperationsView.swift:390`; `AnalyticsView.swift:275,292`; `SettingsView.swift:73` | Yes — page ground. |
| 9 of 10 sheet views paint `surfaceBase` over the sheet | `OperationSheet.swift:288`, `AccountSheet.swift:124`, `CategorySheet.swift:137`, `ICloudSheet.swift:80`, `PeriodsSheet.swift:95`, `PlanActionSheet.swift:98`, `TransferDetailSheet.swift:87`, `BackupRestoreSheet.swift:49`, `DeleteOperationsSheet.swift:134,341` | Contested — §3 P2-3. |
| `AboutSheet` (no background painted) | `AboutSheet.swift:3-8` (comment), `:15-31` | It is the **outlier**, see §1.3. |
| `SheetFooter` band + hairline | `Montra/Design/Forms.swift:42-58`, fill at `:51`, hairline `:52-56` | Yes — the footer has no scrolling content behind it. |
| Cards (`OverviewCard`, `InsetCard`, rows, hero, balance bar) | `Components.swift:178-208`; `OverviewView.swift:155-225,316-377,421-454,473-509` | Yes — HIG forbids glass on the content layer. |
| Pills and controls (`MontraButtonStyle`, `FilterChip`, `CapsuleSearchField`, analytics scope control) | `Components.swift:10-165,427+`; `CapsuleSearchField.swift:82-93`; `AnalyticsView.swift:734-756` | Yes — controls on an opaque band. |
| Analytics day callout | `AnalyticsView.swift:2081-2115` (`surfaceRaised` + shadow) | Yes — it carries figures. |

### 1.3 Measurements that decide two open questions

Sampled from the existing PNGs (dark appearance, values are sRGB):

| Sample | RGB | Meaning |
|---|---|---|
| `AppColors.surfaceBase` (dark) | 23,22,21 | `Theme.swift:16` |
| `AppColors.fillSecondary` (dark) | 40,39,37 | `Theme.swift:22` — the big cards, not the sheet |
| iCloud sheet body | 23,22,21 exactly | app-painted `surfaceBase` (`ICloudSheet.swift:80`) |
| Periods sheet body | 23,22,21 exactly | app-painted (`PeriodsSheet.swift:95`) |
| iPad "New operation" form card interior | 23,22,21 exactly | app-painted (`OperationSheet.swift:288`) |
| Page behind an open sheet | 12,11,11 | page dimmed by the presentation scrim |
| **`AboutSheet` body** (the only sheet with no painted fill) | **28,28,30** | `#1C1C1E`, the system's *cool* background — **not** a visible glass layer |
| iPad bar, unselected capsules | rim ≈1 px lighter, interior == page (23,22,21) | at rest there is no content behind the bar, so only the glass rim is visible |

Two consequences, both used below:

1. **"Delete the sheet background to let the iOS 26 material shine" is not a
   win here.** The system surface a sheet gets is `#1C1C1E` — cool and flatter
   than Montra's warm `#171615`, and behind a sheet the page is static and
   dimmed to near-uniform black, so a material would have nothing to sample.
   The gain is a rim; the cost is a palette break. Do **not** strip the other
   nine sheets (§5.1, rejection 11).
2. **The one glass surface Montra does ship reads as five hairline outlines**,
   because the bar floats over an empty page area at rest: the capsule fill is
   indistinguishable from `surfaceBase`; only the ~1 px light rim and the tinted
   selection are visible. Fixing that is where the "where is the glass?"
   complaint actually comes from (§3, P0).

---

## 2. What Liquid Glass is for, in this app

The rule set the port adopted (`Docs/Research-iPadOS-Features.md:187-203`) boils
down to: glass is the **floating navigation layer over moving content**; one
`GlassEffectContainer` per cluster; `.regular` only; never glass on glass; tint
once (the primary action); never the content layer.

Applying that literally to Montra leaves very few candidates, because Montra's
chrome is *static bands*: the header is a sibling of the `ScrollView`
(`IOSNavigationShell.swift:187-193`), the filter/search bars on Operations are
siblings too (`OperationsView.swift:273-281`), and sheet footers are siblings of
their scroll views. Nothing moves behind them, so glass there would be a tinted
slab, not glass.

That leaves exactly three clusters with real content behind them:

1. the bottom bar's own floating position (iPad) — already glass, under-rendered;
2. the bottom-trailing corner of the Overview list on iPhone/compact — empty today;
3. the onboarding intro's full-screen glow — controls today are bare glyphs.

---

## 3. Prioritized opportunities

Effort/risk are relative to a single focused change. "iOS-only" means the macOS
target must not change (the Mac keeps its window layout and `MACOSX_DEPLOYMENT_TARGET`,
which cannot use `glassEffect` without an availability guard).

### P0 — the glass we already ship does not read as glass

**P0-1. Give the iPad bar one continuous surface instead of five outlined capsules.**

- File: `Montra/Features/Navigation/IOSNavigationShell.swift:253-310`.
- Problem, from the capture: with `GlassEffectContainer(spacing: AppStyle.Spacing.xxSmall /* 4 */)` at `:254` and `HStack(spacing: 4)` at `:255`, the five capsules sit inside the container's blend distance. On the flat `surfaceBase` area the fill is invisible and each capsule contributes its own rim, so the bar reads as five outlined pills with 4 pt gaps, not as the iPhone's single bar (`build/check4/settings-light.png` bottom shows what the system bar looks like: one capsule, one selection lens).
- Proposed: **one** glass capsule platter, and the selection as a **fill** lens (a fill is not a second material, so this stays inside "no glass on glass"):

```swift
HStack(spacing: 0) {
    ForEach(AppTab.allCases) { tab in item(tab) }   // item(): no glassEffect of its own
}
.padding(AppStyle.Spacing.xxSmall)
.glassEffect(.regular, in: .capsule)                // iOS/iPadOS 26 — one surface
```

  `GlassEffectContainer` then has a single child and adds nothing; drop it (it only
  returns if a selection morph is added later).

  and inside `item(_:)`, replace `.glassEffect(...)` with a selection fill:

```swift
.background {
    if isSelected {
        Capsule(style: .continuous).fill(AppColors.accent.opacity(0.16))
    }
}
```

- Cheaper alternative if the platter is too much churn: keep per-item glass but
  set the container's blend distance below the gap — `GlassEffectContainer(spacing: 0)`
  at `:254` and `HStack(spacing: AppStyle.Spacing.xSmall /* 8 */)` at `:255` — so
  the rims stay visibly separate. This is a two-constant change and keeps the
  `glassEffectID` morph on `:295`.
- Trade-off to accept: a single platter cannot be `.interactive()` per item, so
  keep `.hoverEffect(.automatic)` (`:296`) and add a pressed fill. The rest of
  the item plumbing (44 pt `@ScaledMetric` targets `:232-247`, captions dropped at
  accessibility sizes `:240`, VoiceOver label/selected traits `:297-300`, context
  menu `:301-309`) is correct and must survive verbatim.
- Platform: iOS/iPadOS only. No new API beyond what is already used.

### P1 — one genuinely missing piece of glass

**P1-1. Floating quick-add on Overview (iPhone and compact iPad).**

- New view; mounted in `Montra/Features/Overview/OverviewView.swift` next to the
  existing `body` (`:87-106`), applied to the `ScrollView`.
- Why here: it is the only screen position where a control can sit over rows that
  scroll, so the material has something to refract. It is also the iOS 26 pattern
  for a create action (Reminders / Mail style floating button above the tab bar),
  and it puts the app's one primary action under the thumb instead of at the top
  of the screen.
- Shape and placement: bottom-trailing capsule, ~48 pt tall, 24 pt trailing
  (`AppDetailPageLayout.horizontalInset`), 12 pt above the tab bar safe area.
  Mount with `safeAreaInset` so the last card is never covered at rest and rows
  scroll behind it:

```swift
#if os(iOS)
.safeAreaInset(edge: .bottom, spacing: 0) {
    if usesCompactShell {
        HStack {
            Spacer(minLength: 0)
            Button { onNewOperation(nil) } label: {
                HStack(spacing: AppStyle.Spacing.xxSmall) {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.accent)
                    if !accessibilitySize {
                        Text(String(localized: "transaction.new"))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                    }
                }
                .font(AppStyle.Typography.headline)
                .frame(minWidth: 48, minHeight: 48)
                .padding(.horizontal, accessibilitySize ? 0 : AppStyle.Spacing.medium)
            }
            .buttonStyle(.plain)
            .contentShape(.capsule)
            .glassEffect(
                .regular.tint(AppColors.accent.opacity(0.18)).interactive(),
                in: .capsule
            )
            .accessibilityLabel(String(localized: "transaction.new"))
            .accessibilityAddTraits(.isButton)
        }
        .padding(.trailing, AppDetailPageLayout.horizontalInset)
        .padding(.bottom, AppStyle.Spacing.small)
    }
}
#endif
```

- Replaces: the header's "New operation" pill on the Overview tab only —
  `OverviewView.swift:112-123` (`headerTrailing`, the `Button … buttonStyle(.montra(.primary))`
  at `:115-121`), which moves behind `#if !os(iOS)`. Consequence worth having:
  with only the period pill left, the header's `ViewThatFits`
  (`DetailHeader.swift:36-47`) can keep the actions on the title line instead of
  dropping to `stackedRow` (`:110-122`), which removes a whole header row on a phone.
- "Compact shell" is the same condition the shell already uses inline at
  `IOSNavigationShell.swift:90` (`AppPlatform.isPhone || sizeClass == .compact`).
  Extract it once (`AppPlatform` in `Montra/Platform/PlatformSupport.swift:14-37`)
  and use it in both places, so Split View gets the FAB and regular-width iPad does not.
- Do **not** add this on iPad regular width: it would put a second floating
  cluster next to the bottom bar.
- `accessibilitySize` is `@Environment(\.dynamicTypeSize).isAccessibilitySize`
  (`DynamicTypeSize` has it; the bar already relies on the same check at
  `IOSNavigationShell.swift:240`).
- Platform: iOS/iPadOS only. No new localized keys — `transaction.new` already exists.

### P2 — small, contained, optional

**P2-1. Onboarding intro: put the Skip and sound controls on glass.**

- `Montra/Features/Onboarding/OnboardingIntroView.swift:276-303` (`controls`):
  today a bare speaker glyph button at `:279-290` and a plain text "Skip" at
  `:293-302`, over the full-screen glow (`backdrop` `:209-235`).
- This is the one place in the app with rich, non-flat content behind the chrome,
  so glass genuinely refracts. The two controls sit at *opposite ends* of the
  row, so they are not one cluster: two independent
  `.glassEffect(.regular.interactive(), in: .capsule)` views are correct, and a
  `GlassEffectContainer` is only needed if a morph between them is ever added.
  No tint (the tint budget is spent on the FAB), 44 pt minimum target (already
  `IntroControlMetrics.muteSize`).
- Cost/risk: touches a snapshot-covered screen (`-selftest` snapshots and the
  frozen-render path `previewProgress`, `:164-175`), so snapshot review is
  mandatory; the glass must not add animation (Reduce Motion path at `:170-172`).
- Platform: iOS only (`#if os(iOS)`), macOS intro unchanged.

**P2-2. Operations: make the filter/search bar a floating glass bar (restructure).**

- `Montra/Features/Operations/OperationsView.swift:273-281` stacks `filterBar`,
  `plansBar` and `selectAllRow` **above** the `ScrollView` in a `VStack`, so three
  opaque bands (~180 pt on a phone) never have content behind them. The iOS 26
  shape is a single floating glass bar over the rows, with
  `.scrollEdgeEffectStyle(.soft, for: .top)` on the list.
- This is the only other place with moving content behind chrome, but it is a
  layout change, not an additive one: move the bars into a `safeAreaInset(edge: .top)`
  on the `ScrollView`, keep `CapsuleSearchField` (`:584-612`) opaque inside the
  glass bar (a field is not navigation — see §5.1 rejection 6), and re-check the
  pinned day headers (`OperationDateHeader`, `Montra/Features/Operations/OperationDaySection.swift:55`,
  pinned at `OperationsView.swift:288,333`).
- Do it only if the P0/P1 set lands well; it is P2 because it is the one item here
  that can regress scroll behaviour and QA screenshots.

**P2-3. Palette consistency, not glass: `AboutSheet` is the odd one out.**

- `AboutSheet.swift:15-31` paints nothing, so the system gives it `#1C1C1E`
  (measured) while every other sheet and page is the warm `#171615`. Either give
  it the same `AppColors.surfaceBase` as its nine siblings, or leave it and
  accept one cool-toned sheet. Do not "fix" this by stripping the other nine —
  see §1.3 and rejection 11.

---

## 4. HIG constraints and risks, per accepted item

**P0-1 (iPad bar).** One material per cluster: the platter is a single glass
shape (the container becomes redundant), and the spacing alternative keeps one
container with separate shapes.
`.regular` only, never `.clear`: keep. Tint: the selected-item tint is the only
tint on that screen — a platter must not also be tinted, and the fill lens must
stay ≤0.16 opacity so Reduce Transparency (which makes the material frostier and
more opaque) does not turn the lens into a solid blue pill. Selection must remain
double-encoded — the filled `selectedSymbol` (`AppTab.swift:52-58`) plus tint —
because Increase Contrast flattens the material to near-black/white. Touch
targets: 44 pt minimum at every Dynamic Type size (already enforced by the
`min(max(...))` clamps at `IOSNavigationShell.swift:244-247`); the platter must
not shrink the items. VoiceOver: `.accessibilityAddTraits(.isSelected)` and the
`.accessibilityElement(children: .ignore)` pattern must be preserved. Contrast:
text over glass must be `textPrimary`/`textSecondary` (never `textTertiary`, which
is too low on a frostier material).

**P1-1 (Overview FAB).** One tinted primary per screen: enforced by removing the
header pill; if both ever ship, that is a HIG violation ("two primary actions").
Touch target: 48 pt frame, `.contentShape(.capsule)` so the whole glass surface is
tappable — `.glassEffect` does not extend hit testing. Dynamic Type: at
accessibility sizes the label must collapse to the icon (a labelled capsule will
not fit next to the tab bar), and the Accessibility Inspector must still read
"New operation". Contrast: label uses `textPrimary`; only the `plus` glyph carries
`accent` (#0A6ED1 on a light frosted surface is ~4.3:1 — fine for a glyph, not
for body text). Reduce Transparency: the 0.18 tint survives; do not raise it.
Content intersection in steady state: `safeAreaInset` keeps the last card above
the button at rest; rows only pass behind while scrolling, which is the intended
refraction. Reduce Motion: no animation is added (the material's own response is
system-driven). VoiceOver: the sheet it opens is the accessible path to the same
action that the header pill had, so navigation order does not regress.

**P2-1 (onboarding).** Do not glass the "Начать" primary button in the flow's
footer — it sits on an opaque footer bar, and there is already a filled primary
style. The two corner controls only. Keep them reachable at 44 pt and keep the
hidden keyboard shortcuts (`:154-163`) intact.

**P2-2 (Operations).** If the bar goes over the list, the search field's focus
border (`CapsuleSearchField.swift:90-93`) must remain the focus signal, and
`scrollEdgeEffectStyle(.soft, for: .top)` must be added or the first row will
collide with the bar's rim.

---

## 5. Rejections (explicit)

### 5.1 Glass-on-glass and other structural violations

1. **Glass close button floating on the sheet header** (`Forms.swift:28-35`). At
   the partial detents (`BottomSheetHost.swift:32-44` gives `.medium, .large` to
   `transferDetails`/`planActions`) the sheet *is* the material; a glass circle on
   it is glass on glass. At `.large` there is no content behind the header
   (`SheetHeader` is a sibling of the `ScrollView`), so the gesture buys nothing.
   The current `.montra(.secondary, size: .small, width: .square)` circle is right.
2. **Glass `SheetFooter`** (`Forms.swift:42-58`). Same glass-on-glass at partial
   detents, and the footer has no scrolling content behind it. Its fill is
   already identical to the sheet body (measured: both `23,22,21`), so it reads as
   part of one surface; the hairline is the whole separation. Leave it.
3. **Glass page header / collapsing glass top bar** (`DetailHeader.swift:27-52`).
   A ~120 pt banner with a page title and subtitle is content, not a control bar;
   glass under a large title is the "text on a slab" failure. It is also static
   above the scroll view, so nothing would refract. The opaque `surfaceBase`
   (`:51`) is Apple-consistent with a large-title area.
4. **Glass cards, rows, hero, balance bar, period card, recent list**
   (`OverviewView.swift:155-225,316-377,421-454,473-509`; `Components.swift:178-208`).
   Directly forbidden: the content layer must not compete with the navigation layer.
5. **Glass currency chips / filter chips** (`OverviewView.swift:282-312`;
   `Components.swift:427+`). Chips filter content; an accent-tinted chip row over
   the chart's Okabe–Ito colours would be unreadable and would add a second tinted
   cluster on Overview.
6. **Custom glass search pill** (`CapsuleSearchField.swift:82-93`; used at
   `OperationsView.swift:584-612`, `CategoryPicker.swift:42`). It sits in a fixed
   bar above the list (nothing behind it) and it is an input, not navigation. The
   native answer would be `.searchable`, which is currently impossible because the
   whole shell hides the navigation bar (`IOSNavigationShell.swift:194,207`) — do
   not hand-roll glass over an input.
7. **Glass segmented control for the analytics period/scope**
   (`AnalyticsView.swift:734-756`, the capsule track at `:751-756`). It lives in
   the opaque header, Apple's own segmented control is not glass, and this would
   be the third material cluster on one screen (bar + header pills + control).
8. **Glass on the analytics day popup** (`AnalyticsView.swift:2081-2115`). It is
   a data callout over saturated heat cells; numbers need the opaque
   `surfaceRaised` + shadow it has.
9. **Replacing the iPhone `TabView` with custom glass.** The system bar already is
   Liquid Glass, with morphing selection and scroll-edge behaviour we would have
   to re-implement.
10. **`presentationBackground(.thinMaterial)` / `.glassEffect` as a sheet
    background.** iOS 26 owns the sheet surface; a custom background suppresses
    it, and a glass view inside a sheet is glass-on-glass.
11. **Stripping the nine sheet backgrounds "so the material shows".** Measured:
    the one sheet that omits it (`AboutSheet`) renders `#1C1C1E`, flat and cool,
    not visibly glassy; behind a sheet the page is dimmed to near-uniform black
    (12,11,11), so there is nothing for a material to sample. The only visible
    change would be a palette break. Revisit only if a device check at `.medium`
    shows iOS 26's inset glass doing something better than a rim — then apply it
    to `TransferDetailSheet` and `PlanActionSheet` only, never to the `.large` sheets.
12. **Glass "New operation" pill kept in the header** (the naive version of the
    request). It sits on an opaque band with nothing behind it; the result is a
    grey/tinted capsule, and it would be the app's only decorative glass. Move the
    action to the floating corner instead (P1-1).
13. **Third tint.** The budget is one tinted primary per screen. With the FAB
    tinted, nothing else on Overview may be tinted — in particular do not tint the
    period pill, the currency chips or the section labels.

### 5.2 API notes

- `ConcentricRectangle` is **not** needed for any accepted item: capsules have no
  corners to make concentric. It becomes relevant only if a glass surface is a
  rounded rectangle that must match the sheet/window corner (a future floating
  top bar) — using it on a pill would be wrong.
- `glassEffectID` is only meaningful inside a `GlassEffectContainer` with a
  `@Namespace`; it is currently used correctly at `IOSNavigationShell.swift:295`.
  Do not add IDs to one-off glass (the FAB) — with no container they do nothing.
- `scrollEdgeEffectStyle` is already correct at `.bottom` on the iPad shell
  (`:178`). Only add `.top` if P2-2 ships.
- `backgroundExtensionEffect()` is not glass and is out of scope; it would be the
  right tool if the Overview hero ever needs to bleed under the bar.

---

## 6. Recommended minimal set

Five changes at most; the first three are the ones that answer "you don't use
Liquid Glass where you could" without turning the app into a glass demo.

| # | Change | Replaces | Platform | Effort | Risk |
|---|---|---|---|---|---|
| 1 | P0-1 iPad bar: one platter + fill lens (or, minimum, container `spacing: 0` and 8 pt item gap) | Five separately-rimmed glass capsules | iOS/iPadOS | 1 file, ~20 lines | Low; visual only. Verify on device. |
| 2 | P1-1 Overview quick-add FAB, tinted `.regular.interactive()` on `safeAreaInset` | The header "New operation" pill on Overview (`OverviewView.swift:112-123`) | iOS/iPadOS only | 1 file + the `usesCompactShell` helper | Low–medium; removes a header row, so check Dynamic Type and the `ViewThatFits` path. |
| 3 | P2-1 Onboarding intro: glass on the Skip + sound controls | Two bare glyph/text controls (`OnboardingIntroView.swift:276-303`) | iOS only | 1 file | Low; snapshot review required. |
| 4 | P2-2 Operations floating glass filter bar | Three opaque fixed bands (`OperationsView.swift:273-281`) | iOS/iPadOS only | 1 file, layout restructure | Medium; scroll + pinned headers + screenshots. Optional. |
| 5 | P2-3 `AboutSheet` palette match | The cool `#1C1C1E` sheet body | Both | 1 line | Very low; cosmetic consistency, not glass. |

If only two can ship, ship 1 and 2. If the app must visibly gain glass in more
than one screen, add 3; do not add glass to any surface not listed here.

---

## 7. Already correct — do not change

- **iPhone `TabView`** (`IOSNavigationShell.swift:136-145`) and
  `.tabBarMinimizeBehavior(.onScrollDown)` (`:144`). The system bar is the
  reference implementation; the custom iPad bar should imitate it, not replace it.
- **iPad bar plumbing** (`:225-311`): one `GlassEffectContainer`, `.regular` only,
  `.interactive()`, single tint, `@ScaledMetric` 44 pt targets clamped at
  `:244-247`, captions dropped at accessibility sizes (`:240`), VoiceOver
  label + `.isSelected` (`:297-300`), pointer `hoverEffect` (`:296`), and the
  "open in new window" context menu (`:301-309`). Only the surface structure
  changes (P0-1); none of this should be touched.
- **`selectedSymbol` filled variants** (`AppTab.swift:52-58`): selection is not
  encoded in tint alone. Keep.
- **`safeAreaInset` mounting + `.scrollEdgeEffectStyle(.hard, for: .bottom)`**
  (`IOSNavigationShell.swift:171-179`) and **`shellBottomRoom`**
  (`DetailHeader.swift:165-171`): correct pattern, no hard-coded bar heights.
  Reuse it for the FAB rather than inventing a second mechanism.
- **Sheet presentation** (`BottomSheetHost.swift`): per-sheet detents, drag
  indicator, `.presentationContentInteraction(.scrolls)`, `.presentationSizing(.form)`
  at regular width, and **no** `presentationBackground`. Keep all of it.
- **Opaque `SheetHeader` / `SheetFooter`** (`Forms.swift:8-58`) and the footer's
  top hairline: correct as a band that has no content behind it.
- **Opaque content cards** (`OverviewCard`, `InsetCard`, rows, hero, balance bar):
  the single most important "do not glass" decision in the app.
- **Header's opaque `surfaceBase`** (`DetailHeader.swift:51`) and the shared-header
  architecture (`:27-52`, `IOSNavigationShell.swift:26-54`). It exists so the title
  does not cross-fade with the page; glassing it would fight that.
- **Primary/secondary pill styles** (`Components.swift:10-165`) and the header's
  primary on Operations / Account pages (`OperationsView.swift:533-556`): they are
  contextual primaries on non-Overview screens and stay.
- **Search capsule, filter chips, analytics scope control, day popup**: opaque by
  design, for contrast and for hierarchy.
- **No `presentationBackground`, no `Material` anywhere**: the restraint is the reason
  the app does not already look like a glass demo. Keep that discipline.

---

## 8. Verification checklist for whoever implements this

1. Dark **and** light appearance: the FAB and the bar platter must both be
   legible at 0.18 accent tint; in light mode check the FAB label against the
   frosted surface (not against white).
2. Reduce Transparency on → the FAB must not become a solid blue pill; Increase
   Contrast on → the bar's selected item must still read (filled symbol + tint).
3. Accessibility XXXL: the FAB collapses to the icon and keeps a 44 pt target; the
   iPad bar keeps five targets and no truncated caption; the Overview header must
   not reflow into a third line.
4. VoiceOver on Overview: the FAB is reachable, labelled "Новая операция" /
   "New operation" (existing key), and the header no longer exposes a duplicate.
5. Scroll the Overview to the bottom: the last card must clear the FAB at rest and
   pass behind it while scrolling.
6. iPad Split View at compact width: FAB appears (compact shell); at regular
   width: no FAB. iPad bar in both: single platter, no rim collisions.
7. `-selftest` snapshots: onboarding intro (P2-1) and the iPad shell (P0-1) will
   change; review those diffs rather than accepting them blindly.
8. Rotate and Stage Manager-resize: no hard-coded bar/FAB offsets (they are all
   safe-area driven).

---

## 9. Appendix — candidate ideas considered and dropped

| Candidate | Why not |
|---|---|
| Glass on the account rows' hover state | Content layer; already has a fill hover. |
| Glass "period" pill in the header | Static band under it; would be a tinted capsule, and the period is a *value*, not an action. |
| Glass pull-to-refresh / rate spinner | System-provided; leave it. |
| Glass "Пересчитать" / sheet action buttons | Inside sheets: glass on glass, and buttons already have a fill style. |
| Glass toast/undo snackbar | No such component exists; adding one is a feature, not a glass adoption. |
| Glass About page cards | Content. |
| Glass window/back chrome on iPadOS | No window chrome is drawn by the app. |
| `glassEffectTransition(.matchedGeometry)` FAB → sheet | The correct API is `matchedTransitionSource` + `navigationTransition(.zoom)` (iOS 18+), and it is not glass. Optional polish, separate decision. |
| Custom glass tab bar on iPhone | Duplicates the system bar and loses its morph and scroll behaviour. |


---

## 9. Implementation status in `codex/ios-liquid-glass`

Implemented from this audit:

- **P0, iPad bar.** The five per-item glass capsules were replaced with one
  glass platter (`.glassEffect(.regular.interactive(), in: .capsule)` on the
  HStack, one `glassEffectID`) and the selection is an accent fill lens inside
  it. The before/after is `Docs/screenshots/ios-port/feedback-ipad-bar-before-after.png`.
- The iPhone `TabView` remains native and untouched.
- Sheet headers/footers, cards and rows stay opaque: the audit's rejection list
  is respected. Sheet footer glass, glass close buttons and glass content cards
  were not added.

Not implemented in this change (kept as follow-ups): the Overview quick-add
glass FAB (P1), onboarding glass controls (P2), the Operations floating
filter/search bar (P2), and the AboutSheet palette alignment (P2). They need a
separate visual review and, for the FAB, a header layout decision.
