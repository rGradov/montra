# Montra Local HTTP API

After completing onboarding, enable **Local API** under **Settings → Integration**
or choose **Integration → Enable Local API** in the menu bar. Montra accepts HTTP
requests while the app is running and the integration is enabled. It remembers
the setting across launches.

- Send all commands to `POST http://127.0.0.1:8766/v1/commands`.
- Set the `Content-Type: application/json` and `Authorization: Bearer <token>` headers.
- Copy the token from **Settings → Integration** or the **Integration** menu.
  Local scripts can read it from `~/Library/Application Support/Montra/LocalAPI/token`.
- A successful response returns JSON and status `200`. Errors include an
  `error` field. An invalid token returns `401`, a conflict or stale preview
  returns `409`, and a data validation failure returns `422`.

## Calling the API from a terminal

The following command lists accounts and passes the token to curl via stdin.

```bash
{
  printf 'Authorization: Bearer '
  cat "$HOME/Library/Application Support/Montra/LocalAPI/token"
  printf '\n'
} | curl --noproxy 127.0.0.1 --silent --show-error --fail-with-body \
  --header @- --json '{"action":"list_accounts"}' \
  http://127.0.0.1:8766/v1/commands
```

This request creates a transaction in the selected account.

```json
{
  "action": "create_operation",
  "account_id": "be613793-0605-437f-afc7-93bb6cb37a33",
  "currency": "BYN",
  "request_id": "e25c309b-13b2-4a0d-a966-c4bad744e31d",
  "operation": {
    "kind": "expense",
    "date": "2026-11-09T12:30:00+03:00",
    "amount": "12.50",
    "place": "Coffee shop"
  }
}
```

Get the `account_id` from `list_accounts`. Generate a new `request_id` for each
transaction and retain it to retry that same request safely.

## Commands

Pass command parameters at the top level alongside `action`. Transaction fields
go inside the `operation` object or each entry in `rows`.

| Command | Parameters besides `action` |
| --- | --- |
| `status` | No parameters. Returns the version, supported commands in `actions`, and deletion permissions |
| `list_accounts`, `list_categories` | No parameters |
| `get_balances` | No parameters. Balances and totals are grouped by original currency |
| `list_operations` | Optional `account_id`, `category_id`, `kind`, `query`, `from_date`, `before_date`, `limit`, and `offset` |
| `create_account` | `name`, `currency`. Optional `initial_amount`, `icon_name`, `color`, `is_savings`, and `is_hidden_from_overview` |
| `create_category` | `name`, `kind`. Optional `is_mandatory`, `icon_name`, `color`, and `parent_id` |
| `create_operation` | `account_id`, `currency`, `request_id`, `operation` |
| `recategorize_operations` | 1 to 100 unique `operation_ids` and the target category or subcategory `category_id` |
| `create_transfer` | `source_account_id`, `destination_account_id`, `request_id`, `date`, `sent`. Different currencies require `received` |
| `get_transfer` | `transfer_id` from the transfer creation response or transaction list |
| `list_plans` | Optional `account_id`, `series_id`, `status`, `from_date`, `before_date`, `limit`, and `offset` |
| `create_plan` | `account_id`, `currency`, `request_id`, `operation`, `frequency`, `end_date`. Optional `weekdays` for weekly recurrence |
| `link_plan` | `plan_id`, `operation_id` of an existing transaction of the same kind |
| `record_plan` | `plan_id`. Optional `date` defaults to the current time |
| `preview_import` | `account_id`, `currency`, `source`, `rows` |
| `import_operations` | Same fields plus the `preview_token` returned by the preview |
| `preview_delete_account` | `account_id` |
| `delete_account` | `account_id` and the `preview_token` returned by the preview |
| `preview_delete_operations`, `delete_operations` | 1 to 100 unique `operation_ids`. Deletion requires `preview_token` |
| `preview_delete_plan`, `delete_plan` | `plan_id`, optional `scope` (`occurrence` by default, or `series`). Deletion requires `preview_token` |

Each transaction requires `kind` (`income` or `expense`), `date` (ISO 8601 with
an offset), and `amount` (a positive decimal string with a period). It also
accepts `category_id`, `place`, `note`, and `allow_possible_duplicate`. Each
statement row requires a stable `external_id`. A batch contains 1 to 100 rows.
The currency must match the account currency. [Preview and duplicate rules](../mcp/README.md#importing-pdf-statements)

`list_accounts` returns `is_savings` and `is_hidden_from_overview`. Hidden
accounts are excluded from the Overview total and remain available in account
lists, on their own pages, and in Analytics. You can set the flag at creation.

`list_operations` searches all accounts when `account_id` is omitted. Filtering
by a parent category includes its subcategories. Supported values for `kind`
are `expense`, `income`, and `transfer`. The first two exclude transfers.
`from_date` is inclusive and `before_date` is exclusive. To create a subcategory,
specify a top-level parent of the same kind. `list_categories` returns
`parent_id` and `effective_is_mandatory`, which reflects inheritance from the parent.

Use `list_operations` to select transactions and `list_categories` to select the
target category or subcategory. When filtering by a parent, check each result's
`category.id` because the filter also returns subcategory transactions. All
selected transactions must match the target category's kind. The command rejects
transfers. It changes only the category and saves the batch in one transaction.
`updated_count` reports the number of changes, and `operations` returns the
selected records in request order. Repeating the request on the same data
returns an `updated_count` of zero.

A transfer saves two linked transactions atomically. Pass the sent and received
amounts as strings in their respective account currencies. For same-currency
transfers, `received` defaults to `sent`. To safely retry a transfer or recurring
plan creation, reuse the original `request_id` and repeat the same request.

Plans start at `operation.date` and include the final `end_date` in the Mac's
calendar. Supported frequencies are `day`, `week`, `month`, and `year`, with up
to 1,000 occurrences per series. For weekly recurrence, Sunday is 1 and Saturday
is 7. The default is the start date's weekday. `list_plans` defaults to `pending`
and also accepts `all`, `upcoming` (including today), `missed`, and `linked`.
Creating a plan leaves the balance unchanged. `record_plan` creates and links a
transaction, while `link_plan` links an existing transaction.

The **Allow Deletion via API** switch in Settings and the **Integration** menu
controls deletion of accounts, transactions, and plans. It defaults to off.
After upgrading, the switch is on only if both legacy permissions were on.
The `account_delete_enabled` and `entry_delete_enabled` fields in `status` both
reflect this switch.

Deleting an account includes its transactions and plans. Selecting one side of
a transfer for deletion previews both sides. Deleting a linked transaction makes
its plan pending again. Deleting a plan or series preserves linked transactions.
The client confirms the preview and submits its token with the same parameters.

The API accepts one HTTP/1.1 request per connection with `Content-Length` and a
body of up to 256 KiB. Use `127.0.0.1`. Requests with an `Origin` header are
rejected. Browser extensions need a native intermediary.

## Codex and PDF import

FastMCP calls this HTTP API from local Codex. Connect MCP to use the API with
the assistant in chat. Scripts and desktop clients can call the API directly.
[FastMCP setup](../mcp/README.md)
