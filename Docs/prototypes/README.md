# Analytics screen prototype

`analytics.html` is an **interactive design prototype** of the «Аналитика» screen.
It is an approval artefact, not app code: it opens in a browser, uses mock data,
and must not be shipped inside the app bundle.

The screen it proposes replaces today's placeholder
(`Montra/Features/Analytics/AnalyticsView.swift`, "Здесь появятся графики").

## Open it

```bash
open Docs/prototypes/analytics.html
```

Single file, no build step, no network access. Use the dev panel under the
window to switch the theme and to preview the empty state.

## What it proposes

The screen answers four questions in this order, using Montra's own unit of
time — the **period** (payday to payday), not the calendar month:

1. **Сколько ушло и сколько осталось** — one card, three figures separated by
   hairlines, not three coloured boxes. In the period scope: расходы, доходы and
   «Свободно» — the app's own `Finance.free` (доходы минус обязательные). In the
   month scope: расходы, обязательные and свободные, so a partial month with no
   income yet never prints a negative "remainder".
2. **Куда ушли деньги** — a 100% segmented bar in the idiom of the Overview's
   balance bar, plus rows for categories or accounts. Sliced by
   все / обязательные / свободные, with a delta against the previous period and
   an inline list of the latest operations per category.
3. **Быстрее или медленнее обычного** — cumulative spending against the previous
   period's cumulative curve and its even pace, with a today marker and a
   plain-language verdict.
4. **Что из этого следует** — a short "наблюдения" list (share of mandatory
   spending, dominant category, biggest growth, only decline).

A calendar heat grid replaces a daily bar chart: one rent-sized day would flatten
the other thirty bars.

### Deliberate differences from the owner's sketch

The reference image was used for information architecture only. The prototype
does not carry its mint accent, donut chart, 20px+ radii, coloured stat boxes,
gradient fills or floating dark tooltips, because none of those belong to
Montra's palette or component set.

It also does **not** show a monthly budget or a "forecast to the end of the
month": the app has no budget field, so the comparison is grounded in the
previous period's actual total and the observed daily pace.

## Data

All figures derive from one generated ledger — category totals, shares, the
mandatory/free split, per-account totals, daily series, the cumulative curve and
the comparison deltas. Nothing is typed into the markup by hand.

- Contract for the current period: `1 468,53 Br`, of which `1 204,20 Br` (82%)
  mandatory; previous period `1 311,04 Br`.
- `generate-data.py` reproduces the ledger (`build/analytics-data.js`, which the
  prototype inlines). The generator asserts that every category total matches
  the contract and that no operation falls outside its period or after "today".
- The prototype is BYN-only: every mock operation is in the display currency.
  The real screen aggregates into the display currency through
  `ExchangeRates`, the way the Overview already does.

## Fidelity notes

Tokens, radii, spacing and the type scale are copied from
`Montra/Design/Theme.swift`; components follow `Montra/Design/Components.swift`.
Two details worth knowing when comparing against `Docs/screenshots/`:

- The sidebar draws a bare coloured glyph (12px inside a 16px frame), as the
  current code does. The screenshots still show the older coloured icon tiles.
- Onest ships without digits, exactly as in the app, so prose never shows its
  own figures: every number is rendered in SF Rounded.

## Porting to Swift

| Prototype | Where it belongs |
|---|---|
| Aggregates, shares, deltas | extend `Montra/Store/Finance.swift` (pure functions, as today) |
| Segmented bar | reuse `BalanceBar` from `OverviewView.swift` |
| Card and rows | `OverviewCard`, `InsetCardDivider`, `IconTile`, `FilterChip` |
| Colours and type | `AppColors`, `AppStyle`; figures via `TextStyle.numbers` |
| Period switching | `Period` + `PeriodService`; a month is derived, not stored |
| Strings | `Localizable.xcstrings`, `ru` and `en` |

Persisted data does not change: the screen reads accounts, operations,
categories and periods that already exist, so no backup, Local API or MCP work
is required for the read-only version. A later "save this view" or budget
feature would need all three.
