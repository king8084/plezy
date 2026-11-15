
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

Keep personal addresses, device names and installation receipts out of tracked
files. Preserve private installation history under `.git/plezy-private/`.

Do not start an Apple TV build until the owner explicitly says “build apple tv”.
Do not delete or uninstall the owner's Apple TV app as an update workaround.
Preserve the installed app and its data; investigate a non-destructive update.
Never change anything on the owner's Unraid server without their explicit
permission for that change. Never delete anything on Unraid.

Before installing an Apple TV update, keep the TV awake in Apple TV Settings
with Plezy closed. On November 13, an in-place update stalled on Home despite
the app being closed, then completed when the owner entered Settings. Home /
Top Shelf activity is the likely blocker; do not use deletion as a workaround.

The private Apple TV diagnostics URL is saved locally in
`.git/plezy-diagnostics.json` (0600). Read it only for authorized playback
troubleshooting while Plezy is running; never copy its key into tracked files,
commits, public links or build logs. No manual log upload is needed while
that protected LAN endpoint is reachable.

Before reporting that LAN diagnostics are unreachable, retry a failed sandboxed
connection with network permission. On November 14 the sandboxed request failed
but the same saved URL returned HTTP 200 immediately outside the sandbox. Do
not ask for a new link or blame an app update without checking the actual failure.
