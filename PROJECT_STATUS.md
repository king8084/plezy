# Plezy tvOS project

Personal Jellyfin client fork developed on CachyOS with the ChatGPT desktop app.
Playback setup: Apple TV 4K, LG C6H, and Denon AVR-X3800H.

## Current status
November 14 follow-up, local changes only (not built/installed): owner reports
almost everything looks good on installed `25eccb2`, then requested season-tab
position/reset fixes, Seerr recommendations, independent sidebar pins, sidebar
ordering, and a polished Favorites page. General UI feedback is positive;
playback confirmation remains a separate milestone.
- Multi-season TV tabs now sit below Back, above the show hero, with 16 scaled
  pixels before the hero and a 20-scaled-pixel action/episode-rail gap. Remote
  Up follows episodes → actions → information → tabs → Back; Select on a
  season still enters its full episode row. Single-season layout is unchanged.
- Explicit season changes reset to the first media card, including revisiting
  a cached season and loading an empty/pending page. The rail exposes a narrow
  first-item selection method that accounts for the leading season-options
  slot; initial Continue Watching entry still preserves S8 E14. Once a season
  is explicitly changed, the original entry episode cannot reassert itself.
- Seerr request shelves now use `/movie/{id}/recommendations` and
  `/tv/{id}/recommendations`, not `/similar`. Fetch up to three pages (normally
  60 candidates), retain recommendation order and deduplicate across pages;
  keep the existing availability/active-request/blocklist/permission filters.
  A later-page failure preserves earlier results. No real request submitted.
  Official endpoints verified:
  https://docs.seerr.dev/api/get-recommended-movies/
  https://docs.seerr.dev/api/get-recommended-tv-series/
- Settings → Appearance → Navigation adds Pin Favorites to Sidebar, Pin
  Collections to Sidebar, and Sidebar Order. Pins default off and render as
  independent destinations alongside Home/Explore/Settings, never nested in
  Libraries. Ordering persists, handles hidden/unknown entries, and drives both
  rendered order and D-pad order. Nested library rows move with their header;
  reconnect/fullscreen utility controls retain their existing fixed positions.
  In the order sheet, Select lifts a row, Up/Down moves it, Select saves; Back
  cancels a pending move. Drag reordering is supported too.
- Pins load the active profile's visible, non-hidden online libraries, page all
  results and deduplicate by server/item. Favorites query only capable servers
  with the favorite filter. Collections query one shared root per Jellyfin/Emby
  server and each Plex library. Collections use the existing full grid screen.
- Apple TV Favorites reuses Home's spotlight and poster rail, including Poster
  Card Size, full-card/grid-spacing and Home text-size settings. Focus changes
  the show/movie artwork/logo, description, ratings and descriptive metadata.
  A show remains show-level: no episode lookup/file details stand in for it.
  The existing context menu, explicit detail activation and Back paths remain
  in use. Non-TV Favorites uses the existing grid.
Validation: 228 affected detail, recommendation, rail, settings, sidebar-source,
order-sheet and Favorites tests pass (`/tmp/plezy-sidebar-season-tests-final.log`).
Whole-project analysis passes (`/tmp/plezy-sidebar-season-analyze-final.log`);
string/error/diff guards pass. The final mixed-library query adjustment also
passes its two source regressions (`/tmp/plezy-sidebar-source-tests-final.log`).
Local renders inspected at `/tmp/plezy-top-season-tabs-preview.png` and
`/tmp/plezy-favorites-preview.png` (test fonts/placeholders; no overlap). Temporary
preview tests removed. Initial preview capture needed an async test-harness fix;
that did not require any production change. Owner TV visual/remote verification
of this follow-up remains pending. Next step: explicit owner "build apple tv"
before CI; a new scoped authorization is required before further Unraid changes.

November 14: owner explicitly requested "build apple tv" for `25eccb283` and
clarified that the one-time Unraid permission covers ALL steps needed for this
build, including signing and in-place installation. They confirmed Plezy is
closed and Apple TV is awake inside Settings. Use the existing app/account,
preserve current IPAs/backups, and never delete/uninstall. The single authorized
build and installation completed; owner device testing remains separate.
Build #9 `6af8372090e83b09c4fa25e9` started at 13:25 Arabia time for
`25eccb283b8d05f0fae081447783bffc4e562812`, existing M2 unsigned-IPA workflow.
CI succeeded in 5m 12s. Native archive succeeded; this device workflow does not
run native policy tests. IPA verification and staging/install passed; owner
testing remains pending.
https://codemagic.io/app/6af73c658b158cee7474719c/build/6af8372090e83b09c4fa25e9
Preserved `ipas/1/original-before-25eccb2.ipa` and `signed-before-25eccb2.ipa`
through Unraid File Manager; both verified at 0600. Older backups, app
entry/account and signer configuration are preserved.
Verified `/home/koolo7000/Downloads/Plezy-tvOS (7).ipa`, staged locally as
`/tmp/Plezy-25eccb2.ipa` (73,200,007 bytes), SHA-256
`d7409811a7b92cf627e2a033fac43083c924c0231f2ed704a04301f8a6ee62ff`.
ZIP CRC, AppleTVOS platform, bundle ID, local-network declaration and matching
main/Top Shelf app-group entitlements pass. Uploaded this artifact into the
existing `ipas/1` folder, restricted it to 0600, copied it over `original.ipa`,
and verified the active source's 13:31 timestamp and 0600 permissions. Renew
requested once at 13:34. tvsign reports successful signing and in-place
installation on Basement, with the final success log at 13:35 Arabia time.
Latest installed app source: `25eccb283b8d05f0fae081447783bffc4e562812`.
No stall, deletion/uninstall, new app entry or signer/container changes.
Proof: `/tmp/plezy-install-25eccb2.jpg` (Valid card and 13:35 success log).
The build-only Unraid authorization is fulfilled. Next step: owner opens Plezy
and checks Continue Watching → S8 E14, the full season-8 episode row, season
tab switching and the separate library/request shelves. Owner playback and
retained-settings confirmation remain pending; no real Seerr request submitted.

November 14 follow-up, now built and installed: owner requested a Wholphin-style
season selector and separate owned/requestable "More Like This" shelves.
- TV show/season navigation now shows the selected season's FULL horizontal
  episode row, with S1/S2/etc. tabs above it. The owner explicitly clarified
  "one season row", not one episode. Continue Watching preserves its entry
  season/episode (regression: S8 E14 with all 22 season-8 episodes, even when
  server on-deck points to another season). The selected tab scrolls into view.
  Left/Right moves tab focus; Select switches the season and enters its episode
  row; Up returns to tabs, then to the existing action row. Single-season shows
  retain their current layout. Cast follows the one season row immediately.
  Existing season options, paging, adjacent first-page prefetch and focus memory
  remain in use. Non-TV season layouts keep their current navigation.
- The existing Jellyfin similar shelf is labelled "More Like This — In Your
  Library". A second TV shelf, "More Like This — Request", uses the connected
  Seerr account's `/movie/{tmdbId}/similar` or `/tv/{tmdbId}/similar` endpoint.
  It excludes self/duplicate, available/partly available, pending/processing,
  active-request and blocklisted entries using Seerr's linked-server status.
  Cards enter the existing catalog detail / explicit Request flow. No real
  request was submitted while developing or testing this change.
- Seerr loads asynchronously outside the detail reveal/Play gate. Missing TMDB
  mappings, permission loss, disconnect, failures and stale responses cannot
  block the local page; empty/unavailable request shelves stay hidden. Returning
  from catalog details refreshes the shelf's current request/availability state.
Research: Wholphin's `SeerrService.similar` uses separate Seerr similar endpoints,
and its movie/series view models keep those results separate from Jellyfin
similar items. Primary sources:
https://github.com/damontecres/Wholphin/blob/main/app/src/main/java/com/github/damontecres/wholphin/services/SeerrService.kt#L105
https://docs.seerr.dev/api/get-similar-movies/
https://docs.seerr.dev/api/get-similar-tv-series/
Validation: all 312 affected detail, catalog, Seerr client/request, TV rail,
navigation and MediaHub tests pass (`/tmp/plezy-season-seerr-tests-final.log`).
Whole-project analysis passes (`/tmp/plezy-season-seerr-analyze-final.log`);
translation generation, string/error guards and diff whitespace checks pass.
Local layout render inspected at `/tmp/plezy-season-tabs-preview.png` (test font
and placeholder art; no overlap). Temporary preview test was removed locally.
The subsequent authorized build #9 and in-place installation completed above.
Device visual/remote verification remains pending on the installed app.
Any further build or Unraid change requires a new explicit instruction.

Previous installed app source was `fe216e681d8241f049e880fe34909ff0fbc7dc38`.
tvsign reports successful signing and in-place installation on Basement at
12:49 Arabia time, November 14. Existing app entry/account, app data and all
older backups preserved; no deletion/uninstall, signer/container update or
stall. Owner confirmed Plezy closed and Apple TV inside Settings before install.
The build-only Unraid authorization is now fulfilled. Owner confirmation of
playback, retained settings and the new UI/rewind additions remains pending.
Proof: `/tmp/plezy-install-fe216e6.jpg` (Valid card and new 12:49 success log).

Authorized Codemagic build #8 `6af82cbc90e83b09c4fa22de` started at 12:41
Arabia time, November 14, for `fe216e681d8241f049e880fe34909ff0fbc7dc38`
(four UI additions plus independent rewind). Existing M2 / unsigned tvOS IPA
workflow, branch `codex/first-tvos-test-build`. CI succeeded in 5m 14s. Native
archive compiled successfully; this device workflow does not run native policy
tests. Artifact verification and in-place installation passed; owner testing
remains pending.
Build: https://codemagic.io/app/6af73c658b158cee7474719c/build/6af82cbc90e83b09c4fa22de
While CI runs, preserved `ipas/1/original-before-fe216e6.ipa` and
`signed-before-fe216e6.ipa` in the existing Unraid tvsign folder; both verified
at 0600 through File Manager. All older files remain untouched.
Verified `/home/koolo7000/Downloads/Plezy-tvOS (6).ipa`, staged locally as
`/tmp/Plezy-fe216e6.ipa` (73,189,875 bytes), SHA-256
`78711a7f972f478beea2a1ceec19d28f801e2c4c3a011e7aa59eabb95c593651`.
ZIP CRC, AppleTVOS platform, bundle ID, local-network declaration and matching
main/Top Shelf app-group entitlements pass. Upload completed at 12:47 to the
existing `ipas/1` folder. Restricted the new IPA to 0600, copied it over the
existing `original.ipa`, and verified the active source's 12:47 timestamp and
0600 permissions. Renew requested once at 12:49; signing and installation
completed that minute. Existing app entry/account and all backups preserved.

Owner explicitly authorized "build apple tv" and Unraid use for this build
only, confirming Plezy closed and Apple TV awake inside Settings. Before CI
started, they added an independent rewind interval and asked to continue.
Implemented the addition for Apple TV: Settings → Video Playback → Seek and
Timing now has Fast Forward Duration and Rewind Duration (1–120 seconds).
Rewind initially inherits the formerly shared interval once, then persists
independently; existing values and reset behavior are covered by regression.
Now Playing's numbered buttons and spoken labels reflect each configured value,
including custom values beyond the built-in 5/10/30 glyphs. Backward button,
hidden/visible timeline, chapter fallback, hardware/companion skip and shortcut
paths use the independent rewind interval on Apple TV. Other platforms retain
their existing shared interval. No unrelated playback behavior changes.
Validation: 272 settings, shortcut, playback-settings, Select, transient-feedback,
controls and companion-remote tests pass (`/tmp/plezy-rewind-tests.log`), including
independent persisted settings and actual 15 s rewind / 20 s forward seeks with
matching visible button numbers. Whole-project analysis passes
(`/tmp/plezy-rewind-analyze.log`); translation generation, string/error guards
and diff whitespace checks pass. The previous four UI additions retain their
184-test validation below. The single authorized Codemagic build and in-place
installation completed above. Owner playback confirmation is the remaining
milestone. No Unraid deletions occurred.

November 14 follow-up: implemented the owner's four small UI changes locally.
The initial implementation was tested locally; the subsequent authorized build
and installation above now include these four additions.
- Apple TV Now Playing uses the episode's existing series clear logo instead
  of the show-name text, with the existing text fallback when artwork is absent
  or fails. Other platform headers keep their existing presentation.
- Beside S/E numbers, show one gold-star score for the playing episode only.
  Prefer attributed IMDb; the owner explicitly chose "Use the same episode
  score as Home" for Jellyfin's unattributed community score. No series-score
  substitution, critic badge or extra provider ratings are added to the player.
- A graph icon at the end of the existing player controls toggles the existing
  Performance Overlay (Stats for Nerds), using its existing settings and polling
  lifecycle. Remote focus/Select toggles it without changing playback state.
- The final Home technical pill follows audio and combines first-file size and
  overall bitrate, e.g. `4.90GB | 12.0Mbps` or `830MB | 5.0Mbps`. Existing binary
  file-size units match File Info; sizes below 1 GB use MB. Unknown values are
  omitted. Cached partial file metadata is enriched through the existing
  background fetch/cache for that exact episode/movie, outside the Play path.
Validation: all 184 affected header, Home, file-label, remote Select, controls,
auto-hide and stats lifecycle tests pass (`/tmp/plezy-now-playing-tests-final.log`).
Whole-project analysis passes (`/tmp/plezy-now-playing-analyze-final.log`);
hardcoded-string guard, user-facing-error guard and `git diff --check` pass.
Next step: owner verifies the additions on the installed app. Any further build
or Unraid change requires a new explicit instruction.
Visual verification on Apple TV and owner confirmation of these new additions
remain pending. Owner's attached Home photos show the installed cropped-file
4K/1080p labels correctly, and they describe the current player positively;
Select and focused-thumbnail synopsis have not been separately reconfirmed.

Previous installed build was `6d2df7a869985c055fc57afff0ef3f7018534ed7`:
Codemagic succeeded and tvsign reports successful in-place installation on
Basement at 08:49 Arabia time, November 14. The existing app entry/account were
used, Plezy was closed and the owner kept Apple TV inside Settings. No deletion,
uninstall, new app entry, signer/container change or stall occurred. Owner test
of Select, cropped resolution tags and focused-thumbnail synopsis is pending.
This completes the owner's build-only Unraid authorization; no further Unraid
change or new Apple TV build is authorized without a new instruction.

Owner authorized a new Apple TV build and Unraid staging/install for this build
only on November 14, confirming Plezy closed and Apple TV inside Settings.
Paused before starting at the owner's “stop”; at that point only `7e8974054`
had been pushed, with no Codemagic build or Unraid change. Owner then requested
continuation once cropped 1080p/720p are covered too. The small edge-crop
tolerance now applies to both width and height at every tier; cases including
3832×1600 → 4K, 1880×1072 → 1080p and 1240×712 → 720p pass, including stale
cached labels. All 63 affected resolution/mapper/spotlight tests and targeted
analysis pass, in addition to the earlier 406 tests for the three fixes.
Owner clarified the actual 1080p file is 1912×1072. Added that exact case to
the regression table; all 12 quality-label tests pass, classifying it as 1080p.
Codemagic build `6af7f46a90e83b09c4fa14a1` started at 08:41 Arabia time for
`6d2df7a869985c055fc57afff0ef3f7018534ed7` (index 7, M2). This is the single
authorized resumed build. CI succeeded in 6m 15s; in-place installation succeeded
at 08:49. Owner testing remains pending.
Preserved the existing unsigned IPA as `ipas/1/original-before-6d2df7a.ipa`
(0600). Signed IPA backup `signed-before-6d2df7a.ipa` is also verified at 0600
through Unraid's file manager. All earlier backups remain untouched.
Verified artifact `/home/koolo7000/Downloads/Plezy-tvOS (5).ipa`, local copy
`/tmp/Plezy-6d2df7a.ipa` (73,193,889 bytes), SHA-256
`01d79291d108500a4c89ac159a0d872308db4f66f0c6c826c71ae0cdb8166051`.
ZIP CRC, tvOS platform, bundle ID, local-network description and both embedded
app-group entitlements pass. Native archive succeeded; device workflow does not
run native policy tests. Upload to the existing `ipas/1` folder completed at
08:48. Restricted `Plezy-6d2df7a.ipa` to 0600, copied it over the existing
`original.ipa`, and verified the active source's new timestamp and 0600 mode.
Renew requested once at 08:49. Signing and installation succeeded within that
minute; tvsign shows Valid and a new 08:49 successful manual-renewal entry.
Proof screenshot: `/tmp/plezy-install-6d2df7a.jpg`. Both current-build backups
and all older backups remain intact. No Unraid deletions or other changes.
Build URL:
https://codemagic.io/app/6af73c658b158cee7474719c/build/6af7f46a90e83b09c4fa14a1

Previous build `ae237fb423cd5a086da92f233d09d1d6d3dcac33` (tested app source
`2d92f1e2f`) built successfully and tvsign reports successful in-place installation
on Basement at 08:13 Arabia time on November 14. The owner explicitly authorized
both the build and Unraid staging/install, and confirmed the TV was awake inside
Apple TV Settings with Plezy closed. Used the existing app entry/account; no
app deletion, uninstall, new entry, server configuration change or backup deletion
occurred. This attempt completed without the prior app-close stall. Owner testing
of this build now confirms the UI is almost perfect, with three reported issues:
center Select pauses playback, cropped 4K is labeled 1080p, and thumbnail focus
can leave the episode synopsis missing. Retained settings and new-build startup
timings have not been separately confirmed. Local corrections are recorded below;
the subsequent build/install has now been authorized for this build only above.

Codemagic build `6af7ebda90e83b09c4fa12ba` (index 6), M2 workflow, started at
08:04 and succeeded in 6m 15s. Artifact:
`/home/koolo7000/Downloads/Plezy-tvOS (4).ipa`; local staging copy
`/tmp/Plezy-ae237fb.ipa` (73,194,728 bytes), SHA-256
`413407ba21a40d772f41ddeaf63c5eac55bed4810a807d976d3d448499e5dceb`.
Verified ZIP CRC, tvOS platform, bundle ID `com.edde746.plezy`, local-network
usage description and matching app-group entitlements on main and Top Shelf
binaries. Native archive compiled successfully; the device workflow does not run
native tests. Build URL:
https://codemagic.io/app/6af73c658b158cee7474719c/build/6af7ebda90e83b09c4fa12ba

On Unraid preserved `original-before-ae237fb.ipa` and `signed-before-ae237fb.ipa`
in the existing `/mnt/cacheapp/appdata/docker/tvsign/ipas/1` folder, both 0600.
Uploaded `Plezy-ae237fb.ipa`, restricted it to 0600, then copied it over the
existing `original.ipa` (verified 0600 and new timestamp). Older files/backups
remain intact. Renew requested once at 08:12; signing and installation completed,
with a new successful renewal log entry at 08:13. No signer/container update.

Codemagic billing showed 33 / 500 free minutes used while this build was still
running (467 remaining at that observation); current build usage may not yet have
been reflected. At 6–10 min/build that represented about 46–77 further builds,
not a fixed build-count allowance. No subscription/billing change was made.

Build `98c7123d4` (app changes `e4b4390b6`) built successfully in Codemagic
and tvsign reports successful in-place installation at 23:40 on November 13.
The existing app entry/account were used; no app deletion or uninstall occurred.
The owner confirmed Plezy was closed, but installation stalled at 0% while on
the Home screen. The same attempt completed after the owner opened Apple TV
Settings. This strongly suggests Home/Top Shelf activity held the update; it
does not establish the exact process or lock. Future update procedure: close
Plezy and remain in Apple TV Settings until installation finishes.
The owner confirms startup is MUCH faster and the physical Home Play button
now works. Authenticated LAN diagnostics were read successfully (HTTP 200);
unauthenticated access returns HTTP 403. Six installed-build starts reached
UI-ready at 195, 226, 499, 250, 227 and 332 ms (median 238.5 ms), with the QMS
SDR wait skipped. The display manager still reports its end around 2.54 s in
some starts; playback no longer waits for that flag. These are app startup
signals corroborated by owner feedback, not a frame-by-frame HDMI benchmark.
Private access details are kept only in `.git/plezy-diagnostics.json` (0600),
never in Git history. The endpoint is available while Plezy runs; the owner
was told they can close the app after diagnostics have been read. A later
probe was unreachable, so follow-up analysis uses the saved six starts.

Log `j1hgqr` from the installed build shows source resolution in 25–50 ms,
first-frame signals in 130–244 ms, and display-negotiation completion at
2773–2815 ms. UI readiness follows immediately. Thus the measured delay is in
the display-negotiation gate; these logs do not prove the TV is blank for that
whole interval. The owner confirms the same 1080p SDR source in both apps,
matching 60 Hz to 24 Hz on their QMS-capable TV: Rivulet starts instantly.

Upstream CI prepares Flutter 3.47.1 and the separately pinned tvOS engine,
installs CocoaPods and runs Runner reliability tests on a tvOS simulator.
Its release workflow does not publish a tvOS IPA. This fork uses Codemagic
for authorized device builds; do not repeatedly retry unavailable GitHub runners.

## Current requested changes
- IMDb rating stars on media cards use dark gold (`#B8860B`).
- The existing library-density control is labeled Poster Card Size; its range
  controls poster widths, and the default for new tvOS installs is one step
  larger. Existing saved values are preserved.
- Jellyfin's Add Server address starts at `http://192.168.100.46:8096`.
- Collections can be pinned from their context menu. Pins are saved locally,
  and Discover synthesizes home rows by fetching each collection's children;
  this follows Wholphin's direct collection-row approach without a server
  plugin. More items are loaded through the collection paging API.
- Audio pass-through and startup speed are under investigation. Rivulet uses
  AetherEngine, while this Plezy tvOS fork currently uses its Flutter/mpv
  playback path. Rivulet documents AC3/E-AC3 stream-copy into AVFoundation;
  that does not by itself establish unchanged HDMI bitstream output. Output
  format is mediated by tvOS and the selected Apple TV audio settings.
  TrueHD/DTS are decoded to PCM unless optional AetherEngine object rendering
  is used. First-frame startup needs timing on the same source/device before
  choosing a change.

## Milestones
- November 14, `25eccb2`: Codemagic build #9 `6af8372090e83b09c4fa25e9`
  passed in 5m 12s; IPA integrity, tvOS identity and app-group checks pass.
  tvsign reports successful in-place installation on Basement (started 13:34,
  final success 13:35), with Plezy closed and Apple TV in Settings. Same
  app/account, backups preserved, no stall/deletion. Owner confirmation of
  season tabs, full selected-season row, Seerr shelves and playback pending.
- November 14, `fe216e6`: Codemagic build #8 `6af82cbc90e83b09c4fa22de`
  passed in 5m 14s; IPA integrity, tvOS identity and app-group checks pass.
  tvsign reports successful in-place installation on Basement at 12:49, with
  Plezy closed and Apple TV in Settings. Same app/account, no stall/deletion,
  backups preserved. Owner playback/settings/UI confirmation remains pending.
- November 14, `6d2df7a`: Codemagic run `6af7f46a90e83b09c4fa14a1` passed in
  6m 15s; artifact checks pass. tvsign reports successful in-place installation
  on Basement at 08:49, same app/account, no stall or deletion. Both active IPA
  backups and all older files preserved. Owner testing of the fixes pending.
- November 14: Codemagic build `6af7ebda90e83b09c4fa12ba` succeeded for
  `ae237fb` in 6m 15s; unsigned artifact checks pass. tvsign reports successful
  in-place installation on Basement at 08:13 with TV inside Settings. Same
  app entry/account, both active IPA backups preserved, no deletion/uninstall.
  Owner confirmation of new UI/playback/retained settings is pending.
- November 14: new build and Unraid staging/install explicitly authorized.
  Source `2d92f1e2f` has the previously recorded full-suite validation for the
  main follow-ups and 52 passing targeted tests after the final tag addition;
  latest targeted analysis and string/error guards pass. No redundant GitHub
  runner retry is planned. Codemagic will use the existing M2 workflow.
- Owner-confirmed playback on installed `98c7123d4`: substantially faster start
  and working physical Home Play. Authenticated rotating diagnostics are
  readable directly over the LAN. The follow-up UI/navigation edits below were
  subsequently built and installed in `ae237fb`; owner testing is pending.
- Owner authorized the next build and installation on November 13. Codemagic
  build `6af771ce90e83b09c4f9f245` started at 23:23 Arabia time for commit
  `98c7123d4b57e0c5b2657c58a03830a7528d190f` (tested app source `e4b4390b6`),
  branch `codex/first-tvos-test-build`, Mac mini M2. Build succeeded in 9m 35s;
  IPA `/home/koolo7000/Downloads/Plezy-tvOS (3).ipa` (73,188,584 bytes),
  SHA-256 `ab69e608b3ffc94aa280b2f00f9e4fc4766c91814f1f0539341415c64e2601cd`.
  Archive CRC, tvOS platform, unchanged unsigned bundle ID, local-network
  description and both embedded app-group entitlements passed verification.
  Native archive compiled successfully; native policy tests were not run by
  this device-only workflow. Before staging,
  preserved the active unsigned and signed IPAs on Unraid as
  `ipas/1/original-before-98c7123.ipa` and `ipas/1/signed-before-98c7123.ipa`,
  both with owner-only permissions. Existing older backups remain untouched.
  New source uploaded as `ipas/1/Plezy-98c7123.ipa`, restricted to 0600, then
  copied over `ipas/1/original.ipa` (0600) at 23:34. Owner confirms Plezy
  force-closed and TV awake. Renew requested on the existing app/account.
  Signing succeeded at 23:35, then installation stayed at 0% and tvsign
  showed its generic app-open stall label at 23:37. Owner again confirmed
  Plezy was closed. After the owner opened Apple TV Settings, the same
  attempt completed at 23:40. No deletion, uninstall, re-signing or second
  install request was needed to release it. The Top Shelf/Home hypothesis is
  supported by that observation; exact installer lock is unverified. Owner
  playback and retained-settings confirmation on the new build are pending.
- Nov 13 at 22:45: tvsign reports successful signing and installation of build
  `0a77954d6` on Basement through the existing app entry, using the patched
  signer installed by the owner. No app deletion/uninstallation was performed.
  The new IPA is active as `ipas/1/original.ipa` (0600); the older renewal
  source is additionally preserved as `original-renewal-before-signer-retry.ipa`.
  Both earlier IPA backups, the rejected-attempt IPA and
  `plumesign-before-group-fix` remain saved. The app-group signing refusal did
  not recur. The owner confirms Top Shelf Continue Watching now works and
  playback play/pause works. Startup still takes about four seconds. The
  requested missing remote action is Play from a focused Home card. Retained
  settings have not been explicitly confirmed.
- Owner authorized a new Apple TV build on November 13 after the local tests.
  Codemagic build `6af7606290e83b09c4f9eb93` targets commit `0a77954d6`
  on `codex/first-tvos-test-build`; succeeded on a Mac mini M2 in 5m 58s.
  IPA: `/home/koolo7000/Downloads/Plezy-tvOS (2).ipa`; archive integrity passed,
  bundle ID matches the prior unsigned app, and both executable signatures
  contain app-group entitlements. Actual Apple provisioning remains unverified.
  Owner requested installation and specifically authorized securing the uploaded
  IPA, preserving both older IPAs, replacing the existing entry's source and
  pressing Renew. The new `original.ipa` has mode 0600; the old files are
  `original-before-0a77954.ipa` and `signed-before-0a77954.ipa` in the same
  tvsign IPA folder. On Nov 13 at 22:24, signing failed before installation:
  Apple Developer API error 35 says the team-suffixed application group is not
  available. tvsign plans an automatic retry in 45 minutes. The existing Apple
  TV app remains installed; no installation or playback confirmation exists for
  the new build. The owner then explicitly authorized restoration. The old
  unsigned IPA was copied back to `original.ipa` (0600), preserving both backups;
  the new build is retained as `original-0a77954-signing-failed.ipa`. No deletion
  or additional installation was performed. Renewals now use the old source.
  Do not change Unraid further without specific owner authorization.
- Investigated tvsign v1.0.2's exact vendored signer. It concurrently provisions
  app and extension groups, allowing duplicate creation races, and compares
  opaque resource IDs to identifiers when deciding whether the default group
  already exists. A local patch serializes provisioning, avoids duplicate
  default-group creation, and recovers error 35 only if the same team's exact
  group is subsequently found. Compile check passed; a fake-API regression
  test passed recovery, unrelated-group and missing-group scenarios. See
  `tvos/patches/README.md`. This is a candidate fix, not live Apple validation.
  The owner subsequently authorized and deployed the patch; signing and
  installation succeeded at 22:45. No new Apple TV build was necessary.
- Owner explicitly approved administrator Docker packaging on CachyOS,
  replacing only the tvsign signer on Unraid with the original preserved, and
  retrying the existing IPA in place. Automatic review now allowed the local
  build command, but `sudo -n` reports that a password is required. Packaging
  has not run; no signer deployment or new install has been attempted. Owner
  must run the local packaging command in their terminal so their password
  stays private. Prepared source is `/tmp/plezy-tvsign-v102`; patch remains in
  `tvos/patches/tvsign-1.0.2-app-groups.patch`.
- Owner completed local Docker packaging. Verified a 17,570,040-byte x86-64
  Debian-compatible signer, SHA-256
  `762c5b1beaac69594e4484ca5273924415dee237ce5c8bf425658c3215f0fabd`.
  Uploaded it as `ipas/1/plumesign` on Unraid and restricted it to 0600.
  The owner subsequently ran the deployment block and reported version 2.6.1;
  the preserved original signer was also visible in Unraid's file manager.
  Existing SSH authentication fails; the connected browser's terminal button
  does not open an accessible terminal, and `/webterminal/` returns 404.
  The owner completed the Docker copy/backup block; the new IPA was activated
  and the in-place signing/installation retry succeeded at 22:45.
- Owner authorized “build apple tv” on November 13. Codemagic build
  `6af74d5690e83b09c4f9e43f` succeeded for commit `8f9254a71` in 5m 33s;
  the unsigned IPA is `/home/koolo7000/Downloads/Plezy-tvOS (1).ipa`.
  tvsign reports signing and installation on Basement succeeded at 21:25;
  owner subsequently confirmed playback and reported the delay remains.
  The currently installed tvsign UI has no visible replace-IPA control. An
  attempt to upload via New app was rejected by automatic approval review
  because it could create a second app and separate renewal entry. The prior
  installed app and tvsign entry were left intact.
  Owner requested replacement, but the Unraid image `ghcr.io/esalwey/tvsign:1`
  is reported up to date; upstream documents IPA replacement for 1.1.0,
  while latest published release observed was 1.0.2. No container update or
  IPA upload was made at that point. Unraid reports tvsign Autostart OFF, so it will not
  automatically restart after an Unraid reboot unless that is enabled.
  Subsequently, owner requested an in-place update. Backed up the old IPA as
  `ipas/1/original-before-8f9254a.ipa`, uploaded the new IPA to the existing
  folder, copied it over `original.ipa` with owner-only permissions, and used
  the existing entry's manual Renew. Signing succeeded; installation stalled
  at 0%. tvsign suggests the app may be open, but its source labels any stalled
  installation this way; owner reports Plezy is not open. Awaiting force-close
  or Apple TV restart. A second install stalled and was interrupted when the
  owner deleted the old app; a final manual Renew then succeeded at 21:25.
  No new tvsign entry was made. Because the owner deleted the app on the TV,
  its local settings and login may need to be configured again.
- CI build: standard fork CI queued; device IPA run `43454148475` was not
  acquired by a hosted runner while waiting for `macos-26`. Run `43459871032`
  failed after 15 minutes without runner assignment; its annotations explicitly
  report that a hosted runner did not acquire the job after multiple attempts
  and cite macOS ARM64 capacity constraints. Redundant retry `43462680240` was
  cancelled before runner assignment. Codemagic build `6af73c8290e83b09c4f9dda6`
  failed during archive on a Mac mini M2 at commit `bbf2edb15`: the pinned
  collection lookup called a nonexistent `MultiServerProvider.getClient`.
  The call was corrected to `getClientForServer` in `10f04e1cb`. Codemagic
  build `6af7407b90e83b09c4f9df37` succeeded in 8m 27s and produced
  `Plezy-tvOS.ipa` (69.55 MB) for that commit.
- tvsign on Unraid: installed and healthy, using
  `/mnt/cacheapp/appdata/docker/tvsign`; first-run setup complete, Apple ID
  signed in, and Apple TV pairing complete.
- Install on Apple TV: tvsign reports it signed and installed Plezy 2.26.0 on
  Basement; the owner confirmed running that older build. Commit `0a77954d6`
  was installed in place at 22:45. The owner confirms working Top Shelf and
  playback play/pause; startup remains slow.
- Owner-confirmed playback: reported by the owner; startup is about four
  seconds versus about 0.5 seconds in Rivulet. Media details are not yet known.
- Log ID supplied by the owner on the current build showed source resolution
  in 43–64 ms and first-frame signals at 211–459 ms; UI readiness followed at
  3.0–3.5 s. Owner confirmed playback starts much faster when Apple TV Match
  Frame Rate and Match Dynamic Range are disabled, but Rivulet remains fast
  with both enabled. Display negotiation is a strong lead; the current logs
  bracket the wait together with first-frame effects, so do not assert the
  exact split without the added post-negotiation timing. AetherEngine requests
  display criteria before loading its AVPlayer item. Plezy requests criteria
  from decoded mpv output, later. A matching-enabled candidate is implemented
  locally but its effect is not verified. Do not disable matching or promise
  0.5 s.
- Pinning collections: the owner reports not seeing the option. The installed
  build places “Pin collection to Home” in the collection card's long-press
  context menu; actual behavior on the Apple TV still needs owner confirmation.

## Next milestone
Owner test of installed `6d2df7a`: center Select raises controls without pausing,
physical Play/Pause still controls playback, 1912×1072 now shows 1080p,
3832×1600 shows 4K, and focused episode thumbnails show their synopsis at top.
Check playback still starts promptly and existing settings/login remain.
The old private diagnostics URL is retained in `.git/plezy-diagnostics.json`
(0600) with the installed commit updated; read it when Plezy runs if needed.
Previous owner-confirmed fast SDR startup belongs to the earlier build and must
not be reported as new-build confirmation. CI success, in-place installation
and owner testing remain separate milestones. The current install completes
the build-specific Unraid permission. Wait for a new explicit “build apple tv”
and new Unraid authorization before any further build/install. Keep future
updates on the same app entry/account, TV inside Settings and Plezy closed.

## Corrections installed in 6d2df7a (November 14)
- Center Select on the Apple TV player surface raises controls without toggling
  playback. Focused controls still activate normally (including an explicit
  Play/Pause button), Skip Intro remains selectable, and physical Play/Pause
  remains transport. Desktop Enter behavior is unchanged. Updated the old TV
  test that explicitly expected Select to pause.
- Owner's Dexter file is 3832×1600: the exact-3840 width threshold misclassified
  its cropped 4K raster. Resolution bucketing now tolerates a small edge crop
  (up to 16 pixels on either width or height) at 4K, 1080p, 720p and 480p tiers.
  The owner explicitly confirmed the same issue below 1080/720 boundaries;
  all 63 resolution-related tests pass after this extension. Quality labels recompute from known dimensions
  before using the saved canonical label, correcting already-cached `1080`
  values too. Real 1920×800 files stay 1080p; first-audio policy is unchanged.
- Focused-thumbnail synopsis: a regression test reproduces a missing header
  when the listing has no summary but the existing full-item probe returns it.
  That probe previously only updated header ratings. It now also supplies the
  same episode's synopsis and notifies the header when the text arrives, with
  no extra network request or playback prerequisite. Tight hero layout keeps
  at least one description line ahead of logo height. Spoiler preferences still
  apply; cards remain thumbnails/titles with the synopsis in the top panel.
- Diagnostics: the existing saved private URL returned HTTP 200 immediately
  after retrying outside the restricted shell. The sandboxed check failed;
  the installed URL/key had not changed. Saved the current traces locally as
  `/tmp/plezy-latest-network-diagnostics.log` (0600), with no key in tracked
  files. Documented this connection check in AGENTS.md. Sharing's private key
  now survives Stop Sharing, re-enable and service relaunch too, so toggling
  sharing no longer changes the link. Keep the existing authentication,
  fixed port 18765, read-only allowlist and 1 MiB rotating file limit. App must
  be running for the listener to answer; no Unraid service is needed/changed.
- Validation: project analyzer and hardcoded-string/raw-error guards pass.
  All 406 player/detail/mapper/quality/diagnostics tests pass, including the
  formerly failing missing-synopsis regression. Source formatting passes.
  Subsequently built and installed in `6d2df7a` at 08:49; owner verification
  of these fixes is pending.

## Changes installed in ae237fb (November 14)
- Source-file tags requested from the Matrix reference: a separate compact pill
  row below Home metadata shows resolution (1080p/4K), video codec (H.264/HEVC),
  Dolby Vision/HDR when reported, and exactly one audio codec/layout tag. Per
  owner clarification, use the first audio track of the first file version,
  regardless of selected/default flags; do not list multiple audio tracks.
  These describe file metadata, not actual receiver output or passthrough.
  Existing metadata order remains intact. Tags scale with Home text size,
  reserve a consistent slot across titles, and shed trailing pills if too wide;
  an exceptionally short hero band prioritizes the existing text over this row.
  Missing file details load asynchronously for the exact episode/movie through
  the shared metadata cache. Episode tags never borrow the series' file details;
  shared movie enrichment uses one request per ID. No playback gate, broad hub
  field expansion or player configuration was added. Existing quality helpers
  retain their selected-audio behavior outside the new Home tags.
  Validation: targeted analyzer clean, 52 relevant tests pass (first-audio,
  wrong-parent isolation, 150% text, short hero and existing Home behavior),
  formatting and hardcoded-string/raw-error checks pass. The prior full-suite
  result below predates this small addition. These tags were subsequently built
  and installed in `ae237fb`; owner confirmation is pending.
- Final pre-build request: keep the Home line's episode number, scores,
  runtime and air date/year, then append up to two nonempty, distinct genres
  in server order, followed by the age certification (TV-MA, PG, etc.). Moved
  the existing certification to the end rather than duplicating it. Missing
  genres/certification use full item or parent-series metadata through the
  existing cached background rating probe, including when RT is already present.
  Broad Jellyfin listing fields and the playback pipeline are unchanged; this
  lookup is not a prerequisite for playing. Under tight width the existing
  fitted-line policy sheds genres before the core facts. Targeted analysis
  passes and all 37 existing Home/spotlight/metadata tests pass. Subsequently
  built and installed in `ae237fb`; Apple TV owner confirmation is pending.
- Owner could not find a text-size setting because the installed build only
  nudged fixed sizes. Added Settings → Appearance → Home Screen → Home text
  size (85%, 100%, 115%, 130%, 150%). It updates the Home title, metadata/rating
  and synopsis, preserves poster size and does not scale other detail pages.
- Apple TV Home center Select opens movie/show/season details; episode cards
  open their parent show with the episode selected. Physical Play explicitly
  starts/resumes playback regardless of card activation preferences. On a show
  it uses On Deck, or the first unwatched episode; episodes/movies add no
  resolution lookup. Other platforms and normal detail-page actions retain
  their existing behavior.
- Photos show the entire Home info block shrinking/aligning per title. Replaced
  that fitting with fixed, top-aligned logo, metadata and synopsis slots whose
  geometry depends only on viewport and text size. Wider text column (76% of
  viewport) and a broader scrim use the previously empty space for descriptions.
- Owner revised the episode-card request: remove the small synopses below
  thumbnails and show only the focused episode's description in the top panel.
  Removed that extra card band, which restores vertical space to the hero;
  widened its text area and fixed gold stars in its separate TV metadata path.
  The existing focus and full-information sheet behavior remain available.
- Performance: current saved median UI-ready is 238.5 ms; source resolution is
  23–61 ms and most remaining time is between media open and first-frame signal.
  Existing logs do not split demux/track discovery from first-frame decoding.
  Added primary-media-discovered and file-loaded timing markers to the narrow
  rotating trace. No additional speedup is claimed and no speculative decoder,
  seek, buffer or QMS configuration change was made.
- Validation: full Flutter suite passes (8,444 tests, 7 skipped), as do
  analyzer, Dart formatting, strict translation hygiene and hardcoded UI/error
  checks. Native code is unchanged. Generated bindings were regenerated; the
  isolated freshness check passed after source commit `0b58063aa`. These changes
  were subsequently built and installed in `ae237fb` with owner authorization.

## JellyTV episode-start reference (November 14)
- Owner supplied `crucifix86/JellyTV` for startup benchmarking only. Reviewed
  master at `29149d9a2c3b37e83210e44aed6723a065142e0a`; no code was copied,
  no UI/engine port was attempted, and no new device build was started.
- Current source is a .NET 8 / Avalonia Desktop client using its own FFmpeg
  demux/decode pipeline and OpenAL audio. It is not an Apple TV/QMS benchmark.
  README player descriptions differ from the checked-in implementation.
- Selecting an episode constructs `/Items/{id}/Download` locally and opens it
  without a playback-info request. A series first requests its next episode.
  The UI passes `StartTime = 0`; this path does not exercise Plezy's resume seek.
  It still performs FFmpeg input opening and stream-info probing before decoding.
- Its playback-started / AV-started callbacks fire after worker threads start,
  without waiting for a first rendered frame. Those events cannot be compared
  directly with Plezy's first-frame/UI-ready timing. No same-device timing or
  numerical speed ranking was measured.
- Transferable lead: keep episode-to-stream resolution short. Plezy already
  resolves it in 23–61 ms in the saved runs; bypassing that step alone cannot
  explain the old multi-second delay and could lose source/track/resume handling.
  Keep the new discovery/file-loaded markers and measure the remaining open-to-
  first-frame interval before changing buffering, probing or seeking.
- Primary source at the inspected commit:
  [stream URL](https://github.com/crucifix86/JellyTV/blob/29149d9a2c3b37e83210e44aed6723a065142e0a/JellyTV/Services/JellyfinClient.cs#L248),
  [episode selection](https://github.com/crucifix86/JellyTV/blob/29149d9a2c3b37e83210e44aed6723a065142e0a/JellyTV/ViewModels/MainWindowViewModel.cs#L580),
  [zero-position open](https://github.com/crucifix86/JellyTV/blob/29149d9a2c3b37e83210e44aed6723a065142e0a/JellyTV/Controls/VideoPlayerControl.axaml.cs#L241),
  [player startup](https://github.com/crucifix86/JellyTV/blob/29149d9a2c3b37e83210e44aed6723a065142e0a/AvaloniaMediaPlayer/AvaloniaMediaPlayer.Core/Core/VideoPlayer.cs#L63).

## Installed changes in 98c7123d4 (November 13)
- Remote clarification: playback play/pause already works. The missing action
  is pressing Play on a focused Home media card. Home now listens for that
  action and launches/resumes that card directly. It ignores pause-only events,
  inactive/covered routes, non-media action slots, and duplicate pending launches.
- QMS: added an SDR-only fast-start path, enabled by default for this personal
  fork's known LG setup. It keeps preferredDisplayCriteria/frame-rate matching
  active, but releases the manual first-frame pause without waiting for the
  display manager's completion flag. HDR/Dolby Vision and an explicit nonzero
  Display Switch Delay keep the existing wait. The new Playback setting
  “QMS fast start for SDR” can restore waiting on displays that blank.
  This policy uses the owner-confirmed setup, not automatic QMS detection;
  SDR following an HDR output mode may still involve a physical range switch.
  The owner now confirms a major improvement; authenticated traces show
  UI-ready in 195–499 ms for six SDR starts. HDR/DV behavior is not yet verified.
- Native display diagnostics now record requested range/rate/dimensions,
  start/end notifications, pending/in-progress state and release reason at
  info level. Observers are armed before the criteria write, so a switch that
  ends before the first frame cannot cause a fresh full wait; only the remaining
  settle budget is spent. Added native policy tests, not runnable on Linux.
- Compared primary source in Rivulet and AetherEngine: their display controller
  distinguishes SDR cadence changes from HDR waits and observes switches at
  the criteria write. Plezy remains on mpv; no Aether code was copied. A source
  comparison is not a same-device performance benchmark.
  Sources: https://github.com/l984-451/Rivulet and
  https://github.com/superuser404notfound/AetherEngine .
- Home spotlight title/metadata/summary fonts are nudged larger. Show/season
  detail rating badges opt into gold audience stars. The installed build put
  three-line synopses under episode cards; the owner now requests moving them
  to the focused hero instead. The specialized TV hero metadata still needs the
  separate gold-star change in the pending follow-ups above.
- Rotating diagnostics are implemented in app-private storage: four files of
  up to 256 KiB, a bounded asynchronous queue and an allowlist of timing,
  display and remote events. Titles, media/server URLs, tokens and error
  payloads are excluded. They survive ordinary process restarts; tvOS may
  reclaim local file storage. Full application logs remain in memory.
- Settings → Advanced → View Logs has an explicit LAN-sharing control. It
  exposes a read-only private-key URL on the Apple TV (port 18765); enablement
  and key survive relaunch, and Stop Sharing closes the listener. It is
  reachable while Plezy runs on the LAN. The owner must enable it and share
  the displayed URL after installation before the assistant can read it.
  The owner explicitly asked to keep diagnostics network-readable. This needs
  no Unraid logging container;
  after installation, obtain the private LAN link once through View Logs.
  Owner enabled sharing and supplied the private link in a photo. Verified
  HTTP 403 without its key and HTTP 200 with it. Access is retained only in
  `.git/plezy-diagnostics.json` (0600); never commit its key to the repository.
- Validation: full Flutter suite passes (8,436 tests, 7 skipped). Final analyzer,
  Dart formatting, strict translation hygiene, hardcoded-string/error checks,
  workflow/script guards, icon consistency and unused-code/file checks pass.
  Native-format runner cannot run here because JDK 17+ is missing; Swift/Xcode
  native compilation and the new native policy tests are also unavailable on
  this Linux host. Translation bindings were regenerated and the isolated
  generated-file freshness checker passed after commit `e4b4390b6`.
  These changes were subsequently built in `98c7123d4` and installed in
  place at 23:40. Owner subsequently confirmed much faster SDR startup and
  working Home Play; HDR/DV and retained settings are not explicitly verified.

## Earlier built changes / historical investigation
- Home row ordering is stored on this device and accessible via the Home toolbar;
  episode artwork has an E-number badge and the toolbar has a full-description
  dialog. The spotlight uses gold stars and fetches missing Rotten Tomatoes
  ratings for a movie or an episode's parent series when available.
- The tvOS media-key fallback now emits playback actions instead of swallowing
  them, with duplicate suppression. Neither the remote nor these UI changes
  have been verified on the Apple TV.
- Added timestamps for source resolution, player configuration, media open,
  first-frame signal and display-ready gate. The cause of the reported delay
  is not yet established: device timings and matching source/mode are needed.
  Rivulet's AetherEngine uses byte prewarming for the next Plex episode; that
  does not prove the cause of this owner's initial Jellyfin playback delay.
- The owner installed Flutter 3.47.1 on CachyOS at
  `/home/koolo7000/Developer/flutter-3.47.1`; local Dart/Flutter tests can now
  run. tvOS Swift compilation and device tests still require a Mac/Apple TV.
- The card-size setting now offers two larger levels (6 and 7), preserving the
  previous sizes at levels 1–5. The default tvOS launcher icon uses the
  existing blue ocean artwork. Both await an authorized build and owner test.
- The installed unsigned IPA already includes the Top Shelf extension, but the
  owner reports a black shelf. The app and extension hardcode the upstream app
  group. Both Mach-O executables in the unsigned IPA lack a code-signature load
  command, so no entitlement is embedded for a sideload signer to read. Current
  PlumeImpactor source detects groups from executable entitlements and may
  suffix the group with the team ID. Subsequent inspection of the installed
  signed IPA confirmed that both executables lack the app-group entitlement.

## Pending changes after the installed build
- Inspected the signed IPA saved by tvsign: neither main app nor extension has
  the application-groups entitlement, and the app log reports the Top Shelf
  shared container unavailable. Packaging scripts now ad-hoc sign each Mach-O
  with its requested app-group entitlement so tvsign can detect and provision
  it. Both targets select an accessible upstream or team-suffixed group from
  their embedded provisioning profile. Added a profile-selection contract test.
  This candidate was built in `0a77954d6` and successfully signed with the
  owner's account using the patched signer. Top Shelf display awaits owner test.
- The owner confirmed playback starts much faster when Apple TV match settings
  are disabled. Added a candidate early display criteria request for eligible
  direct-play SDR/HDR sources to overlap mode switching with startup, without
  disabling matching. Dolby Vision, transcoding and incomplete metadata skip
  preflight. Incorrect source metadata may still trigger a second switch; the
  result did not improve the owner-observed speed. The installed build now
  distinguishes display negotiation from first-frame effects; log `j1hgqr`
  isolates the measured delay to negotiation. See the QMS candidate above.
- The owner reports the physical play/pause button still does nothing. The
  player previously discarded Apple TV system media-control playback events;
  these now enter the existing cross-source duplicate guard with play and pause
  intent preserved. Added focused tests and an info-level remote action log.
  Focused remote tests pass; the owner now confirms playback play/pause works.
  Their missing Home Play shortcut is a separate new local change above.
- Local CI checks exposed poster-row overflows and context-menu initialization
  problems. Corrected the layout and settings initialization, aligned TV size
  test expectations with the new default, formatted Dart, normalized missing
  translation keys and regenerated translations. Analyzer, formatting,
  translations, icon consistency, unused-code/file checks, CI guards, the
  bundled Linux and Windows preferences tests (26 each) and wakelock tests (8)
  pass. Generated outputs match a fresh generation; the standard codegen
  checker passed after the generated files were committed. The full Flutter suite
  passed: 8,432 tests, 7 skipped. Chrome-specific tests need Chrome, which is
  not installed here; tvOS native tests and device behavior remain unverified.
- The owner explicitly forbids deleting/uninstalling the app for future updates.
  The earlier in-place installation stalled; its cause is unknown and a future
  update preserving app data still needs proof. Inspection of the local signed
  IPA shows that tvsign adjusted the original bundle identifier; keep the same
  account, signing identity and existing app entry, and verify actual signed
  identifiers before an update attempt. Newer upstream tvsign documentation
  describes a Replace the IPA action, but the installed version previously did
  not expose it; no Unraid update is authorized. Do not try deletion as a fix.
- Owner requests bounded rotating diagnostics readable without manual uploads,
  without repeated manual uploads. Full app logs are a 5 MiB in-memory ring.
  App-private rotating playback diagnostics and an opt-in authenticated
  read-only LAN endpoint are implemented locally above, not installed yet.
  No Unraid receiver is authorized or required. Do not expose full logs,
  Apple sessions, Jellyfin tokens, or a writable endpoint on the LAN.
- Owner explicitly forbids any Unraid changes without permission for the
  specific change, and forbids all Unraid deletion. The earlier IPA backup,
  staging and replacement modified Unraid; no further change is authorized by
  the logging request alone. Never delete the staging files or backups there.

## Playback testing
Record the app commit, source video profile, audio format, and what the LG
and Denon report. Evaluate AetherEngine after testing the stock build.

## Notes / decisions
- Wholphin's merged PR #915 adds a collection or playlist as a home row by
  finding it in a search dialog. Plezy's equivalent stores collection IDs
  locally and builds rows from the existing server collection endpoint.
- Rivulet's speed goal is not yet a measured comparison. Plezy already starts
  online playback-data resolution in parallel with mpv setup, then waits for
  resolution, subtitle selection, and the player open path. Record phase times
  before removing any correctness or display-matching gates.
- AetherEngine stream-copies AC3/E-AC3 where supported. Apple TV's default Auto
  mode decodes to the best supported output, commonly multichannel PCM; its
  Dolby Digital 5.1 option re-encodes to DD and Apple recommends that only when
  the connected equipment lacks Atmos or multichannel PCM. Verify the X3800H's
  reported format with the owner before claiming a pass-through result.
- References: [Wholphin PR #915](https://github.com/damontecres/Wholphin/pull/915),
  [Rivulet](https://github.com/l984-451/Rivulet),
  [AetherEngine formats](https://github.com/superuser404notfound/AetherEngine/blob/main/docs/formats.md),
  and [Apple TV audio settings](https://support.apple.com/guide/tv/change-audio-settings-atvba773c3c9/tvos).
- The previous Codemagic device build is installed and owner-tested. The newer
  successful `0a77954d6` build was installed in place but is not yet owner-tested.
- Run `43454148475` was started by a branch-limited push trigger on
  `codex/first-tvos-test-build`; the workflow is back to manual dispatch only
  for subsequent builds. It ended without any build steps running. The sideload
  workflow now targets the valid `macos-15` label.
- The pinned tvOS engine release contains only the ARM64 host
  `gen_snapshot`; an Intel macOS runner is not compatible with this bundle.
  Keep the sideload job on a GitHub-hosted ARM64 macOS runner while waiting for
  runner capacity.
- Run `43459871032` used a valid `macos-15` label, but GitHub's annotations
  report it was not acquired after multiple attempts because of macOS ARM64
  capacity constraints. Run `43462680240`, which used the same runner pool,
  was cancelled by us without starting. Do not dispatch the same job again
  until a different ARM64 Mac capacity route is available. GitHub larger
  runners require a Team or Enterprise organization. References:
  https://docs.github.com/en/actions/reference/runners/github-hosted-runners
  https://docs.github.com/en/actions/how-tos/manage-runners/larger-runners/use-larger-runners.
- Codemagic documents a personal free tier with 500 monthly M2 build minutes.
  The prepared workflow follows the existing unsigned IPA steps. Its YAML was
  parsed locally; the first Codemagic build identified a Dart compilation error.
  https://docs.codemagic.io/billing/pricing/
