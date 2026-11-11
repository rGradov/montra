---
name: montra-feature-release
description: >
  Release Montra features and fixes for macOS (SwiftUI and SwiftData) from a
  dedicated Git branch through backup, Local API, MCP, localization, tests, and
  DMG verification. If GitHub is configured, open a pull request with a brief
  summary and before and after visuals for UI changes. Use for changes to
  behavior, settings, screens, persisted data, Local API, MCP, or backups.
  For documentation-only or skill-only changes and behavior-preserving
  refactors, follow the applicable Git and pull request workflow.
---

# Montra feature release and pull requests

## 0. Release rules

1. Start each separate task on a dedicated branch. Verify backup, Local API,
   MCP, localization, and documentation for feature changes. Run tests before
   packaging the DMG. When GitHub is configured, deliver through a pull request.
2. Include every new persisted setting, model field, and entity in backups.
   Document eligible exceptions and their reasons in
   `Scripts/feature-sync-allowlist.txt`.
3. Represent user data and actions in the Local API. MCP must be able to make
   the same writes with the same fields, values, and semantics as the app.
4. Update both layers and both docs. `LedgerAPI.swift` implements actions.
   `mcp/server.py` registers the tools separately.
5. Keep old `.montra` files readable through optional fields with defaults or
   explicit format versions and migrations.
6. Require `ALL CHECKS PASSED` from `-selftest`. Run smoke tests when the API
   or MCP changes.
7. Package a DMG after tests pass for every feature.
8. Require zero failures from `python3 Scripts/audit-feature-sync.py --require-dmg`.
9. Report the results using section 12.

## 1. Workflow

Read `AGENTS.md` and `Docs/Feature-Workflow.md` before editing. For persisted
state, API/MCP, or packaging, read the corresponding reference in section 15.
Track the applicable steps.

```text
[ ] 0. Task branch and baseline audit and tests
[ ] 1. Feature code, model, localization
[ ] 2. Backup capture, restore, versions, self-test
[ ] 3. Local API JSON, input, actions, docs
[ ] 4. MCP tool, parameters, docs, smoke coverage
[ ] 5. README, Feature Inventory, and integration docs
[ ] 6. Self-test, snapshots, MCP smoke as applicable
[ ] 7. Synchronization audit
[ ] 8. DMG via make-dmg.sh <tag> --open, then audit with --require-dmg
[ ] 9. Commit. When GitHub is configured, push and open a pull request
[ ] 10. User report
```

### 1.1. Branches and commits

- For each feature, fix, refactor, or standalone documentation task, create
  `codex/<short-name>` from the current target branch. Continue the same task
  on its existing branch. Use a separate worktree when the current one contains
  changes for another task.
- Commit only the current task's changes. Use Conventional Commits
  (`type(scope): action`, with optional scope). Choose a suitable type such as
  `feat`, `fix`, `refactor`, `docs`, or `test`. Start with an action verb,
  omit the final period, aim for 50 characters, and stay within 72. Explain
  migration and breaking-change consequences in the body.

### 1.2. Documentation and skill changes

For changes limited to documentation or skills, review the diff and run
applicable documentation checks. Skip app builds, runtime tests, DMG packaging,
app updates, and version bumps. Follow the branch and pull request rules.
Write repository Markdown, including `AGENTS.md`, skills, playbooks, READMEs,
and new documentation, in English. Preserve code identifiers, commands, and
the product's localization requirements.

## 2. Repository map

| Area | Path |
|---|---|
| SwiftData models | `Montra/Models/Models.swift`, `Montra/Models/Plan.swift` |
| Repositories | `Montra/Store/Repositories.swift`, `Montra/Store/PlanRepository.swift` |
| Settings | `Montra/Store/SettingsStore.swift` |
| Backup format | `Montra/Backup/BackupArchive.swift` |
| Backup capture and restore | `Montra/Backup/BackupService.swift` |
| Backup UI | `Montra/Features/Settings/SettingsView.swift`, `Montra/Features/Settings/BackupRestoreSheet.swift` |
| Local API | `Montra/Integration/LedgerAPI.swift` |
| HTTP server and token | `Montra/Integration/LocalHTTPServer.swift`, `Montra/Integration/LocalIntegration.swift` |
| MCP | `mcp/server.py`, `mcp/README.md` |
| API docs | `Docs/Local-API.md` |
| Self-test | `Montra/Snapshot/SelfTest.swift` |
| Feature inventory | `Docs/Feature-Inventory.md` |
| Translations | `Montra/Resources/*.xcstrings` |
| Synchronization audit | `Scripts/audit-feature-sync.py` |
| Audit exclusions | `Scripts/feature-sync-allowlist.txt` |
| DMG | `Scripts/make-dmg.sh` |

## 3. Implement the feature

- Follow the existing `Features/<Feature>/` structure, repositories, design
  tokens, `AppStyle`, and `AppColors`. Route SwiftData writes through the
  existing repositories.
- Give persisted model fields defaults, such as `var isPinned: Bool = false`,
  for lightweight migration and compatibility with old stores.
- Use `String(localized:)` or `Text("key")` for user-facing strings and add
  entries in `Localizable.xcstrings` for `en` and `ru`. Russian remains the
  app catalog's source language.
- Update `Docs/Feature-Inventory.md` when models, repositories, seed data, or
  presentation change. Include the ID, check, type, and priority.
- Use the dedicated backup and API steps to cover those surfaces.

## 4. Back up the feature

Verify that restoring a backup on a new Mac recovers the feature's state.

| Change | Backup work |
|---|---|
| New field on `Account`, `Category`, `Operation`, or `PlannedOperation` | Add an optional field to `*Backup` in `BackupArchive.swift`. Map it in capture and restore `insert` in `BackupService.swift`. Validate references in `PreparedPayload`. Bump `currentSchemaVersion` and add a self-test. |
| New `SettingsStore` switch or setting | Add an optional `SettingsBackup` field, capture it in `SettingsBackup.init(_:)`, restore with a default in `BackupService.apply`, and add a self-test. |
| New state outside SwiftData, such as rates or Local API settings | Update `BackupService.Environment`, the optional `BackupPayload` section, both capture callers (`SettingsView` and `BackupRestoreSheet`), `RestoreReport`, and the post-restore application. |
| New entity | Add a `BackupPayload` array, `BackupSummary` count, capture and restore, foreign key validation, restore sheet row, and self-test. |
| Machine-specific, secret, or temporary value | Exclude it and record the reason in the allowlist. Examples include the API token, `lastBackupAt`, `active`, and `failure`. |
| Changed meaning or type of an existing field | Bump `currentFormatVersion`, preserve reading of older files, and test migration. |

Restore additive fields with defaults such as `row.flag ?? false`. Read and
apply every optional field explicitly. Update `BackupSummary` and
`BackupRestoreSheet` for new entities or changed counts. Bump
`currentFormatVersion` for payload changes when older versions should prompt
the user to update. Bump `currentSchemaVersion` for new persisted model
properties. Keep machine paths and caches out of backups. Let the encoder
calculate `checksum`.

Add coverage to the existing backup block in `SelfTest.swift`. Check that the
field reaches `archive.payload`, survives encoding and decoding, and restores
into a fresh `ModelContext`. Run self-test before release.

## 5. Update Local API

MCP must be able to reproduce each app write and read the result.

1. Add the `snake_case` field to `accountJSON`, `categoryJSON`,
   `operationJSON`, or `planJSON` in `LedgerAPI.swift`.
2. Add it to the corresponding input (`AccountInput`, `CategoryInput`,
   `ImportRow`, or `PlanInput`). Use an optional field when older clients can
   omit it and apply the default in `Store.create*`.
3. Compare the new value in idempotency checks. A retry with a different
   supplied value must surface the conflict.
4. For a new action, update `Action`, `writes`, `execute`, `Store`, and the
   JSON response. Use `LedgerError` with `422`, `409`, `403`, or `404`
   according to the error.
5. Add the action to the table in `Docs/Local-API.md`. Describe parameters and
   semantics, including read actions such as `list_accounts`.

Hiding an account from Overview is a working example. `AccountInput` accepts
optional `isHiddenFromOverview`, `Store.createAccount` defaults it with
`?? false` and compares it on retries, and `accountJSON` emits
`is_hidden_from_overview`. Both docs cover the field, MCP accepts it, and smoke
verifies it on a newly created hidden account.

Use the allowlist for deliberate API exclusions such as server-assigned
`createdAt`, server-side sorting, coordinates represented by text `place`,
and periods without API commands. Include the reason for each exclusion.

## 6. Update MCP

1. Register one `@mcp.tool` per action in `mcp/server.py`. Match the function
   name to the action.
2. Use typed `snake_case` parameters such as `Currency`, `Kind`, `Amount`,
   `Timestamp`, `Color`, and `PageLimit`.
3. Choose `READ`, `CREATE`, or `DELETE` based on behavior. Delete tools
   require `preview_token`.
4. Describe behavior, required parameters, and retry semantics in the docstring.
5. Forward every new field in `call_api(...)` and update the tool table in
   `mcp/README.md`.
6. Extend `mcp/tests/smoke.py` to check creation, readback, retry, and
   rejection. The HTTP fixture and MCP share an in-memory store.
7. Keep currencies, categories, defaults, and other business rules in the app.

## 7. Update localization and docs

- Add new keys in `Localizable.xcstrings` with `en`, `ru`, and
  `state: translated`. Follow existing interpolation formats such as
  `%@` and `%lld`.
- Update the README's Features section for user-visible features.
- Add the ID and checks to `Docs/Feature-Inventory.md`. If the self-test suite
  grows, update the check count in the introduction and section 4.
- Update `Docs/Local-API.md` and `mcp/README.md` whenever integrations change.
- Update `MasterPrompt.md` or `PLAN.md` when a feature changes a documented
  product rule or implementation agreement.

## 8. Run tests

### 8.1. Build and self-test

```bash
xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \
  -derivedDataPath build/DerivedData-debug \
  OTHER_SWIFT_FLAGS=-disable-sandbox build

APP=build/DerivedData-debug/Build/Products/Debug/Montra.app
"$APP/Contents/MacOS/Montra" -selftest
```

The DSH outer sandbox blocks the nested `sandbox-exec` used by the SwiftData
macro plugin. Use `-disable-sandbox` there and omit it in a regular terminal.
Require `ALL CHECKS PASSED` and exit code 0 before packaging.

### 8.2. UI

```bash
"$APP/Contents/MacOS/Montra" -snapshot build/snaps-<tag>
```

For screens, flows, and animations, compare changed PNGs with
`build/snaps-current` or the previous snapshot folder. Use
`-preview-onboarding` to preview onboarding with a temporary store. Capture
the base and task branches with the same fixtures, window size, theme, and
language. Refresh the evidence in the pull request after UI review changes.

### 8.3. API and MCP

```bash
./mcp/tests/build-fixture.sh
mcp/.venv/bin/python mcp/tests/smoke.py
```

Smoke checks HTTP and MCP authorization, previews, retries, deletion, and tool
and action parity. Cover every new action or field.

### 8.4. Backup

Extend the backup block in `SelfTest.swift` to cover capture, encode/decode,
and restore. For format changes, restore a backup created before the change.
Use a copy of the store for real data. For a manual check, save a backup in
Settings, change the state, restore the backup, and verify the new field.

## 9. Run the synchronization audit

```bash
python3 Scripts/audit-feature-sync.py
python3 Scripts/audit-feature-sync.py --require-dmg
```

The audit checks Swift localization keys in both languages, persisted model
fields and settings in backup, action parity across the API, MCP, and both
docs, serialization or input for model fields exposed through the API, and
MCP coverage of API inputs. `--require-dmg` also checks image freshness.
Fix failures at the source. Record reasons in the allowlist only for
machine-specific, derived, or temporary values.

## 10. Package the DMG

```bash
Scripts/make-dmg.sh <tag> --open
```

Use a short kebab-case tag such as `hidden-accounts`, `api-hidden`, or
`transfer-fix`. The script builds Release, runs self-test, verifies signing,
stages the app and Applications link, creates
`build/Montra-<version>-<tag>.dmg`, then mounts it and verifies the app,
signature, and version. It prints the path and size.

If `hdiutil` fails with `Operation not permitted` or `Directory not empty`,
rerun packaging with raw disk access outside the sandbox. Reuse the built and
tested app when possible.

Open the DMG, install Montra into Applications, and verify the requested
scenario. Report the path and present the file if the host supports it.
Use tags to distinguish builds. Bump `MARKETING_VERSION` only on request or
when the installed copy will not update.

## 11. Definition of done

- [ ] Feature and existing scenarios work.
- [ ] New state round-trips through `.montra`. Old backups open or migrate.
- [ ] Local API and MCP expose the applicable fields and actions, and docs match.
- [ ] New strings are translated in `ru` and `en`.
- [ ] Feature Inventory and README cover user-visible changes.
- [ ] `-selftest` reports `ALL CHECKS PASSED`.
- [ ] API/MCP smoke passes for integration changes.
- [ ] Snapshots have been reviewed for UI changes.
- [ ] `audit-feature-sync.py --require-dmg` reports zero failures.
- [ ] DMG has been built, mounted, and verified.
- [ ] With GitHub configured, the branch is pushed and the PR includes a summary
      and before and after evidence for UI changes.
- [ ] The user has the report and DMG path.

## 12. Pull request and final report

### 12.1. GitHub pull request

When the GitHub remote and write access are available, push the task branch
and open a PR against the intended target. Merge only on direct request.
Report publication status when the remote or access is unavailable.

Create and update PRs with GitHub CLI or the GitHub REST API. If `gh` is
available and authenticated, pass explicit `--base`, `--head`, `--title`,
and `--body-file` to `gh pr create`. Otherwise use an authenticated
`POST /repos/{owner}/{repo}/pulls`. Verify the target and return the PR URL.
If both routes are unavailable, explain why and link the branch comparison
when the branch was pushed. Keep PR creation and editing in the CLI or API.

Use a short title and a few bullets describing changes, checks, and applicable
backup, Local API, and MCP updates. Add two to four manual steps when a reviewer
can try the scenario.

For UI changes, include labeled Before and After screenshots for affected
screens or states. Show them side by side when helpful. For a new screen, show
the former path or say the screen is new and include the After capture. Use a
short video for animations or multistep flows where it helps. Use test data
and verify reviewer access. Use `gh pr create --attach` if supported, otherwise
include accessible URLs. If uploads are unavailable, attach the evidence to
the user report and say so.

### 12.2. User report

Write a brief report in Russian.

```text
Feature: <change>
Backup: <fields and older file compatibility>
Local API: <actions, fields, docs>
MCP: <tools, parameters, docs>
Localization: <new ru/en keys>
Tests: <self-test count, smoke, snapshots>
Audit: <result>
DMG: build/Montra-1.0-<tag>.dmg (<size>), version 1.0 (1)
PR: <URL if opened>
Manual verification: <two to four steps>
```

For a deliberate API exclusion, explain why and point to the allowlist entry.
For documentation-only work, report the docs, applicable checks, and PR status.

## 13. Examples

- **Account switch.** Add `var isPinned: Bool = false`, wire the initializer
  and repository, add the switch and translations, update `AccountBackup`
  capture and restore, bump schema, and add self-test coverage. Update
  `AccountInput`, `createAccount`, `accountJSON`, MCP `is_pinned`, the docs,
  smoke, and the `ACC-xx` inventory. Test, audit, and package.
- **Category field.** Follow the same process with `CategoryBackup`,
  `CategoryInput`, `categoryJSON`, and `create_category`. Preserve subcategories
  and `parent_id`. Check the parent after restore.
- **Visual feature.** For an animation, shadow, or empty state, localize any
  new strings, review snapshots for affected screens, and package the DMG.
  Explain in the report why no backup or API changes apply.
- **New action.** For account archiving, cover the model or flag, backup,
  `Action`, Store method, MCP tool, docs, smoke, inventory, and DMG. Require a
  preview and `preview_token` for destructive actions.

## 14. Common gaps

- Deliver UI, backup, API, MCP, and docs together for a feature.
- Capture and restore optional persisted fields explicitly.
- Fix failing checks before packaging.
- Use the allowlist for eligible fields with documented reasons.
- Keep the README and Feature Inventory current.
- Run destructive tests on a temporary store or copy.

## 15. References

- [Backup playbook](references/backup-playbook.md)
- [Local API and MCP playbook](references/api-mcp-playbook.md)
- [Release playbook](references/release-playbook.md)
