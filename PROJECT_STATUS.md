# Plezy tvOS fork

## Release checkpoints
- Working branch: `codex/first-tvos-test-build`.
- Last installed source: `22f5fc8bb363d42c969fe9b5e5b1a17e1d26434c` (build 18).
- Owner approved Home / Continue Watching and the season layout. Build 17 was
  visually approved; build 18 only reordered Favorite below watch-state actions.
- Build 18 archived and installed in place. New menu-order, retained-settings
  and playback confirmation are separate pending milestones.
- No new Apple TV archive, device installation or Unraid operation is authorized
  by the current release-hardening request.
- Full historical handoff, verified Git bundle, pinned engine and installed IPA are retained privately
  in `.git/plezy-private/release-2026-11-15/`. Keep that archive out of commits.

## Current release work (November 15)
Owner authorizes audit fixes, bug regression work and a subtle metallic gold
border on favorite show posters. Preserve approved typography, synopsis slots,
poster geometry and navigation. Do not add the proposed feature backlog.

Implemented / being validated:
- Full sanity CI now covers the working branch. The unsigned archive workflow
  runs translation, codegen, format, analysis and full Flutter checks first.
- Translation keys normalized and generated bindings regenerated.
- Removed the household server address from the connection form.
- Read more keeps its large complete text and scrolls with remote arrows;
  episode titles include series, season/episode number and episode title.
- Favorite series decoration is paint-only and keeps the focus border separate.
  Session-scoped favorite state is shared with parent-show menu lookups.
- Menus open while favorite and delete-permission probes resolve; focus and
  action intent survive late updates. Failed unknown favorite lookups retry soon.
  Unknown
  favorite state cannot offer a misleading Add/Remove action.
- Delta refreshes accept pinned rows only for successfully fetched servers.
  Pin titles/library metadata are cached; saved pins remain removable in Settings
  even if a collection disappears or the server is unavailable.
- Signer recovery and checksum verification documented without server changes.
- Full CI exposed new Go/Svelte advisories. Small toolchain/dependency patch
  updates pass local relay race/build/scans and website tests/build/audit; no
  running service, website deployment or server container was changed.

## Validation
- Combined release gate passed: 8,609 Flutter tests, 7 skipped; isolated codegen,
  strict translations, formatting, full analysis, icons and repository guards pass.
- Vendored settings-storage and wakelock suites: 60 tests pass. Unused code/files
  checks pass. Favorite/menu connection-recovery follow-up: 84 tests pass.
- Sanity CI on source `8c2a7ee63`: Code Analysis, tvOS/macOS native, Windows x64,
  both Linux native runs, native format and Linux packaging smoke pass. Unit,
  iOS/Android/Windows arm64 are pending; server/website advisory fixes await CI.
- No IPA archive or installation is requested.
- Record Apple native CI and formatting results separately from Dart validation.
- Installed app remains at the checkpoint above; candidate appearance, retained
  settings and playback await a separately authorized device release and owner test.

## Deferred until device evidence / release checks
- Duplicate display-criteria watchdog hypothesis: saved traces do not establish
  two criteria writes followed by the start watchdog in one playback attempt.
  Capture a cropped/scope start before changing the native matching policy.
- QMS SDR fast start: prior owner reports faster startup. Existing switch
  notifications alone do not prove visible HDMI blanking. Keep the preference
  and default until actual display/receiver behavior is observed.
- Fork `main` is behind the working branch and includes the old client getter
  error. Merge a validated release into it through the owner's fork; preserve
  its history and avoid a destructive reset.
- Do not change the intentionally stable diagnostics-sharing key automatically.

## Standing rules / next step
- Follow AGENTS.md. Never delete/uninstall the app or delete anything on Unraid.
- Build/install only after explicit Apple TV build request and scoped Unraid
  authorization; app closed, Apple TV awake in Settings before installation.
- Keep environment addresses, household device names and install receipts private.
- After strings change: clean translations, regenerate, commit generated outputs.
- Next: finish release regressions and full checks, record failures honestly,
  commit the validated candidate, then await the owner's build request.
