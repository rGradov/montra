# Montra agent instructions

## Feature release requirements

Use the **`montra-feature-release`** skill
(`.agents/skills/montra-feature-release/SKILL.md`) for features, behavior changes,
model fields, settings, screens, Local API or MCP actions, and backup format changes.

Read the skill before editing. A feature is complete when it passes all applicable
checks.

1. **Code and localization.** Verify the feature and add every new user-facing
   string to `Localizable.xcstrings` in `ru` and `en`.
2. **Backup.** Include new persisted fields, settings, and entities in `.montra`
   capture and restore. Verify that older backups still open.
3. **Local API.** Represent user data and actions in
   `Montra/Integration/LedgerAPI.swift` and update `Docs/Local-API.md`.
4. **MCP.** Expose the tool and its parameters in `mcp/server.py`. Update
   `mcp/README.md` and smoke coverage. MCP tools are registered separately.
5. **Tests.** Require `ALL CHECKS PASSED` from `-selftest`. Review snapshots
   for UI changes and run `mcp/tests/smoke.py` for API or MCP changes.
6. **Audit.** Require zero failures from
   `python3 Scripts/audit-feature-sync.py --require-dmg`.
7. **DMG.** After the tests pass, package the app with
   `Scripts/make-dmg.sh <tag> --open`.
8. **Report.** Summarize backup, API, MCP, and test changes. Include the DMG path
   and two to four manual verification steps.

Backup and API exclusions apply only to machine-specific, derived, or temporary
values. Record each reason in `Scripts/feature-sync-allowlist.txt`.

For documentation-only changes, follow the skill's documentation workflow.
Review the diff and run applicable documentation checks.

## Commands

```bash
# Synchronization audit
python3 Scripts/audit-feature-sync.py

# Build and self-test
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build
build/DerivedData-debug/Build/Products/Debug/Montra.app/Contents/MacOS/Montra -selftest

# API and MCP
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py

# Installer image
Scripts/make-dmg.sh <tag> --open
```

Use `-disable-sandbox` in DSH because its outer sandbox blocks the SwiftData
macro's nested `sandbox-exec`. Omit the flag in a regular terminal.

## Boundaries

- Use a copy of the store for destructive tests.
- Keep secrets and the Local API token out of commits.
- Preserve the historical checks in `Docs/Feature-Inventory.md` unless a change
  requires updating them. The inventory is the source of truth for tests.
- Keep `MARKETING_VERSION` fixed unless a version change is requested. Use the
  DMG tag to distinguish builds.
- If the sandbox blocks `hdiutil`, rerun packaging with full disk access and
  produce a DMG.

## Documentation

- `Docs/Feature-Workflow.md` explains the release workflow and manual checks.
- `.agents/skills/montra-feature-release/references/` contains the backup,
  API/MCP, and release playbooks.
