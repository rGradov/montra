# Montra MCP

FastMCP gives Codex access to Montra's local HTTP API. Other apps can call the API
directly. [API setup and HTTP examples](../Docs/Local-API.md)

## Setup

Build and launch Montra. Complete onboarding and enable **Local API** under
**Settings → Integration** or from the menu bar. Keep Montra running during
imports. FastMCP reads the token from a private file created by the app.

FastMCP requires `uv` and Python 3.12–3.14. Run these commands from the repository root.

```bash
uv sync --project mcp --locked --python 3.13
codex mcp add montra -- "$PWD/mcp/run.sh"
codex mcp list
```

In the Codex desktop app, select **MCP servers → Add server → STDIO** and enter
the absolute path to `mcp/run.sh`. If the server already uses this command, restart
Codex. Set `default_tools_approval_mode = "writes"` in the Codex configuration to
require approval for writes. [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

## Importing PDF statements

Give local Codex the path to the statement and ask it to prepare the import.

> Read this PDF statement and prepare an import into the Card account in Montra
> in BYN. Reconcile the amounts and count of posted transactions with the
> statement. Show a preview and possible duplicates. Import after I confirm.

1. Match the account and currency with `list_accounts`, and use
   `list_categories` for categories. Use the debit or credit amount in the account
   currency. When creating an account for a full history, use the opening balance
   immediately before the first imported transaction.
2. Extract posted transactions. Skip totals and balances. Flag ambiguous rows,
   transfers between the user's own accounts, and differences between purchase
   and posting dates for review. If the statement gives only a date, use noon in
   the statement's time zone and disclose this choice. Include seconds and an
   offset, for example `2026-11-09T12:00:00+03:00`.
3. Call `preview_import` for one account and currency, with at most 100 rows per
   batch. Pass each amount as a positive decimal string with a period. BTC supports
   up to eight decimal places and other currencies support up to two. The row kind
   determines the sign. Categories are optional. Create accounts and categories
   when requested by the user.
4. Show the row count, total expenses and income, already imported rows, and
   potential matches. Review possible duplicates with the user using
   `list_operations` and remove confirmed duplicates from the batch. After review,
   use `allow_possible_duplicate: true` on the specific row for distinct payments
   with the same amount. Get a fresh preview after any change to the batch.
5. After confirmation, call `import_operations` with the same batch and
   `preview_token`. The app saves the batch in one transaction. The tool returns
   counts for newly created and already imported transactions.

### Duplicate detection

Use a consistent `source` for each bank or statement format, such as
`bank-statement`. Set `external_id` to the bank's stable transaction ID. If none
exists, use a stable statement ID and the original row number. Reuse the same values
on subsequent imports. For rows without bank IDs across different documents, review
matches on account, local date, amount, and kind. Different posting dates or amounts
can hide duplicates, so also compare overlapping statements against the originals.
A retry with the same ID and changed financial fields is rejected.

The server accepts structured rows. The assistant in chat reads the PDF. The server has no built-in OCR. For
scanned statements, verify the recognized amounts before importing.

## Tools

| Tool | Action |
| --- | --- |
| `status` | Returns the version and commands available in the running app |
| `list_accounts`, `get_balances`, `list_categories` | Lists accounts, totals by currency, categories, and subcategories |
| `list_operations` | Searches one or all accounts with filters and pagination |
| `create_account`, `create_category` | Creates an account with optional `is_savings` and `is_hidden_from_overview`, or a category or subcategory using `parent_id` |
| `create_operation` | Creates one transaction. Save `request_id` and reuse it on retry |
| `recategorize_operations` | Moves 1 to 100 selected expenses or income transactions to a category or subcategory of the same kind |
| `create_transfer`, `get_transfer` | Records a transfer between accounts and reads both sides |
| `create_plan`, `list_plans` | Creates a recurring payment and lists occurrences |
| `link_plan`, `record_plan` | Links a plan to an existing transaction or records it as a new one |
| `preview_import`, `import_operations` | Previews and writes a batch |
| `preview_delete_account`, `delete_account` | Previews and deletes an account with its transactions and plans |
| `preview_delete_operations`, `delete_operations` | Previews and deletes transactions, including both sides of a transfer |
| `preview_delete_plan`, `delete_plan` | Previews and deletes an occurrence or series while preserving linked transactions |

To delete accounts, transactions, or plans, enable **Allow Deletion via API**
under **Settings → Integration** or in the Montra menu bar. Show the preview and
submit its token after the user confirms. If the data changes, get a new preview.

## Connecting to ChatGPT in a browser

Codex connects directly to local `stdio`. For browser-based ChatGPT, connect the
same `mcp/run.sh` through OpenAI Secure MCP Tunnel if your workspace supports
custom MCP servers. Set up a tunnel, get a dedicated key for `tunnel-client`, and
confirm access in ChatGPT. Use the absolute path to `mcp/run.sh` as
`--mcp-command` in the tunnel profile and select **Tunnel** when adding the server.
Run the tunnel client on the Mac. [Secure MCP Tunnel guide](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)

## Verification

```bash
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py
```

The test exercises HTTP and MCP against the same in-memory SwiftData store. It
covers authorization, previews, retries, legacy IDs, and account deletion.
