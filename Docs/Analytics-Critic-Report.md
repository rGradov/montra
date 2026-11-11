# Analytics critic pass

Date: **2026-11-11**
Branch: `wip/analytics-swift-impl`
Scope: native `Аналитика` screen after the owner's review
Verdict: **Approve with minors**

This pass reviews the SwiftUI screen, the engine numbers, the light and dark
renders, and the behavior changed by the review. It is a code-and-render critic
pass; no separate critic agent could be launched from this delegated session.

## Build and evidence

- `-selftest`: **ALL CHECKS PASSED**, 160 checks.
- `audit-feature-sync.py --require-dmg`: **7 passed, 0 warnings, 0 failures**.
- DMG: `build/Montra-1.0-analytics-screen-v3.dmg`.
- Renders: `build/analytics-snaps/06b-analytics-tall.png`,
  `build/analytics-snaps/08b-analytics-light.png`.
- Docs: `Docs/screenshots/analytics.png`, `Docs/screenshots/analytics-light.png`.

The test store has no spending in the previous period, so the summary
intentionally says «нет прошлого периода» and the chart has no previous/pace
line. The comparison path is covered by the engine tests.

## Data reconciliation

| Figure | Value | Cross-check |
|---|---|---|
| Expenses | 1 468,53 Br | categories sum to 1 468,53 |
| Categories | 950,00 + 278,50 + 98,90 + 56,90 + 33,43 + 26,00 + 24,80 | 1 468,53 |
| Heat days | 950,00 + 214,30 + 50,50 + 33,43 + 86,40 + 24,80 + 83,10 + 26,00 | 1 468,53 |
| Chart endpoint | 1 468,53 Br | same total |
| Average | 52,45 Br/day | 1 468,53 ÷ 28 elapsed |
| Income | 5 198,89 Br | 3 incomes |
| Remaining | 3 730,36 Br | 5 198,89 − 1 468,53; 71,8% |
| Savings in | 100,00 Br | destination leg of the transfer to the BTC savings account |
| Operations | 17 | 13 spending/income operations + 4 transfer legs |
| Y axis | 0 / 500 / 1 000 / 1 500 / 2 000 | five labels, not sixteen |

Savings transfers are excluded from expenses and income. The transfer's two legs
do not appear in categories, the bar, the heat map, or the cumulative chart.
They appear only in the savings line. The engine test covers both directions:
100 into savings, 50 out, with expenses and income unchanged.

## New in this pass

- **Year scope.** Period, Month, and Year sit in the same header control. Year
  renders the year summary, the category breakdown, a 365-day cumulative chart
  with month labels, and a 12-month “По месяцам года” card. The day heat map is
  intentionally period/month only.
- **“Прочее”.** Expense categories below 1% of total expenses collapse into one
  “Прочее” row. It alone is expandable; its children show their own amount and
  share. The other category and account rows remain informational.
- **Interactive day popup.** The popup now survives the pointer moving from the
  cell into it, scrolls through every operation, has a close delay, and uses the
  raised card surface with a small caret. The old 4-item truncation is gone.

## Scroll, animation, and palette pass

- Removed the per-row hover. The only remaining hover is on the progress bar;
  the row highlight is driven by that bar. When the bar scrolls out of view there
  is no hover state left to recalculate, and scrolling over the category rows no
  longer invalidates the card. This is the code-level fix for the reported
  stutter; no Computer Use / Instruments capture was possible in this session.
- The summary expenses/income/remaining now reveal from 0 with
  `.numericText()` and `AppMotion.number`, matching Overview. The reveal runs on
  first appearance and value changes.
- The heat above-average accent changed from amber/brown to `Chart.sky`, so the
  calendar no longer reads brown against the dark new-operation sheet. The
  legend and above-average cells use the same cool accent in light and dark.

1. **Category and account icons — fixed.** Rows use `ListRowIcon`, the same plain
   category-coloured glyph as the transaction list. The rounded gradient tiles
   are gone. The bar still uses the palette colour.
2. **Calendar focus — fixed.** The heat grid and chart overlay use
   `.focusEffectDisabled()`. The giant white focus rectangle is gone; keyboard
   focus remains, and only the today/active cell rings are drawn.
3. **Above-average days — fixed.** Days above `snapshot.average` use the amber
   chart colour with an opacity tied to the heat level. The legend has an amber
   «выше среднего» swatch; the day readout and accessibility label append
   «выше среднего». In the demo, 4/5/8/10 are amber, 6/7/9/11 stay neutral.
4. **Pace chart — fixed.** The Y axis uses a nice step chosen from the peak and
   shows four or five labels. The demo shows 0/500/1,000/1,500/2,000; a 5,741 Br
   period would show 0/2,000/4,000/6,000.
5. **Savings — fixed.** A savings footer appears under the three summary
   columns: «В сбережения» in green with the transfer amount, or «Из сбережений»
   as a negative amount for the reverse direction. The snapshot shows
   `100,00 Br`; the cash balance drops to `188,60 Br` without going negative.
6. **Light/dark.** Both renders use the app tokens. The amber heat cells remain
   legible in light mode; the plain icons keep their colour.
7. **Density.** The plain icons reduce visual noise in the breakdown. The summary
   footer adds one row without breaking the three-column rhythm.
8. **Day operations popup — added.** After a 350 ms hover, the heat cell opens a
   floating card with the date, the day's total, up to four expense operations
   (category icon, title, original amount), and “ещё N” when there are more. It
   uses the raised surface, hairline border, app typography and plain row icon;
   it disappears when the pointer leaves. The readout and popup now use the
   actual `AnalyticsDay`, so the amount and the operations always agree.
9. **Category rows — simplified.** The rows and the bar are no longer clickable,
   and the partial four-operation inline list is gone. A category shows its
   total, count, share and delta; the full ledger is opened in Operations, and a
   single day can be inspected in the calendar popup. This removes the
   “random four operations” problem the owner reported.
10. **“Прочее” grouping — added.** The threshold is 1% of total expenses. The
    group is the only expandable row and reveals the minor categories, not
    operations. The demo store has no category below 1%, so it is absent from the
    docs image; the test store does not exercise the view grouping.
11. **Year — added.** The year header shows `2026`, `Год`, the same summary and
    breakdown, a cumulative pace chart with `янв./март/май/июль/сент./сегодня`,
    and 12 month tiles. The current month is outlined; future months are muted.
12. **Popup — fixed interaction.** The popup is hit-testable; moving into it
    cancels the close, leaving both closes after 220 ms. The content scrolls up
    to 180 pt, so a long day is fully readable. The caret points at the cell and
    the raised surface distinguishes it from the card.

## Interaction and performance findings

- Row hover and selection, dimension, filter, and heat-day state live in the
  card views, not in `AnalyticsView`. Hovering a row no longer invalidates the
  chart or the whole page. This removes the likely source of the reported scroll
  stutter: parent-owned hover/selected/heat state caused the chart, heat grid,
  and summary to re-render on pointer movement.
- The rounded gradient tiles were replaced with plain glyphs, removing per-row
  gradient and compositing work.
- The chart computes its data and axes once per period change; it is not
  re-evaluated on scroll.
- The year scope uses the same chart and a lightweight 12-tile summary instead of
  a 365-cell heat grid, so switching to Year does not create a huge calendar.
- No Instruments capture was run in this session; the fix is code-level. If a
  stutter remains on a very large store, profile the `ScrollView` with Time
  Profiler and check the chart before changing the layout again.
- The calendar keeps arrow keys after the focus ring is disabled. The chart keeps
  hover and left/right focus inspection. The category rows keep Tab, up/down,
  and Escape.

## Minors (not approval blockers)

- The demo snapshot has no previous-period spending, so the comparison UI is not
  visible in the docs image; the engine test covers it.
- The month scope is covered by engine tests, not by a tall snapshot.
- The chart omits the crowded `30` tick when today is 28 so «сегодня» stays
  complete.
- Savings do not reduce «Остаток»; they are money moved, not spent, and the
  savings line explains the movement.
- Categories roll up to the top level; a subcategory's spending is shown under
  its parent.
- A missing exchange rate contributes zero rather than a guessed amount.
- The screen uses the primary currency; there is no per-screen currency selector.
- The Calendar focus ring is disabled, so the card relies on the cell rings and
  the readout for keyboard feedback.
- The year view has no day-level heat map; switch to Month or Period for it.
- The “Прочее” group is not visible in the docs demo because every seeded
  category is above 1%. It needs a real or test category below the threshold.
- A one-operation day leaves empty space in the 220 pt popup frame; the popup
  stays compact at the top or bottom, but the frame is intentionally fixed so
  the caret stays attached.
- The popup is hover-only; keyboard users get the readout, not the operations
  list.
- The first attached screenshot is the category picker, not the Analytics
  calendar popup. Its material/blur background is outside the Analytics files
  and was not changed in this pass.
- The user mentioned a video, but no video file was included; only the two
  screenshots were available, so no frame-by-frame review was possible.

## What is genuinely good

- The period/month unit, prior-period comparison, and heat calendar agree with
  the product language.
- The savings line corrects the false "spent" reading without disturbing the
  category, chart, or heat totals.
- The plain icons match the transaction list and make the breakdown quieter.
- Above-average amber is an explainable signal rather than decoration.
- The chart and heat interactions survive the focus and performance changes.
- The day popup is the right place for a per-day operation preview; it does not
  turn Analytics into a second, truncated ledger.

## Recommended next checks

1. On a large real store, scroll `Куда ушли деньги` and confirm no hover-driven
   chart redraw.
2. Make a transfer into a savings account and verify the summary says
   «В сбережения», while expenses, categories, heat, and the chart stay
   unchanged.
3. Make a transfer out of savings and verify the negative «Из сбережений» line.
4. Inspect the month scope and the empty state visually.
5. Hover several heat cells, including the first/last column, and check the popup
   stays inside the card and above/below the cell without clipping.
6. Switch to Year and check the month labels, the current month outline, and the
   year totals; switch back to Period.
7. Add a category below 1% of spending, reload Analytics, and expand “Прочее”.
