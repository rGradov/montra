# Release playbook

Package each feature as an installable DMG from verified code.

## 1. Order of operations

1. Build Debug and run `-selftest`.
2. Review snapshots if the UI changed.
3. Run the MCP fixture and smoke test if API or MCP changed.
4. Run the synchronization audit.
5. Build Release and create the DMG.
6. Verify the mounted image.
7. Try the requested scenario in the installed app.
8. Report the DMG path.

For documentation-only changes, review the diff and run applicable documentation
checks. See the documentation workflow in `../SKILL.md`.

## 2. Debug build

```bash
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build

APP=build/DerivedData-debug/Build/Products/Debug/Montra.app
```

DSH's outer sandbox can block the SwiftData macro plugin's nested sandbox. Look
for `SwiftDataMacros.PersistentModelMacro` or
`sandbox-exec: sandbox_apply: Operation not permitted` in the build log.
Use `-disable-sandbox` there. Omit the flag in a regular terminal.

## 3. Self-test

```bash
"$APP/Contents/MacOS/Montra" -selftest
```

Expect `PASS ...` lines followed by `ALL CHECKS PASSED` and exit code 0.

Self-test uses an in-memory store and a separate `UserDefaults` suite. It covers
periods, balances, currencies, transfers, plans, categories, Spotlight, and the
full backup round trip. If a check fails, rerun to rule out interference from
another instance. If it still fails, locate `FAIL` and fix the cause before
packaging.

## 4. Snapshots

```bash
"$APP/Contents/MacOS/Montra" -snapshot build/snaps-<tag>
```

Compare changed PNGs with `build/snaps-current` or a previous snapshot folder.
For onboarding, use the preview mode. Snapshot rendering uses a temporary
in-memory store.

```bash
"$APP/Contents/MacOS/Montra" -preview-onboarding
```

## 5. MCP smoke test

```bash
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py
```

The fixture script compiles the Swift models and `LedgerAPI` into a separate
HTTP fixture. The smoke test uses MCP over stdio and covers authentication,
previews, retries, deletion, and plans. It checks
`set(tools) == set(status.actions)`.

If the macro sandbox blocks the fixture build, verify that
`mcp/tests/build-fixture.sh` passes `-disable-sandbox`. It defaults to
`MONTRA_DISABLE_MACRO_SANDBOX=1`.

## 6. Audit

```bash
python3 Scripts/audit-feature-sync.py
python3 Scripts/audit-feature-sync.py --require-dmg
```

Run the first command during development and use `--require-dmg` before
reporting completion. Require zero failures. An old DMG warning is expected
until packaging. Allowlist entries apply only to machine-specific, derived, or
temporary values and require a reason after `#`.

## 7. DMG

```bash
Scripts/make-dmg.sh <tag> --open
```

The script reads `MARKETING_VERSION` from `project.pbxproj` (currently `1.0`),
builds Release in `build/DerivedData-release`, runs `-selftest`, and verifies
the signature with `codesign --verify --deep --strict`. It stages `Montra.app`
and the `Applications -> /Applications` link, creates the UDZO image at
`build/Montra-<version>-<tag>.dmg`, mounts it, and verifies the app, link,
signature, and version. It prints the path, version, and size.

Use a short kebab-case tag such as `hidden-accounts`, `api-hidden`, or
`plans-fix`. The file modification time records the date.

### Troubleshooting hdiutil

If `hdiutil` or `newfs_apfs` reports `Operation not permitted` for raw disk
access, rerun packaging with full disk access outside the sandbox. The build
and self-test may already have passed. A `Directory not empty` error can also
come from the underlying `newfs_apfs` denial.

### Manual verification

```bash
hdiutil attach -nobrowse -readonly build/Montra-1.0-<tag>.dmg
ls "/Volumes/Montra/Montra.app"
codesign --verify --deep --strict "/Volumes/Montra/Montra.app"
hdiutil detach "/Volumes/Montra"
```

Open the image, drag the app into Applications, and test the feature there.
macOS may offer to replace an existing installation of the development build.

## 8. Versions

- `MARKETING_VERSION` is the product version, currently `1.0`.
- `CURRENT_PROJECT_VERSION` is the build number, currently `1`.
- Use tags to distinguish builds. Bump the version only when asked or when
  the installed copy will not update.
- Local development builds use local signing and skip notarization.

## 9. Final report

```text
Feature: ...
Backup: ...
Local API: ...
MCP: ...
Tests: self-test ALL CHECKS PASSED, MCP smoke passed, snapshots ...
Audit: 0 failures
DMG: build/Montra-1.0-<tag>.dmg (<size>), version 1.0 (1)
Manual verification: ...
```

Attach the DMG if the host supports `present`. Otherwise link to the file path.

## 10. Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `PersistentModelMacro could not be found` | Sandbox blocks the macro plugin server | Pass `OTHER_SWIFT_FLAGS=-disable-sandbox` |
| `newfs_apfs: Operation not permitted` | Sandbox blocks raw disk access | Package with full disk access |
| `hdiutil: create failed - Directory not empty` | Possible underlying `newfs_apfs` denial | Check raw disk access |
| One `-selftest` check fails | Regression or interference from another instance | Rerun and fix the cause if it persists |
| MCP smoke: `set(tools) != set(actions)` | One layer lacks a corresponding action or tool | Synchronize `server.py` and `LedgerAPI` |
| Audit: `model field do not cross the API` | Field missing from JSON or input | Add it or document an eligible allowlist entry |
| Audit: `DMG is older` | Sources changed after packaging | Rebuild the DMG |
