# Release playbook

Цель: после каждой фичи отдать пользователю устанавливаемый DMG, собранный из
проверенного кода.

## 1. Порядок

1. Debug-сборка и `-selftest`.
2. Snapshot, если менялся UI.
3. MCP fixture + smoke, если менялись API/MCP.
4. Аудит синхронизации.
5. Release-сборка + DMG.
6. Проверка смонтированного образа.
7. Короткий ручной сценарий в установленной копии.
8. Отчёт с путём к DMG.

## 2. Debug-сборка

```bash
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build

APP=build/DerivedData-debug/Build/Products/Debug/Montra.app
```

Если `xcodebuild` падает с
`external macro implementation type 'SwiftDataMacros.PersistentModelMacro' could
not be found` и в логе есть `sandbox-exec: sandbox_apply: Operation not permitted`,
это внешний sandbox DSH блокирует вложенный sandbox Apple-овского macro plugin
server. `-disable-sandbox` решает. Макрос принадлежит Apple, риск минимальный; в
обычном терминале флаг не нужен.

## 3. Self-test

```bash
"$APP/Contents/MacOS/Montra" -selftest
```

Ожидаемо: строки `PASS ...` и последняя `ALL CHECKS PASSED`, код 0.

Тест использует in-memory store и отдельный `UserDefaults` suite, реальные данные
не трогает. Он покрывает периоды, балансы, валюты, переводы, планы, категории,
Spotlight и полный backup round-trip.

Если одна проверка упала:

1. запусти ещё раз, чтобы исключить пересечение с другим запущенным экземпляром;
2. если повторяется — найди `FAIL` в выводе и чини причину, а не тест;
3. не собирай DMG с падающим selftest.

## 4. Snapshot

```bash
"$APP/Contents/MacOS/Montra" -snapshot build/snaps-<tag>
```

Сравни изменённые PNG с `build/snaps-current` или предыдущей папкой. Для
онбординга:

```bash
"$APP/Contents/MacOS/Montra" -preview-onboarding
```

Snapshot использует временную базу в памяти.

## 5. MCP smoke

```bash
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py
```

Скрипт компилирует Swift-модели и `LedgerAPI` в отдельный HTTP-фикстур, поднимает
его и прогоняет MCP через stdio. Проверяются auth, preview, повторы, удаление,
планы и соответствие `set(tools) == set(status.actions)`.

Если fixture не собирается из-за macro sandbox — проверь, что
`mcp/tests/build-fixture.sh` передаёт `-disable-sandbox`
(`MONTRA_DISABLE_MACRO_SANDBOX=1` по умолчанию).

## 6. Аудит

```bash
python3 Scripts/audit-feature-sync.py
python3 Scripts/audit-feature-sync.py --require-dmg
```

Первый запуск — во время работы; `--require-dmg` — перед отчётом. Ноль failures
обязателен. Warnings про старый DMG ожидаемы до сборки.

Allowlist — только для машинных/производных/временных значений. Каждая строка
должна иметь причину после `#`.

## 7. DMG

```bash
Scripts/make-dmg.sh <tag> --open
```

Что делает скрипт:

- читает `MARKETING_VERSION` из `project.pbxproj` (сейчас `1.0`);
- собирает Release в `build/DerivedData-release`;
- запускает `-selftest` на собранном приложении;
- проверяет `codesign --verify --deep --strict`;
- собирает staging: `Montra.app` + ссылка `Applications -> /Applications`;
- создаёт `build/Montra-<version>-<tag>.dmg` (`UDZO`);
- монтирует образ, проверяет наличие приложения/ссылки/подписи/версии;
- печатает путь, версию и размер.

Тег: короткий kebab-case, например `hidden-accounts`, `api-hidden`,
`plans-fix`. Не используй пробелы и даты — дата уже есть в mtime.

### Если hdiutil падает

`hdiutil: create failed - Operation not permitted` или
`newfs_apfs: /dev/rdisk...: Operation not permitted` — sandbox не даёт доступ к
raw disk. Перезапусти упаковку с full disk access / вне sandbox. Сборка и
selftest уже прошли; приложение пересобирать не нужно.

`hdiutil: create failed - Непустая папка` обычно означает ту же проблему с
нижележащим `newfs_apfs`, а не реальную непустую папку.

### Ручная проверка

```bash
hdiutil attach -nobrowse -readonly build/Montra-1.0-<tag>.dmg
ls "/Volumes/Montra/Montra.app"
codesign --verify --deep --strict "/Volumes/Montra/Montra.app"
hdiutil detach "/Volumes/Montra"
```

Затем `open` образа, перетащить в Applications, запустить и пройти сценарий
фичи. Если приложение уже было установлено, macOS может показать замену — это
нормально для локальной dev-сборки.

## 8. Версии

- `MARKETING_VERSION` — версия продукта, сейчас `1.0`.
- `CURRENT_PROJECT_VERSION` — build number, сейчас `1`.
- Автоматически не поднимай: тег отличает сборки.
- Поднимай по просьбе пользователя или если установленная копия не обновляется.
- Не нотаризуй: это локальная сборка без Developer ID. Пользователь ставит её
  сам.

## 9. Финальный отчёт

```
Фича: ...
Бэкап: ...
Local API: ...
MCP: ...
Тесты: selftest — ALL CHECKS PASSED; smoke — passed; snapshots — ...
Аудит: 0 failures
DMG: build/Montra-1.0-<tag>.dmg (<size>), version 1.0 (1)
Проверить руками: ...
```

Если хост поддерживает `present`, приложи DMG как файл. Иначе дай ссылку на путь.

## 10. Частые ошибки

| Симптом | Причина | Что делать |
|---|---|---|
| `PersistentModelMacro could not be found` | sandbox блокирует macro plugin server | `OTHER_SWIFT_FLAGS=-disable-sandbox` |
| `newfs_apfs: Operation not permitted` | sandbox блокирует raw disk | запустить упаковку с full disk access |
| `hdiutil: create failed - Непустая папка` | тот же отказ `newfs_apfs` | то же |
| `-selftest` падает на одной проверке | реальная регрессия или пересечение экземпляров | повторить, затем чинить |
| MCP smoke: `set(tools) != set(actions)` | добавили action без tool или наоборот | синхронизировать `server.py` |
| Аудит: `model field do not cross the API` | новое поле не в JSON/input | добавить или allowlist с причиной |
| Аудит: `DMG is older` | собрали код после DMG | пересобрать DMG |
