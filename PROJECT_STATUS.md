# Plezy tvOS project

Personal Jellyfin client fork developed on CachyOS with the ChatGPT desktop app.
Playback setup: Apple TV 4K, LG C6H, and Denon AVR-X3800H.

## Current status
Personal tvOS changes are in progress on top of the stock Plezy fork. A manual
macOS GitHub Actions workflow now packages an unsigned tvOS IPA for tvsign. The
official tvsign container is installed on Unraid at
`192.168.100.46:8765` and reports healthy; the owner reports tvsign setup and
Apple TV pairing are complete. Codemagic produced an unsigned device IPA and
tvsign reports successful signing and installation on Basement. The owner has
reported playback on the TV with approximately four seconds of startup delay.
The standard CI workflow
was previously queued for the latest main commit.
Commit `606fc715b` is pushed to `king8084/plezy` on `main`.

Upstream inspection: CI prepares Flutter 3.47.1 and the separately pinned tvOS
engine, installs CocoaPods, then runs the Runner native reliability tests on a
tvOS simulator. The upstream release workflow does not build or publish a tvOS
IPA, so producing a stock device build will need a fork-side macOS workflow.

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
  Basement and shows the app up to date. Owner confirmation on the TV is pending.
- Owner-confirmed playback: reported by the owner; startup is about four
  seconds versus about 0.5 seconds in Rivulet. Media details are not yet known.
- Pinning collections: the owner reports not seeing the option. The installed
  build places “Pin collection to Home” in the collection card's long-press
  context menu; actual behavior on the Apple TV still needs owner confirmation.

## Next milestone
Wait for the owner to explicitly say “build apple tv” before starting any Apple
TV build. After the next build and install, verify the home changes and remote
on the TV, then collect startup timings for the same file and playback mode as
Rivulet. The owner has no Mac; builds can use the connected Codemagic workflow.

## Unbuilt changes requested by the owner
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
- Added focused tests for the remote-key fallback and gold audience star, but
  Flutter and Dart are unavailable locally, so they have not been run.
- The card-size setting now offers two larger levels (6 and 7), preserving the
  previous sizes at levels 1–5. The default tvOS launcher icon uses the
  existing blue ocean artwork. Both await an authorized build and owner test.
- The installed unsigned IPA already includes the Top Shelf extension, but the
  owner reports a black shelf. The app and extension hardcode the upstream app
  group. Both Mach-O executables in the unsigned IPA lack a code-signature load
  command, so no entitlement is embedded for a sideload signer to read. Current
  PlumeImpactor source detects groups from executable entitlements and may
  suffix the group with the team ID. The installed signed app's entitlements
  remain unverified. Added an unavailable-container diagnostic; the shelf is
  not yet fixed. Inspect the signed app and exact tvsign signer version, then
  determine how both targets can share an authorized group before changing
  signing. Never log server credentials.

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
- No local build or tests were run for these edits. The current environment does
  not have the Dart executable, so local formatting/code generation is pending.
  The Codemagic device build succeeded; owner testing is still pending.
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
