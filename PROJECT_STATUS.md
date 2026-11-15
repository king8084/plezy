# Plezy tvOS fork

## Release checkpoints
- Working branch: `codex/first-tvos-test-build`.
- Installed app source: `73439a2268b7426b47ea71c552c19e6954e183c4` (build 21).
- Current candidate: Simkl recommendation row and redesigned TV sidebar.
  Local release gate passed; cloud/native CI pending. Not archived or installed.
- Draft release PR into the owner's fork: https://github.com/king8084/plezy/pull/1.
  Both branches belong to `king8084/plezy`; upstream is untouched.
- Previous installed sources `d627ca4c7` (build 20) and `22f5fc8bb`, with
  their IPA backups, are preserved. Owner approved the earlier layouts.
- Build 21 signed and installed in place successfully; no deletion/uninstall.
  Current appearance, retained settings and playback await owner confirmation.
- Full historical handoff, verified Git bundle, pinned engine and installed IPA are retained privately
  in `.git/plezy-private/release-2026-11-15/`. Keep that archive out of commits.

## Remaining-time update / build 21
- Episode/movie TV header runtime now shows remaining time for active progress,
  e.g. `14 min left`; unstarted/completed items and series keep total runtime.
- Shared by Home/spotlights and detail pages; no new fetch, geometry or file-info
  duration change. Remaining minutes round up, including sub-minute progress.
- Required analysis/unit/tvOS native CI passes on 73439a2 (run 43719430628).
- Cloud gate passed: 8,622 Flutter tests, 7 skipped, plus analysis/codegen/guards.
- Archive, IPA checks and in-place installation passed. Receipts and backups
  remain private. Build-scoped Unraid authorization is fulfilled.

## Simkl and sidebar enhancement (November 15)
- TV show/movie detail order: owned related titles, Simkl, Seerr request row.
  Simkl reads `users_recommendations`, never the genre-based `similar` field;
  deduplicates by native entry identity, caches/coalesces and allows up to 60.
- Verified library copies keep their artwork, favorite state, menus and routes.
  Missing titles open Seerr where a TMDB ID is known; show Need request or
  Requested. Failed/offline library checks never imply absence. Loading is
  supplemental, bounded to four availability probes, and navigation-safe.
- IMDb-only score and compact boxed votes reuse cached community enrichment,
  including MDBList. No substitution of TMDB/Simkl scores or recommendation votes.
- TV sidebar uses outlined icons and a legible focused panel. Libraries are
  independent top-level pins; the old Libraries folder is gone on TV.
- Appearance > Customize sidebar has explicit Pin / Up / Down controls,
  immediate saving, no move mode, and no inactive service entries. Existing
  order/pins survive; unavailable pins remain saved. Desktop grouping remains.
- Full local gate: 8,645 passed, 7 skipped; strict translations, isolated codegen,
  formatting, analyzer, icon/string/error/CI guards pass. Real-font Home tests
  cover all seven poster sizes; sidebar and pin persistence render tests pass.
- No Apple TV build or Unraid access authorized/used for this enhancement.

## Prior audit hardening
Owner authorizes audit fixes, bug regression work and a subtle metallic gold
border on favorite show posters. Preserve approved typography, synopsis slots,
poster geometry and navigation. Do not add the proposed feature backlog.

Implemented and source/native CI validated:
- Sanity CI covers the branch; every archive runs the complete release gate.
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

## Prior native CI / unresolved issues
- Build 21 branch CI 43719426061 passes 14 jobs; iOS fails the paused
  audio 2x-speed test. The required analysis/unit/tvOS checks pass on both runs.
  The parallel PR run 43719430628 passed all 14 enabled jobs, including both iOS
  speed tests, on identical source. Duplicate push/PR triggers explain repeated
  emails. Root cause of inconsistent iOS results remains unresolved; preserve
  both logs. Do not hide failures or weaken assertions to obtain green.
- Track native CI, archive, installation and owner playback separately.

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
- Next: current-candidate cloud CI; archive/install only after a new explicit
  build request. Diagnose inconsistent iOS speed results separately.
  PR #1/main approval remains pending. Recovery receipts/bundles remain private.
