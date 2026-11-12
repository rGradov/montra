# MasterPrompt — Montra

Product, design, and implementation reference for reproducing or extending
Montra while preserving its visual language. It describes the implementation
at the time of this specification. The feature inventory tracks later changes.

## 1. Product

**Montra** is a native macOS app for personal finances. It supports accounts in
multiple currencies, expenses and income, mandatory expense categories, and an
adjustable **payday-to-payday financial month**.

The stack is SwiftUI and SwiftData with no third-party dependencies. The single
target supports macOS 15 and later. Data stays local. The app has groundwork
for iCloud and CloudKit sync, which is disabled in this version.
[iCloud setup](Docs/iCloud-Setup.md)

## 2. User and scenario

One person living in Belarus gets paid in BYN and keeps some money in EUR,
USD, and crypto. Payday may be before or after the 15th. A financial month
runs from one paycheck to the next, with adjustable dates for each period.

1. See the total balance and where the money is held at a glance.
2. Record an expense or income quickly using the account currency.
3. Understand what happened in the current financial period.
4. Keep mandatory and optional expenses separate.

## 3. Visual language

### 3.1 Window and layout

| Parameter | Value |
|---|---|
| Window width | Fixed at **980 pt**, with adjustable height |
| Default and minimum heights | 700 and 600 pt |
| Window style | `hiddenTitleBar`, with traffic lights over the sidebar |
| Sidebar | **240 pt**, `surfaceCard` background, 1 px `borderSubtle` divider |
| Sidebar top inset | 42 pt below the traffic lights |
| Content | **24 pt** horizontal inset and 20 pt top inset |
| Cards | **14 pt** radius, `fillSecondary` or `surfaceCard`, 0.5 px border |
| Card row | 12 / 14 pt padding and a 0.5 px full-width divider |
| Icon tile | **28×28**, continuous radius 7.28 (0.26), white 13 pt medium glyph |
| Capsule button | 30 pt high (24 / 38 variants), 14 pt padding |
| Filter chip | About 28 pt high, capsule shape, 14 pt icon, 13 pt label, and count |
| Row checkbox | Native `.checkbox`, 14 pt |
| Switch | 38×22 track in `fillSecondaryPressed` or `statusSafeText`, 18 pt thumb |

### 3.2 Palette

Warm graphite neutrals from `Montra/Design/Theme.swift`.

| Token | Light | Dark | Use |
|---|---|---|---|
| `textPrimary` | `#2E2D2B` | `#ECEAE6` | Titles and amounts |
| `textSecondary` | `#64625E` | `#A6A39D` | Subtitles |
| `textTertiary` | `#85827C` | `#807D78` | Dates and percentages |
| `surfaceBase` | `#F6F5F3` | `#171615` | Page background |
| `surfaceCard` | `#FFFFFF` | `#1E1D1C` | Sidebar and quiet Overview cards |
| `surfaceRaised` | `#FFFFFF` | `#2B2A28` | Fields, pickers, hover |
| `fillSecondary` | `#EFEDEA` | `#282725` | Grouped cards and secondary buttons |
| `fillSecondaryHover` | `#E8E6E2` | `#2F2E2C` | Hover |
| `borderSubtle` | `#E6E3DF` | `#302F2D` | Dividers and outlines |
| `borderStrong` | `#D5D2CD` | `#3D3B38` | Control outlines |
| `actionPrimary` | `#353431` | `#ECEAE6` | Primary button, a light capsule in Dark mode |
| `onActionPrimary` | `#FFFFFF` | `#171615` | Primary button text |
| `statusSafeText/Fill` | `#1F7A35` / `#E6F4EA` | `#5FD36B` / `#1B2E22` | Income and current time |
| `statusCheckText/Fill` | `#8A5300` / `#FAEEDA` | `#F2B84B` / `#332910` | Mandatory expenses and warnings |
| `statusDangerText/Fill` | `#B4302A` / `#FBE8E5` | `#F47468` / `#321B19` | Deletion |
| Chart blue / sky / amber / vermillion / purple / teal | Okabe–Ito | Lighter variants | Allocation bar and tiles |

Blue accent `#0A6ED1 / #4C9EEA` marks focused fields. Primary buttons use
the appearance-specific text and fill tokens above.

### 3.3 Typography

Text uses variable **Onest**, bundled as `Resources/Fonts/OnestText.ttf`
under the OFL. Its numeral glyphs have been removed. The app draws numerals
in **SF Rounded**.

| Role | Style |
|---|---|
| Hero amount | **SF Rounded 26 bold** |
| Page title | Onest 20 semibold |
| Section title | Onest 13 semibold in secondary color |
| Row title | Onest 13 semibold |
| Body and button text | Onest 13 regular or semibold |
| Row subtitle | Onest 12 regular |
| Metadata | Onest 11 and SF Rounded 11 for numerals |
| Badge | Onest 11 medium |
| Sidebar | Onest 13 medium or semibold |
| Amount in a list row | SF Rounded 13 semibold |
| Amount in an Overview row | SF Rounded 15 semibold |

Numerals use `monospacedDigit` and align to the trailing edge.

### 3.4 Components

- `MontraButtonStyle` supports `primary / secondary / destructive / quiet / soft`,
  heights 24 / 30 / 38, and widths `fit / fill / fixed / square`. Hover takes
  0.12 seconds. Disabled opacity is 0.45.
- `InsetCard`, `OverviewCard`, and `InsetCardDivider` group rows.
- `IconTile` shows a tinted gradient and white glyph. An empty symbol uses a
  dashed tile. A matching image asset takes precedence over the glyph.
- `AppBadge` uses 11 medium, 6 / 2 pt padding, a 6 pt radius, 14% fill, and
  a 22% border.
- `FilterChip` supports tabs and dropdowns. Selection changes background
  and text weight. `Chain` uses `FlowLayout` to wrap chips.
- `MontraSwitchStyle` uses a dark track, white thumb, and a green on state.
- `NumberStepper` is a 28 pt control with minus, editable value, and plus.
  At rest it shows a full label such as “15th day.” Clicking reveals a numeric
  field and suffix. Bounds disable the corresponding button, numbers animate
  with `.numericText()`, Return or loss of focus commits, and VoiceOver
  can adjust the value.
- Shared controls include `PageHeader`, `SectionLabel`, `SheetHeader/Footer`,
  `FieldLabel`, `MontraTextField`, `DropdownMenu`, `DatePickerField`,
  `PopoverMenu`, `EmptyState`, and `RowCheckbox`.
- `BalanceBar` is 14 pt high. Rectangular segments have 2 pt gaps and a minimum
  width of 4 pt. One `Capsule` clips the ZStack so only the outside ends are
  rounded. The track appears when all values are ≤ 0. Hover dims the other
  segments to 30% and highlights the corresponding account row.

### 3.5 Animation

| Behavior | Timing and effect |
|---|---|
| Hover or press | `easeOut 0.12` |
| Number changes | `easeInOut 0.45` and `.numericText()` |
| Balance segments | `easeOut 0.6` |
| Page change | `easeInOut 0.22` fade |
| Row entrance | `easeInOut 0.22` |
| Sidebar icon from outline to fill | `snappy 0.2` |
| Settings layout | `spring(response: 0.28, damping 0.9)` |
| New transaction | `spring(response: 0.34, damping 0.86)`, offset 7 pt, scale 0.985→1, blur 1.2→0, and fade |
| New row highlight | Lighter background, `borderStrong`, and 4.5% overlay. Fades after 1.4 seconds with `easeOut 0.9` |
| Page title and subtitle | Rise 4 pt from blur 2 with `easeOut 0.36`. Subtitle delayed 0.07 seconds |
| Subtitle counts | `.numericText()` and `easeInOut 0.45` |
| Stepper | `.numericText()` and `easeInOut 0.2`. Buttons dim at bounds |
| Currency switch in onboarding or new account | Old symbol moves up and fades, new one enters from below in 0.22 seconds, fixed-width slot |
| Period change | Header range updates and the subtitle rises and fades back in over 0.36 seconds after closing the sheet |
| Route change | `SharedDetailHeader` and `DetailHeaderHost` stay outside the content crossfade. `AnimatedPageTitle` moves the old title up and out and brings the new one in from below. Subtitle motion is subtler. Page content crossfades with `spring 0.4/0.92`. Actions update in the same header |
| Account filter change | Rows collapse to zero height or reopen with `spring 0.4 / 0.86` and a 0.02-second stagger. Spacing collapses with the row and the empty state fades in |

Honor `accessibilityReduceMotion` by disabling motion transitions.

## 4. Information architecture

```text
[Montra logo]
Overview
Accounts       → Cash, Card, Revolut, Crypto
Savings        → Savings accounts …
Money          → Categories
Analysis       → Analytics
…
[+ New Account]                ← Primary action at the bottom of the sidebar
Settings
About
[iCloud disconnected]          ← Status pill opens a sheet
```

Open the full transaction list from Recent Transactions in Overview or with
⌘2. Overview remains selected and the page offers a back link.

Under Overview, each account row shows a colored icon, name, and balance in
its own currency. Savings accounts are grouped below regular accounts. Click
a row to open it and see its selected state. The list scrolls independently
of the branding and bottom block.

Routes are `overview`, `operations`, `categories`, `analytics`, `settings`,
`about`, and `account(id)`. Route changes crossfade within the same window.
The first launch opens onboarding.

Shortcuts are ⌘N for a new transaction, ⇧⌘N for a new account, ⌘1 for Overview,
⌘2 for all transactions, ⌘3 for Categories, ⌘4 for Analytics, and ⌘, for Settings.

## 5. Data model

SwiftData models support CloudKit. Attributes have defaults and optional
relationships have inverses. Models use no `.unique` constraints.

```swift
Account  { id: UUID, name, currencyRaw, initialAmount: Decimal, iconName, colorRaw,
           createdAt, sortIndex, operations: [Operation]? }
Category { id, name, kindRaw, colorRaw, iconName, isMandatory, isSystem, sortIndex, createdAt }
Operation{ id, kindRaw, amount: Decimal, currencyRaw, date, place, latitude?, longitude?,
           note, createdAt, account: Account?, category: Category? }
Period   { id, start, end (inclusive), isManual, createdAt }
```

- `Account.balance = initialAmount + Σ income − Σ expenses` for the account.
- `Account.isSavings` groups accounts in Savings and supports future savings
  trends. Balances, transactions, and transfers use the same logic.
- `Operation.currency` records the account currency at creation.
- `Operation.signedAmount` is positive for income and negative for expenses.
  `MoneyFormat` originally used `ru_RU`, a narrow no-break thousands
  separator, and a decimal comma.
- `SettingsStore` stores appearance, hidden amounts, primary currency, and
  period rule in `UserDefaults`, ready for `NSUbiquitousKeyValueStore`.
- Writes go through `AccountRepository`, `OperationRepository`,
  `CategoryRepository`, and `PeriodService` for future sync integration.

### Currencies

The original set is `BYN, EUR, USD, USDC, USDT, BTC` with symbols
`Br, €, $, USDC, USDT, ₿`. It uses two decimal places, except BTC with eight.
The brief's “UTC” was interpreted as USDC. The `Currency` enum defines the list.

### Exchange rates

Totals and currency conversions use **BYN as the base**, expressed as BYN
per unit of each currency.

- The National Bank of Belarus is the official USD and EUR source. Use
  `https://api.nbrb.by/exrates/rates?periodicity=0` and divide
  `Cur_OfficialRate` by `Cur_Scale`.
- The public feed at `cdn.jsdelivr.net/.../currencies/byn.json` provides BTC,
  USDT, and USDC data and backs up fiat when the official source is unavailable.
- USDT and USDC use the USD rate and the interface discloses that.
- Cache the table in `UserDefaults` under `montra.rates.v1`. Refresh at launch,
  every six hours, and on request in Settings. Offline, show cached rates or a
  labeled approximate rate if the cache is empty.
- `RateSource` (`nbrb / currencyAPI / cache / fallback`) appears in Settings
  and the Overview rate row.

### Recurring payments

- A `PlannedOperation` represents one upcoming or missed occurrence. It holds
  `seriesID`, template amount, account, category, place, note, payment date,
  `day/week/month/year` frequency, weekday mask, series bounds, and `linkedOperationID`.
- Generate up to 1,000 plans up front. They do not affect balances until
  recorded as transactions. Each occurrence can be linked, deleted, or skipped.
- Daily recurrence uses every day, weekly uses selected weekdays, monthly
  uses the same day clamped to month end, and yearly uses the same month and day.
- Unlinked dates before today are Missed, today's are Today, and future ones
  are Plan. Linked plans disappear from the plan list. The recorded transaction stays.

### Financial period

- `payday` uses a day from 1 to 31, clamped to the month. A period ends one
  second before the next payday.
- `fixedDays` uses fixed lengths (7 to 60 days in this model description)
  from an anchor date.
- Persist six past periods, the current one, and three future periods.
  Moving a start updates the previous end. Moving an end updates the next start.
- Set `isManual` for manual edits. Recalculate from Rule rebuilds automatic
  periods only.
- Overview and Settings show the current period. The period sheet lets users
  select a month, adjust either boundary, and reset it to the rule.

### Default categories

Expense categories are Housing, Food, Transport, and Health (mandatory), plus
Restaurants, Entertainment, Shopping, Subscriptions, and Other. Income
categories are Salary, Freelance, Gifts, Investments, and Other.

- Mandatory status applies to expenses, affects the Mandatory Expenses and
  Available values in Overview, and passes from parent to subcategory.
- Subcategories have one level. Choose a Parent Category or No Parent.
  A category with children cannot change its parent.
- System categories cannot be deleted. Deleting a custom category sends its
  transactions to Other of the same kind and promotes its children.

## 6. Screens

### 6.0 Onboarding

Delete All Data immediately starts live onboarding in the real store. The
created account persists and completion opens Overview. The preview from
About uses a temporary store, shows a preview banner, and also ends on Overview.

The flow fills the window without the sidebar. It uses a 520 pt column,
240×38 buttons, blur 8 and opacity transitions over 0.45 seconds, staggered
entrance at `index × 0.08`, and a completion screen with sparkles and an animated balance.

1. **Welcome.** 148 pt app icon with shadow, 15 medium welcome text,
   SF Rounded 56 semibold wordmark, subtitle, and Get Started.
2. **First account.** Name, 3×2 currency grid, and opening balance. A name is
   required. Save a real `Account` and make its currency primary. Savings
   accounts are created later from the account sheet.
3. **Categories.** Two 3×N chip grids for expenses and income, with checkmarks.
   Housing, Food, and Salary are preselected. Continue creates the selection.
   Skip creates Other only. Both kinds of Other are always created and stay
   out of the grid.
4. **First expense.** Amount, account context, and a 3×3 category grid. Default
   to Food when selected earlier, otherwise the first created category or
   Other after a skip. Add Expense saves a real `Operation`. Skip is available.
5. **Done.** Sparkles, 56 pt rounded balance, account and expense summary,
   and Open Montra. The app appears while the account card moves and scales
   into its sidebar row with a 0.58-second spring. The row appears after
   landing. Reduce Motion uses blur 12 and a 0.45-second fade.

Onboarding starts for a fresh store. Older stores with accounts are marked
complete on launch. Demo data is available by an explicit Settings action.
Onboarding creates the starter categories and fills in periods after completion.
Delete All Data clears all records, including categories, and resets onboarding.

### Overview

- Overview title and a subtitle such as “5 accounts · 13 transactions this
  period · 6 days left.” The header offers Period and New Transaction.
- A 26 bold SF Rounded hero shows the converted total. The trailing value
  shows converted period spending.
- The rate row shows the source and refresh time. Hovering an account or
  segment displays the original balance and its equivalent, such as
  “Revolut · €470.01 ≈ Br 1,572.65.”
- The allocation bar uses converted account shares. Hover highlights the
  matching account and dims other segments. Currency chips show total capital
  in each currency and switch the display currency.
- Account rows show tile, name, currency, transaction count, share, native
  balance, and converted equivalent where needed. Click to open account detail.
- The Period card shows the current range, mandatory expenses, and the amount
  available (income minus mandatory expenses), converted to the display currency.
- Recent Transactions shows five rows with category tile, account, place,
  date, and amount.

### All transactions

- Open from Overview and use the back link to return. All, Expenses, and Income
  chips show counts. Search uses a capsule, magnifier, placeholder, clear
  button, and focus outline. ⌘F focuses and Escape clears. Search matches all
  tokens across category, account, place, note, kind, amount, and date.
- The chip counts, subtitle count, and total in the primary currency reflect
  visible matches. Day groups use Today, Yesterday, Tomorrow, and localized
  dates, with a year for other years. Headers stick. Amount sort uses a flat list.
- Period selection is beside sort. Select All applies to visible rows.
  Sort by date or amount.
- No Results includes Clear Search, Show All when another kind matches, and
  Search All Time when matches fall outside the period.
- Rows show a checkbox, tile, category, date, account, place, amount, and
  Mandatory or Income badge. Click to edit. The context menu offers Edit and
  Delete. Multi-select deletion requires confirmation.
- A new row enters with a 0.34-second spring, slight scale and blur. A lighter
  background, stronger border, and overlay fade after 1.4 seconds. This also
  applies in Overview and account detail. Batch demo loads and resets do not flash.

### Account detail

- Back to Overview, account name, currency and opening balance, Edit, and New
  Transaction. The hero shows the balance with an all-time total on the right.
- Kind chips, checkboxes, and Select All support a selection count and amount.
  Delete (N) opens the shared confirmation list and success screen.
- Day groups use Today, Yesterday, and dates. Small accounts use collapsing
  rows and larger accounts use a lazy list with sticky headers.
- Plans appear alongside transactions in day groups, with Plan, Today, or
  Missed badges and status under the amount. Missed lists unlinked past
  occurrences. Upcoming includes up to two years or the end of the series.
  Account chips are beside All, Expenses, and Income. They are mutually
  exclusive with the kind filter. Clicking the active chip returns to All.
- A plan opens actions to link an existing transaction, record a new one with
  prefilled fields, delete the occurrence, or delete the series.
- An account-specific `@Query` applies a predicate and store-side sorting.
  Up to 60 records use collapsing rows. Above that, `LazyVStack` creates
  visible rows on demand. Track new rows by count changes. For collapsing rows,
  filter changes animate height and spacing, and an empty state fades in.

### Categories

- Expense and Income sections show tile, name, mandatory or system subtitle,
  and count. Indent children under their parents with a vertical line.
  Parent counts include children's transactions.
- The sheet offers kind at creation, name, Parent Category, mandatory status,
  deletion, and the same Appearance section as the account sheet: an
  Icon/Emoji switch, five one-tap glyphs for the kind, the full catalog behind
  "…", and the color dots below. Parents must be top-level and of the same
  kind. Subcategories inherit mandatory status. Parents with children stay
  top-level.
- Deleting a parent moves its transactions to Other and promotes its children.

### Analytics

A Coming Soon card uses a faint chart and explains the planned functionality.
The placeholder uses no fictional figures.

### Settings and About

- **General.** Hide Amounts masks values as `••••`. Appearance shows system,
  light, and dark window previews with an outline around the selection.
- **Financial period.** Choose the mode. Compact steppers cover payday 1–31
  and length 1–90 in the UI. Click the value to edit digits. Return or loss
  of focus clamps the value. The minus and plus buttons still work.
  Open the period sheet from Periods.
- **Exchange rates.** Show the source (official, public feed, cache, or approximate),
  USD/EUR/USDT/BTC rates against BYN, refresh time, and a Refresh button with loading state.
- **Data.** Primary currency, iCloud disconnected status and explanatory sheet,
  CSV export, and Delete All Data with confirmation.
- **About.** Show `MontraArtwork` (`artwork.png`), name, version, a total across
  accounts, account and transaction count, feature summary, and footer.
  The onboarding preview opens over the window with an in-memory store and
  closes with X or Escape.

### Forms

- The shared sheet is 470 pt wide and uses a custom header, close button,
  and hairline footer.
- The account form shows a tile preview, name, currency (read-only when editing),
  opening balance, Savings Account switch, and the Appearance section shared
  with categories: an Icon/Emoji switch, five one-tap glyphs, the full catalog
  behind "…", and the color dots. The savings
  flag leaves deposits and withdrawals available.
- The transaction form opens on the active income or expense filter when
  applicable. It shows a large amount in the account currency and an account
  picker with balances.
- `MontraDateTimePicker` provides month arrows, a 6×7 grid, selected day fill,
  current day outline, validated `hh:mm`, Now, and Done. Date range constraints
  disable unavailable days. The default is now.
- Category selection offers the five most frequent categories and a searchable
  More popover with the full parent-child hierarchy. Keep the selected category
  among the quick choices. The form also supports place text, geolocation, notes,
  and deletion when editing.
- Require a positive amount, selected account and category, and a nonempty name
  where applicable.

## 7. Technical requirements

- Xcode uses `PBXFileSystemSynchronizedRootGroup`, `SWIFT_VERSION = 5.0`,
  and `MACOSX_DEPLOYMENT_TARGET = 15.0`, with no dependencies.
- One `ModelContainer`. `ModelContainerFactory` is the CloudKit switch point
  from `.none` to `.private("iCloud.com.vladrudenua.montra")`.
- Use CloudKit-compatible models and repository writes.
- `RateStore` loads cached rates immediately, refreshes from official and
  public sources with a short timeout off the UI path, and preserves currencies
  when a response is partial.
- Sync groundwork includes `SyncService`, `CloudSyncState`, and
  `Docs/Montra.entitlements`.
- Register the font from a copy in Application Support so CoreText can
  reread it even if a Debug build loses its bundle.
- Apply theme through `NSApplication.shared.appearance` with dynamic colors.
- Label icon-only controls, make rows accessible with `accessibilityElement`,
  expose readable numeric values, and maintain contrast ≥ 4.5:1.
- Use `-selftest` for period arithmetic, balances, signs, categories,
  pluralization, conversion, and clean launch. Use `-snapshot <dir>` to render
  screens and onboarding steps through NSHostingView.

## 8. Decisions and assumptions

1. The original interface and numeric formatting used Russian and `ru_RU`.
2. Onest supplies text and SF Rounded supplies numerals.
3. The brief's “UTC” currency entry maps to USDC in `Currency`.
4. The window is fixed at 980 pt wide with adjustable height.
5. Account currency is fixed at creation to preserve transaction history.
6. Load demo data explicitly from Settings. Onboarding creates a real first
   account and optionally a first expense.
7. Account deletion warns the user and cascades to its transactions.
8. Use the National Bank of Belarus for official USD/EUR rates. The public
   feed covers timeouts and crypto rates. Stablecoins use the USD rate.
   Show the source in the interface.
9. Analytics is intentionally a placeholder in this specification.

## 9. Acceptance criteria

1. The window is 980 pt wide. Traffic lights sit over the sidebar and the
   background uses the palette tokens.
2. Overview follows the documented spacing, radii, tiles, and badges.
3. Account creation accepts icon, color, currency, and opening balance.
   Transactions affect balances, and sidebar rows show those balances.
4. Overview converts and totals account balances. Hovering any account,
   including Revolut, shows both the original and converted amount.
5. Expenses and income use the account currency and default to now. They
   support place and note, editing, and deletion.
6. Filter categories by transaction kind and show and apply mandatory status.
7. Configure periods, show the current one, and adjust boundaries while
   preserving continuity.
8. Appearance switches and Hide Amounts masks values.
9. Refresh and cache rates and label fallback sources.
10. Provide iCloud groundwork, accurate status, and setup instructions.
11. `xcodebuild` completes without errors or warnings and `-selftest` passes.

## 10. Outside the original iteration

Charts and analytics, budgets and limits, cross-currency transfers, recurring
transactions, live sync, statement import, an iOS target, and localization were
outside the original iteration. Historical amounts use current exchange rates.
Transaction-date rates were deferred.
