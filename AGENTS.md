
## Personal tvOS fork

Read PROJECT_STATUS.md at the start of each task. Check the current branch and
recent commits. After meaningful changes, update the handoff with decisions,
test results, unresolved issues, and the next step. Track CI builds, installs
on the Apple TV, and owner-confirmed playback as separate milestones.

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
