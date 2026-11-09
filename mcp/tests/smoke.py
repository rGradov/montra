"""Test both the native HTTP API and FastMCP against an in-memory SwiftData store."""

import asyncio
import http.client
import json
import socket
import subprocess
from contextlib import contextmanager
from pathlib import Path
from uuid import UUID, uuid4, uuid5

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "a" * 64


def http_command(port: int, payload: dict, token: str | None = TOKEN, **headers) -> tuple[int, dict]:
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
    try:
        headers["Content-Type"] = "application/json"
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        conn.request("POST", "/v1/commands", json.dumps(payload), headers)
        response = conn.getresponse()
        return response.status, json.loads(response.read())
    finally:
        conn.close()


@contextmanager
def fixture(allow_delete: bool = False):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    child = subprocess.Popen([
        ROOT / ".build" / "montra-http-fixture", str(port), str(int(allow_delete)),
    ])
    try:
        yield port
    finally:
        child.terminate()
        child.wait(timeout=5)


async def wait_for_fixture(port: int, allow_delete: bool) -> None:
    for _ in range(50):
        try:
            status, data = http_command(port, {"action": "status"})
        except OSError:
            await asyncio.sleep(0.1)
            continue
        assert status == 200 and data["version"] == 1
        assert data["account_delete_enabled"] == data["entry_delete_enabled"] == allow_delete
        return
    raise RuntimeError("HTTP fixture did not start.")


def client(port: int) -> Client:
    return Client(StdioTransport(
        command=str(ROOT / "run.sh"), args=[],
        env={"MONTRA_API_PORT": str(port), "MONTRA_API_TOKEN": TOKEN},
    ))


async def exercise(port: int) -> None:
    async with client(port) as mcp:
        async def call(tool: str, **args) -> dict:
            return (await mcp.call_tool(tool, args)).data

        async def reject(tool: str, expected: str, **args) -> None:
            result = await mcp.call_tool(tool, args, raise_on_error=False)
            assert result.is_error and expected in result.content[0].text, result

        tools = {tool.name: tool for tool in await mcp.list_tools()}
        capabilities = await call("status")
        assert set(tools) == set(capabilities["actions"])
        assert tools["preview_import"].annotations.readOnlyHint
        assert tools["delete_account"].annotations.destructiveHint

        accounts = (await call("list_accounts"))["accounts"]
        assert len(accounts) == 1 and accounts[0]["balance"] == "25"
        account_args = {
            "name": "Тест EUR", "currency": "EUR", "initial_amount": "50.25",
            "is_savings": True, "is_hidden_from_overview": True,
        }
        created = await call("create_account", **account_args)
        assert created["created"]
        assert created["account"]["is_savings"] is True
        assert created["account"]["is_hidden_from_overview"] is True
        assert not (await call("create_account", **account_args))["created"]
        await reject("create_account", "already has this name",
                     **{**account_args, "is_hidden_from_overview": False})
        account_id = created["account"]["id"]

        category_args = {"name": "Кофе", "kind": "expense"}
        category = (await call("create_category", **category_args))["category"]
        assert (await call("list_categories"))["categories"] == [category]
        assert not (await call("create_category", **category_args))["created"]
        parent_args = {"name": "Обязательные", "kind": "expense", "is_mandatory": True}
        parent = (await call("create_category", **parent_args))["category"]
        child_args = {**category_args, "parent_id": parent["id"]}
        child = (await call("create_category", **child_args))["category"]
        assert child["id"] != category["id"] and child["parent_id"] == parent["id"]
        assert child["effective_is_mandatory"] and not child["is_mandatory"]
        assert not (await call("create_category", **child_args))["created"]
        await reject("create_category", "top-level", **{**child_args, "parent_id": child["id"]})

        first = {
            "external_id": 'строка/"1"💳', "date": "2026-11-09T12:30:00+03:00",
            "kind": "expense", "amount": "5.50", "category_id": child["id"], "place": "Тест",
        }
        second = {"external_id": "row-2", "date": first["date"], "kind": "income", "amount": "20.25"}
        batch = {"account_id": account_id, "currency": "EUR", "source": "test-bank", "rows": [first, second]}
        status, preview = http_command(port, {"action": "preview_import", **batch})
        assert status == 200
        assert preview == await call("preview_import", **batch)
        old_id = uuid5(UUID(account_id), json.dumps(["statement:test-bank", first["external_id"]]))
        assert preview["rows"][0]["operation_id"] == str(old_id)
        assert preview["to_create"] == 2 and preview["needs_review"] == 0
        assert preview["income_to_create"] == "20.25" and preview["expense_to_create"] == "5.5"
        assert (await call("list_operations", account_id=account_id))["total"] == 0

        commit = {**batch, "preview_token": preview["preview_token"]}
        await reject("import_operations", "preview changed", **{**commit, "rows": [first]})
        await reject("import_operations", "Choose an existing category", **{
            **commit, "rows": [first, {**second, "category_id": category["id"]}],
        })
        await reject("preview_import", "Currency mismatch", **{**batch, "currency": "USD"})
        await reject("preview_import", "Duplicate external IDs", **{**batch, "rows": [first, first]})
        await reject("preview_import", "decimal places", **{**batch, "rows": [{**first, "amount": "0.001"}]})
        await reject("preview_import", "valid timestamp", **{
            **batch, "rows": [{**first, "date": "2026-02-31T12:00:00+03:00"}],
        })
        assert (await call("list_operations", account_id=account_id))["total"] == 0

        assert (await call("import_operations", **commit))["created"] == 2
        retry = await call("import_operations", **commit)
        assert retry["created"] == 0 and retry["already_imported"] == 2
        await reject("preview_import", "conflicts", **{**batch, "rows": [{**first, "amount": "6.50"}]})

        duplicate = {**batch, "rows": [{**first, "external_id": "different-id"}]}
        overlap = await call("preview_import", **duplicate)
        assert overlap["needs_review"] == 1 and overlap["to_create"] == 0
        await reject("import_operations", "Possible duplicates", **duplicate, preview_token=overlap["preview_token"])

        page = await call("list_operations", account_id=account_id, limit=1)
        assert page["account"]["balance"] == "65" and page["total"] == 2 and page["next_offset"] == 1
        assert page["operations"][0]["date"] == "2026-11-09T09:30:00Z"
        search = await call("list_operations", query="Тест кофе", category_id=parent["id"], kind="expense")
        assert search["total"] == 1 and search["operations"][0]["id"] == str(old_id)

        delete_preview = await call("preview_delete_account", account_id=account_id)
        assert delete_preview["operation_count"] == 2

        operation = {"kind": "expense", "amount": "0.01", "date": "2026-11-10T12:00:00+03:00"}
        single = {"account_id": account_id, "currency": "EUR", "request_id": str(uuid4()), "operation": operation}
        concurrent = await asyncio.gather(call("create_operation", **single), call("create_operation", **single))
        assert sorted(result["created"] for result in concurrent) == [0, 1]

        ledger = await call("list_operations", account_id=account_id)
        expenses = [row for row in ledger["operations"] if row["kind"] == "expense"]
        expense_ids = [row["id"] for row in expenses]
        income_id = next(row["id"] for row in ledger["operations"] if row["kind"] == "income")
        recategorize = {"operation_ids": expense_ids, "category_id": category["id"]}
        await reject("recategorize_operations", "same kind", **{**recategorize, "operation_ids": [*expense_ids, income_id]})
        await reject("recategorize_operations", "category of kind income", operation_ids=[income_id], category_id=category["id"])
        await reject("recategorize_operations", "not found", **{**recategorize, "operation_ids": [*expense_ids, str(uuid4())]})
        await reject("recategorize_operations", "distinct operation IDs", **{**recategorize, "operation_ids": [expense_ids[0]] * 2})
        assert await call("list_operations", account_id=account_id) == ledger

        status, updated = http_command(port, {"action": "recategorize_operations", **recategorize})
        expected = [{**row, "category": category} for row in expenses]
        assert status == 200 and updated == {"updated_count": 2, "operations": expected}
        assert await call("recategorize_operations", **recategorize) == {"updated_count": 0, "operations": expected}
        refreshed = await call("list_operations", account_id=account_id)
        assert refreshed["account"] == ledger["account"] and refreshed["total"] == ledger["total"]
        assert [row for row in refreshed["operations"] if row["kind"] == "expense"] == expected
        restored = await call("recategorize_operations", operation_ids=[str(old_id)], category_id=child["id"])
        assert restored["updated_count"] == 1 and restored["operations"][0]["category"] == child

        transfer_args = {
            "source_account_id": accounts[0]["id"], "destination_account_id": account_id,
            "request_id": str(uuid4()), "date": operation["date"], "sent": "10",
        }
        await reject("create_transfer", "received amount", **transfer_args)
        transfer_args["received"] = "3.00"
        transfer = await call("create_transfer", **transfer_args)
        assert transfer["created"] and not (await call("create_transfer", **transfer_args))["created"]
        await reject("create_transfer", "different or incomplete transfer", **{**transfer_args, "sent": "9"})
        pair = await call("get_transfer", transfer_id=transfer["transfer"]["id"])
        assert pair["complete"] and len(pair["operations"]) == 2
        assert (await call("list_operations", kind="transfer"))["total"] == 2
        assert (await call("list_operations", kind="income"))["total"] == 1
        balances = await call("get_balances")
        assert balances["totals"] == [{"currency": "BYN", "balance": "15"}, {"currency": "EUR", "balance": "67.99"}]
        operation_ids = [pair["operations"][0]["id"]]
        await reject("recategorize_operations", "Transfers cannot be recategorized",
                     operation_ids=[*expense_ids, *operation_ids], category_id=category["id"])
        removal = await call("preview_delete_operations", operation_ids=operation_ids)
        assert removal["operation_count"] == 2
        removed = await call("delete_operations", operation_ids=operation_ids, preview_token=removal["preview_token"])
        assert removed["deleted_operation_count"] == 2
        assert (await call("list_operations", kind="transfer"))["total"] == 0

        plan_args = {
            "account_id": account_id, "currency": "EUR", "request_id": str(uuid4()),
            "operation": {**operation, "amount": "2.50"},
            "frequency": "day", "end_date": "2026-11-12T12:00:00+03:00",
        }
        planned = await call("create_plan", **plan_args)
        assert planned["created"] and planned["plan_count"] == 3
        assert not (await call("create_plan", **plan_args))["created"]
        series = {"series_id": planned["series_id"]}
        plans = (await call("list_plans", **series))["plans"]
        assert len(plans) == 3 and (await call("list_operations", account_id=account_id))["total"] == 3
        first_plan, second_plan, third_plan = [row["id"] for row in plans]
        assert (await call("link_plan", plan_id=first_plan, operation_id=str(old_id)))["linked"]
        await reject("link_plan", "already linked", plan_id=second_plan, operation_id=str(old_id))
        fact = await call("record_plan", plan_id=second_plan, date=operation["date"])
        assert fact["created"]
        assert not (await call("record_plan", plan_id=second_plan, date=operation["date"]))["created"]
        assert (await call("list_plans", **series, status="linked"))["total"] == 2
        operations = [fact["operation"]["id"]]
        fact_removal = await call("preview_delete_operations", operation_ids=operations)
        assert fact_removal["linked_plan_count"] == 1
        assert (await call("delete_operations", operation_ids=operations, preview_token=fact_removal["preview_token"]))["reopened_plan_count"] == 1
        plan_preview = await call("preview_delete_plan", plan_id=third_plan, scope="series")
        assert plan_preview["plan_count"] == 3 and plan_preview["linked_operation_count"] == 1
        await reject("delete_plan", "plan changed", plan_id=third_plan, preview_token=plan_preview["preview_token"])
        assert (await call("delete_plan", plan_id=third_plan, scope="series", preview_token=plan_preview["preview_token"]))["deleted_plan_count"] == 3
        assert (await call("list_operations", account_id=account_id))["total"] == 3

        await reject("delete_account", "changed", account_id=account_id, preview_token=delete_preview["preview_token"])
        await call("create_plan", **{**plan_args, "request_id": str(uuid4())})
        foreign = await call("create_plan", **{
            **plan_args, "account_id": accounts[0]["id"], "currency": "BYN", "request_id": str(uuid4()),
            "end_date": operation["date"],
        })
        foreign_plan = (await call("list_plans", series_id=foreign["series_id"]))["plans"][0]
        await call("link_plan", plan_id=foreign_plan["id"], operation_id=str(old_id))
        latest = await call("preview_delete_account", account_id=account_id)
        assert latest["plan_count"] == 3 and latest["reopened_plan_count"] == 1
        status, deleted = http_command(port, {
            "action": "delete_account", "account_id": account_id, "preview_token": latest["preview_token"],
        })
        assert status == 200 and deleted["deleted_operation_count"] == 3 and deleted["deleted_plan_count"] == 3
        assert deleted["reopened_plan_count"] == 1
        pending = (await call("list_plans"))["plans"]
        assert len(pending) == 1 and pending[0]["id"] == foreign_plan["id"]
        assert len((await call("list_accounts"))["accounts"]) == 1


async def main() -> None:
    with fixture() as port:
        await wait_for_fixture(port, allow_delete=False)
        request = {"action": "list_accounts"}
        assert http_command(port, request, token=None)[0] == 401
        assert http_command(port, request, token="b" * 64)[0] == 401
        assert http_command(port, request, Host="attacker.example")[0] == 403
        assert http_command(port, request, Origin="https://attacker.example")[0] == 403
        status, data = http_command(port, request)
        assert status == 200
        account_id = data["accounts"][0]["id"]
        status, preview = http_command(port, {"action": "preview_delete_account", "account_id": account_id})
        assert status == 200
        assert http_command(port, {
            "action": "delete_account", "account_id": account_id, "preview_token": preview["preview_token"],
        })[0] == 403

        for action in ("delete_operations", "delete_plan"):
            assert http_command(port, {"action": action})[0] == 403

    with fixture(allow_delete=True) as port:
        await wait_for_fixture(port, allow_delete=True)
        await exercise(port)
    print("Montra local HTTP and MCP smoke test passed.")


if __name__ == "__main__":
    asyncio.run(main())
