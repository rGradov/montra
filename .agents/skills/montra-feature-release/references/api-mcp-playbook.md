# Local API + MCP playbook

Local API — Swift-слой внутри приложения (`Montra/Integration/LedgerAPI.swift`).
MCP — отдельный Python-процесс (`mcp/server.py`), который вызывает HTTP API.
Это два независимых слоя: изменение в одном не появляется во втором само.

Инвариант: **MCP должен уметь воссоздать любую пользовательскую запись Montra.**
Если пользователь может поставить тумблер в приложении, MCP должен уметь поставить
его и прочитать обратно.

## 1. Local API: поля

### Чтение

Добавь ключ в нужный сериализатор в `LedgerAPI.swift`:

```swift
private func accountJSON(_ account: Account) -> JSONObject {
    [
        "id": id(account.id),
        // ...
        "is_pinned": account.isPinned,
    ]
}
```

Ключи — `snake_case`. `JSONDecoder` на входе использует
`keyDecodingStrategy = .convertFromSnakeCase`, поэтому Swift-поле
`isPinned` читается из `is_pinned`.

### Запись

```swift
private struct AccountInput: Decodable {
    let name: String
    @CurrencyCode var currency: Currency
    // ...
    let isPinned: Bool?
}
```

Optional — для обратной совместимости со старыми клиентами. В `Store.createAccount`:

```swift
let isPinned = input.isPinned ?? false
```

### Идемпотентность

Если `create_account` умеет возвращать существующий счёт, новое поле должно
участвовать в сравнении:

```swift
let pinnedMatches = input.isPinned.map { $0 == existing.isPinned } ?? true
guard matches.count == 1, existing.initialAmount == amount, pinnedMatches else {
    throw LedgerError("An account already has this name and currency. Inspect list_accounts before proceeding.")
}
```

Иначе повтор с другим значением молча вернёт старую запись — это рассинхрон,
который аудит не увидит.

## 2. Local API: новое действие

```swift
private enum Action: String, Decodable, CaseIterable {
    case archiveAccount = "archive_account"

    var writes: Bool {
        switch self {
        // ...
        case .archiveAccount: true
        }
    }
}
```

В `execute`:

```swift
case .archiveAccount:
    output = try store.archiveAccount(decoder.decode(AccountSelection.self, from: data))
```

В `Store`:

```swift
func archiveAccount(_ selection: AccountSelection) throws -> JSONObject {
    let account = try findAccount(selection.accountId)
    guard !account.isArchived else { return ["archived": false, "account": accountJSON(account)] }
    account.isArchived = true
    return ["archived": true, "account": accountJSON(account)]
}
```

Правила:

- `status.actions` собирается из `Action.allCases`, отдельно обновлять не нужно.
- Ошибки — `LedgerError(message, status:)`: `422` правила данных, `409` конфликт
  или устаревший preview, `403` запрещено настройкой, `404` не найдено.
- Запись сохраняется один раз в конце `execute`; не вызывай `context.save()` из
  Store-метода.
- Разрушительное действие — сначала `preview_*`, потом `*` с `preview_token`.
- Не добавляй в API секреты, токены и машинные пути.

## 3. MCP: инструмент

Один tool на action, имя функции = action:

```python
@mcp.tool(annotations=CREATE)
def archive_account(account_id: UUID) -> dict:
    """Archive an account without deleting its operations. Repeating the call is safe."""
    return call_api("archive_account", account_id=str(account_id))
```

Правила:

- Параметры — `snake_case`, с типами из шапки `server.py`.
- Для денег — `Amount` (положительная десятичная строка), для дат — `Timestamp`
  с offset, для валют — `Currency`.
- `READ` / `CREATE` / `DELETE` — по смыслу; delete требует `preview_token`.
- Docstring должен объяснять повтор и побочные эффекты.
- Передавай **все** поля, которые принимает Swift-input. Аудит сравнивает имена.
- Не добавляй бизнес-логику, которой нет в приложении.

## 4. Документация

`Docs/Local-API.md`:

- строка в таблице команд;
- параметры и optional-поля;
- абзац о семантике (что читается в `list_*`, что меняется, что запрещено);
- пример JSON, если поведение неочевидно.

`mcp/README.md`:

- строка в таблице инструментов;
- особенности (например, «скрытый счёт не входит в итог обзора»);
- если появился новый workflow — короткий сценарий.

## 5. Smoke-тест

`mcp/tests/smoke.py` поднимает HTTP-фикстуру и MCP на одной in-memory базе.
Добавляй утверждения рядом с существующими:

```python
created = await call("create_account", name="Тест", currency="EUR",
                     initial_amount="10", is_pinned=True)
assert created["account"]["is_pinned"] is True
assert not (await call("create_account", name="Тест", currency="EUR",
                       initial_amount="10", is_pinned=True))["created"]
await reject("create_account", "already has this name",
             name="Тест", currency="EUR", initial_amount="10", is_pinned=False)
```

Проверяй:

- создание с новым полем;
- чтение поля обратно;
- повтор (idempotency);
- конфликт при другом значении;
- если есть preview — неверный/устаревший токен.

`build-fixture.sh` компилирует Swift-модели и `LedgerAPI` напрямую. В DSH он
передаёт `-disable-sandbox`, иначе SwiftData-макрос не может запустить свой
plugin server внутри внешнего sandbox.

## 6. Реальный пример: скрытие счёта

Полный путь, который уже работает:

1. `Account.isHiddenFromOverview` в модели (бэкап уже поддерживает).
2. `AccountInput.isHiddenFromOverview` — optional.
3. `Store.createAccount` — `?? false` + сравнение при повторе.
4. `accountJSON` — `"is_hidden_from_overview": account.isHiddenFromOverview`.
5. `Docs/Local-API.md` — `create_account`, абзац про `list_accounts`.
6. `mcp/server.py` — `create_account(..., is_hidden_from_overview=False)`.
7. `mcp/README.md` — строка про `create_account`.
8. `mcp/tests/smoke.py` — создание скрытого счёта, проверка флага, повтор,
   отказ при другом флаге.

Если делаешь аналогичный тумблер, повторяй этот путь, а не только UI.

## 7. Что не выносить в API

Только осознанно и только через allowlist:

- `createdAt` — назначает сервер;
- `sortIndex` — сортировка применяется сервером;
- координаты операции — в API есть текстовое `place`;
- `weekdayMask` — в API есть массив `weekdays`;
- периоды — у API нет команд периодов;
- секреты, токены, кеш, временные флаги.

Если сомневаешься — вынеси в API. Дешевле добавить поле, чем объяснять, почему
MCP не видит данные пользователя.

## 8. Чек-лист

- [ ] Поле в JSON-сериализаторе.
- [ ] Поле в input-структуре (optional, если можно не присылать).
- [ ] Применение в `Store.create*`.
- [ ] Сравнение при идемпотентном повторе.
- [ ] `Action` + `writes` + `execute`, если новое действие.
- [ ] `Docs/Local-API.md`.
- [ ] `@mcp.tool` + все параметры.
- [ ] `mcp/README.md`.
- [ ] Утверждение в `smoke.py`.
- [ ] `./mcp/tests/build-fixture.sh && mcp/.venv/bin/python mcp/tests/smoke.py`.
- [ ] `python3 Scripts/audit-feature-sync.py` — api/mcp зелёные.
