# Personal tvOS release process

## Validation and checkpoints

Work on `codex/first-tvos-test-build`. Keep a known-good installed source commit
and an independent local backup before starting a release. A Git bundle preserves
history and refs without depending on the continued existence of an upstream
repository. Keep it private: earlier history can contain environment details.

Run `bash scripts/check_tvos_release.sh` on the candidate. Generated outputs must
be committed before the freshness check can pass. The branch also runs the full
sanity CI workflow, including platform-native reliability jobs. Treat source
checks, native tests, IPA archive, installation and owner playback confirmation
as separate checkpoints. Never describe one as proof of another.

After changing strings, clean translations and run `scripts/codegen.sh`; include
all generated changes. Preserve the approved TV layout with the existing real-size
Home/detail/rail regressions. Keep TV-only changes in small helpers where possible.

## Recovery materials

Keep private copies of:

- The full Git bundle and latest source checkpoint, including local changes.
- The pinned tvOS engine archive, verified against `tvos/engine.sha256`.
- The known-good unsigned IPA, its checksum, and the prior install receipts.
- The signer source revision and patch documented in `tvos/patches/README.md`.

Record SDK and dependency versions from the checked-in workflow, lockfiles and
engine metadata. A source backup alone does not preserve a remotely hosted engine
binary. Store credentials and diagnostics links separately from all source exports.
For disk-loss protection, copy the private recovery directory to an independent
drive or backup destination; another folder on the same disk cannot provide that.

Restore source with `git clone /path/to/recovery.bundle plezy-restored`, then
check out the recorded source ref. Verify the engine and IPA checksums before use.
Restore dependencies from their lockfiles and rerun release checks. Do not claim
that an unsigned IPA alone can reinstall without valid signing/provisioning.

## Device release

An explicit owner request to build Apple TV is required before archiving an IPA.
Unraid actions require authorization for that build. Preserve previous IPA/signer
files; never delete or uninstall the app to work around an update failure.
Check the deployed signer checksum before renewal. Install in place using the
existing app identity, with the app closed and Apple TV awake in Settings.

Record archive, installation, retained settings, visual approval and tested
playback formats independently. Confirm visible HDMI behavior before changing
QMS defaults; a switch notification by itself does not establish a visible blank.

After all release checks pass, advance the owner's fork main through a normal
fast-forward or reviewed merge. Preserve history; never reset it to hide failures.
