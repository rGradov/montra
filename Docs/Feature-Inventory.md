# Montra feature inventory and test plan

As of **November 9, 2026**. The code in `Montra/` is the source of truth.
Each area has IDs, checks, expected outcomes, and negative or edge cases.

> Automated coverage includes **160 checks** in `-selftest` and full screen
> rendering with `-snapshot`. See sections 4 and 5 for coverage and gaps.

## 0. How to use this inventory

| ID prefix | Area |
|---|---|
| `SHL` | Window, sidebar, shared header, commands |
| `ONB` | Onboarding, preview, Delete All Data |
| `ACC` | Accounts and account detail |
| `OPS` | Transaction list, day groups, search, filters, bulk actions |
| `FRM` | Transaction form |
| `TRF` | Transfers |
| `CAT` | Categories and subcategories |
| `PER` | Financial periods |
| `PLN` | Recurring payments |
| `SET` | Settings, rates, API, iCloud, CSV, backups |
| `DEL` | Deletion and confirmations |
| `DAT` | SwiftData, migrations, persistence |
| `API` | Local HTTP API |
| `SPT` | Spotlight and App Intents |
| `ABT` | About and Analytics |
| `FMT` | Formatting, pluralization, dates |
| `A11Y` | Accessibility, keyboard, Reduce Motion |
| `VIS` | Visual and animation requirements |

**P0** covers money, data, or core workflows. **P1** covers important UX.
**P2** covers polish. Test types include `unit` (pure logic), `ui`,
`integration`, `persistence`, and `visual`.

## 1. Fixtures and environment

| ID | Fixture | Contents |
|---|---|---|
| F-EMPTY | Clean launch | No accounts, transactions, or categories before the category step. Periods are absent and onboarding is incomplete |
| F-ONE | One account | Cash, BYN, opening balance 420, three transactions, current period |
| F-MULTI | Multiple currencies | BYN/EUR/USD/USDC/USDT/BTC/ETH accounts, fixed rates, multiple currencies |
| F-MANY | Large list | More than 60 transactions for the collapsing list boundary and more than 1,000 for performance |
| F-CAT | Hierarchy | Mandatory parent, subcategory, and transactions in both |
| F-PER | Period edge cases | Payday on the 31st, February, leap year, manual boundaries, fixed 10 days |
| F-TRF | Transfer | Two accounts with different currencies, one pair sharing a `transferID` |
| F-PLN | Plans | Monthly occurrences yesterday (missed), today, and tomorrow, weekly with chosen days, the 31st, a linked transaction, and a link candidate |
| F-HIDE | Hidden amounts | `hideBalances = true` |
| F-RATE | Rates | National Bank of Belarus preview, fallback currency API, and a missing rate |
| F-API | API | Completed onboarding, enabled Local API, token, and `allowDelete` on and off |
| F-ONB | Onboarding | Empty live store and `hasCompletedOnboarding = false`. After opening onboarding, `hasStartedOnboarding = true` |
| F-REPLAY | Preview | Live data plus onboarding preview launched from About |

```bash
# Build
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug build
APP=~/Library/Developer/Xcode/DerivedData/Montra-*/Build/Products/Debug/Montra.app

# Run 131 logic checks in memory
"$APP/Contents/MacOS/Montra" -selftest

# Render all screens to PNG in memory
"$APP/Contents/MacOS/Montra" -snapshot /tmp/montra-snaps

# Preview onboarding with a temporary store
"$APP/Contents/MacOS/Montra" -preview-onboarding
```

Before destructive scenarios such as deleting all data or an account, copy
`~/Library/Application Support/Montra.store` and its `-wal` and `-shm` files.
Use a 980×700 window with a 240 pt sidebar and `hiddenTitleBar`.

## 2. Feature checks

### 2.1 App shell, navigation, and header

| ID | Feature | Key checks | Type |
|---|---|---|---|
| SHL-01 | Window and layout | Fixed 980 width, minimum height, hidden title bar, traffic lights over the sidebar, 240 pt sidebar, and content stays in place | ui/visual |
| SHL-02 | Sidebar | Overview, account balances, Categories with count, Analytics, New Account, Settings, About, and iCloud status. Sort by `sortIndex`. Check the selected route, including Overview remaining active in account and transaction views | ui |
| SHL-03 | Sidebar keyboard focus | Tab moves focus. Rows use a subtle fill in place of the system ring. Space or Return activates. Main content uses standard focus | a11y/ui |
| SHL-04 | Shared header | Route owns title, subtitle, back link, and actions. Header stays outside page crossfade. Prior bank to Overview has no doubled title. Actions update and top-level pages reserve the back-link row | visual/ui |
| SHL-05 | Header animation | Old title rises and fades, new title enters, and subtitle motion is subtler. Check for stretched or doubled text. Back link leaves title in place. Reduce Motion disables springs | visual/a11y |
| SHL-06 | Commands and shortcuts | ⌘N new transaction, ⇧⌘N new account, ⌘1…⌘4 routes, ⌘, Settings, menu entries, and ⌘F in transaction search | ui |
| SHL-07 | Touch Bar | Account list and New Transaction. The open account is preselected. Unavailable outside the active window or while a sheet is open | manual/ui |
| SHL-08 | Account not found route | Deleted or unknown account ID shows Account Not Found and a link to Overview | ui |
| SHL-09 | Route after onboarding | Live and preview onboarding end at Overview regardless of starting route | ui |

### 2.2 Onboarding

| ID | Feature | Key checks | Type |
|---|---|---|---|
| ONB-01 | First launch | Empty store and `!hasCompletedOnboarding` show Welcome without the sidebar. Accounts and transactions require user action | persistence/ui |
| ONB-02 | Account step | Name required, amount ≥0, any supported currency, icon and color. Create Account persists a real regular account, sets `primaryCurrency`, and opens categories. Savings accounts are created later in the account sheet | ui |
| ONB-03 | Account style | Icon and color popover. Selection updates preview and cancellation leaves the form usable | ui |
| ONB-03b | Categories | Expense and income grids with checkmarks. Only Housing, Food, and Salary are selected by default. Continue creates the selection, Skip creates only Other, and retry creates no duplicates | ui/unit |
| ONB-04 | First expense | Positive amount, category, and account. Preselect Food, the first created category, or Other after a skip. Add Expense saves a transaction. Skip proceeds without a transaction | ui |
| ONB-05 | Completion | Shows account and expense. Open Montra opens Overview and moves the card into its sidebar row. Reduce Motion uses a fade | ui |
| ONB-06 | Validation | Empty name, blank or negative amount, or missing category disables the action. The step cannot create a second account | ui |
| ONB-07 | Delete All Data | Confirm deletion of transactions, accounts, categories, periods, and plans. Reset `hasCompletedOnboarding=false` and immediately open live onboarding. Its category step creates categories and its account persists | persistence/ui |
| ONB-08 | Preview from About | Temporary in-memory store, live data stays intact, preview banner says data will not be saved, X closes, and completion opens Overview | ui |
| ONB-09 | `-preview-onboarding` | Runs with an in-memory store and leaves live data intact | integration |
| ONB-10 | Incomplete onboarding | Create an account and quit before completion. Relaunch opens onboarding again and proceeds from Welcome to Categories using the existing account. Open Montra marks the flow complete and ends relaunch prompts | persistence |
| ONB-13 | Older installation | Existing accounts and `hasStartedOnboarding = false` indicate a pre-onboarding store. Launch marks onboarding complete once and opens the app | persistence |
| ONB-12 | Account transition | Completion moves and scales the account card into its sidebar row. The row stays hidden until landing. Reduce Motion or missing frame measurements use a fade | ui |
| ONB-11 | Onboarding categories | No categories before the category step. Create selected system categories and Other for both kinds. Skip creates only Other. Repeating creates no duplicates | unit/ui |
| ONB-14 | Mascot hand-off into the icon | After the intro, the mascot flies into the welcome icon and shrinks onto the mascot painted inside it. Position and scale come from the eyes measured in both PNGs. While it flies, the icon is defocused and the copy and the button are hidden by opacity only, so the icon never shifts. It dissolves while the icon is still soft, so the swap is invisible, and the icon then focuses up. Reduce Motion, or a missing measurement, falls back to the old cross-fade | ui |

### 2.3 Accounts

| ID | Feature | Key checks | Type |
|---|---|---|---|
| ACC-01 | Account creation | Name, currency, opening balance, icon, color, Savings Account, and Hide from Overview. Trim name, accept zero, and disable for negative or invalid amounts | ui/unit |
| ACC-02 | Editing | Change name, opening balance, icon, color, savings, or Overview visibility. Currency is read-only in the header. Opening balance changes recalculate the balance | ui |
| ACC-03 | Account deletion | Confirmation warns that transactions and planned payments cascade. The account route shows Account Not Found or returns to Overview | persistence/ui |
| ACC-04 | Balance | `initial + income − expense`. Transfers count. Hide Amounts masks it | unit/ui |
| ACC-05 | Account detail | Back, Edit, New Transaction, and Delete (N) on selection. Balance, account label, all-time value, and conversion to the primary currency | ui |
| ACC-05a | Accounts in Overview | Account color or the chosen emoji, drawn without a tile backing. Amount and share on the right. Click opens the account | ui/visual |
| ACC-06 | Account filters | All, Expenses, Income, counts, selection and Select All. Delete only selected rows | ui |
| ACC-07 | Collapsing or lazy list | Up to 60 transactions use collapsing rows. Above 60 use LazyVStack. Filters preserve rows and scroll behavior. Plans appear in the list | ui/performance |
| ACC-08 | Account plans | Only this account's plans in the current period. Linked plans are hidden. Plan, Today, or Missed badge. Click opens plan detail | ui |
| ACC-08a | Account plan filters | Missed and Upcoming chips with counts beside All, Expenses, and Income. Exclusive with kind filters. Select All hidden. Click active filter to return to All | ui |
| ACC-08b | Upcoming on account | Pending plans from today through the earlier of two years ahead or the series end. Ascending day groups. Empty results show EmptyState | unit/ui |
| ACC-08c | Missed on account | Pending plans before today, including past periods, in descending order. Empty results show EmptyState | unit/ui |
| ACC-09 | Multiple currencies | Use the account currency and convert to the primary currency when a rate exists | unit/ui |
| ACC-10 | Sidebar | Sorted accounts, balances and currencies, compact BTC, masked amounts, separate Savings group, and account navigation | ui |
| ACC-11 | Savings account | Persist and edit the flag. Show savings label in detail and Overview. Preserve balance, income, expenses, and transfers. API returns `is_savings` | unit/ui/API |
| ACC-12 | Hide from Overview | Persist and edit the flag. Exclude hidden accounts from Overview total, allocation bar, currency chips, and account list. Keep sidebar, detail, transactions, and Analytics behavior. Hidden from Overview: N opens the account. All hidden shows an empty state. Balance and savings flag are unaffected. The account sheet uses a full-width Hide from Overview card with its switch aligned to the savings switch | unit/ui |

### 2.4 Transaction list, day groups, search, and filters

| ID | Feature | Key checks | Type |
|---|---|---|---|
| OPS-01 | Day groups | Today, Yesterday, Tomorrow, and dates such as November 7. Include year for other years. Newest first and sticky headers | unit/ui |
| OPS-02 | Kind filter | All, Expenses, and Income. Counts reflect search results. Empty states and selection reset on filter change | ui |
| OPS-03 | Search | AND across tokens in category, account, place, note, kind, Transfer, amount, or date. Update counts and subtitle amount. Verify ⌘F, Escape, Search All Time, empty filter state, and Clear Search | unit/ui |
| OPS-04 | Period | Current Period and All Time, inclusive boundaries, subtitle, and selection reset on change | ui/unit |
| OPS-05 | Sort | By Date uses day groups. By Amount uses a flat list with Plans grouped separately. Stable ordering | ui |
| OPS-06 | Selection and deletion | Checkboxes and Select All apply to visible rows. Confirm and show success. Expand transfer pairs. Reset selection on search, filter, period, or plan changes | ui/unit |
| OPS-07 | Transaction row | Icon in the category color without a tile backing in Overview, the operations list, account pages, and lists inside dialogs. Account, place, time, amount, and mandatory badge. Transfer row, Edit and Delete menu, and new-row highlight | ui/visual |
| OPS-08 | Empty states | No transactions in period, no search matches, create or clear action | ui |
| OPS-09 | Header subtitle | Transaction count, period or all-time total, and plan count. Show selected count on selection and Missed or Upcoming count on plan filters | ui |
| OPS-10 | Plans in full list | Transaction-style cards in the period's day groups. No selection. Plan, Today, or Missed badge under amount. Click opens plan | ui |
| OPS-11 | Plan filters | Missed and Upcoming buttons with counts, active highlight, reset. Hide Select All, period, and sort. Apply search and kind | ui |
| OPS-12 | Upcoming plans | Pending dates from today through the earlier of two years ahead or series end. Include today, ascending, with EmptyState for no results | unit/ui |
| OPS-13 | Missed plans | Pending dates before today, newest first. Hide linked occurrences. Empty results show EmptyState | unit/ui |
| OPS-14 | Performance | With 1,062 transactions, the lazy list builds rows on demand. Search and filter changes stay responsive | performance |

### 2.5 Transaction form

| ID | Feature | Key checks | Type |
|---|---|---|---|
| FRM-01 | Tabs | Expense, Income, and Transfer. Editing offers expense and income only. Switching clears incompatible values. New Transaction follows the active kind filter | ui |
| FRM-02 | Amount, account, category | Amount >0, parse `12,50`, spaces, and NBSP. Select the account and use its currency. Category matches kind | unit/ui |
| FRM-03 | Quick categories | Five most frequent plus current selection. More opens hierarchy search. Parent subtitle and selection checkmark | ui/unit |
| FRM-04 | Date and time | Defaults to now. Arbitrary date and time, calendar and bounds, and a future date | ui |
| FRM-05 | Place | Manual text or geolocation supplies place and coordinates. Errors and unavailable location leave manual input usable | ui/integration |
| FRM-06 | Editing | Prefilled fields, save, confirm deletion, return, and allow amount, account, and category changes | ui |
| FRM-07 | Validation | Blank, zero, and negative amount, missing account or category, no accounts, and changed category kind. Action disables as applicable | unit/ui |
| FRM-08 | Cancel and close | X, Cancel, and ⌘. dismiss without saving. Reopen cleanly | ui |
| FRM-09 | Recurring payment | Only when creating expense or income. Toggle, day/week/month/year (month by default), weekly Mon–Sun with any/all/none, end date default +1 year and max +5 years, localized count and period summary, Create Plan leaves transactions unchanged | ui/unit |
| FRM-10 | Record plan | Prefill amount, account, category, place, and note. Editable date defaults to today. No recurrence section. Save creates and links a transaction | ui |
| FRM-11 | Transfer | See TRF. Hide recurrence on the transfer tab | ui |

### 2.6 Transfers

| ID | Feature | Key checks | Type |
|---|---|---|---|
| TRF-01 | Accounts | From and To, minimum two accounts, and pickers prevent the same account on both sides | ui/unit |
| TRF-02 | Amounts | Positive debit and credit, currency codes, rate estimate for different currencies, manual received amount persists, and Use Rate resets it | unit/ui |
| TRF-03 | Creation | Two transactions share `transferID`. Source debited, destination credited, balances updated, and currencies correct | unit |
| TRF-04 | Totals | Exclude transfers from period expenses, income, mandatory and converted totals. Show transfer badge and icon | unit/ui |
| TRF-05 | Detail and deletion | Read-only pair detail. Deleting one side expands to both, removes both, and reverses balance changes | ui/unit |
| TRF-06 | Limitation | The transfer tab hides recurrence and supports one-off transfers | manual |

### 2.7 Categories

| ID | Feature | Key checks | Type |
|---|---|---|---|
| CAT-01 | List | Expense and Income sections. Icons in the category color without a tile backing. Subcategories indented with a connector line. Parent count includes subcategory transactions. Mandatory categories are marked | ui/visual |
| CAT-02 | Creation | Name, kind, color, icon, and mandatory status. Parent must be top-level and same kind. No Parent available. One nesting level | ui |
| CAT-03 | Mandatory status | Applies to expenses and is inherited by subcategories. Reflected in the form and totals. Unavailable for income | unit/ui |
| CAT-04 | Editing | Name, color, icon, mandatory status, and parent. Prevent choosing a child as parent and protect system categories | ui |
| CAT-05 | Deletion | Protect system categories. Reassign transactions and plans to Other, promote children to top level, and update counts | unit/ui |
| CAT-06 | Picker | The five most frequent categories plus the selected one. More opens a search by name and parent with the hierarchy. Icons in the category color without a tile backing, a checkmark on the selected row, and the list limited to the operation kind | ui/visual |
| CAT-07 | Empty state | If no categories match the kind, show guidance and block save. Other is the fallback | ui |
| CAT-08 | Counts | Category count in Settings and sidebar. Transaction count updates after deletion and creation | ui |

### 2.8 Periods

| ID | Feature | Key checks | Type |
|---|---|---|---|
| PER-01 | Generation | Continuous periods, payday or fixed length, clamp the 31st to month end, February and leap year | unit |
| PER-02 | Current period | Inclusive bounds, title, days remaining, and current or all-time scope | unit/ui |
| PER-03 | Settings | Payday or fixed, stepper 1…31 or 1…90, mode change regenerates periods, and persist defaults | unit/ui |
| PER-04 | Period sheet | List and selection, boundaries, range and neighbor validation, Save Period, Reset to Rule, and Recalculate with confirmation | ui |
| PER-05 | Manual edit | Set `isManual`, update neighboring periods, keep history continuous, and reset to rule | unit/ui |
| PER-06 | Bounds and empty cases | No periods, extreme boundaries, period without transactions, and switching preserves data | ui/unit |
| PER-07 | UI updates | Header subtitle and Current Period label, period card, and refresh after closing the sheet | ui |

### 2.9 Recurring payments

| ID | Feature | Key checks | Type |
|---|---|---|---|
| PLN-01 | Series creation | Inclusive start and end, daily/weekly/monthly/yearly, start time, first and last occurrences, clamp the 31st and return to 31 in March, selected weekdays, max 1,000, and shared seriesID | unit |
| PLN-02 | Balance | Plans leave `Operation` records, balances, and totals unchanged until recorded | unit |
| PLN-03 | Status | Future, today, or missed. Hide linked from pending. Show Plan, Today, or Missed | unit |
| PLN-04 | Plan row | Like a transaction row: icon in the category color without a tile backing, headline title, callout metadata, amount on the right, Plan/Today/Missed badge under the amount. No checkbox and no overflow menu. Click opens the plan | ui/visual |
| PLN-05 | Plan detail | Amount, account, category, date, recurrence, end date, series count, place and note. Link, Record, and delete one or all | ui |
| PLN-06 | Link to transaction | Candidates match kind and are unlinked to other plans. Search and sort by nearest date. Select to set plan.linkedOperationID, hide the plan, and retain the transaction. Empty state explains | ui/unit |
| PLN-07 | Record as transaction | Prefilled form with editable date defaulting to today. Create and link the transaction. Cancel preserves the plan | ui/unit |
| PLN-08 | Deletion | Choose occurrence or series, confirm with count, retain linked transactions, and remove pending occurrences on series deletion | unit/ui |
| PLN-09 | Full and account lists | Plans appear in day groups in the current period. Account detail only includes its own plans. Apply kind and search. Amount sort groups Plans separately | ui |
| PLN-10 | Missed and Upcoming | See OPS-11…13 and ACC-08a…c. Two-year or series-end limit, counts, reset, and empty states | unit/ui |
| PLN-11 | Integrity | Account, category, and full deletion remove or reassign plans as applicable. Check the behavior when deleting a linked transaction separately | unit/persistence |

### 2.10 Settings

| ID | Feature | Key checks | Type |
|---|---|---|---|
| SET-01 | Hide Amounts | Mask amounts in Overview, sidebar, rows, plans, and pickers immediately and persist the setting | ui/unit |
| SET-02 | Appearance | System, light, and dark apply to the whole window and persist | ui/visual |
| SET-03 | Primary currency | Converted total and amounts, persistence, and missing-rate handling | unit/ui |
| SET-04 | Financial period | Mode, payday, length, Periods link, regeneration, and persistence | ui/unit |
| SET-05 | Rates | National Bank of Belarus or fallback source, table, Refresh, updated state, error, six-hour cache, and disabled control during refresh | ui/unit |
| SET-06 | Local API | On and off, unavailable before onboarding, 127.0.0.1 and port, copy token, allowDelete, and persistence | ui/integration |
| SET-07 | iCloud | Disconnected status and instructions sheet. Data stays local and sync is inactive | ui/manual |
| SET-08 | CSV | Export all recorded transactions. Header, `;` delimiter, BOM, CRLF, escaping, date sort, cancellation and error, and plans excluded | unit/ui |
| SET-09 | Delete All Data | See ONB-07. Check alert text, immediate onboarding, and resulting category, period, plan, account, and transaction state | ui/persistence |
| SET-10 | About in Settings | Static version and storage rows | ui |
| SET-11 | Save backup | Dated `.montra` filename. Includes accounts, both transfer sides, categories and parents, plans, periods, settings, rates, and API switches. Last backup date, cancel and write failure, and repeat save without overwriting | unit/ui |
| SET-12 | Load backup | Open panel filters by extension. Reject unrelated files, unsupported old or new format versions, checksum tampering, and broken references. Sheet shows date, version, counts, replacement warning, option to save current state, and success screen | ui/persistence |
| SET-13 | Safe restore | Full replacement preserves `id`, decimal amounts, transfer links, category parents, and manual periods. Apply settings, rates, and API switches, then open Overview. Empty backup returns to onboarding. Validation failure leaves existing data intact | unit/persistence |

### 2.11 Deletion and persistence

| ID | Feature | Key checks | Type |
|---|---|---|---|
| DEL-01 | Delete transactions | Confirmation shows items and total, success screen, selected rows removed, and counts, balance, and period update | ui/unit |
| DEL-02 | Delete transfer | Selection expands to both sides. Check message, two removed transactions, and balance | unit/ui |
| DEL-03 | Delete account | See ACC-03. Transactions and plans cascade, account page is unavailable | persistence |
| DEL-04 | Delete category | See CAT-05. Reassign to fallback and promote children | unit |
| DEL-05 | Delete plan | Occurrence or series, retain linked transactions, and confirm | unit/ui |
| DEL-06 | Delete all | See ONB-07 | persistence |
| DAT-01 | SwiftData schema | Account, Category, Operation, Period, and PlannedOperation. CloudKit-compatible defaults, optionals, inverses, and no unique constraints | unit |
| DAT-02 | Migration | Upgrade older store to PlannedOperation schema without losing data. Check counts and backup | persistence |
| DAT-03 | Repositories | Single write path, save and rollback, cascades, and fallbacks | unit |
| DAT-04 | Relaunch | Accounts, transactions, plans, settings, and periods persist. Deleted records stay deleted | persistence |
| DAT-05 | No first-launch demo data | `SeedData.bootstrap` is limited to categories and periods. Onboarding creates accounts | unit |
| DAT-06 | Backup | See SET-11…SET-13. Verify `.montra` format, lossless round trip, and restore into a clean store | unit/persistence |

### 2.12 Local API and Spotlight

| ID | Feature | Key checks | Type |
|---|---|---|---|
| API-01 | Auth and status | Token, 127.0.0.1, POST, 401 for invalid token, unavailable during onboarding or while disabled | integration |
| API-02 | list_accounts/categories/operations | JSON, sorting, date filters, limit, offset, amounts, and currencies | integration |
| API-03 | create_account/category | Validate name, currency, kind, and parent. Trim names, cover `is_savings` and `is_hidden_from_overview`, and check 422 errors | integration |
| API-04 | create_operation/import | Account currency, required fields, idempotency by external ID, batch 1…100, 409 for unsaved changes, and rollback on error | integration |
| API-05 | preview_import/import | Preview token, 409 on mismatch, duplicates, and row limit | integration |
| API-06 | Preview and delete account | 403 with allowDelete off. Preview token covers operation_ids and plan_ids. Delete account, transactions, and plans and check counts | integration |
| API-07 | Spotlight actions | Create expense, income, transfer, account, category, and subcategory. Double-to-Decimal amount, received amount required for different currencies, and errors and dialogs | integration |
| API-08 | Spotlight queries and Overview | Entity search by name, currency, and parent. Balance, overview, missingCurrencies, hideBalances, and macOS 26 availability | integration |
| API-09 | API settings | On and off, token, allowDelete, launch integration after onboarding, and surface failures | ui/integration |

### 2.13 About and Analytics

| ID | Feature | Key checks | Type |
|---|---|---|---|
| ABT-01 | About | Montra artwork, version, total across accounts in the primary currency, feature summary, and footer | ui/visual |
| ABT-02 | Replay | Preview banner, no writes, X closes, and completion opens Overview | ui |
| ABT-03 | Analytics | Period, month, and year scopes, previous/current stepper, summary expenses/income/left, savings transfers shown separately, category or account split, essential/discretionary filters, informational rows with plain transaction-style icons, expandable "Other" group for categories below 1% of expenses, cumulative chart with previous/even pace and month labels on the year axis, chart hover and keyboard, heat map with today marker, above-average accent palette and readout, interactive day-operations popup with scroll and close delay, non-clickable informational category/account rows, empty state, light/dark, and year boundaries. Engine: totals, savings in/out, comparison windows, cumulative endpoint, heat levels, chart ceiling, year day count | unit/ui/visual |

### 2.14 Formatting, accessibility, and animation

| ID | Feature | Key checks | Type |
|---|---|---|---|
| FMT-01 | Money | Narrow NBSP and decimal comma for Russian, symbol or code, per-currency precision, compact BTC, masks, and plus or minus signs | unit |
| FMT-02 | Pluralization | Russian one, few, and many forms for transaction, account, day, and payment | unit |
| FMT-03 | Dates | Today, Yesterday, Tomorrow, localized November 7, year for other years, time, periods, and genitive month names in Russian | unit |
| A11Y-01 | VoiceOver and labels | Labels for icons, buttons, rows, and headings, plus selection traits and empty states | ui |
| A11Y-02 | Keyboard | Tab and Shift-Tab, Space and Return, Escape, ⌘F, subtle sidebar focus, and standard content focus | ui |
| A11Y-03 | Reduce Motion | Disable blur, offset, spring, and digit transitions while keeping content accessible | ui |
| VIS-01 | Animations | Persistent route header with title and subtitle transitions and content crossfade. New rows, numeric transitions, hover, sheets, onboarding, and plans | visual |
| VIS-02 | Visuals | Light and dark, color and typography tokens, no clipped or doubled text, and header height | visual |
| VIS-03 | Snapshots | All screens render without crashing and can be compared with baselines, including Analytics tall dark and light | visual |

## 3. Invariants across scenarios

1. **Balances.** `balance = initial + incomes − expenses`. A transfer has two
   entries and stays out of expense, income, and mandatory totals. Plans stay
   out of financial totals until recorded.
2. **Writes.** Use the corresponding `*Repository` and `save()`. A failed write
   leaves no partially saved state.
3. **Periods.** Bounds are inclusive, transactions outside the current period
   leave its totals unchanged, and manual periods remain continuous.
4. **Categories.** Transactions have an Other fallback. Subcategories inherit
   mandatory status. Plans fall back to Other on category deletion.
5. **Plans.** Linking hides the pending plan and preserves the transaction.
   Deleting a series preserves linked transactions. Upcoming extends to two
   years or the series end, whichever comes first.
6. **Masks.** Check `hideBalances` across plans, sidebar, pickers, and API
   snapshots. Review CSV separately.
7. **Currency.** Amounts use the account currency. Convert only when a rate is known.
8. **Routing.** Onboarding ends at Overview. Incomplete onboarding resumes on
   relaunch, while older stores with accounts open the app. About preview leaves
   live data intact. Delete All Data immediately starts live onboarding.
9. **Identity.** Deleting and renaming preserve valid references. `transferID`
   and `seriesID` remain stable.
10. **Accessibility.** All actions are keyboard-accessible. Reduce Motion
    leaves content available.

## 4. Current automated coverage (`-selftest`, 160)

- Period generation, continuity, February clamping, fixed length, manual edits,
  and neighboring boundaries.
- Balances, signs, mandatory spending, allocation shares, conversions, totals,
  and compact BTC.
- Savings and Hide from Overview flags persist and can be cleared, with
  balances and transactions preserved.
- Category deletion fallback, subcategories, and inherited mandatory status.
- Transfer pair and `transferID`, balances, expense exclusion, and pair deletion.
- Today and Yesterday groups and new-row highlights.
- First launch without demo accounts, starter categories, live onboarding
  after reset with plans removed, resuming an interrupted flow with its existing
  account, and launching an older store without onboarding.
- Plans cover monthly clamping, weekly days, series, unchanged balance, linking,
  missed and upcoming filters, and series deletion.
- Analytics totals, free/mandatory split, savings in/out (transfers excluded from expenses and income), category rollup, previous-period comparison, cumulative endpoint, daily heat levels and their operations, filter counts, average, chart ceiling, month range, and current-year range with elapsed days.
- Formatting and pluralization.
- Spotlight ledger covers accounts, categories, subcategories, transfers,
  required received amounts, balances, Overview, missingCurrencies, and hideBalances.
- Backups cover format and checksum, capture, encoding, on-disk read, restore
  of all entities, exact Decimal amounts, hide flags, relationships, settings,
  rates, API switches, and rejection of damaged or unrelated files.
- The full round trip includes five accounts, 15 transactions, categories, a
  plan, periods, settings, rates, and API switches. It verifies balances,
  category parents, transfer links, plans, manual periods, and failure on a
  broken reference before deleting current data.

## 5. Gaps in automated coverage

- Live and preview onboarding UI, Delete All Data, and routing to Overview.
- Transaction form validation, quick categories, date and time, geolocation,
  editing, deletion, and recurrence.
- Plan detail, link picker, record flow, occurrence and series deletion, and
  missed and upcoming filters.
- Search, filters, periods, sorting, selected-row deletion, and empty states.
- Account editing and deletion, collapsing and lazy rows, and account plans.
- Category parent picker, system category protection, counts, and period UI.
- Appearance, hidden amounts, primary currency, rate refresh and fallback,
  CSV, reset, and API settings.
- Backup save and open panels, preview, pre-restore save, and success screen.
- Local HTTP API authentication, errors, idempotency, deletion and plans, and
  Spotlight App Intents beyond the ledger tests.
- Older store migration, relaunch, and restore UI. Self-test already covers
  the backup round trip.
- Shared header, Reduce Motion, focus, dark and light, and snapshot diffs.
- Analytics chart hover/focus, row keyboard navigation, and heat-grid arrow keys need a UI pass; the engine math and static snapshots are covered.

## 6. Known limitations

- iCloud uses CloudKit `.none`. `SyncService` is groundwork for future sync.
- Analytics converts every figure to the primary currency. A missing rate contributes zero rather than a guessed value.
- Analytics groups spending at the top-level category; a subcategory rolls into its parent.
- The Analytics month scope compares the previous month through the same elapsed days for totals and rows, while the chart shows the previous full month for context.
- Savings transfers are shown as a separate summary line and do not reduce the remaining figure; they are not spending.
- The year scope shows a 12-month summary card instead of the day calendar; use Period or Month for the day-level heat map.
- The "Other" group covers expense categories below 1% of total expenses and expands to its children; the other category rows remain read-only. The demo store has no such category, so it is not visible in the docs image.
- The calendar day popup is hover-only. It stays open while the pointer is over the cell or the popup and closes after a short delay when both are left.
- Recurrence is unavailable on Transfer.
- Editing a whole plan series requires deleting and recreating it.
- A linked plan stores `linkedOperationID`. Check the behavior when deleting
  the transaction separately.
- The default account list shows current-period plans. The full transaction list
  offers a future view.
- Open the full transaction list from Overview, ⌘2, or the menu.
- Local API and Spotlight availability depend on mode and macOS version.
  Settings shows why a feature is unavailable.
- CSV exports recorded transactions only.

## 7. Release smoke scenarios (P0)

1. **ONB.** Start from a clean store, create a 1,000 BYN account and first
   expense, finish onboarding, and verify the account in Overview.
2. **Onboarding after reset.** Delete all data, confirm live onboarding starts,
   create an account, and quit before finishing. Relaunch and verify that
   onboarding resumes with a single account. Complete it, verify Overview and
   the persisted account, and check that old plans are gone.
3. **ACC.** Create a EUR account, change its opening balance, and delete it
   with transactions. Verify balances and lists.
4. **OPS.** Create ten transactions on different days and check Today,
   Yesterday, and dated groups. Search, filter, change period and sort, and
   delete selected records.
5. **FRM.** Record an expense and income, use quick categories and More, set
   date and place, then edit and delete.
6. **TRF.** Transfer BYN to EUR with a manual received amount. Verify two rows
   and balances. Delete one side and verify both disappear and period spending
   is correct.
7. **CAT.** Create a mandatory parent and subcategory. Delete the parent and
   verify the child moves to the top level and transactions move to Other.
8. **PER.** Use payday on the 31st in February, edit a period, verify continuous
   neighbors, and recalculate.
9. **PLN.** Create a monthly plan with missed and upcoming occurrences. Test
   both filters, link an existing transaction, record a new transaction, and
   delete one occurrence and a series.
10. **SET.** Hide amounts, switch appearance and primary currency, export CSV,
    and delete all data. Verify onboarding and Overview.
11. **BAK.** Save a backup, change or delete data, and restore. Verify counts,
    balances, category parents, plans, manual periods, appearance, masks, and
    currency. Verify Overview opens and a damaged file leaves current data intact.
12. **DAT.** Relaunch and verify accounts, transactions, plans, periods, and settings.
13. **API/SPT.** When available, verify status and token, create a transaction,
    delete an account with plans, and run Spotlight actions.
14. **ABT.** Open Analytics, switch Period and Month, step through periods and
    months, change Category/Account and the filters, expand a row, hover the
    chart and heat map, and verify the empty state on a store without spending.

## 8. Coverage priorities

1. **P0 money logic.** `Finance`, `PeriodService`, `PlanSchedule`,
   `MoneyFormat`, `CSVExporter`, and repository writes, cascades, and fallbacks.
2. **P0 data integrity.** Delete transactions, transfers, accounts, categories,
   plans, and all data. Cover store migration, relaunch, backup round trip,
   restore, and failures.
3. **P0 UI flows.** Live, preview, and post-reset onboarding, Overview routing,
   transaction and transfer forms, and deletion.
4. **P1 lists.** Day groups, search, filters, period, sorting, selection, plans,
   and plan filters.
5. **P1 settings.** Masks, theme, primary currency, periods, rates, CSV, API,
   and backup UI.
6. **P1 integrations.** Local API authorization, errors, preview, import, and
   deletion, plus Spotlight on macOS 26.
7. **P2 visuals and accessibility.** Shared header, Reduce Motion, focus,
   light and dark, and snapshot diffs.

Use Swift Testing or XCTest with an in-memory `ModelContainer` for pure logic,
as in `SelfTest.swift`. Use XCUITest on a temporary store for UI flows, with
`-preview-onboarding` for onboarding and a separate store for other cases.
Start `LocalHTTPServer` in API tests and check HTTP status and JSON, including
the token and onboarding gate. Compare PNGs from `-snapshot` against baselines.
Check static header and dimensions. Video and frame-by-frame animation checks
are optional. Copy the store before destructive tests and restore it afterward.
