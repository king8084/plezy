# Plezy tvOS fork

## Release checkpoints
- Working branch: `codex/first-tvos-test-build`.
- Installed app source: `b84551ee1` (Codemagic build 30, Nov 18, in place via
  tvsign Renew; signing and upload OK). Simkl row votes, dictation
  auto-return, mic key beside "a", Seerr row boxed vote tag. Build 29 failed
  at clone (Codemagic could not reach github.com); one justified retry.
  Local gate GATE_EXIT=0 (8,708 tests), Codemagic gate passed; fork Actions
  disabled. Backups `*-before-b84551e.ipa`; private receipt in
  `.git/plezy-private/`. Owner device check pending (dictation auto-return
  is the first device run of that close path).
- Previous install: `85fa8a279` (Codemagic build 28, Nov 18, in place via
  tvsign Renew; signing and upload OK). Instant index search results, one
  caption (rating/votes/year) on all More like this rows, IMDb crew/votes in
  the index (service already live). Local gate GATE_EXIT=0 (8,705 tests),
  Codemagic gate passed; fork Actions disabled. Backups
  `*-before-85fa8a2.ipa`; private receipt in `.git/plezy-private/`. Owner
  device check pending.
- Previous install: `9044a33d836b1be76b2cce6d362f3d765ceabf68` (Codemagic build 27,
  Nov 18, in place via tvsign Renew; signing and upload OK). Flutter-drawn
  static search header (Search + Find, Rivulet-style full-width keys) and the
  short audio badge. Local gate GATE_EXIT=0 (8,700 tests), Codemagic gate
  passed; fork Actions disabled. Backups `*-before-9044a33.ipa`; private
  receipt in `.git/plezy-private/`. Owner device check of search pending.
- Previous install: `e28336a70bf8b00634455fc1a6471c0408a908bb` (Codemagic build 26,
  Nov 18 04:24 local, in place via tvsign Renew; OK, no errors). Contains the
  docked Apple search keyboard (Search + Find), classic show page with Season
  pills and labeled actions, blended More Like This. Local gate GATE_EXIT=0
  (8,701 tests), Codemagic gate passed; fork Actions disabled. Backups
  `*-before-e28336a.ipa`; private receipt in `.git/plezy-private/`. Owner
  device checks of the docked keyboard (first device run) are pending.
- Previous install: `a85be64aa0fe01b36ebc3fd537a05d54774f3b9e` (Codemagic build 25,
  Nov 17 18:05 local, in place via tvsign Renew; signing and upload OK). Local
  gate GATE_EXIT=0 (8,702 tests) and the Codemagic gate passed; fork Actions
  disabled, so fork CI did not run. Build 25 sat ~30 min in Codemagic's
  machine queue before starting (minutes were available). Backups
  `*-before-a85be64.ipa`; private receipt in `.git/plezy-private/`. Owner
  checks of the redesigned show page, Apple search keyboard (first device
  run of native code), Find, smart rows and Mark All Previous are pending.
- Previous install: `d92d0d90e8e95b7ee11cda4c2f7cad9879680cb3` (Codemagic build 24,
  Nov 17 06:11 local, in place via tvsign Renew). Local gate and Codemagic gate
  passed; fork GitHub Actions is disabled, so fork CI did not run for this build.
  Build 23 failed on a Codemagic DNS error while fetching the engine; one
  justified retry. Owner checks of Search, Home Back, Mark played and playback
  are pending. Build 22 (`6f2026663`) IPAs are backed up as `*-before-d92d0d9`.
- PR https://github.com/king8084/plezy/pull/1 merged into the fork's `main` on
  Nov 17 at the owner's request (merge commit `416683ba6`); the working branch
  is kept for the Codemagic workflow. Upstream is untouched.
- Previous installed sources `73439a226` (build 21), `d627ca4c7` and `22f5fc8bb`, with
  their IPA backups, are preserved. Owner approved the earlier layouts.
- Build 22 signed and installed in place successfully; no deletion/uninstall.
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
- November 16: authorized build 22 passed the cloud gate (8,645 tests, 7 skipped),
  native archive and IPA identity/integrity/app-group checks. Installed in place.
  Verified prior IPAs preserved; signer checksum matched, binary unchanged.
  Installation proof and receipt are private. Scoped Unraid permission fulfilled.

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
- Candidate runs 43740308821 / 43740315253 passed every enabled job except iOS.
  Both speed tests failed in the PR run; logs saved privately. Unresolved;
  no assertions weakened, native changes or blind retries for this build.
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

## AI search research (November 16)
- Research and measured pilot results: docs/ai-search-research.md. Owner's latest
  direction is automatic fast matches plus a separate asynchronous AI row rather
  than the earlier checkbox idea. UI remains a proposal; approved layouts unchanged.
- Initial tiny connection check passed using the supplied restricted account
  (admin/deletion disabled) and local Ollama. Credentials, inventory and receipts
  remain Git-ignored/private; keep environment details out of tracked documents.
- Owner then authorized Modern Family season 4 indexing. Only server write scope
  is the dedicated smartsearch folder recorded in the private scope file; rule
  saved in AGENTS.md. Never alter existing media/Jellyfin-managed files. No
  container or server-setting changes authorized by this pilot.
- Fetched all 24 S4 episodes with descriptions, validated identities. Added local
  embeddinggemma:300m (about 622 MB) while retaining existing models. Document
  embeddings: four batches, 1.889 s request time including first model load,
  excluding download/DB writes. Model pull took about 13 s.
- Pilot retrieval: 13/13 preselected positive queries ranked correctly first;
  simple text baseline 11/13. Median local text lookup 0.107 ms; warm query
  embedding median 71 ms (66–164 ms), vector ranking median 0.534 ms. These are
  small-corpus engine/request measurements, not whole-library or TV UI latency.
- Nearest-vector search also returns candidates for unsupported questions.
  Three separate reasoning checks passed: one supported answer with literal
  source evidence and two rejections. First 7.127 s includes 5.352 s model load;
  two subsequent short rejections about 1 s. Not a general accuracy guarantee.
- Built SQLite locally, closed it, exported a new immutable snapshot (172,032
  bytes) with corpus/results/harness/report/hash manifest only within the approved
  folder. Verified bytes, integrity and 24-row count read-only across the mount;
  no live writable database/journals there. Exact private path is in pilot state.
- Owner subsequently approved a 500-item mixed test and requires its work to seed
  the final index. Added isolated scripts/search_index_pilot.py; no application
  search/UI change. Private plan freezes sample size, identities and query cases.
- Reusable seed now has 386 episodes across 14 shows, 100 movies and 14 show
  records. Reused all 24 original vectors; generated only 476 new vectors in
  21.403 s of embedding requests. Also saved 40 query vectors. Actual resume run
  preserved all 500 vectors with zero new document embedding requests.
- Mixed retrieval: 33/34 predefined answers first, 34/34 in top three; Phil/Jay
  fishing query remains correct without the series name. Median query embedding
  110.457 ms, ranking 0.116 ms, local text lookup 0.595 ms. Curated small corpus;
  these are not whole-library accuracy or Apple TV UI measurements.
- Original batch AI verifier passed only 10/13; wrong/omitted characters and
  reversed actors escaped quote checking. Preserved as a failed baseline and
  superseded by the default verifier below; never silently fall back to it.
- New-content architecture: permanent writer/index on Unraid, Ollama on the PC.
  Restricted-account event socket handshake/keepalive and clean close verified
  using ApiKey query spelling. No actual library-change event occurred during the
  bounded observation; no source changes were manufactured. Scoped changed-since
  API filtering verified on an existing item using past/future cutoffs. Persisted
  event queue/upsert/cache replay and transaction rollback pass local checks.
- Flagged one placeholder overview and performed a real API recheck of only that
  item; next check due in 24 h. Tag/resolve behavior tested locally. Daily queue
  is saved in the seed DB; permanent listener/worker/scheduler is not deployed.
  Jellyfin scanning/notification batching can delay visibility of new content.
- Closed 4,390,912-byte seed exported to a new folder only in approved smartsearch
  storage, with results/failures, model provenance, queues, harness and hashes.
  Read-only exported integrity/count passed; original S4 snapshot preserved.
  Private state records the exact path and incremental-probe addendum.
- Mixed pilot fulfilled. No full index, service deployment, Apple TV build/install.
  Preserve this seed and caches. Ordinary search must work with inference PC asleep.

## Verifier correction before full indexing (November 16)
- Owner explicitly requests fixing the false confirmations before a full run.
  Default pilot verify now uses independent-evidence-v5. No client/UI changes.
- New isolated evidence/entailment/evaluation modules check source-backed names
  and show identity, require two independent local semantic checks with actual
  quotations, and veto unbound active agents and unsupported dependent clauses.
  Ambiguous surname aliases never merge distinct people. Missing/invalid evidence
  stays possible; identity mismatches are rejected. Existing candidates remain.
- Final curated evaluation: 56 cases, zero incorrect confirmations; 27/27
  unsupported queries unconfirmed. All 29 legitimate targets retained: 23
  confirmed, six possible. Strict fully-confirmed expectations remain 50/56;
  do not report 56/56 or a general accuracy guarantee. Original labels/failures
  and unsuccessful intermediate approaches are preserved.
- 36 offline unit tests pass; all 56 saved decisions replay identically offline.
  Default entry point passes a fail-closed gate requiring no false confirmations
  and retention of all valid targets. All 500 index rows/document/query vectors
  remain byte-for-byte unchanged; zero new embedding requests in this work.
- Added a pinned, hash-verified English NLI model/tokenizer (~253 MB) and isolated
  Python runtime only on the PC; no system package/service changes. The small
  classifier runs on CPU; existing Ollama handles the generator. Verification
  is query-shortlist work with reusable caches, not an LLM pass over every item.
- Tested code, exact results/uncertainties, caches, pinned model and hashes are
  saved additively in approved smartsearch storage; exact bundle path in private
  verifier state. The original index and all prior snapshots remain intact.
- No full index, permanent Unraid worker/daily scheduler, build or installation
  started. Next: agreed full-index/server deployment scope using the retained
  seed; validate actual server/runtime/permissions and reconnect handling there.
  These English curated cases do not establish whole-library/device accuracy.

## Full-library smart search (November 16, Claude took over from Codex)
- Codex stopped mid-task (usage limit) after writing an untested full indexer.
  Its drafts `scripts/search_library_indexer.py` / `search_library_events.mjs`
  are superseded by `smartsearch/` and intentionally left uncommitted.
- Owner approved: the full-library index; an always-on dedicated container that
  the owner creates by pasting a reviewed command; broad freedom to improve Plezy.
  Absolute rule: never delete any file on Unraid (see AGENTS.md).
- New `smartsearch/plezy_search` package (README there): resumable indexer with
  genres/IMDb rating/cast/tags/networks/language/status; instant search
  (no AI) with query understanding, title-first ranking and typo tolerance;
  smart search (embeddings plus full text, re-ranked by the unchanged
  independent-evidence-v5 checker); LAN API; supervisor; hash-pinned runtime.
- Full import from this PC: 61,832 items (2,470 movies, 1,438 shows, 57,928
  episodes) in ~5 min; all 500 pilot vectors carried over by content hash with
  no new requests for them; ~30 embeddings/s on the PC GPU.
- Daily recheck queue (live data): ~1.2k missing descriptions (mostly
  episodes), placeholder descriptions, upcoming titles and items with no
  rating/genres. Live event socket and per-minute catch-up verified
  read-only against the real server.
- Instant benchmark (full library, private cases): every filter case clean
  (zero results violating kind/genre/rating/year/person/studio/runtime/language);
  typo cases fixed; p50 ~6 ms server-side. Pilot scene questions are the smart
  path's job. 21 offline unit tests plus Codex's 36 verifier tests pass.
- Embeddings complete: 61,832/61,832, zero failures, ~34 min on the PC GPU.
  Closed, integrity-checked snapshot (610 MB) kept locally.
- Smart search (full library; private case files): tuned set 33/38 top-1,
  35/38 top-3. Honest held-out sets written after tuning: set 1 10/16 top-1,
  14/16 top-10 (2 answers absent from the metadata); set 2 10/13 top-1,
  13/13 top-10. Not a general accuracy guarantee. Typical latency: instant
  ~6-30 ms; smart re-rank ~0.1-0.3 s; with generator recall ~1.2 s warm.
- Generator recall (qwen3.5:9b) only proposes titles; only owned titles are
  used and they stay "possible" unless the evidence checks confirm them.
- Deployed files (additive, O_EXCL, hash-verified) into new smartsearch
  folders code/config/models/live (863 MB). The existing pilot folders are
  untouched. An empty `.probe-owner-check` file created there by mistake is
  left in place (no deletions). The local end-to-end test of the service
  layout passed (auth, health, instant, smart, indexer up to date, events
  connected).
- Container `plezy-smartsearch` is live on Unraid (host network; bridge
  networking failed because the restricted account has remote access
  disabled and Jellyfin saw the Docker address as remote). It runs as
  99:100, read-only rootfs, caps dropped, writes only to smartsearch/live.
  Indexer up to date with live events and per-minute catch-up; library
  membership tagged. LAN round trips: instant ~8-55 ms; AI ~0.1-0.5 s, about
  1.2 s with generator recall. Code updates hot-reload from smartsearch/code.
- Nov 17: the owner allowed removing things the agent created on Unraid (the
  probe file was removed; the first, broken container was replaced).
- App integration (local only, not built for TV): SmartSearchClient
  (zero-config, same server id, user's own Jellyfin token), index-ordered
  instant titles via JellyfinClient.fetchItemsInOrder with hidden-library
  filtering from index library ids, server search still covers music, quiet
  fallback with a 4 s ceiling, "Smart matches"/"Possible matches" section
  appended after results for 3+ word requests, 250 ms debounce on Search
  only when the index is known reachable. Flutter 3.47.1 installed in
  ~/development/flutter (analytics off). Full local release gate passed:
  8,662 tests, 7 skipped, plus all static checks.
- Nov 17 owner requests (local, gate passed: 8,666 tests, 7 skipped): Home
  Back on the TV rows returns to the first item of the first row before the
  sidebar; player "Mark as played" button after Next (an episode plays the
  next and marks the one left played; a movie or last episode is marked played
  and the player closes; the stop report goes first). The owner confirmed
  that the player closes after marking a movie played.
- TV waking investigation: tvsign's log shows overnight installs (Nov 15 04:07,
  04:43, 05:44; Nov 16 04:05 local). Each install wakes the Apple TV, which
  turns the TV on via HDMI-CEC. tvsign does no automatic device contact
  between installs (next renewal about a year out). Nothing in the app can wake a
  sleeping Apple TV. Awaiting the owner's confirmation of timing. Rule:
  install only after "build apple tv" and tell the owner first.
- Next: owner decides on pushing (CI) and says "build apple tv" to try it on
  the TV. Then owner checks Search, Home Back and Mark played, then playback.
- Committed locally on this branch only (not pushed: avoid triggering CI
  until the owner decides). No Apple TV build; the owner's magic words
  "build apple tv" are still required.

## After build 24 (November 17)
- Owner: search works; genre results included anime. Server-side fix live (no
  TV build needed): anime/cartoon libraries (by library name) are left out of
  genre, rating, description and AI results unless the request mentions anime
  or cartoons; title matches and named-show requests are unaffected.
  Open question: also hide animated shows in normal libraries (Gravity Falls,
  Bluey)? This would also hide adult animation.
- Search keyboard: the docked in-app keyboard opens on Select, results stay
  visible and update while typing, and Search or a companion-remote query
  closes it and focuses results. It replaces the full-screen system keyboard,
  which loses Siri dictation and iPhone typing. Not built yet.
- Diagnostics: the owner allows reading the LAN logs for any debugging they ask for.

## Enhancement batch for the next build (November 17, not built yet)
Owner asked for improvements before the next build; playback start (~245 ms
from the logs) is already fast enough, so it was left alone.
- Home top bar: Search replaces Reorder (Read more stays). Home-row ordering
  moved to Settings > Home & Sidebar: every Home row with Show/Hide and Up/Down,
  plus sidebar items/order, pinned collections and libraries in one place.
  Appearance no longer duplicates the pin/sidebar entries.
- Smart Home rows from the index: "Top rated you haven't watched" (IMDb) and
  "Because you watched <title>" (seeded by the viewer's most recent play,
  episodes count as their show). Watched titles and hidden libraries drop out.
  Bounded at 4 s per Home pass; a miss keeps rows already shown. Server
  endpoints `/v1/top` and `/v1/similar` are live in `plezy-smartsearch`.
- "Because you watched <title>": seed is the viewer's last played movie or
  show (episode -> its show). Four best-first sources are blended: the index's
  meaning-based neighbours (`/v1/similar`), Jellyfin's own Similar items,
  Simkl recommendations and Trakt related titles (when connected). Simkl/Trakt
  and Jellyfin results map to library titles through `/v1/resolve`
  (IMDb/TMDB/TVDB ids and item ids, same library scope; a seed from an
  anime/cartoon library keeps that group). Each source adds 1/(rank+5), so
  agreement ranks first. Both smart rows drop watched and partly watched
  titles (in progress, or any episode of a show played).
- Smart rows refresh on every Home pass (start, 15-min stale return, new
  media, manual refresh) and also ~5 s after any watch event (play progress,
  watched/unwatched), waiting while the player is up; only the two rows are
  refetched, and an unchanged answer does not touch Home.
- Show page Find (owner request, Nov 17): a Find button next to Shuffle on
  shows whose server has the index opens a small search screen scoped to that
  show (`/v1/smart?series=<id>`; the request is read as "<show> episode ...").
  Results update while typing (meaning + text, ~0.2-0.5 s); Search adds the
  language model and focuses the results; Select plays the episode. Live
  check in Modern Family: "phil basketball" -> S1E20 Benched, S8E16 Basketball;
  "haley goes to college" -> S4E2 Schooled.
- Show/season page redesign (owner approved the mockup, Nov 17): new TV layout
  for shows and seasons in `media_detail/tv_modern_layout.dart`. Fixed
  top-anchored block (title/logo, one info slot showing the show or the
  focused episode, labeled actions), "Season N" tabs right above the episodes,
  no on-screen back arrow, episode cards without the E# corner badge, plain
  recommendation row names; cards keep IMDb rating, votes, year and badges.
  Restore points: git tag `show-page-classic` (83066b1b4) and Settings >
  Appearance > Classic show page (old layout, still fully tested).
  Second pass (owner: "everything we discussed" in the next release): Resume/
  Play label + time-left note, creators/directors first in Cast & crew,
  inset rail for wider margins, Request/Requested/In library pills, focused
  episode still as backdrop (650 ms rest, not for spoiler-hidden episodes),
  season poster header, next-row heading peek and a one-line header on lower
  rows. The rail still shows one active row (Home's component); full
  multi-row stacking would need a shared-rail rewrite.
- Episode menu "Mark All Previous as Watched" (owner request for background
  shows): marks every unwatched episode before the chosen one, earlier
  seasons included, specials excluded, through the normal watched path
  (Jellyfin + Trakt/Simkl). Shown for episodes past S1E1, online only.
- Apple search keyboard (Settings > Appearance, on by default on Apple TV):
  `tvos/Runner/NativeSearchPlugin.swift` presents UISearchController in a
  UISearchContainerViewController over Search and Find (channel
  `plezy/native_search`); typed or dictated text streams back live, Down
  hands focus to Plezy's results, Menu returns to the field. If it cannot be
  shown, the docked keyboard opens instead for the session. Native code is
  compiled only on Codemagic (no Mac here): first device build is its test.
- Owner (Nov 17): animated shows in normal TV libraries stay in results; only
  the anime/cartoon libraries are excluded unless asked for (unchanged).
- Search: "unwatched"/"haven't seen" requests filter by the viewer's own watch
  state; a dictation (mic) button opens the system keyboard for Siri.
- Player: optional "Still watching?" after 2–5 automatic episodes, Off by
  default (Settings > Playback); remote input resets the count.
- Logs: `/applog` on the diagnostics endpoint serves the redacted app log.
- Full local gate after Find: GATE_EXIT=0, 8,688 Flutter tests passed, 7 skipped;
  smartsearch Python tests 31/31. Earlier at 7c167862c: 8,685 passed.
  Work after the PR #1 merge is on the branch only (not yet in `main`). Earlier gate at 32e2a51a1: 8,682 passed,
  plus strict translations, isolated codegen, format, guards and analyzer;
  smartsearch Python tests 29/29. Two earlier runs failed the codegen check
  because a batch commit had run `dart format` over 33 generated `.g.dart`
  files; generator output restored (identical to build 24). Never format them.
- Not built, not installed. Fork Actions disabled, so fork CI did not run.

## Build 25 owner feedback (Nov 17, evening): two regressions to fix
- Search: the native keyboard was presented as a modal over Plezy's own search
  field, so two "Search movies, shows, music..." lines stacked and the empty
  state showed underneath. Owner wants Neptune's search (reference photo):
  big query line, Apple's one-row keyboard under it, category tabs and results
  directly below on one page, keyboard staying visible while browsing results,
  hold-mic dictation. Plan: embed UISearchContainerViewController as a child
  view of the Flutter view controller at the top of Search (not modal), hide
  Plezy's field while docked, Flutter lays results below it; focus handoff:
  Down from the keyboard -> native disables its focus and Flutter focuses the
  first result; Up from the first result row -> channel asks native to take
  focus back. Keep the docked Flutter keyboard as the fallback.
- Show page (redesign): on the owner's TV the season tabs floated mid-screen,
  episode cards were tiny and the synopsis/actions were clipped; owner switched
  to Classic. Local renders (1080p, safe areas, 4K, all densities/text sizes)
  do not reproduce it. Cause: the redesign positions tabs and the text block
  from an estimated rail height. Plan: measurement-driven Column layout (tabs
  attached to the rail, text block takes the remaining space, actions always
  visible) plus app-log diagnostics of real sizes to confirm on the device.

- Fixes made (not built yet): show page is now a measured column (text block
  fits itself above the tabs; tabs attached to the rail; rail capped to an
  explicit box) and logs `TV show page layout: ...` to the app log. Search docks
  Apple's keyboard as a child view in a rectangle reserved at the top of
  Search/Find (`NativeSearchDock`), hides Plezy's own field, starts
  unfocusable, takes the remote only while the hidden focus stand-in is
  focused, hands Down to the results and gets Up back, hides while focus is
  outside the page (expanded sidebar), and is removed when the tab or route
  is not current. Fallback: Plezy's docked keyboard if docking fails.

- Owner decision (Nov 17, late): drop the show page redesign and the Classic
  setting; keep the classic layout, only prettier: "Season N" pill tabs,
  labeled action pills ("Play/Resume S1 · E3", Shuffle, Find, Mark watched,
  More; only at 1280+ wide, i.e. always on tvOS). The redesign file is
  deleted. The show page's first "More Like This" row is replaced (after the
  page loads) by the blended list used for Home's "Because you watched",
  seeded by that show. Find uses the docked Apple keyboard like Search.

## Build 26 owner feedback (Nov 18): show page perfect, search still broken
- Owner: "show page is now perfect". Search with the docked native keyboard
  failed on the device: letters spilled under the sidebar, typing did not
  work, and the keyboard stayed stuck over other screens.
- Fix (commit `f708bd896`, not built yet): Search and Find on Apple TV use a
  Flutter-drawn static header (`lib/widgets/tv_search_header.dart`): big query
  line, one key row (123/abc, space, a-z, delete, mic), results directly
  below. The row is one focus target; Left/Right move keys, Select types,
  Down goes to results, Up returns, Back clears then leaves. The mic key
  opens Apple's system keyboard for dictation; phone/companion keyboards type
  directly. Nothing native is docked or presented, so it cannot get stuck.
  The Apple search keyboard setting and strings are removed. The native
  plugin (`NativeSearchPlugin.swift`) is still registered but no longer
  called (inert); remove later with the pbxproj.
- Rendered at 1920x1080 in a widget test with real fonts (empty and typed
  states) and checked; scratch render files deleted. Local gate GATE_EXIT=0
  (8,698 tests). Owner device check pending.
- Owner compared with Rivulet (open source, PolyForm Noncommercial; studied,
  not copied). Rivulet's whole Search page is native UIKit: results are the
  UISearchController's searchResultsController, so keyboard and results share
  one focus system. Plezy's results are Flutter, which is why docking Apple's
  keyboard failed; the Flutter header stays and now copies Rivulet's look
  (keys spread full width, hairline under them, SPACE caps).
- Show page audio badge shortened to "English / EAC3 / 5.1 / 640k" (Atmos
  replaces channels; bitrate parsed from the track title when present).
  Gate GATE_EXIT=0 (8,700 tests). Not built yet.

## Build 27 owner feedback (Nov 18): search "much better"; follow-ups
- Mic: tvOS has no public API for an app to start dictation (Speech is not on
  tvOS). The mic key opens Apple's keyboard; once it is up, holding the Siri
  Remote's mic button dictates without selecting Apple's on-screen mic.
- Speed (app log): the index answered in ~50-130 ms, but the screen waited
  for the server's own search and people (2.7-5.4 s). Fix `a2e29ebc0`: index
  titles shown as soon as they arrive (`onEarlyHits`), results kept on screen
  while the next keystroke searches, debounce 150 ms.
- More like this captions: one caption on every card (star, IMDb score, vote
  box, year). Owner rule (Nov 18): library titles use Jellyfin's community
  rating (the household's IMDb score), never MDBList; MDBList only for titles
  not in the library.
- Index check: the index has years and up to 25 actors per title, but the
  owner's Jellyfin metadata has no directors at all (checked read-only:
  Inception, Interstellar, The Dark Knight, Oppenheimer, Memento list cast
  only). Built `smartsearch/plezy_search/imdb_extras.py`: joins IMDb's public
  datasets (title.crew, name.basics, title.ratings; personal non-commercial
  use) to the library's IMDb ids (3,892 of 3,909 titles) into
  `smartsearch/live/imdb_extras.json` (new file, 0.55 MB; built locally,
  copied finished). Service loads it on refresh: director/writer names join
  the people vocabulary, results carry `votes`, new `/v1/votes`. Deployed to
  the code folder (hot reload); live check: "christopher nolan" -> The Dark
  Knight, Inception, Interstellar...; "quentin tarantino 90s" -> Pulp Fiction,
  Reservoir Dogs, Jackie Brown. Show page library cards show the vote count.
  The file is a one-time snapshot; no scheduler installed. Refresh by
  rerunning the builder (votes drift slowly; new titles get crew on rebuild).
  Single surnames ("nolan movies") are not matched; names need 2-3 words.
- Gate GATE_EXIT=0 (8,705 tests); smartsearch tests 33 OK. Not built yet.
- Owner decision (Nov 18): do not mount or read the 4 GB household imdb.db
  for vote drift. Searches use only Jellyfin's year and IMDb rating; the
  vote snapshot in imdb_extras.json is enough for show-page captions.

## Build 28 owner feedback (Nov 18): "search is INSTANT"
- Simkl row lost vote counts for library titles (they moved to the server
  rating caption without votes). Fixed: the page keeps fetched IMDb votes by
  item id and applies them to the Simkl row's owned titles as it streams.
- Mic: apps cannot start tvOS dictation without Apple's keyboard. New
  `DictationAutoReturn`: a multi-character insertion (dictation) followed by
  1 s of quiet closes Apple's keyboard and returns to Plezy's search bar
  (Search and Find). Typing one character at a time never triggers it. The
  native keyboard close path (`closeTextInput`) is unverified on device.
- Gate GATE_EXIT=0 (8,708 tests). Not built yet.
- Mic key moved beside "a" (123, SPACE, mic, a-z, delete; starts on "a").
  Seerr "More like this" row now uses the shared caption with the boxed
  vote tag (only that row). Gate GATE_EXIT=0 (8,708 tests). Not built yet.

## Anime/cartoon episodes in global search (Nov 18, server-only)
- Owner report confirmed on the live index: "anime conan forest" returned
  35 movies, 65 shows, 0 episodes; "anime naruto" and "cartoon spongebob
  jellyfish" no episodes. Cause: the unlock word became a genre filter and
  filtered requests list only Series/Movie.
- Fix (deployed to the code folder, hot reload): `instant` strips the
  unlock words (anime/animes/manga..., cartoon/cartoons/kids...) when the
  rest has no filters and searches the rest with that library opened.
  Live: "anime conan forest" -> Conan forest episodes; "cartoon spongebob
  jellyfish" -> "Jellyfishing"; "anime comedies"/"90s cartoons" unchanged.
  Service tests 37 OK. Owner rule kept: without the word, the anime and
  Cartoons libraries stay closed.
- Open: kids cartoons in the general "TV Shows" library (Bluey, Gravity
  Falls) still appear for "funny shows"/"mystery shows"; awaiting owner's
  choice (treat kids animation as cartoons; adult animation stays).

## Search housekeeping and library words (Nov 18)
- App (`14eaa5b03`, not built): leaving the Search tab clears it; Back from
  any result/chip returns to the keys on "a" (query kept, list at top); an
  always-visible scrollbar; "N results" under the filter row.
- Server (`f0dfa5924`, deployed): owner flipped the library rule for
  searches. anime/animes -> anime library (+ anime movies, all movies live in
  Movies); cartoon(s) -> Cartoons (+ animated non-anime movies);
  show(s)/series/tv -> TV Shows; no library word -> every library. Home rows
  keep the earlier scope. "show me ..." no longer parses as "shows". Live:
  "anime conan hits the ball" -> only Conan episodes. Service tests 39 OK.
- Show page "More like this stops loading when scrolling fast": not
  reproduced (4 rows, rapid Down presses: every card built); regression test
  added. Need the owner's description (blank posters, grey cards, or missing
  rows; does it recover).
- Gate GATE_EXIT=0 (8,711 tests). Not built yet.
- Build 30 backed up at the owner's request: IPA (also in tvsign as
  `Plezy-b84551e.ipa`), git bundle, local tag `tvos-build-30`, search service
  tarballs (fd07ddd53 confirmed-working, f0dfa5924 live) and the
  imdb_extras.json snapshot, in `.git/plezy-private/release-2026-11-18/build30-backup/`.

## Standing rules / next step
- Follow AGENTS.md. Never delete/uninstall the app or delete anything on Unraid.
- Build/install only after explicit Apple TV build request and scoped Unraid
  authorization; app closed, Apple TV awake in Settings before installation.
- Keep environment addresses, household device names and install receipts private.
- After strings change: clean translations, regenerate, commit generated outputs.
- Next: build only on "build app"; then owner checks the new search header
  (Search + Find, typing, Down/Up, mic dictation).
  Owner visual/settings/playback checks of build 24 remain open.
  Diagnose inconsistent iOS speed results separately; native behavior unchanged.
  Recovery receipts/bundles remain private.
