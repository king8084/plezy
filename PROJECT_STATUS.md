# Plezy tvOS fork

## Release checkpoints
- Working branch: `codex/first-tvos-test-build`.
- Validated app source: `db99359cbc5fbed709fa7104014fe798ed6fff40`.
- Build candidate: `d627ca4c7d422e9ea83198c1f889a8399143f9a4` (script-only fix).
- All 15 sanity CI jobs passed on the original app-source checkpoint:
  https://github.com/king8084/plezy/actions/runs/43691531120.
- Draft release PR into the owner's fork: https://github.com/king8084/plezy/pull/1.
  Both branches belong to `king8084/plezy`; upstream is untouched.
- Last installed source: `d627ca4c7d422e9ea83198c1f889a8399143f9a4` (build 20).
- Previous installed source `22f5fc8bb` and its IPA backups are preserved.
- Owner approved the existing Home / Continue Watching and season layouts.
- Build 20 signed and installed in place successfully; no deletion/uninstall.
  Candidate appearance, retained settings and playback await owner confirmation.
- Owner authorized build/install on November 15, with build-scoped Unraid
  permission; Plezy is closed and Apple TV is in Settings.
- Build 19 setup failure and the d627ca4 dependency fix are preserved privately.
- Build 20 succeeded on d627ca4 in 22m 59s (native archive 5m 15s):
  https://codemagic.io/app/6af73c658b158cee7474719c/build/6af99fcc90e83b09c4fa8c1a.
- Full historical handoff, verified Git bundle, pinned engine and installed IPA are retained privately
  in `.git/plezy-private/release-2026-11-15/`. Keep that archive out of commits.

## Pending after build 20
- Episode/movie TV header runtime now shows remaining time for active progress,
  e.g. `14 min left`; unstarted/completed items and series keep total runtime.
- Shared by Home/spotlights and detail pages; no new fetch, geometry or file-info
  duration change. Remaining minutes round up, including sub-minute progress.
- 190 formatter/spotlight/detail/real-font layout regressions, full analysis and
  strict translation checks pass. Bindings regenerated; source-only, not installed.

## Current release work (November 15)
Owner authorizes audit fixes, bug regression work and a subtle metallic gold
border on favorite show posters. Preserve approved typography, synopsis slots,
poster geometry and navigation. Do not add the proposed feature backlog.

Implemented and source/native CI validated:
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
  Unknown favorite state cannot offer a misleading Add/Remove action.
- Delta refreshes accept pinned rows only for successfully fetched servers.
  Pin titles/library metadata are cached; saved pins remain removable in Settings
  even if a collection disappears or the server is unavailable.
- Signer recovery and checksum verification documented without server changes.
- Full CI exposed new Go/Svelte advisories. Small toolchain/dependency patch
  updates pass local relay race/build/scans and website tests/build/audit; no
  running service, website deployment or server container was changed.

## Validation
- Build 20 release gate passed: 8,610 Flutter tests, 7 skipped; isolated codegen,
  strict translations, formatting, full analysis, icons and repository guards pass.
- Vendored settings-storage and wakelock suites: 60 tests pass. Unused code/files
  checks pass. Favorite/menu connection-recovery follow-up: 84 tests pass.
- Final sanity CI on `db99359cb`: all 15 jobs pass, including full unit/package
  tests, Code Analysis, tvOS/iOS/macOS native, Android, both Windows architectures,
  both Linux native runs, native format, Linux packaging, server and website.
- Build 20 archive, IPA CRC/identity/app-group checks and in-place installation
  pass. Signer checksum matched the documented patch; its binary is unchanged.
- Corrected-source PR CI 43694202831 passes all 14 enabled jobs. Branch CI
  43694199314 passes the other 14 jobs but iOS audio 2x-speed tests failed; an
  isolated retry still failed one. These unchanged upstream tests need separate
  diagnosis. Do not conceal failures or relax playback/test policy to obtain green.
- Record Apple native CI and formatting results separately from Dart validation.
- Installation is complete. Candidate appearance, retained settings and playback
  remain unverified by the owner; do not infer those from installation success.

## Deferred until device evidence / release checks
- Duplicate display-criteria watchdog hypothesis: saved traces do not establish
  two criteria writes followed by the start watchdog in one playback attempt.
  Capture a cropped/scope start before changing the native matching policy.
- QMS SDR fast start: prior owner reports faster startup. Existing switch
  notifications alone do not prove visible HDMI blanking. Keep the preference
  and default until actual display/receiver behavior is observed.
- Fork `main` remains at `9d783d09` and includes the old client getter error.
  Automatic approval review rejected a direct fast-forward because the earlier
  audit required the owner's explicit main-branch strategy approval. Draft PR #1
  is ready for that decision; do not merge or push main without approval.
- Do not change the intentionally stable diagnostics-sharing key automatically.

## Standing rules / next step
- Follow AGENTS.md. Never delete/uninstall the app or delete anything on Unraid.
- Build/install only after explicit Apple TV build request and scoped Unraid
  authorization; app closed, Apple TV awake in Settings before installation.
- Keep environment addresses, household device names and install receipts private.
- After strings change: clean translations, regenerate, commit generated outputs.
- Source changes, regenerated bindings and this handoff are committed on the
  working branch. Build 20 receipts and recovery bundles remain private.
- Build-scoped Unraid authorization is fulfilled. Next: owner visual/settings/
  playback checks and separate iOS test diagnosis. PR #1/main approval remains
  pending; the build request does not authorize merging it.
