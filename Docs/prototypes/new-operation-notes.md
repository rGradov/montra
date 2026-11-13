# New operation sheet prototype

`new-operation.html` is an **interactive approval prototype** of the «Новая операция»
sheet. It is not app code: it opens in a browser, uses mock data, and must not be
shipped inside the app bundle.

The current screen is the owner's complaint: eight sections of equal weight, a
comment field that disappears under the footer, field heights that read as an
accident, and the same 12 pt gap everywhere. The owner's gold standard is the
**«Новый счёт»** sheet — calm groups, one switch card, one hairline section, a
footer that never covers a field.

## Open it

```bash
open Docs/prototypes/new-operation.html
```

The sheet is open on load. Close it with the X, «Отмена» or `Esc`; the background
«Новая операция» button reopens it. The dev bar below the window toggles
dark/light and resets the form.

- Type an amount to enable the primary action.
- Tabs switch Расход / Доход / Перевод; the account supplies the currency.
- Account row: listbox with balances.
- Category: five quick chips + «Ещё» with search; the current category is pinned
  first in the picker.
- Date: calendar, month arrows, editable time, «Сейчас».
- Repeat: the switch card expands in place with frequency, end date and a
  payment-count summary; the footer becomes «Создать график».
- Transfer: from/to, sent/received with a rate, swap, validation.
- `⌘↵` adds, `Esc` closes; a success toast stays after the sheet closes.

## What it proposes

1. **One focal figure.** The amount is a 48 pt field with a 26 pt SF Rounded
   number; everything else is 13 pt or quieter. The current form gives the amount
   the same visual weight as the place field.
2. **Счёт and Дата и время on one 32 pt row.** Two short values instead of two
   full-width blocks. This saves 53 pt and lets the comment sit above the footer.
   The account balance stays in the field label, where the app already puts it.
3. **Repeat is the account sheet's switch card.** Same fill, border, icon, title,
   description and switch as «Скрыть из обзора». When on, the schedule grows
   inside the card — frequency, end date, «13 платежей · ежемесячно · до …» —
   rather than becoming another section.
4. **A real hierarchy for the optional fields.** A 1 pt hairline splits the core
   (amount / account / category / repeat) from the quiet details (place, comment).
   The details use the same 32/48 pt fields, not a second visual language.
5. **No clipping.** The sheet is 470 × 674; the default content is exactly 533 pt
   in a 533 pt body, so the comment and its border are fully visible above the
   footer. The current sheet's comment is cut by the footer.
6. **Light and dark from the app's tokens**, not a new palette. The switch,
   secondary actions, chip selection and focus rings all have light and dark
   values.

## Deliberate differences from the current screen

- **Two-column account/date row.** The account sheet is single-column; a
  desktop operation form can pair two short values without breaking the rhythm.
  The row is the reason the whole form fits at 674 pt. If the owner rejects it,
  the fallback is a single column plus either a taller sheet or an explicit
  «Детали» disclosure.
- **Repeat expansion inside the card.** The account sheet's switch does not
  expand, but a recurrence needs its schedule next to the switch. The card keeps
  the account-sheet surface and typography; the extra is an inner block, not a
  new card.
- **674 pt instead of 650.** The operation form has more fields than the account
  form. At 674 the form fits without clipping and leaves 23 pt above/below in a
  720 pt window; in the app's 700 pt default window it leaves 13 pt. The account
  sheet remains 650.
- **1 pt section/footer hairlines.** The app uses 0.5 pt; the prototype uses 1 pt
  so the grouping is visible at 1× and in screenshots. In Swift, use the app's
  0.5 pt `borderSubtle`.
- **Line icons in the category chips.** The owner's current data mixes emoji and
  symbols. This prototype uses the app's icon appearance consistently; the app
  still supports emoji through the same picker.
- **Mock data and a fixed demo clock.** The amount starts empty; the date is
  12 нояб. 2026, 14:56 to match the owner's screenshot; «Сейчас» uses the real
  clock.

## Fidelity notes

Tokens are copied from `Montra/Design/Theme.swift`; component behaviour follows
`Montra/Design/Forms.swift` and `Components.swift`; the screen structure follows
`OperationSheet.swift` and the rhythm of `AccountSheet.swift`.

| Prototype | Swift |
|---|---|
| Sheet 470 × 674, 14 pt radius | `.frame(width: 470)`, sheet chrome |
| Header (15/12) + 24 pt close | `SheetHeader` |
| Mode chips (28 pt) | `ChipGroup` + `FilterChip(.tab)` |
| Amount 48 pt, 26 pt rounded | `TextField` + `.system(size: 26, weight: .semibold, design: .rounded)` |
| Account + date row | two `FormField`s in an `HStack`; `DropdownMenu` + `DatePickerField` |
| Category chips + «Ещё» | `FlowLayout` + `categoryChip` + `CategoryPickerPopover` |
| Repeat card | `Toggle` + `ChipGroup` + `DatePickerField` inside the card surface |
| Details | `FormField` + `MontraTextField` (place), vertical text field (note) |
| Footer | `SheetFooter` + `MontraButtonStyle` |
| Account / category / date popovers | `PopoverMenu`, category picker panel, `MontraDateTimePicker` |
| Validation | `OperationSheet.isValid` / `planIsValid` / transfer validation |
| Theme | `AppColors`, `AppStyle`; numbers through `TextStyle.numbers` |

Sheet geometry in the prototype: 24 pt horizontal insets, 12 pt group rhythm,
16 pt around the section hairline, 24 pt top / 16 pt header bottom, 16 pt footer
vertical, 63 pt footer. Type: 15/600 title, 12 subtitle, 26/600 amount,
13 body, 12/500 labels, 11 hints.

## Native port

The redesign is implemented in SwiftUI on branch `codex/new-operation-sheet`:

- `Montra/Features/Operations/OperationSheet.swift` — 534 pt scrolling body in a
  470×674 sheet: amount hero, account/date pair with the balance left-aligned,
  repeat card on `fillSecondary` with raised chips, hairline before place/note,
  transfer from/to row with a swap control, and auto-scroll to the repeat card.
- `Forms.swift` / `Components.swift` — `ChipGroup.chipBackground` and
  `FilterChip.unselectedBackground` keep inner chips readable on the card.
- `SnapshotRunner.swift` — fixtures `10`, `10a` filled, `10b` repeat, `10c`
  transfer, `10d` light.
- `Localizable.xcstrings` — `transaction.form.swap_accounts` (ru/en).

Build and `-selftest` pass. The native keeps the app's category hierarchy, the
weekly weekday picker, the transfer «По курсу» reset and approximate-rate note,
and the «Создать план» vocabulary.

## Verification

- **54/54 interaction checks** (headless Chrome, CDP): initial validation, income
  switch + category reset, EUR account + currency, date picker, repeat month/week,
  transfer prefill/conversion/swap/validation, theme toggle, add → toast → close
  → reopen, `Esc`, and no JavaScript errors.
- Evidence renders: `build/proto/newop/critic/01-default-dark.png` … `08-full-composition.png`.
- The independent critic pass and the applied changes are recorded in
  [`Docs/New-Operation-Critic-Report.md`](../New-Operation-Critic-Report.md).

## Known limitations

- Mock data only: adding an operation shows a toast and closes the sheet; it does
  not change the mocked ledger behind it.
- The transfer form is short and leaves empty space above the footer; the sheet
  height is fixed like the app's sheet.
- The repeat expansion scrolls the body to the repeat card; place and comment
  stay reachable. The scroll fade only appears when the body overflows.
- The account/title backdrop is a static mock, not a real Overview render.
- The demo date is fixed to 12 Nov 2026 for the owner's comparison; it is not
  today's date.
- Exchange rates are fixed mock values; no network access.
- The prototype is 470 CSS px wide. It is intended for a desktop browser; there
  is a narrow-window fallback, not a mobile layout.

## Files

- `Docs/prototypes/new-operation.html` — the self-contained prototype (HTML + CSS
  + JS + embedded Onest).
- `Docs/prototypes/reference/new-operation-current.webp` — the owner's current
  screen.
- `Docs/prototypes/reference/new-account-reference.webp` — the account sheet
  used as the gold standard.
- `build/proto/newop/` — evidence, metrics, interaction tests and the critic
  report (working folder).
