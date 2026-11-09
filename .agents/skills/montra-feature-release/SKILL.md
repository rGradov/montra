---
name: montra-feature-release
description: >
  Полный цикл новой фичи или изменения поведения в Montra (macOS, SwiftUI,
  SwiftData): реализация, проверка влияния на бэкап, синхронизация локального
  HTTP API и MCP, локализация, тесты, документация и финальная DMG-сборка для
  установки. Use whenever the user asks to add, change, remove, or fix a
  user-visible feature, setting, model field, screen, account/category/operation/
  plan option, local API action, MCP tool, or backup behavior in this repository.
  Also use for a feature request that sounds small ("just add a toggle") — the
  backup and integration consequences are the point of this skill.
whenToUse: >
  Load before writing code for any Montra feature or behavior change. Skip only
  for read-only questions, code review, or refactors that provably change no
  behavior and no persisted state.
---

# Montra: фича → бэкап → API/MCP → тесты → DMG

Монтра хранит деньги. Незаметная потеря одного флага при восстановлении из копии
или рассинхрон между приложением и MCP — это не «мелкий техдолг», а тихая порча
данных. Поэтому здесь фича не считается сделанной, пока весь путь не закрыт.

## 0. Железные правила

1. **Порядок не обсуждается**: сначала фича, потом бэкап, потом Local API, потом
   MCP, потом локализация и docs, потом тесты, потом DMG.
2. **Любое новое сохраняемое значение обязано попасть в бэкап.** Новый тумблер,
   поле модели, сущность, настройка — всё. Если значение не должно попадать в
   бэкап, это осознанное решение с причиной в
   `Scripts/feature-sync-allowlist.txt`, а не забывчивость.
3. **Любые данные или действие, которые пользователь может создать/изменить,
   должны быть представимы через Local API.** MCP обязан уметь повторить любую
   пользовательскую запись: те же поля, те же значения, та же семантика.
4. **Local API и MCP — два разных слоя.** Правка в `LedgerAPI.swift` не добавляет
   инструмент в `mcp/server.py`; правка в MCP не добавляет действие в приложение.
   Синхронизировать нужно оба и оба README.
5. **Старые `.montra`-файлы должны восстанавливаться.** Никаких «переживём»:
   либо поле optional с дефолтом, либо версия формата и явная миграция.
6. **Тесты — ворота, а не ритуал.** `-selftest` должен закончиться
   `ALL CHECKS PASSED`. API/MCP-изменения дополнительно прогоняют smoke.
7. **DMG собирается в конце каждой фичи**, после зелёных тестов. Не «когда-нибудь
   потом» и не «если останется время».
8. **Зелёный аудит — обязателен**:
   `python3 Scripts/audit-feature-sync.py --require-dmg`.
9. **В финале — отчёт по шаблону** (раздел 12). Пользователь должен видеть, что
   изменилось в бэкапе, API, MCP, тестах и где лежит DMG.

## 1. Рабочий цикл

Заведи todo-список по шагам и закрывай его по мере работы:

```
[ ] 0. Baseline: аудит и текущие тесты зелёные
[ ] 1. Фича: код, модель, локализация
[ ] 2. Бэкап: capture / restore / версия / selftest
[ ] 3. Local API: JSON, input, action, docs
[ ] 4. MCP: tool, параметры, docs, smoke
[ ] 5. Документация: README, Feature-Inventory, Local-API, mcp/README
[ ] 6. Тесты: selftest, snapshot, MCP smoke
[ ] 7. Аудит: --require-dmg
[ ] 8. DMG: make-dmg.sh <tag> --open
[ ] 9. Отчёт пользователю
```

Перед началом прочитай `AGENTS.md` и `Docs/Feature-Workflow.md`, если они есть.
При работе с сохранённым состоянием открой
`references/backup-playbook.md`; при работе с API/MCP —
`references/api-mcp-playbook.md`; при сборке —
`references/release-playbook.md`.

## 2. Карта репозитория

| Что | Где |
|---|---|
| Модели SwiftData | `Montra/Models/Models.swift`, `Montra/Models/Plan.swift` |
| Репозитории и запись | `Montra/Store/Repositories.swift`, `PlanRepository.swift` |
| Настройки | `Montra/Store/SettingsStore.swift` |
| Бэкап: формат | `Montra/Backup/BackupArchive.swift` |
| Бэкап: capture/restore | `Montra/Backup/BackupService.swift` |
| Бэкап: UI и восстановление | `Montra/Features/Settings/SettingsView.swift`, `BackupRestoreSheet.swift` |
| Local API | `Montra/Integration/LedgerAPI.swift` |
| HTTP-сервер и токен | `Montra/Integration/LocalHTTPServer.swift`, `LocalIntegration.swift` |
| MCP | `mcp/server.py`, `mcp/README.md` |
| Документация API | `Docs/Local-API.md` |
| Self-test | `Montra/Snapshot/SelfTest.swift` |
| Инвентарь фич | `Docs/Feature-Inventory.md` |
| Переводы | `Montra/Resources/*.xcstrings` |
| Аудит синхронизации | `Scripts/audit-feature-sync.py` |
| Исключения аудита | `Scripts/feature-sync-allowlist.txt` |
| DMG | `Scripts/make-dmg.sh` |

## 3. Шаг 1 — сама фича

- Следуй существующей архитектуре: `Features/<Feature>/`, репозитории, токены
  дизайна, `AppStyle`, `AppColors`. Не создавай параллельных путей записи в
  SwiftData.
- Новое поле модели объявляй с дефолтом:
  `var isPinned: Bool = false`. Это нужно и для лёгкой миграции SwiftData, и для
  старых store.
- Все пользовательские строки — через `String(localized:)` или `Text("key")` и
  сразу в `Localizable.xcstrings` с `en` и `ru`. Русский — source language.
- Если фича меняет модель, репозиторий, сиды или отображение — добавь/обнови
  строку в `Docs/Feature-Inventory.md` (ID, что проверять, тип, приоритет).
- Не трогай `BackupArchive`/`LedgerAPI` «по ходу»: для них есть отдельные шаги,
  чтобы ничего не забыть.

## 4. Шаг 2 — бэкап (главный источник тихих потерь)

Задай себе один вопрос: **«Если человек сделает копию сейчас, а завтра восстановит
её на новом Mac, увидит ли он эту фичу в том же состоянии?»** Если нет — идём
чинить.

### 4.1. Матрица решений

| Изменение | Что сделать в бэкапе |
|---|---|
| Новое поле `Account` / `Category` / `Operation` / `PlannedOperation` | Добавить поле в `*Backup` в `BackupArchive.swift`; маппинг в `BackupService.swift` (capture-extension и restore `insert`); проверить ссылки в `PreparedPayload`; bump `currentSchemaVersion`; добавить проверку в `SelfTest.swift` |
| Новый тумблер/настройка в `SettingsStore` | Поле в `SettingsBackup` (optional); capture в `SettingsBackup.init(_:)`; `BackupService.apply` с дефолтом для старых файлов; проверка в selftest |
| Новое состояние вне SwiftData (как курсы или настройки API) | Добавить в `BackupService.Environment`, в `BackupPayload` (optional), в оба вызова `BackupService.capture` (`SettingsView`, `BackupRestoreSheet`), в `RestoreReport` и в применение после restore |
| Новая сущность | Новый массив в `BackupPayload`, поле в `BackupSummary`, capture/restore, валидация внешних ключей, строка в `BackupRestoreSheet`, selftest |
| Машинное/секретное/временное | Не включать. Явно добавить в allowlist с причиной: токен API, `lastBackupAt`, `active`, `failure` |
| Меняется смысл или тип существующего поля | Bump `currentFormatVersion`, продумать чтение старых файлов, миграцию данных и selftest на старый формат |

### 4.2. Порядок правок

1. `BackupArchive.swift`: добавь поле в структуру. Для аддитивного поля —
   `Optional`, чтобы старый JSON без него декодировался.
2. `BackupService.swift`:
   - в `capture` — значение из модели;
   - в `insert` — восстановление с дефолтом (`row.flag ?? false`);
   - если поле — ссылка, добавь проверку в `PreparedPayload.init`;
   - если это настройка — в `SettingsBackup.init(_:)` и `apply`.
3. `BackupSummary`/`BackupRestoreSheet` — только если появилась новая сущность или
   изменился смысл счётчиков.
4. Версии:
   - `currentFormatVersion` — версия формата файла. Любое изменение payload
     (даже аддитивное) лучше сопровождать bump: старая Montra тогда скажет
     «обновите Montra», а не «файл повреждён».
   - `currentSchemaVersion` — поколение SwiftData-моделей. Bump при новом
     сохранённом свойстве модели.
5. `SelfTest.swift`: добавь проверку в существующий backup-блок (около
   `копия помечена собственным форматом` и `флаг скрытия счёта восстановлен`).
   Минимум: значение попало в `archive.payload`, пережило encode/decode и
   восстановилось в новый `ModelContext`.
6. Запусти selftest. Без новой проверки фича не закрыта.

### 4.3. Чего нельзя делать

- Добавлять non-optional поле в `*Backup` без версии формата и дефолта: старые
  копии перестанут открываться.
- Считать, что «optional поле не надо проверять»: его всё равно надо явно
  прочитать и применить.
- Класть в бэкап токен, путь, кеш или дату последней копии.
- Менять `checksum` вручную: он считается по payload автоматически.
- Чинить бэкап «после релиза».

## 5. Шаг 3 — Local API

Инвариант: **MCP должен уметь воссоздать любую запись, которую пользователь может
сделать в приложении.** Если пользователь поставил тумблер на счёте, у MCP должен
быть способ поставить тот же тумблер и прочитать его обратно.

### 5.1. Что менять

1. **Чтение**: добавь поле в `accountJSON`, `categoryJSON`, `operationJSON` или
   `planJSON` в `LedgerAPI.swift`. Ключи — `snake_case`.
2. **Запись**: добавь поле в соответствующий `*Input` (`AccountInput`,
   `CategoryInput`, `ImportRow`, `PlanInput`, …). Сделай его optional, если старые
   клиенты могут его не присылать; в `Store.create*` примени дефолт.
3. **Идемпотентность**: если у действия есть проверка «такая запись уже есть»,
   включи новое поле в сравнение. Иначе повтор с другим значением молча вернёт
   старую запись.
4. **Новое действие**: `Action` case, ветка в `writes`, ветка в `execute`,
   метод в `Store`, JSON-ответ. Ошибки — `LedgerError` с `422`, `409`, `403` или
   `404` по смыслу.
5. **Документация**: строка в таблице `Docs/Local-API.md`, параметры и
   особенности — в прозе ниже. `list_accounts` и другие чтения описывай явно.

### 5.2. Пример из этого репозитория

Скрытие счёта из обзора — реальный пример полного цикла:

- `AccountInput.isHiddenFromOverview` — новый optional-параметр;
- `Store.createAccount` применяет `?? false` и сравнивает флаг при повторном
  создании;
- `accountJSON` возвращает `is_hidden_from_overview`;
- `Docs/Local-API.md` — колонка `create_account` и абзац про `list_accounts`;
- `mcp/server.py` — параметр `is_hidden_from_overview`;
- `mcp/README.md` — строка про `create_account`;
- `mcp/tests/smoke.py` — создание скрытого счёта и проверка флага.

Если делаешь похожий тумблер — повтори этот путь целиком, не только UI.

### 5.3. Когда API не нужен

Бывает, что значение сознательно не пересекает API: координаты операции
(в API есть только текстовое место), `createdAt`, серверная сортировка, периоды
(у API нет команд периодов). Такие случаи — только через
`Scripts/feature-sync-allowlist.txt` с причиной. Если сомневаешься — добавь в API,
это дешевле, чем объяснять пользователю, почему MCP не видит его данные.

## 6. Шаг 4 — MCP

MCP — тонкий прокси над HTTP API, но со своей типизацией и своим README.

1. Один `@mcp.tool` на одно действие; имя функции совпадает с action.
2. Параметры — `snake_case`, с типами из шапки `server.py` (`Currency`, `Kind`,
   `Amount`, `Timestamp`, `Color`, `PageLimit`, …). Не принимай «сырой» JSON, если
   можно выразить тип.
3. Аннотации: `READ`, `CREATE`, `DELETE` — по смыслу. Delete-тулы должны
   требовать `preview_token`.
4. Docstring — короткое правило для модели: что делает, что обязательно, что
   вернёт при повторе.
5. Передай **все** новые поля в `call_api(...)`. Если поле есть в Swift-input, но
   нет в MCP-параметрах, аудит упадёт.
6. Обнови таблицу инструментов в `mcp/README.md`.
7. Если менял API — добавь утверждение в `mcp/tests/smoke.py`: создание,
   чтение, повтор, отказ. Smoke проверяет и HTTP, и MCP на одной in-memory базе.
8. Не добавляй в MCP бизнес-логику, которой нет в приложении: он не должен
   придумывать валюты, категории или дефолты, расходящиеся с Montra.

## 7. Шаг 5 — локализация и документация

- Новая строка → `Localizable.xcstrings`, `en` и `ru`, `state: translated`.
  Для интерполяций ключ заканчивается на `%@`/`%lld` — не выдумывай формат,
  посмотри соседние ключи.
- `README.md` → раздел «Что умеет», если фича видна пользователю.
- `Docs/Feature-Inventory.md` → новая строка с ID и проверками; обнови счётчик
  проверок в шапке и в разделе 4, если selftest вырос.
- `Docs/Local-API.md` и `mcp/README.md` → обязательно при любом API/MCP-изменении.
- Если фича меняет продуктовые правила — обнови `MasterPrompt.md` или `PLAN.md`
  только когда это действительно меняет договорённости, а не в качестве дневника.

## 8. Шаг 6 — тесты

### 8.1. Базовая сборка и selftest

```bash
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build

APP=build/DerivedData-debug/Build/Products/Debug/Montra.app
"$APP/Contents/MacOS/Montra" -selftest
```

`OTHER_SWIFT_FLAGS=-disable-sandbox` нужен в DSH: внешний sandbox блокирует
вложенный `sandbox-exec`, которым SwiftData-макрос запускает plugin server.
Макрос Apple-овский, так что это безопасно; в обычном терминале флаг можно не
передавать.

Обязательный результат: `ALL CHECKS PASSED`, код выхода 0. Если упала хотя бы одна
проверка — не переходи к DMG.

### 8.2. UI

Если менялся экран, поток или анимация:

```bash
"$APP/Contents/MacOS/Montra" -snapshot build/snaps-<tag>
```

Открой новые/изменённые PNG и сравни с `build/snaps-current` или предыдущей
папкой. Для онбординга можно запустить `-preview-onboarding` на временном
хранилище.

### 8.3. API и MCP

```bash
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py
```

Smoke поднимает HTTP-фикстуру и MCP на одной in-memory базе, проверяет авторизацию,
предпросмотры, повторы, удаление и соответствие набора tools набору actions.
Любое новое поле/действие должно быть покрыто утверждением.

### 8.4. Бэкап

- Расширь backup-блок в `SelfTest.swift` (capture → encode/decode → restore).
- Если менял формат — проверь старый файл: можно сохранить копию до изменений и
  открыть её после. Не тестируй на реальных данных без копии store.
- Ручной сценарий: Настройки → Сохранить копию → изменить состояние → Восстановить
  → проверить новое поле.

## 9. Шаг 7 — аудит синхронизации

```bash
python3 Scripts/audit-feature-sync.py
python3 Scripts/audit-feature-sync.py --require-dmg   # перед отчётом
```

Скрипт проверяет:

- все Swift-ключи локализации существуют и переведены на `en` + `ru`;
- все сохранённые поля моделей и настройки упомянуты в бэкапе;
- каждое `Action` из `LedgerAPI` есть в MCP и в обоих README;
- каждое поле модели, пересекающее API, сериализуется или принимается;
- каждый input-параметр API доступен в MCP;
- DMG не старше исходников (с `--require-dmg`).

Красный аудит — это не «шум», а список конкретных дыр. Исправляй код, а не
подкручивай проверку. В allowlist попадают только машинные, производные или
временные значения, и только с причиной в комментарии.

## 10. Шаг 8 — DMG

```bash
Scripts/make-dmg.sh <tag> --open
```

Тег — короткое kebab-case описание фичи: `hidden-accounts`, `api-hidden`,
`transfer-fix`. Скрипт:

1. собирает Release;
2. прогоняет `-selftest` на собранном приложении и останавливается при ошибке;
3. проверяет подпись;
4. собирает staging с `Montra.app` и ссылкой на `/Applications`;
5. создаёт `build/Montra-<version>-<tag>.dmg`;
6. монтирует образ, проверяет приложение, подпись и версию;
7. печатает путь и размер.

Если `hdiutil` падает с `Operation not permitted` / «Непустая папка» — это sandbox
не даёт доступ к raw disk. Перезапусти упаковку с full disk access (или вне
sandbox). Сборка и selftest при этом уже прошли; не пересобирай приложение без
необходимости.

После сборки:

- `open build/Montra-<version>-<tag>.dmg`, перетащи в Applications, запусти;
- проверь ровно тот сценарий, который просил пользователь;
- в финальном ответе дай путь и, если хост поддерживает, вызови `present` с DMG.

Версию `MARKETING_VERSION` автоматически не поднимай: тег отличает сборки.
Поднимай только по прямой просьбе или когда установленная копия не обновляется.

## 11. Definition of Done

- [ ] Фича работает и не ломает существующие сценарии.
- [ ] Новое состояние сохраняется и восстанавливается из `.montra`.
- [ ] Старые копии открываются (или версия формата bump-нута и есть миграция).
- [ ] Поля/действия доступны в Local API и MCP, docs обновлены.
- [ ] Все новые строки есть на `ru` и `en`.
- [ ] `Feature-Inventory` и `README` обновлены, если фича видима.
- [ ] `-selftest` — `ALL CHECKS PASSED`.
- [ ] API/MCP smoke — passed, если трогал интеграции.
- [ ] UI snapshots проверены, если трогал экраны.
- [ ] `audit-feature-sync.py --require-dmg` — 0 failures.
- [ ] DMG собран, смонтирован и проверен.
- [ ] Пользователь получил отчёт и путь к DMG.

## 12. Финальный отчёт

Пиши по-русски, коротко и по делу:

```
Фича: <что сделано>
Бэкап: <затронут/нет; какие поля; совместимость старых файлов>
Local API: <actions/поля; docs>
MCP: <tools/параметры; docs>
Локализация: <новые ключи ru/en>
Тесты: -selftest — ALL CHECKS PASSED (N проверок); MCP smoke — passed; snapshots — ...
Аудит: 0 failures
DMG: build/Montra-1.0-<tag>.dmg (<размер>), версия 1.0 (1)
Проверить руками: <2–4 шага>
```

Если что-то сознательно не сделано (например, поле не вынесено в API), это
отдельная строка «Осознанно не в API: …» с причиной и ссылкой на allowlist.

## 13. Примеры

### Пример A. Новый тумблер на счёте

1. Модель: `var isPinned: Bool = false` + инициализатор + репозиторий.
2. UI: тумблер в форме счёта; строки в `Localizable.xcstrings`.
3. Бэкап: `AccountBackup.isPinned`, capture/restore, bump schema, selftest.
4. API: `AccountInput.isPinned`, `createAccount`, `accountJSON`.
5. MCP: параметр `is_pinned`, docs, smoke.
6. Feature-Inventory: `ACC-xx`.
7. Тесты, аудит, DMG.

### Пример B. Новая категория с новым полем

То же, но `CategoryBackup`, `CategoryInput`, `categoryJSON`, `create_category`;
подкатегории и `parent_id` не ломаются; selftest проверяет parent после restore.

### Пример C. Чисто визуальная фича

Анимация, тень, пустое состояние. Бэкап не меняется, API/MCP не нужны. Но:
локализация — если есть строки; snapshot — если менялся экран; DMG — обязательно.
В отчёте явно скажи, что бэкап/API не затронуты и почему.

### Пример D. Новое действие (например, архивирование счёта)

Это не только UI. Нужны: модель/флаг, бэкап, новое `Action`, Store-метод, MCP-tool,
docs, smoke, Feature-Inventory, DMG. Если действие разрушительное — preview +
`preview_token`, как у удаления.

## 14. Антипаттерны

- «Сначала UI, API потом» — потом не наступит; фича уедет в DMG без API.
- «Поле optional, значит бэкап не нужен» — нет, optional нужен именно для бэкапа.
- «Добавлю в API, MCP сам подхватит» — MCP это отдельный Python-файл.
- «Тесты падают, но вручную всё работает» — не выпускаем DMG.
- «DMG соберу после следующей фичи» — нет, DMG это финиш каждой фичи.
- «Добавлю в allowlist, чтобы аудит позеленел» — только с причиной и только для
  машинных/производных значений.
- «Обновлю README потом» — README и Feature-Inventory входят в Definition of Done.
- «Проверю на реальных данных» — сначала копия store; destructive-тесты только на
  временном хранилище.

## 15. Reference-файлы

- `references/backup-playbook.md` — подробные правки бэкапа, версии, selftest.
- `references/api-mcp-playbook.md` — точные формы input/action/tool и smoke.
- `references/release-playbook.md` — сборка, DMG, диагностика sandbox/hdiutil.
