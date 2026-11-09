# Новая фича в Montra: рабочий цикл

Этот документ описывает правило, по которому теперь идёт любая фича в Montra:
**код → бэкап → Local API → MCP → локализация → тесты → DMG**. Правило живёт в
skill `montra-feature-release` и в `AGENTS.md`; здесь — человеческое объяснение и
команды.

## Зачем

У Montra три поверхности, которые легко расходятся:

1. **Приложение** — SwiftUI + SwiftData.
2. **Бэкап** — JSON `.montra`, из которого человек восстанавливает деньги на
   другом Mac.
3. **Интеграции** — локальный HTTP API и MCP-прокси для Codex/ChatGPT.

Если добавить тумблер только в UI, он не попадёт в копию и потеряется при
восстановлении. Если добавить поле только в API, MCP о нём не узнает. Если
собрать DMG до тестов, пользователь проверит сломанную сборку. Поэтому фича
считается готовой только целиком.

## Что происходит автоматически

Когда ты просишь «добавь фичу», агент загружает skill
`montra-feature-release` и идёт по воротам:

```
0. baseline   — аудит и текущие тесты зелёные
1. фича       — код, модель, строки
2. бэкап      — capture/restore, версия формата, selftest
3. Local API  — JSON, input, action, Docs/Local-API.md
4. MCP        — tool, параметры, mcp/README.md, smoke
5. документация — README, Feature-Inventory
6. тесты      — selftest, snapshots, smoke
7. аудит      — audit-feature-sync.py --require-dmg
8. DMG        — make-dmg.sh <tag> --open
9. отчёт      — что изменилось и что проверить руками
```

## Ворота

### 1. Код и локализация

- Новое поле модели — с дефолтом (`var isPinned: Bool = false`), чтобы SwiftData
  сделала лёгкую миграцию.
- Все пользовательские строки — в `Localizable.xcstrings`, `ru` + `en`.
- Новая фича с ID и сценариями — в `Docs/Feature-Inventory.md`.

### 2. Бэкап

Главный вопрос: «Если сделать копию сейчас и восстановить завтра на новом Mac,
увижу ли я фичу в том же состоянии?»

Типовые правки:

| Что появилось | Куда идти |
|---|---|
| Поле `Account`/`Category`/`Operation`/`Plan` | `*Backup` в `BackupArchive.swift`, capture/restore в `BackupService.swift`, selftest |
| Настройка в `SettingsStore` | `SettingsBackup` + `BackupService.apply` |
| Состояние вне SwiftData (курсы, API) | `BackupService.Environment` + optional-секция payload + применение в `BackupRestoreSheet` |
| Новая сущность | новый массив payload, `BackupSummary`, restore, счётчик в sheet |

Старые `.montra` должны открываться: новое поле — `Optional` с дефолтом, либо
bump `currentFormatVersion` + миграция. Секреты (токен API) и машинные даты
(`lastBackupAt`) в копию не попадают.

Подробные примеры кода — в
`.agents/skills/montra-feature-release/references/backup-playbook.md`.

### 3. Local API

Инвариант: **MCP должен уметь воссоздать любую пользовательскую запись.**

- чтение — в `accountJSON`/`categoryJSON`/`operationJSON`/`planJSON`;
- запись — в `AccountInput`/`CategoryInput`/`ImportRow`/`PlanInput`;
- повтор с другим значением не должен молча возвращать старую запись;
- новое действие — `Action` + `writes` + `execute` + `Store`;
- `Docs/Local-API.md` обновляется в той же правке.

Подробности — в
`.agents/skills/montra-feature-release/references/api-mcp-playbook.md`.

### 4. MCP

MCP — отдельный Python-файл `mcp/server.py`, он не подхватывает API сам.

- один `@mcp.tool` на action, имя функции = action;
- все новые параметры — в сигнатуре и в `call_api(...)`;
- `mcp/README.md` — строка в таблице инструментов;
- `mcp/tests/smoke.py` — утверждение на создание/чтение/повтор.

### 5. Тесты

```bash
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build

build/DerivedData-debug/Build/Products/Debug/Montra.app/Contents/MacOS/Montra -selftest
```

Ожидаемо: `ALL CHECKS PASSED`. Сейчас это 131 проверка, включая полный
backup round-trip.

Если менялся UI:

```bash
build/DerivedData-debug/Build/Products/Debug/Montra.app/Contents/MacOS/Montra \
  -snapshot build/snaps-<tag>
```

Если менялись API/MCP:

```bash
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py
```

`-disable-sandbox` нужен в DSH: внешний sandbox блокирует вложенный
`sandbox-exec`, которым SwiftData-макрос запускает plugin server.

### 6. Аудит

```bash
python3 Scripts/audit-feature-sync.py
python3 Scripts/audit-feature-sync.py --require-dmg
```

Скрипт проверяет:

- ключи локализации существуют и переведены на `en` + `ru`;
- сохранённые поля моделей и настройки есть в бэкапе;
- каждое `Action` есть в MCP и в обоих README;
- поля моделей, пересекающие API, сериализуются или принимаются;
- input-поля API доступны в MCP;
- DMG не старше исходников (с `--require-dmg`).

Красный аудит — список конкретных дыр, а не повод ослабить проверку.

### 7. DMG

```bash
Scripts/make-dmg.sh <tag> --open
```

Скрипт собирает Release, прогоняет `-selftest`, проверяет подпись, делает
`build/Montra-1.0-<tag>.dmg`, монтирует его и проверяет содержимое.

Тег — короткое описание: `hidden-accounts`, `api-hidden`, `plans-fix`.

Если `hdiutil` падает с `Operation not permitted` — sandbox не даёт доступ к raw
disk; упаковку нужно запускать с full disk access. Это не ошибка кода.

## Файлы

| Файл | Роль |
|---|---|
| `.agents/skills/montra-feature-release/SKILL.md` | основной skill |
| `.agents/skills/montra-feature-release/references/` | playbook'и по бэкапу, API/MCP, релизу |
| `AGENTS.md` | короткое правило для агента, загружается всегда |
| `Scripts/audit-feature-sync.py` | механическая проверка синхронизации |
| `Scripts/feature-sync-allowlist.txt` | осознанные исключения с причинами |
| `Scripts/make-dmg.sh` | Release + selftest + DMG |
| `Docs/Feature-Workflow.md` | этот документ |

## Осознанные исключения

Иногда значение не должно пересекать API или бэкап: `createdAt`, `sortIndex`,
координаты операции (в API только текстовое место), `weekdayMask` (в API массив
`weekdays`), периоды (у API нет команд), токен и `lastBackupAt`. Такие случаи
добавляются в `Scripts/feature-sync-allowlist.txt` строкой вида:

```
api:Account.createdAt    # назначается сервером, клиент не задаёт
```

Без причины строку не добавлять. Если сомневаешься — добавь поле в API/бэкап.

## Как проверить, что правило работает

```bash
python3 Scripts/audit-feature-sync.py --require-dmg
```

Сейчас аудит зелёный. В качестве живого примера синхронизации:
`is_hidden_from_overview` и `is_savings` у счёта проходят путь
модель → бэкап → `LedgerAPI` → `mcp/server.py` → smoke.

## Если нужно изменить само правило

1. Правь `SKILL.md` или reference-файл.
2. Если меняется проверка — правь `audit-feature-sync.py` и добавляй тест на
   новый случай.
3. Обнови этот документ и `AGENTS.md`, если изменились ворота.
4. Прогони аудит на текущем репозитории: он должен остаться зелёным.
