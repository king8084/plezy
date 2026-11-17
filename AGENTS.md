
## Personal tvOS fork

Read PROJECT_STATUS.md at the start of each task. Check the current branch and
recent commits. After meaningful changes, update the handoff with decisions,
test results, unresolved issues, and the next step. Track CI builds, installs
on the Apple TV, and owner-confirmed playback as separate milestones.

When user-facing strings change, run
`python3 scripts/checks/clean_translations.py --clean`, then
`scripts/codegen.sh`, and include the generated outputs with the change.
Before a release, require strict translation hygiene, generated-file freshness,
formatting, analysis and the full Flutter suite to pass. Record native CI,
device installation and owner playback confirmation separately; an IPA archive
alone does not establish that the release checks passed.
Check Code Analysis, Unit Tests and Apple native reliability (tvOS) on the
candidate in the owner's fork before starting its device archive.

Keep personal addresses, device names and installation receipts out of tracked
files. Preserve private installation history under `.git/plezy-private/`.

Do not start an Apple TV build until the owner explicitly says “build apple tv”
or, equivalently (owner, Nov 17), “build app”.
Do not delete or uninstall the owner's Apple TV app as an update workaround.
Preserve the installed app and its data; investigate a non-destructive update.
Never change anything on the owner's Unraid server without their explicit
permission for that change. Never delete anything on Unraid.

Never delete, edit, overwrite, rename, or move the owner's video files or
Jellyfin-managed files, including its existing databases, configuration,
metadata, artwork, subtitles, and media sidecars. For search/indexing work,
read metadata through Jellyfin's API; do not use metadata-management, refresh,
or deletion operations to alter the source library.
The owner permits additive creation of separate Plezy-owned search/index
files and databases within the agreed task. Keep them in a dedicated folder,
separate from existing Jellyfin files; maintain only these Plezy-owned additions
and never overwrite an existing unrelated path. This permission does not
authorize changing containers, Jellyfin settings, or unrelated Unraid services.
For Jellyfin search/index work, the only authorized server write location is
the owner's dedicated smartsearch directory. Its exact Unraid and CachyOS-mount
paths are recorded privately in `.env.plezy-search-scope.json`; read and enforce
that scope before writing. Do not write to its parent or any sibling folder.
Use unique additive pilot directories and preserve all existing files. Do not
open a live writable SQLite database across the network mount: build locally
and copy a closed snapshot, or run the eventual writer locally on Unraid.
Keep test credentials in a private ignored local file, never in tracked files
or tool output. Initial testing is a bounded metadata/Ollama pilot, not an
automatic full-library index or Apple TV build.
Preserve indexing pilot data as a seed for the eventual full database, not a
throwaway benchmark. Reuse metadata and document/query embeddings when the
document hash, model digest and preprocessing version match. Save completed
batches and retain immutable snapshots; never regenerate unchanged descriptions
merely because the inventory grows or an update event is replayed.
The intended permanent indexer/database live on Unraid and call the configured
Ollama host for inference. New-item events update text first and queue embeddings
separately, with reconnect reconciliation. Flag missing/known placeholder
descriptions for a daily metadata-only recheck; resolve the flag when a real
description arrives and embed only the changed text. A pilot does not install
a permanent background service or scheduler automatically.
On November 16 the owner approved the full-library index and an always-on
service in one dedicated Docker container (`plezy-smartsearch`) that the owner
creates by pasting a reviewed command. It writes only to `smartsearch/live`;
code, config and models are mounted read-only. Never delete anything on
Unraid that the agent did not create itself: the owner's files, media,
Jellyfin-managed files and earlier pilot folders are never deleted. The owner
clarified (Nov 17) that the agent may remove things it created itself (its
own probe files, its own containers). Keep SQLite side files intact anyway:
use PERSIST journals there (never WAL), write status files in place, and
update code by reloading the mounted folder. Stage files locally and copy only
finished files to the share.
Search evidence must preserve the query's characters, show, actor/patient roles
and additional conditions. A matching quote, vector score or single model vote
is not sufficient confirmation. Use the current verifier entry point; never
fall back silently to the historical batch checker. Keep uncertain candidates
as possible matches instead of asserting facts or dropping valid search hits.
Cache raw checks by source/input/model identity, reapply the current policy,
and preserve failed evaluations. Verification work must not re-embed unchanged
library items or hold up ordinary search results.

For installs the owner allows adding and editing files only inside the tvsign
appdata folder (`/mnt/unraid_appdata/docker/tvsign/` on this PC's mount):
back up `original.ipa`/`signed.ipa` as new `*-before-<sha>.ipa` files, add
`Plezy-<sha>.ipa`, replace `original.ipa`, then Renew through tvsign's API
using the private, git-ignored `.env.plezy-release-access.json`. Never open
tvsign's live database across the mount. Fork Actions are currently disabled;
note when CI could not run.
Before installing an Apple TV update, keep the TV awake in Apple TV Settings
with Plezy closed. On November 13, an in-place update stalled on Home despite
the app being closed, then completed when the owner entered Settings. Home /
Top Shelf activity is the likely blocker; do not use deletion as a workaround.

The private Apple TV diagnostics URL is saved locally in
`.git/plezy-diagnostics.json` (0600). The owner allows reading it whenever they
ask for debugging of any kind (Nov 17), while Plezy is running; never copy its key into tracked files,
commits, public links or build logs. No manual log upload is needed while
that protected LAN endpoint is reachable.

Before reporting that LAN diagnostics are unreachable, retry a failed sandboxed
connection with network permission. On November 14 the sandboxed request failed
but the same saved URL returned HTTP 200 immediately outside the sandbox. Do
not ask for a new link or blame an app update without checking the actual failure.
