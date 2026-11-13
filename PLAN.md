# Montra implementation plan

The design uses a warm graphite palette, Onest typography, SF Rounded numerals,
compact controls, and animated transitions. The personal finance workflows
were designed for Montra.

## Phases

- [x] **0. Visual foundations**
  Defined the palette and typography, 980×700 window, 240-point sidebar,
  24/30/38-point buttons, 4/6/8/14-point radii, Onest with numerals removed,
  SF Rounded numerals, and 0.12/0.15/0.45/0.6-second animations. Reviewed
  `AppColors`, `AppStyle`, `FilterChip`, `AppChrome`, and `SettingsView`.
- [x] **1. Project skeleton**
  Xcode synchronized group, macOS 15+, and a build without errors or warnings.
- [x] **2. Design system**
  Color, type, and layout tokens, `MontraButtonStyle`, cards, rows, pills, badges,
  chips, toggles, popovers, fields, hover and press states, and `accessibilityReduceMotion`.
- [x] **3. Data**
  CloudKit-compatible SwiftData models (Account, Category, Operation, Period),
  seed data, repositories, `PeriodService`, `SettingsStore`, and `SyncService`.
- [x] **4. App shell**
  Title-bar-free window, sectioned sidebar with New Account, routing, and status pill.
- [x] **5. Overview**
  Hero balance, allocation bar with hover details, accounts, period, recent
  transactions, empty states, and currency chips.
- [x] **6. Transactions**
  Filter chips, selection, sorting, batch deletion, creation and editing of
  expenses or income, date and time, place, geolocation, note, and context menu.
- [x] **7. Accounts**
  Creation with icon, color, currency, and opening balance, plus detail,
  editing, and cascade deletion.
- [x] **8. Categories**
  Fourteen starter categories, mandatory status, custom categories, editing,
  and transaction reassignment on deletion.
- [x] **9. Financial periods**
  Payday or fixed length, materialized periods, manual boundaries, reset to
  rule, and a period sheet.
- [x] **10. Settings, Analytics, and About**
  Appearance, hidden amounts, period, CSV export, iCloud status, and Analytics placeholder.
- [x] **11. Visual verification**
  Rendered every screen through NSHostingView and refined spacing, menus, the
  toggle, appearance previews, and date fields.
- [x] **12. Wrap-up**
  App icon, `-selftest`, README, MasterPrompt, iCloud instructions, and build.
- [x] **13. Sidebar accounts and rates**
  All accounts with balances under Overview, a total across currencies,
  National Bank of Belarus conversion with a public fallback feed, six-hour
  cache, rate row and account breakdown on hover, and an approximation marker
  in the account list and detail.
- [x] **14. New transaction animation**
  A new row enters with slight scale and blur (0.34-second spring) and a
  1.4-second highlight that fades in Transactions, Overview, and account
  detail. Batch inserts do not flash.
- [x] **15. Transactions as an Overview subpage**
  Open the full list from Overview or with ⌘2. Overview stays selected in
  the sidebar and the page has a back link.
- [x] **16. Onboarding**
  Welcome, first real account, starter categories (skip keeps Other), optional
  first expense, and a completion screen with sparkles and an animated balance.
  Steps use 0.45-second blur and opacity transitions, staggered entrances,
  and 240×38 buttons. The flow starts on a fresh store.
- [x] **16b. Account transition after onboarding**
  The account card moves and scales into its sidebar row with a spring.
  The row stays hidden until the card lands and the rest of the app appears
  during the transition. Reduce Motion or missing measurements use a fade.
- [x] **16c. Savings accounts**
  Added a Savings Account switch to account creation, editing, and onboarding
  at this stage. Savings accounts have their own group and a label in Overview
  and account detail. Deposits, withdrawals, and transfers work as before.
  The flag also supports future savings trends in Analytics.
- [x] **17. Animated page subtitles**
  Titles and subtitles rise with blur on entry. The subtitle is delayed by
  0.07 seconds and counts animate digit changes. Overview shows the current
  period and replays the subtitle after closing the period sheet.
- [x] **18. Collapsing rows on filter changes**
  Account rows stay in the hierarchy and animate height with a 0.4-second
  spring and 0.02-second stagger. Spacing collapses with each row, and empty
  states fade in.
- [x] **19. Transaction search**
  Capsule field matches category, account, place, note, and amount. Updates
  chip counts and the header subtitle. Offers Clear Search, Show All, Search
  All Time, and the ⌘F and Escape shortcuts.
- [x] **20. Balance allocation bar**
  Rectangular segments share one capsule, with 2-point gaps and a minimum
  width of 4 points. Only the outer ends are rounded.
- [x] **21. Compact steppers**
  Payday and Period Length in Settings and the period sheet use
  `− value +` controls with bounds and animated digits.
- [x] **22. Direct stepper input**
  Click the value to enter digits. Return or loss of focus clamps to the
  valid range. The label shows the value and unit at rest. The step buttons
  still work.
- [x] **23. About and onboarding preview**
  About shows the logo placeholder, name and version, total balance, feature
  summary, and a button to repeat onboarding. The preview opens over the
  window with an in-memory store and closes via X or Escape. Welcome uses
  the same logo placeholder.
- [x] **24. Currency change animation**
  In onboarding and the new account sheet, the currency symbol animates in
  a fixed slot over 0.22 seconds. The old symbol rises out and the new one
  enters from below. Currency capsules animate selection.
- [x] **25. Account appearance and completion animation**
  A pencil tile beside the first account name opens icon and color choices.
  The new account uses that appearance. Completion sparkles scale, rotate,
  and glow gently, and stay static with Reduce Motion.
- [x] **26. Calendar and time picker**
  `MontraDateTimePicker` provides month arrows, a 6×7 grid in the app palette,
  selected and current days, validated `hh:mm`, Now, Today, Done, and range
  support. It is used for transactions and periods.
- [x] **27. Transaction deletion**
  Select rows or Select All. The header shows the count and amount with
  Delete (N). A confirmation sheet lists the transactions and total. A
  success screen shows a drawn checkmark, amount, count, time, and Done.
- [x] **28. Selection and deletion on the account page**
  Compact rows have checkboxes and Select All follows the current filter.
  The header shows the selection count and amount and Delete (N). The full
  transaction list and account page share confirmation and success screens.
- [x] **29. Performance with large accounts**
  Query only the account's transactions with `@Query` and sort in the store.
  Use `LazyVStack` above 60 records and collapsing rows for smaller accounts.
  Avoid rebuilding ID arrays during animations and row tracking. Verified
  with over 1,000 transactions.
- [x] **30. Transfers between accounts**
  The third transaction tab uses the common account picker, sent and received
  amounts, a rate estimate, and a manual received amount. Two linked entries
  share a `transferID`, show a Transfer label and read-only details, and are
  excluded from period income and expenses. Deleting one side deletes both.
- [x] **31. Subcategories and category selection**
  One nesting level, Parent Category and No Parent choices, a hierarchy on
  the categories page, inherited mandatory status, and child promotion after
  parent deletion. The transaction form shows five frequent categories and
  a More popover with capsule search across the hierarchy.
- [x] **32. Day groups**
  The full transaction list and account page group by Today, Yesterday,
  Tomorrow, or dates such as October 7, with the year when needed. Headers
  stick on scroll. Sorting by amount uses a flat list. Small accounts keep
  collapsing rows.
- [x] **33. Recurring payments**
  The transaction form offers daily, weekly, monthly, or yearly recurrence,
  weekdays, and an end date. Generated plans appear in the full list and
  account page without changing balances. Missed and Upcoming filters,
  linking, recording, and occurrence or series deletion are available.
  Upcoming plans are limited to two years or the end of the series.
- [x] **34. Onboarding after reset**
  Delete All Data immediately starts onboarding on the live store and the
  account persists. Both live onboarding and the About preview end at
  Overview. The preview explains that data will not be saved.
- [x] **35. First account is a regular account**
  Removed the Savings Account switch from onboarding. Savings accounts are
  created later through the account sheet. Only Housing, Food, and Salary
  are selected by default, and other categories can be selected with one click.
- [x] **36. Backup**
  One `.montra` file includes accounts, both sides of transfers, categories
  and parents, plans, periods, settings, exchange rates, and Local API
  switches. **Settings → Backup** offers save and load panels, a contents
  preview with replacement warning, and a pre-restore backup. Montra checks
  the format version, SHA-256, amounts, and references before deleting any
  existing records. Successful restore opens the updated Overview.
  [Backup format](Docs/Backup.md)

## Verification

- `-selftest` passed 131 checks covering period continuity, clamping the 31st,
  fixed lengths, adjusted boundaries, balances, amount signs, mandatory
  expenses, category deletion and reassignment, USD/EUR/BYN conversion, totals
  across accounts, row highlights, clean launch, onboarding after reset,
  currency formatting, pluralization, and backup round trips. Backup coverage
  includes file writes and reads, decimal precision, invalid and unrelated files,
  relationships, settings, rates, API switches, and rejection before deleting data.
- `-snapshot` generated 34 PNGs covering Overview and its full page,
  Transactions, account detail, Categories, Settings, Analytics, About, light
  appearance, and sheets including backup restore.
- `xcodebuild` reported `BUILD SUCCEEDED` without Swift warnings.

## Next steps at the end of this iteration

1. Analytics for spending by category and period trends. Data is already grouped.
2. Transfers between accounts with rates and history.
3. Recurring transactions for rent and subscriptions with prefilled fields.
4. ~~Enable iCloud.~~ Done: SwiftData mirrors the ledger through CloudKit into
   the private database. See `Docs/iCloud-Setup.md`.
5. Custom account icon assets. `IconTile` already renders a matching named asset.
6. An iOS target using shared models.
