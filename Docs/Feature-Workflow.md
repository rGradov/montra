# Montra feature workflow

Every feature goes through implementation, backup, Local API, MCP,
localization, testing, and DMG packaging. The requirements live in
`AGENTS.md` and the `montra-feature-release` skill.

The SwiftUI and SwiftData app, the `.montra` JSON backup, and the local HTTP
API and MCP proxy each need explicit changes. A switch added to the app can
be lost on restore if the backup omits it. An HTTP field is unavailable in MCP
until the tool exposes it. Package the app once the tests pass.

## Workflow

0. Establish a baseline with the audit and current tests.
1. Implement the feature, model changes, and localized strings.
2. Update backup capture, restore, versions, and self-test.
3. Update Local API JSON, input, actions, and `Docs/Local-API.md`.
4. Update the MCP tool, parameters, `mcp/README.md`, and smoke assertions.
5. Update README and Feature Inventory as applicable.
6. Run self-test and review snapshots or smoke results as applicable.
7. Run the synchronization audit, including DMG freshness after packaging.
8. Package and verify the DMG with `Scripts/make-dmg.sh <tag> --open`.
9. Report what changed and how to verify it manually.

Documentation-only tasks use the skill's documentation workflow. Review the
diff and run relevant documentation checks. App builds, runtime tests, DMG
packaging, and version changes are outside that workflow.

## Release checks

### 1. Code and localization

- Give new model fields a default, such as `var isPinned: Bool = false`, for
  lightweight SwiftData migration.
- Add user-facing strings to `Localizable.xcstrings` in `ru` and `en`.
- Record feature IDs and scenarios in `Docs/Feature-Inventory.md`.

### 2. Backup

A backup restored on a new Mac should recover the same feature state.

| Change | Backup work |
|---|---|
| Field on `Account`, `Category`, `Operation`, or `Plan` | Add to `*Backup` in `BackupArchive.swift`, capture and restore in `BackupService.swift`, and cover in self-test |
| Setting in `SettingsStore` | Update `SettingsBackup` and `BackupService.apply` |
| State outside SwiftData such as rates or API settings | Update `BackupService.Environment`, add an optional payload section, and apply it from `BackupRestoreSheet` |
| Entity | Add a payload array, `BackupSummary` count, restore support, and a row in the restore sheet |

Keep old `.montra` files readable with optional fields and defaults. For a
format change requiring migration, update `currentFormatVersion` and implement
migration. Exclude secrets such as the API token and machine-specific dates
such as `lastBackupAt`.
[Backup playbook](../.agents/skills/montra-feature-release/references/backup-playbook.md)

### 3. Local API

MCP must be able to reproduce any user write in the app.

- Add read fields to `accountJSON`, `categoryJSON`, `operationJSON`, or `planJSON`.
- Add write fields to `AccountInput`, `CategoryInput`, `ImportRow`, or `PlanInput`.
- Check for differing values when a retry would otherwise return an existing record.
- Register new actions in `Action`, `writes`, `execute`, and `Store`.
- Update `Docs/Local-API.md` with the code.
  [API and MCP playbook](../.agents/skills/montra-feature-release/references/api-mcp-playbook.md)

### 4. MCP

- Register one `@mcp.tool` in `mcp/server.py` per action and match the function name.
- Include every parameter in the signature and forward it in `call_api(...)`.
- Update the tool table in `mcp/README.md`.
- Add creation, readback, and retry assertions to `mcp/tests/smoke.py`.

### 5. Tests

```bash
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build

build/DerivedData-debug/Build/Products/Debug/Montra.app/Contents/MacOS/Montra -selftest
```

Expect `ALL CHECKS PASSED`. The suite has 131 checks, including a full backup
round trip. Use `-disable-sandbox` in DSH because the outer sandbox blocks the
nested `sandbox-exec` that launches the SwiftData macro plugin server.

For UI changes, render and review snapshots.

```bash
build/DerivedData-debug/Build/Products/Debug/Montra.app/Contents/MacOS/Montra \
  -snapshot build/snaps-<tag>
```

For an animation change, capture it frame by frame. Real time is far too fast for
a bitmap capture to sample, so the frames are rendered frozen at each step:

```bash
APP=build/DerivedData-debug/Build/Products/Debug/Montra.app
"$APP/Contents/MacOS/Montra" -animate-onboarding-intro build/handoff
"$APP/Contents/MacOS/Montra" -intro-snapshots build/intro
ffmpeg -framerate 48 -i build/handoff/frame_%03d.tiff \
  -vf "scale=980:-1:flags=lanczos" -pix_fmt yuv420p build/handoff.mp4
```

`-animate-onboarding-intro` renders the mascot's hand-off into the welcome icon:
`frame_000` is the screen before the trip, then progress 0 to 1, then the two
states it hands over to. `-intro-snapshots` renders the intro's moments and the
welcome screen that follows.

For API or MCP changes, run the fixture and smoke test.

```bash
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py
```

### 6. Audit

```bash
python3 Scripts/audit-feature-sync.py
python3 Scripts/audit-feature-sync.py --require-dmg
```

The script checks that localization keys exist in `en` and `ru`, persisted model
fields and settings are represented in backups, and every action is covered by
MCP and both API docs. It checks that model fields crossing the API are serialized
or accepted and that input fields are available in MCP. `--require-dmg` also
requires an image at least as recent as the source. Fix the gap reported by the
audit.

### 7. DMG

```bash
Scripts/make-dmg.sh <tag> --open
```

The script builds Release, runs `-selftest`, checks the signature, creates
`build/Montra-1.0-<tag>.dmg`, mounts it, and verifies the contents. Use a short
tag such as `hidden-accounts`, `api-hidden`, or `plans-fix`. If the sandbox
blocks raw disk access with `Operation not permitted`, rerun packaging with
full disk access.

## Files

| File | Role |
|---|---|
| `.agents/skills/montra-feature-release/SKILL.md` | Agent release workflow |
| `.agents/skills/montra-feature-release/references/` | Backup, API/MCP, and release playbooks |
| `AGENTS.md` | Repository instructions for agents |
| `Scripts/audit-feature-sync.py` | Synchronization checks |
| `Scripts/feature-sync-allowlist.txt` | Documented exclusions |
| `Scripts/make-dmg.sh` | Release build, self-test, and packaging |
| `Docs/Feature-Workflow.md` | This guide |

## Deliberate exclusions

Examples include `createdAt`, `sortIndex`, coordinates represented as text
`place`, `weekdayMask` represented as `weekdays`, periods with no API commands,
the API token, and `lastBackupAt`. Record each reason in
`Scripts/feature-sync-allowlist.txt`.

```text
api:Account.createdAt    # Assigned by the server
```

Expose or back up the field when there is no reason to exclude it.

## Verify the workflow

```bash
python3 Scripts/audit-feature-sync.py --require-dmg
```

Account fields `is_hidden_from_overview` and `is_savings` demonstrate the full
path from model to backup, `LedgerAPI`, `mcp/server.py`, and smoke coverage.

## Changing the workflow

1. Edit `SKILL.md` or the relevant reference file.
2. If an audit rule changes, update `audit-feature-sync.py` and add a test.
3. Update this guide and `AGENTS.md` if the release checks change.
4. Run the applicable audit and verify it passes.
