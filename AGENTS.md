# Montra — инструкции для агента

## Новая фича = полный цикл

Любая фича, изменение поведения, новое поле модели, настройка, экран, действие
Local API/MCP или формат бэкапа в этом репозитории выполняются по skill
**`montra-feature-release`** (`.agents/skills/montra-feature-release/SKILL.md`).

Прочитай skill перед первой правкой. Не считай фичу готовой, пока не закрыты все
ворота:

1. **Код и локализация** — фича работает; все новые строки есть в
   `Localizable.xcstrings` на `ru` и `en`.
2. **Бэкап** — новое сохранённое значение попадает в `.montra` и восстанавливается;
   старые копии продолжают открываться. Новое поле модели, настройка или сущность
   без бэкапа — это незаконченная фича.
3. **Local API** — пользовательские данные и действия представимы через
   `Montra/Integration/LedgerAPI.swift`; обновлён `Docs/Local-API.md`.
4. **MCP** — инструмент и все параметры есть в `mcp/server.py`; обновлён
   `mcp/README.md`; smoke дополнен. MCP не подхватывает API автоматически.
5. **Тесты** — `-selftest` печатает `ALL CHECKS PASSED`; при UI-изменениях
   проверены snapshots; при API/MCP — `mcp/tests/smoke.py` passed.
6. **Аудит** — `python3 Scripts/audit-feature-sync.py --require-dmg` без failures.
7. **DMG** — `Scripts/make-dmg.sh <tag> --open` собрал образ после тестов.
8. **Отчёт** — что изменилось в бэкапе, API, MCP, тестах; путь к DMG; 2–4 шага
   ручной проверки.

Исключения из бэкапа/API допустимы только для машинных, производных или
временных значений, и только с причиной в
`Scripts/feature-sync-allowlist.txt`.

## Команды

```bash
# аудит синхронизации
python3 Scripts/audit-feature-sync.py

# сборка и self-test
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build
build/DerivedData-debug/Build/Products/Debug/Montra.app/Contents/MacOS/Montra -selftest

# API + MCP
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py

# установочный образ
Scripts/make-dmg.sh <tag> --open
```

`-disable-sandbox` нужен только из-за внешнего sandbox DSH: он блокирует
вложенный `sandbox-exec` SwiftData-макроса. В обычном терминале флаг не нужен.

## Границы

- Не тестируй разрушительные сценарии на реальном store без копии.
- Не коммить секреты и токен Local API.
- Не меняй `Docs/Feature-Inventory.md` задним числом без причины: это источник
  истины для тестов.
- Не поднимай `MARKETING_VERSION` автоматически; сборки различаются тегом DMG.
- Если `hdiutil` не может создать образ из-за sandbox — перезапусти упаковку с
  full disk access, а не заменяй DMG на zip.

## Документация

- `Docs/Feature-Workflow.md` — как устроен цикл и как запускать проверки вручную.
- `.agents/skills/montra-feature-release/references/` — подробные playbook'и по
  бэкапу, API/MCP и релизу.
