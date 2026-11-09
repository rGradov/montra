#!/usr/bin/env python3
"""Audit Montra's feature-sync rules.

The script is the mechanical half of the `montra-feature-release` skill. It
checks four things that are easy to forget once a feature works on screen:

  1. every persisted model field and setting has a home in the backup format;
  2. every local API action has an MCP tool and a line in both docs;
  3. every model field that crosses the API is serialized or accepted;
  4. every new UI string exists in Localizable.xcstrings in English and Russian.

It also warns when the newest DMG is older than the app sources.

Usage:
    python3 Scripts/audit-feature-sync.py
    python3 Scripts/audit-feature-sync.py --require-dmg
    python3 Scripts/audit-feature-sync.py --verbose

Exit code 0 means the gates are green. Exit code 1 means at least one hard
gate failed. Deliberate exceptions go to Scripts/feature-sync-allowlist.txt
with a reason, never silently.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ARCHIVE = ROOT / "Montra/Backup/BackupArchive.swift"
BACKUP_SERVICE = ROOT / "Montra/Backup/BackupService.swift"
SETTINGS_STORE = ROOT / "Montra/Store/SettingsStore.swift"
INTEGRATION = ROOT / "Montra/Integration/LocalIntegration.swift"
LEDGER_API = ROOT / "Montra/Integration/LedgerAPI.swift"
MCP_SERVER = ROOT / "mcp/server.py"
MCP_README = ROOT / "mcp/README.md"
LOCAL_API_DOC = ROOT / "Docs/Local-API.md"
LOCALIZABLE = ROOT / "Montra/Resources/Localizable.xcstrings"
ALLOWLIST = ROOT / "Scripts/feature-sync-allowlist.txt"
MODEL_FILES = [
    ROOT / "Montra/Models/Models.swift",
    ROOT / "Montra/Models/Plan.swift",
]
DMG_DIR = ROOT / "build"

RELATIONSHIP_TYPES = {"Account", "Category", "Operation", "Period", "PlannedOperation"}

# The structs a client fills in. Every field has to be reachable from the MCP
# tool that fronts the same action; otherwise the app can create a record that
# MCP cannot reproduce.
MCP_INPUT_STRUCTS = [
    "AccountInput",
    "CategoryInput",
    "LedgerOperationFilter",
    "ImportRow",
    "OperationRecategorization",
    "ImportInput",
    "TransferInput",
    "LedgerPlanFilter",
    "PlanInput",
    "PlanLink",
    "PlanRecord",
    "PlanDeletion",
    "OperationDeletion",
    "AccountSelection",
    "TransferSelection",
]

# Read serializer + write input used when checking that a model field crosses
# the local API. Period is deliberately absent: the API has no period commands.
API_FIELD_CONTEXT = {
    "Account": (["accountJSON", "createAccount"], ["AccountInput"]),
    "Category": (["categoryJSON", "createCategory"], ["CategoryInput"]),
    "Operation": (["operationJSON", "handleImport"], ["ImportRow"]),
    "PlannedOperation": (["planJSON", "createPlan"], ["PlanInput"]),
}


class Audit:
    def __init__(self, verbose: bool = False) -> None:
        self.verbose = verbose
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.passes: list[str] = []
        self.notes: list[str] = []

    def ok(self, message: str) -> None:
        self.passes.append(message)

    def fail(self, message: str) -> None:
        self.failures.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def note(self, message: str) -> None:
        if self.verbose:
            self.notes.append(message)


# ---------------------------------------------------------------------------
# Swift source helpers
# ---------------------------------------------------------------------------


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"cannot read {path.relative_to(ROOT)}: {exc}") from exc


def brace_body(source: str, open_brace: int) -> str:
    """Return the text inside the braces starting at `open_brace`."""
    depth = 0
    index = open_brace
    while index < len(source):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[open_brace + 1 : index]
        index += 1
    raise ValueError("unbalanced braces")


def named_body(source: str, name: str, kind: str = r"\w+", prefix: str = "") -> str:
    pattern = rf"\b{prefix}{kind}\s+{re.escape(name)}\b[^{{]*\{{"
    match = re.search(pattern, source)
    if not match:
        raise SystemExit(f"cannot find {name} in the Swift source")
    return brace_body(source, match.end() - 1)


def function_body(source: str, name: str) -> str:
    match = re.search(rf"\bfunc\s+{re.escape(name)}\s*\(", source)
    if not match:
        raise SystemExit(f"cannot find function {name} in the Swift source")
    opening = source.find("{", match.end())
    if opening < 0:
        raise SystemExit(f"cannot find the body of {name}")
    return brace_body(source, opening)


def whole_word(name: str, text: str) -> bool:
    return re.search(rf"(?<![\w]){re.escape(name)}(?![\w])", text) is not None


def camel_to_snake(value: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", value).lower()


def stored_model_properties(verbose: bool = False) -> dict[str, list[str]]:
    """Stored properties of every @Model class, minus relationships."""
    source = "\n".join(read(path) for path in MODEL_FILES)
    properties: dict[str, list[str]] = {}
    for match in re.finditer(r"@Model\s+final class\s+(\w+)\s*\{", source):
        model = match.group(1)
        body = brace_body(source, match.end() - 1)
        for line in body.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("//"):
                continue
            if stripped.startswith("@Relationship"):
                continue
            field = re.match(
                r"(?:@\w+(?:\([^)]*\))?\s+)*(?:private\s+|public\s+|internal\s+)?var\s+(\w+)\s*:\s*([^={]+)",
                stripped,
            )
            if not field:
                continue
            if "{" in stripped:
                # Computed property; relationships and derived values live here.
                continue
            name, type_name = field.group(1), field.group(2).strip()
            base = type_name.rstrip("?").strip()
            if base.startswith("[") or base in RELATIONSHIP_TYPES:
                continue
            properties.setdefault(model, []).append(name)
        if verbose:
            print(f"    {model}: {', '.join(properties.get(model, []))}")
    return properties


def published_properties(path: Path) -> list[str]:
    source = read(path)
    return re.findall(r"@Published\s+(?:private\(set\)\s+)?var\s+(\w+)", source)


# ---------------------------------------------------------------------------
# Allowlist
# ---------------------------------------------------------------------------


def load_allowlist(audit: Audit) -> dict[str, str]:
    entries: dict[str, str] = {}
    if not ALLOWLIST.exists():
        return entries
    for number, line in enumerate(ALLOWLIST.read_text(encoding="utf-8").splitlines(), start=1):
        key, _, reason = line.partition("#")
        key = key.strip()
        reason = reason.strip()
        if not key:
            continue
        if not reason:
            audit.warn(f"allowlist:{number}: {key} has no reason; explain why it is excluded")
        entries[key] = reason
    return entries


def allowed(entries: dict[str, str], key: str, audit: Audit) -> bool:
    if key not in entries:
        return False
    audit.note(f"allowlisted {key}: {entries[key] or 'no reason'}")
    return True


# ---------------------------------------------------------------------------
# Localization
# ---------------------------------------------------------------------------


def check_localization(audit: Audit) -> None:
    try:
        catalog = json.loads(read(LOCALIZABLE))
    except json.JSONDecodeError as exc:
        audit.fail(f"localization: Localizable.xcstrings is not valid JSON: {exc}")
        return
    entries: dict[str, dict] = catalog.get("strings", {})
    if not entries:
        audit.fail("localization: Localizable.xcstrings has no strings")
        return

    used: dict[str, list[str]] = {}
    for path in sorted((ROOT / "Montra").rglob("*.swift")):
        source = read(path)
        for match in re.finditer(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"', source):
            raw = match.group(1)
            prefix = raw.split("\\(")[0]
            if "\\(" in raw and not prefix:
                continue
            line = source.count("\n", 0, match.start()) + 1
            used.setdefault(prefix, []).append(f"{path.relative_to(ROOT)}:{line}")

    missing: list[str] = []
    untranslated: list[str] = []
    for prefix, locations in sorted(used.items()):
        if prefix in entries:
            candidates = [prefix]
        elif prefix.endswith("."):
            candidates = [key for key in entries if key.startswith(prefix)]
        elif "\\(" in prefix or prefix.endswith(" "):
            candidates = [key for key in entries if key.startswith(prefix)]
        else:
            candidates = []
        if not candidates:
            missing.append(f"{prefix!r} used at {', '.join(locations[:3])}")
            continue
        for key in candidates:
            localizations = entries[key].get("localizations", {})
            for language in ("en", "ru"):
                localization = localizations.get(language, {})
                unit = localization.get("stringUnit")
                variations = localization.get("variations")
                if unit and unit.get("state") == "translated" and unit.get("value"):
                    continue
                if variations:
                    continue
                untranslated.append(f"{key!r} has no translated {language} value")
                break

    if missing:
        audit.fail(f"localization: {len(missing)} key(s) used in Swift but absent from Localizable.xcstrings")
        for item in missing[:20]:
            audit.fail(f"  - {item}")
        if len(missing) > 20:
            audit.fail(f"  - ... and {len(missing) - 20} more")
    if untranslated:
        audit.fail(f"localization: {len(untranslated)} key(s) missing an English or Russian translation")
        for item in untranslated[:20]:
            audit.fail(f"  - {item}")
    if not missing and not untranslated:
        audit.ok(f"localization: {len(used)} call sites resolve, all translations present")


# ---------------------------------------------------------------------------
# Backup coverage
# ---------------------------------------------------------------------------


def check_backup(audit: Audit, allowlist: dict[str, str]) -> None:
    archive = read(ARCHIVE)
    service = read(BACKUP_SERVICE)
    backup_text = archive + "\n" + service

    models = stored_model_properties(audit.verbose)
    missing_models: list[str] = []
    for model, properties in models.items():
        for prop in properties:
            if prop.endswith("Raw"):
                audit.note(f"backup: {model}.{prop} is represented by its typed accessor")
                continue
            key = f"backup:{model}.{prop}"
            if allowed(allowlist, key, audit):
                continue
            if not whole_word(prop, backup_text):
                missing_models.append(f"{model}.{prop} is not read or written by BackupArchive/BackupService")

    settings = published_properties(SETTINGS_STORE)
    settings_backup = named_body(archive, "SettingsBackup", kind="struct")
    apply_body = function_body(service, "apply")
    missing_settings: list[str] = []
    for prop in settings:
        key = f"backup:SettingsStore.{prop}"
        if allowed(allowlist, key, audit):
            continue
        if not whole_word(prop, settings_backup):
            missing_settings.append(f"SettingsStore.{prop} is missing from SettingsBackup")
        elif not whole_word(prop, apply_body):
            missing_settings.append(f"SettingsStore.{prop} is not applied by BackupService.restore")

    integration = published_properties(INTEGRATION)
    integration_backup = named_body(archive, "IntegrationBackup", kind="struct")
    missing_integration: list[str] = []
    for prop in integration:
        key = f"backup:LocalIntegration.{prop}"
        if allowed(allowlist, key, audit):
            continue
        if not whole_word(prop, integration_backup):
            missing_integration.append(f"LocalIntegration.{prop} is missing from IntegrationBackup")

    secret_fields = re.findall(
        r"\b(?:var|let)\s+(\w*(?:token|secret|password)\w*)\s*:", archive, re.IGNORECASE
    )
    if secret_fields:
        audit.fail(f"backup: machine secret(s) found in the archive: {', '.join(sorted(set(secret_fields)))}")

    failures = missing_models + missing_settings + missing_integration
    if failures:
        audit.fail(f"backup: {len(failures)} persisted value(s) would be lost on export/restore")
        for item in failures:
            audit.fail(f"  - {item}")
    else:
        audit.ok(
            f"backup: {sum(len(value) for value in models.values())} model fields, "
            f"{len(settings)} settings and {len(integration)} integration switches covered"
        )

    schema = re.search(r"currentSchemaVersion\s*=\s*(\d+)", archive)
    format_version = re.search(r"currentFormatVersion\s*=\s*(\d+)", archive)
    if schema and format_version:
        audit.ok(
            f"backup: format v{format_version.group(1)}, schema v{schema.group(1)} "
            "(bump when the shape changes)"
        )
    else:
        audit.fail("backup: cannot read currentFormatVersion/currentSchemaVersion")


# ---------------------------------------------------------------------------
# Local API actions
# ---------------------------------------------------------------------------


def api_actions(audit: Audit) -> list[str]:
    source = read(LEDGER_API)
    body = named_body(source, "Action", kind="enum", prefix="private ")
    actions: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        match = re.match(r'case\s+(\w+)(?:\s*=\s*"([^"]+)")?', stripped)
        if not match:
            continue
        actions.append(match.group(2) or match.group(1))
    if not actions:
        audit.fail("api: cannot read any Action cases from LedgerAPI.swift")
    return actions


def check_api_mcp_docs(audit: Audit) -> None:
    actions = api_actions(audit)
    if not actions:
        return
    action_set = set(actions)

    mcp_source = read(MCP_SERVER)
    calls = set(re.findall(r'call_api\(\s*"([a-z0-9_]+)"', mcp_source))
    tool_defs = set(
        re.findall(r"@mcp\.tool\([^)]*\)\s*\ndef\s+(\w+)\s*\(", mcp_source, re.DOTALL)
    )

    api_doc_tokens = set(re.findall(r"`([a-z0-9_]+)`", read(LOCAL_API_DOC)))
    mcp_doc_tokens = set(re.findall(r"`([a-z0-9_]+)`", read(MCP_README)))

    problems: list[str] = []
    for action in actions:
        if action not in calls:
            problems.append(f"{action}: no call_api(...) in mcp/server.py")
        if action not in tool_defs:
            problems.append(f"{action}: no @mcp.tool def named {action} in mcp/server.py")
        if action not in api_doc_tokens:
            problems.append(f"{action}: missing from Docs/Local-API.md")
        if action not in mcp_doc_tokens:
            problems.append(f"{action}: missing from mcp/README.md")

    stale = sorted(calls - action_set)
    for action in stale:
        problems.append(f"{action}: MCP calls an action that LedgerAPI.Action does not declare")
    stale_tools = sorted(tool_defs - action_set)
    for tool in stale_tools:
        problems.append(f"{tool}: MCP tool has no matching LedgerAPI.Action case")

    if problems:
        audit.fail(f"api: {len(problems)} action(s) are not mirrored in MCP and both docs")
        for item in problems:
            audit.fail(f"  - {item}")
    else:
        audit.ok(f"api: {len(actions)} actions mirrored in MCP and both docs")


# ---------------------------------------------------------------------------
# API field coverage
# ---------------------------------------------------------------------------


def check_api_fields(audit: Audit, allowlist: dict[str, str]) -> None:
    source = read(LEDGER_API)
    models = stored_model_properties(audit.verbose)
    contexts = {
        name: (read_sources, input_sources) for name, (read_sources, input_sources) in API_FIELD_CONTEXT.items()
    }

    missing: list[str] = []
    for model, (read_functions, input_structs) in contexts.items():
        read_text = "\n".join(function_body(source, name) for name in read_functions)
        input_text = "\n".join(named_body(source, name, kind="struct") for name in input_structs)
        combined = read_text + "\n" + input_text
        for prop in models.get(model, []):
            if prop.endswith("Raw"):
                audit.note(f"api: {model}.{prop} is exposed through its typed accessor")
                continue
            key = f"api:{model}.{prop}"
            if allowed(allowlist, key, audit):
                continue
            if not whole_word(prop, combined):
                missing.append(
                    f"{model}.{prop} is neither serialized nor accepted; "
                    f"add it to {', '.join(input_structs)} and/or {', '.join(read_functions)}"
                )

    if missing:
        audit.fail(f"api: {len(missing)} model field(s) do not cross the local API")
        for item in missing:
            audit.fail(f"  - {item}")
    else:
        checked = sum(len(models.get(model, [])) for model in contexts)
        audit.ok(f"api: {checked} model fields are readable or writable through the HTTP API")


def check_mcp_input_parity(audit: Audit, allowlist: dict[str, str]) -> None:
    source = read(LEDGER_API)
    mcp_source = read(MCP_SERVER)
    missing: list[str] = []

    for struct in MCP_INPUT_STRUCTS:
        try:
            body = named_body(source, struct, kind="struct", prefix="private ")
        except SystemExit:
            audit.warn(f"mcp: cannot inspect {struct}; update MCP_INPUT_STRUCTS if it was renamed")
            continue
        fields = re.findall(r"(?:let|var)\s+(\w+)\s*:", body)
        for field in fields:
            key = f"mcp:{struct}.{field}"
            if allowed(allowlist, key, audit):
                continue
            snake = camel_to_snake(field)
            if not whole_word(snake, mcp_source):
                missing.append(f"{struct}.{field} (JSON: {snake}) is not a parameter or argument in mcp/server.py")

    if missing:
        audit.fail(f"mcp: {len(missing)} API input field(s) are not reachable from MCP")
        for item in missing:
            audit.fail(f"  - {item}")
    else:
        audit.ok(f"mcp: all {len(MCP_INPUT_STRUCTS)} input structs are mirrored by tool parameters")


# ---------------------------------------------------------------------------
# DMG freshness
# ---------------------------------------------------------------------------


def newest_source_mtime() -> tuple[float, str]:
    candidates: list[Path] = []
    candidates.extend((ROOT / "Montra").rglob("*.swift"))
    candidates.extend((ROOT / "Montra/Resources").glob("*.xcstrings"))
    candidates.append(MCP_SERVER)
    newest = max(candidates, key=lambda path: path.stat().st_mtime)
    return newest.stat().st_mtime, str(newest.relative_to(ROOT))


def check_dmg(audit: Audit, require_dmg: bool) -> None:
    images = sorted(DMG_DIR.glob("Montra-*.dmg"), key=lambda path: path.stat().st_mtime)
    if not images:
        message = "release: no DMG in build/; run Scripts/make-dmg.sh <tag> after the tests"
        if require_dmg:
            audit.fail(message)
        else:
            audit.warn(message)
        return

    newest = images[-1]
    source_mtime, source_name = newest_source_mtime()
    if newest.stat().st_mtime < source_mtime:
        message = (
            f"release: {newest.name} is older than {source_name}; "
            "rebuild it with Scripts/make-dmg.sh <tag>"
        )
        if require_dmg:
            audit.fail(message)
        else:
            audit.warn(message)
    else:
        size = newest.stat().st_size / (1024 * 1024)
        audit.ok(f"release: {newest.name} is newer than the app sources ({size:.1f} MB)")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--require-dmg",
        action="store_true",
        help="fail when build/ has no DMG newer than the app sources",
    )
    parser.add_argument("--verbose", action="store_true", help="print allowlisted entries and model maps")
    args = parser.parse_args()

    audit = Audit(verbose=args.verbose)
    allowlist = load_allowlist(audit)

    print("Montra feature sync audit")
    print("=" * 60)
    if args.verbose:
        print("models:")
        stored_model_properties(verbose=True)

    check_localization(audit)
    check_backup(audit, allowlist)
    check_api_mcp_docs(audit)
    check_api_fields(audit, allowlist)
    check_mcp_input_parity(audit, allowlist)
    check_dmg(audit, args.require_dmg)

    print()
    for message in audit.passes:
        print(f"OK    {message}")
    for message in audit.warnings:
        print(f"WARN  {message}")
    for message in audit.failures:
        print(f"FAIL  {message}")
    if audit.notes:
        print()
        print("notes:")
        for message in audit.notes:
            print(f"      {message}")

    print()
    print(
        f"summary: {len(audit.passes)} passed, "
        f"{len(audit.warnings)} warning(s), {len(audit.failures)} failure(s)"
    )
    if audit.failures:
        print()
        print("next: fix the FAIL lines, then rerun; deliberate exceptions go to")
        print("      Scripts/feature-sync-allowlist.txt with a reason.")
        return 1
    print("next: run the tests in the skill, then Scripts/make-dmg.sh <tag>.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
