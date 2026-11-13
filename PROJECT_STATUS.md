# Plezy tvOS project

Personal Jellyfin client fork developed on CachyOS with the ChatGPT desktop app.
Playback setup: Apple TV 4K, LG C6H, and Denon AVR-X3800H.

## Current status
Personal tvOS changes are in progress on top of the stock Plezy fork. A manual
macOS GitHub Actions workflow now packages an unsigned tvOS IPA for tvsign. The
official tvsign container is installed on Unraid at
`192.168.100.46:8765` and reports healthy; the owner reports tvsign setup and
Apple TV pairing are complete. No device IPA build, Apple TV install, or
owner-confirmed playback has happened yet. The standard CI workflow is queued
for the latest main commit.
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
  playback path. Rivulet documents AC3/E-AC3 stream-copy into tvOS, but Apple
  TV does not expose raw compressed bitstream output to third-party apps;
  output format is mediated by tvOS and the selected Apple TV audio settings.
  TrueHD/DTS are decoded to PCM unless optional AetherEngine object rendering
  is used. First-frame startup needs timing on the same source/device before
  choosing a change.

## Milestones
- CI build: standard fork CI queued; device IPA run `43454148475` was cancelled
  while waiting for its `macos-26` runner. GitHub returned no executed steps,
  build logs, or IPA artifact. Replacement run `43459871032` was also cancelled
  before runner assignment; fresh run `43462680240` is queued on the stable
  `macos-15` ARM runner, with no build steps started yet.
- tvsign on Unraid: installed and healthy, using
  `/mnt/cacheapp/appdata/docker/tvsign`; first-run setup complete, Apple ID
  signed in, and Apple TV pairing complete.
- Install on Apple TV: not done; planned through tvsign after the IPA build.
- Owner-confirmed playback: not done.

## Next milestone
Keep tvsign on Choose an app while run `43459871032` waits for a runner. When
the workflow succeeds, add Plezy through “Other app…”, then install it on the
paired Apple TV. Confirm startup, sign-in, and playback, and record the app
commit plus video/audio details. Capture open-to-first-frame timings for
representative direct-play files before changing the player.

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
- No build or tests run for these edits. The current environment does not have
  the Dart executable available, so Dart formatting/code generation is also
  pending.
- Run `43454148475` was started by a branch-limited push trigger on
  `codex/first-tvos-test-build`; the workflow is back to manual dispatch only
  for subsequent builds. It ended cancelled before any build steps ran. The
  sideload workflow now targets `macos-15`; run `43459871032` was dispatched
  manually from the updated branch and remains queued without build logs.
- The pinned tvOS engine release contains only the ARM64 host
  `gen_snapshot`; an Intel macOS runner is not compatible with this bundle.
  Keep the sideload job on a GitHub-hosted ARM64 macOS runner while waiting for
  runner capacity.
- Run `43459871032`, checked 2026-11-13, was cancelled after 15 minutes with
  no runner assigned, steps, or logs; the run record does not expose why it
  was cancelled. Fresh run `43462680240` is queued. Both workflow commits use
  the documented `macos-15` ARM64 hosted-runner label, so this is not the
  invalid-label case described in the older community thread. Reference:
  https://docs.github.com/en/actions/reference/runners/github-hosted-runners.
