# Local API and MCP playbook

The Local API runs in Swift inside the app (`Montra/Integration/LedgerAPI.swift`).
MCP runs as a separate Python process (`mcp/server.py`) and calls the HTTP API.
Update both layers explicitly. MCP must be able to reproduce any write available
in the app, including setting a flag and reading it back.

## 1. Local API fields

### Read

Add the key to the appropriate serializer in `LedgerAPI.swift`.

```swift
private func accountJSON(_ account: Account) -> JSONObject {
    [
        "id": id(account.id),
        // ...
        "is_pinned": account.isPinned,
    ]
}
```

Use `snake_case` for API keys. The decoder uses
`keyDecodingStrategy = .convertFromSnakeCase`, so it reads `isPinned` from
`is_pinned`.

### Write

```swift
private struct AccountInput: Decodable {
    let name: String
    @CurrencyCode var currency: Currency
    // ...
    let isPinned: Bool?
}
```

Use an optional field for compatibility with older clients. Apply the default in
`Store.createAccount`.

```swift
let isPinned = input.isPinned ?? false
```

### Idempotency

If `create_account` can return an existing account, compare the new field when
the client provides it.

```swift
let pinnedMatches = input.isPinned.map { $0 == existing.isPinned } ?? true
guard matches.count == 1, existing.initialAmount == amount, pinnedMatches else {
    throw LedgerError("An account already has this name and currency. Inspect list_accounts before proceeding.")
}
```

Without that comparison, a retry with a different value silently returns the
existing record. The audit cannot detect that behavior.

## 2. New Local API actions

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

Add the action to `execute`.

```swift
case .archiveAccount:
    output = try store.archiveAccount(decoder.decode(AccountSelection.self, from: data))
```

Implement it in `Store`.

```swift
func archiveAccount(_ selection: AccountSelection) throws -> JSONObject {
    let account = try findAccount(selection.accountId)
    guard !account.isArchived else { return ["archived": false, "account": accountJSON(account)] }
    account.isArchived = true
    return ["archived": true, "account": accountJSON(account)]
}
```

- `status.actions` comes from `Action.allCases`.
- Use `LedgerError(message, status:)` with `422` for validation, `409` for a
  conflict or stale preview, `403` for an action disabled in Settings, and
  `404` for a missing record.
- Save once at the end of `execute`. Keep `context.save()` out of Store methods.
- For destructive actions, add a `preview_*` action and require
  `preview_token` to execute the confirmed action.
- Keep secrets, tokens, and machine-specific paths out of the API.

## 3. MCP tools

Register one tool per action and match the function name to the action name.

```python
@mcp.tool(annotations=CREATE)
def archive_account(account_id: UUID) -> dict:
    """Archive an account without deleting its operations. Repeating the call is safe."""
    return call_api("archive_account", account_id=str(account_id))
```

- Use `snake_case` parameters and the types defined in `server.py`.
- Use `Amount` for positive decimal strings, `Timestamp` for dates with an
  offset, and `Currency` for currencies.
- Select `READ`, `CREATE`, or `DELETE` based on behavior. Delete tools require
  `preview_token`.
- Explain retry behavior and side effects in the docstring.
- Pass every field accepted by the Swift input. The audit compares names.
- Keep business rules in the app.

## 4. Documentation

Update `Docs/Local-API.md` with a command table row, required and optional
parameters, and behavior including which fields appear in `list_*`, what changes,
and which requests are rejected. Include JSON for behavior that needs an example.

Update the tool table in `mcp/README.md`. Explain relevant behavior, such as a
hidden account's exclusion from the Overview total, and show new workflows.

## 5. Smoke test

`mcp/tests/smoke.py` starts the HTTP fixture and MCP against one in-memory store.
Add assertions alongside the existing checks.

```python
created = await call("create_account", name="Test", currency="EUR",
                     initial_amount="10", is_pinned=True)
assert created["account"]["is_pinned"] is True
assert not (await call("create_account", name="Test", currency="EUR",
                       initial_amount="10", is_pinned=True))["created"]
await reject("create_account", "already has this name",
             name="Test", currency="EUR", initial_amount="10", is_pinned=False)
```

Check creation, readback, idempotent retry, conflict on a different value, and
invalid or stale tokens for actions that require a preview.

`build-fixture.sh` compiles the Swift models and `LedgerAPI` directly. In DSH,
it uses `-disable-sandbox` so the SwiftData macro can launch its plugin server.

## 6. Example: hiding an account from Overview

1. The model and backup support `Account.isHiddenFromOverview`.
2. `AccountInput.isHiddenFromOverview` is optional.
3. `Store.createAccount` defaults it with `?? false` and compares it on retry.
4. `accountJSON` includes `"is_hidden_from_overview": account.isHiddenFromOverview`.
5. `Docs/Local-API.md` documents `create_account` and `list_accounts`.
6. `mcp/server.py` exposes `create_account(..., is_hidden_from_overview=False)`.
7. `mcp/README.md` documents `create_account`.
8. The smoke test covers creation, readback, retry, and rejection with a different flag.

Follow the same path for similar switches.

## 7. API exclusions

Document deliberate exclusions and their reasons in the allowlist.

- The server assigns `createdAt` and applies `sortIndex`.
- Coordinates are represented by text `place`.
- `weekdayMask` is represented by the `weekdays` array.
- Periods have no API commands.
- Secrets, tokens, caches, and temporary flags stay local.

Expose a user value when none of these reasons apply.

## 8. Checklist

- [ ] Field in the JSON serializer.
- [ ] Field in the input struct, optional when clients may omit it.
- [ ] Default applied in `Store.create*`.
- [ ] Comparison on idempotent retries.
- [ ] `Action`, `writes`, and `execute` for a new action.
- [ ] Updated `Docs/Local-API.md`.
- [ ] `@mcp.tool` and all parameters.
- [ ] Updated `mcp/README.md`.
- [ ] Assertions in `smoke.py`.
- [ ] `./mcp/tests/build-fixture.sh && mcp/.venv/bin/python mcp/tests/smoke.py`.
- [ ] API and MCP checks pass in `python3 Scripts/audit-feature-sync.py`.
