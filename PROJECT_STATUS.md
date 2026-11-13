# Plezy tvOS project

Personal Jellyfin client fork developed on CachyOS with the ChatGPT desktop app.
Playback setup: Apple TV 4K, LG C6H, and Denon AVR-X3800H.

## Current status
Installed build `0a77954d6` was updated in place through the existing tvsign
entry on November 13 at 22:45; no deletion/uninstallation was performed.
The owner confirms working Top Shelf Continue Watching and playback play/pause.
Startup still takes about four seconds. New changes below are local only;
no new Apple TV build has been authorized for them.

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
Local app changes are committed as `e4b4390b6`; signer preservation/history is
committed as `9d30e24cd`. Local Dart/Flutter checks and generated-file freshness
pass. Next is an explicitly authorized device build, followed by an in-place
installation and separate owner confirmation of QMS startup and Home Play.
A further Apple TV build requires the owner to explicitly say “build apple tv”
again. Keep the existing tvsign entry/account and preserve the installed app.
CI success, installation and owner-confirmed playback remain separate milestones.
The owner has no Mac, so native compilation and on-device timing remain pending.

## Local changes after the installed build (November 13)
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
  This is an implemented candidate, not an Apple TV timing result.
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
  detail rating badges now opt into gold audience stars. Episode cards in the
  Apple TV detail rail show a three-line synopsis, respect Hide Spoilers and
  reserve layout space even with full-card styling selected.
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
  The installed build has none of this yet. No Unraid change was made or
  authorized for diagnostics.
- Validation: full Flutter suite passes (8,436 tests, 7 skipped). Final analyzer,
  Dart formatting, strict translation hygiene, hardcoded-string/error checks,
  workflow/script guards, icon consistency and unused-code/file checks pass.
  Native-format runner cannot run here because JDK 17+ is missing; Swift/Xcode
  native compilation and the new native policy tests are also unavailable on
  this Linux host. Translation bindings were regenerated and the isolated
  generated-file freshness checker passed after commit `e4b4390b6`.
  No CI build, installation or owner playback verification exists for these
  local changes.

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
