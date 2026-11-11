"""Generate a coherent mock ledger for the Analytics prototype.

Usage: python3 Docs/prototypes/generate-data.py [out.js]
Default output: build/analytics-data.js (git-ignored; the HTML inlines it).

Single source of truth: individual operations. Category totals, daily series,
account splits and comparisons are all derived from them, so the page cannot
show numbers that disagree with each other.
"""

import json
import random
import sys
from datetime import date, datetime, timedelta

random.seed(20261111)

CENT = 1

CATEGORIES = [
    # key, ru name, color key, mandatory, glyph
    ("housing", "Жильё", "blue", True, "house"),
    ("food", "Еда", "green", True, "cart"),
    ("transport", "Транспорт", "teal", True, "tram"),
    ("restaurants", "Рестораны", "orange", False, "fork"),
    ("subscriptions", "Подписки", "amber", False, "repeat"),
    ("shopping", "Покупки", "pink", False, "bag"),
    ("health", "Здоровье", "red", True, "health"),
    ("entertainment", "Развлечения", "purple", False, "gamepad"),
]
# Health and housing are mandatory in the seed; health is flagged mandatory too.
MANDATORY = {"housing", "food", "transport", "health"}

ACCOUNTS = [
    ("Карта", "card", "blue"),
    ("Наличные", "cash", "green"),
    ("Revolut", "revolut", "sky"),
    ("Крипто", "crypto", "amber"),
]

ACCOUNT_WEIGHTS = {
    "housing": [1.0, 0.0, 0.0, 0.0],
    "food": [0.58, 0.37, 0.05, 0.0],
    "transport": [0.5, 0.5, 0.0, 0.0],
    "health": [0.7, 0.3, 0.0, 0.0],
    "restaurants": [0.45, 0.2, 0.35, 0.0],
    "entertainment": [0.4, 0.0, 0.6, 0.0],
    "shopping": [0.45, 0.0, 0.35, 0.2],
    "subscriptions": [0.3, 0.0, 0.7, 0.0],
}

PLACES = {
    "housing": ["Аренда квартиры"],
    "food": ["Евроопт", "Корона", "Green", "Копеечка", "Рынок", "Алми", "Санта"],
    "transport": ["Метро", "Автобус", "Яндекс Go", "Такси", "Проездной"],
    "health": ["Аптека", "Стоматология"],
    "restaurants": ["Кофейня у дома", "Суши", "Пицца", "Бар «Среда»", "Обед с командой"],
    "entertainment": ["Кино", "Концерт", "Настольные игры"],
    "shopping": ["Wildberries", "Ozon", "Книги", "Одежда"],
    "subscriptions": ["iCloud+", "Spotify", "Notion", "VPN"],
}

# Exact contract per period, in cents.
PERIODS = [
    {
        "key": "p-2",
        "start": date(2026, 8, 15),
        "end": date(2026, 9, 14),
        "today": None,
        "title": "15 авг. — 14 сен.",
        "expenses": {
            "housing": 60000, "food": 28000, "transport": 11000, "restaurants": 7000,
            "subscriptions": 5500, "shopping": 3000, "health": 2500, "entertainment": 1000,
        },
        "income": [("Зарплата", "salary", 390000, date(2026, 8, 15), 0), ("Фриланс", "freelance", 10000, date(2026, 8, 25), 0)],
        "counts": {"housing": 1, "food": 15, "transport": 11, "restaurants": 5,
                   "subscriptions": 2, "shopping": 2, "health": 1, "entertainment": 1},
    },
    {
        "key": "p-1",
        "start": date(2026, 9, 15),
        "end": date(2026, 10, 14),
        "today": None,
        "title": "15 сен. — 14 окт.",
        "expenses": {
            "housing": 62000, "food": 31000, "transport": 10800, "restaurants": 8800,
            "subscriptions": 6220, "shopping": 5234, "health": 5200, "entertainment": 1850,
        },
        "income": [("Зарплата", "salary", 390000, date(2026, 9, 15), 0), ("Фриланс", "freelance", 15000, date(2026, 9, 27), 0)],
        "counts": {"housing": 1, "food": 15, "transport": 11, "restaurants": 6,
                   "subscriptions": 3, "shopping": 3, "health": 1, "entertainment": 2},
    },
    {
        "key": "p0",
        "start": date(2026, 10, 15),
        "end": date(2026, 11, 14),
        "today": date(2026, 11, 11),
        "title": "15 окт. — 14 нояб.",
        "expenses": {
            "housing": 67552, "food": 35245, "transport": 13217, "restaurants": 10280,
            "subscriptions": 7343, "shopping": 5874, "health": 4406, "entertainment": 2936,
        },
        "income": [("Зарплата", "salary", 400000, date(2026, 10, 15), 0), ("Фриланс", "freelance", 20000, date(2026, 10, 28), 0)],
        "counts": {"housing": 1, "food": 16, "transport": 12, "restaurants": 6,
                   "subscriptions": 3, "shopping": 3, "health": 1, "entertainment": 2},
    },
]


def pick(weights):
    r = random.random()
    acc = 0.0
    for i, w in enumerate(weights):
        acc += w
        if r <= acc:
            return i
    return max(i for i, w in enumerate(weights) if w > 0)


def split_total(total, n, lo, hi):
    """n amounts in cents summing exactly to total, each within [lo, hi] where possible."""
    if n == 1:
        return [total]
    for _ in range(400):
        weights = [random.uniform(0.35, 1.0) for _ in range(n)]
        s = sum(weights)
        raw = [total * w / s for w in weights]
        amounts = [max(lo, int(round(x))) for x in raw]
        amounts = [min(hi, a) for a in amounts]
        delta = total - sum(amounts)
        # Spread the remainder over the amounts with the most room.
        for _ in range(abs(delta)):
            order = sorted(range(n), key=lambda i: amounts[i], reverse=delta > 0)
            moved = False
            for i in order:
                if delta > 0 and amounts[i] < hi:
                    amounts[i] += 1
                    delta -= 1
                    moved = True
                elif delta < 0 and amounts[i] > lo:
                    amounts[i] -= 1
                    delta += 1
                    moved = True
                if delta == 0:
                    break
            if not moved:
                break
        if sum(amounts) == total and all(lo <= a for a in amounts):
            return amounts
    raise RuntimeError(f"cannot split {total} into {n} parts within [{lo},{hi}]")


def generate_period(spec):
    start, end = spec["start"], spec["end"]
    last_day = spec["today"] or end
    ops = []

    for key, name, color, mandatory, _glyph in CATEGORIES:
        total = spec["expenses"][key]
        n = spec["counts"][key]
        if key == "housing":
            amounts = [total]
        elif key == "subscriptions":
            base = total // n
            amounts = [base] * n
            amounts[0] += total - base * n
        else:
            lo = max(150, total // (n * 4))
            hi = max(lo + 100, total // max(1, n // 2))
            amounts = split_total(total, n, lo, hi)

        for amount in amounts:
            weights = ACCOUNT_WEIGHTS[key]
            account = pick(weights)

            if key == "housing":
                day = date(2026, 11, 1) if spec["key"] == "p0" else start + timedelta(days=17)
                hour, minute = 10, 0
            elif key == "subscriptions":
                day = start + timedelta(days=random.choice([3, 6, 19]))
                hour, minute = 9, random.choice([0, 30])
            else:
                span = (last_day - start).days
                day = start + timedelta(days=random.randint(0, max(0, span)))
                hour = random.randint(8, 21)
                minute = random.choice([0, 12, 20, 35, 47, 55])

            if day > last_day:
                day = last_day

            # Weekend pull for food out and fun.
            if key in ("restaurants", "entertainment", "shopping") and day.weekday() < 5:
                bump = day + timedelta(days=(5 - day.weekday()))
                if bump <= last_day:
                    day = bump

            ops.append({
                "date": day.isoformat(),
                "time": f"{hour:02d}:{minute:02d}",
                "kind": "expense",
                "amount": amount,
                "category": key,
                "categoryName": name,
                "mandatory": mandatory,
                "color": color,
                "account": ACCOUNTS[account][1],
                "accountName": ACCOUNTS[account][0],
                "place": random.choice(PLACES[key]),
            })

    for name, key, amount, day, account in spec["income"]:
        ops.append({
            "date": day.isoformat(),
            "time": "10:00",
            "kind": "income",
            "amount": amount,
            "category": key,
            "categoryName": name,
            "mandatory": False,
            "color": "green",
            "account": ACCOUNTS[account][1],
            "accountName": ACCOUNTS[account][0],
            "place": "Поступление",
        })

    ops.sort(key=lambda o: (o["date"], o["time"]))
    return ops


def verify(periods):
    problems = []
    for spec, ops in zip(PERIODS, periods):
        for key, *_ in CATEGORIES:
            got = sum(o["amount"] for o in ops if o["kind"] == "expense" and o["category"] == key)
            want = spec["expenses"][key]
            if got != want:
                problems.append(f"{spec['key']}/{key}: {got} != {want}")
        for o in ops:
            if o["date"] < spec["start"].isoformat() or o["date"] > (spec["today"] or spec["end"]).isoformat():
                problems.append(f"{spec['key']}: out of range {o['date']}")
        total = sum(o["amount"] for o in ops if o["kind"] == "expense")
        mand = sum(o["amount"] for o in ops if o["kind"] == "expense" and o["mandatory"])
        print(f"{spec['key']} {spec['title']}: expenses {total/100:,.2f} "
              f"(mandatory {mand/100:,.2f}, free {(total-mand)/100:,.2f}), ops {len(ops)}")
    return problems


all_ops = [generate_period(spec) for spec in PERIODS]
problems = verify(all_ops)
if problems:
    raise SystemExit("INCONSISTENT:\n" + "\n".join(problems))

meta = []
for spec, ops in zip(PERIODS, all_ops):
    meta.append({
        "key": spec["key"],
        "title": spec["title"],
        "start": spec["start"].isoformat(),
        "end": spec["end"].isoformat(),
        "today": (spec["today"] or spec["end"]).isoformat(),
    })

payload = {"periods": meta, "operations": [o for ops in all_ops for o in ops]}
out = sys.argv[1] if len(sys.argv) > 1 else "build/analytics-data.js"
with open(out, "w") as f:
    f.write("// Generated by build/analytics-data.py — do not edit by hand.\n")
    f.write("window.MONTRA_ANALYTICS = ")
    json.dump(payload, f, ensure_ascii=False, indent=2)
    f.write(";\n")

print(f"wrote {out}", len(payload["operations"]), "operations")
