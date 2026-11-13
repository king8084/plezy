# tvsign 1.0.2 signing candidate

`tvsign-1.0.2-app-groups.patch` applies to the official tvsign v1.0.2 source
at commit `17b57b4bcae160cee1263b205cb170e700383a7f`. It changes the vendored
Impactor signer; it does not modify Plezy's bundle identifier or Apple account.

The signer provisions the main app and extensions concurrently. Both can look
up the same missing group and attempt to create it, producing Apple error 35.
It also compares opaque group resource IDs with a group identifier when deciding
whether the default group needs creation. The observed error is consistent with
these flaws; it does not establish that they are the only cause of the refusal.

The patch:

- Provisions bundles sequentially, avoiding concurrent creation of shared groups.
- Compares group identifiers before requesting a duplicate default group.
- On error 35, looks up the exact identifier again for the same team. It only
  recovers if that group is now present, otherwise it returns Apple's error.
- Tests recovery, an unrelated group, and a still-missing group against a local
  fake developer API. The test uses no Apple account or external API.

Validated locally: `cargo check --locked -p plumesign` and
`cargo test --locked -p plume_core --lib app_group_conflict_recovers_only`.
The test passed all three response scenarios. The owner deployed the patched
binary, and tvsign successfully signed and installed the existing Plezy IPA
in place at 22:45 on November 13, 2026. The original signer is preserved as
`ipas/1/plumesign-before-group-fix`. The owner subsequently confirmed working
Top Shelf and playback; startup remains slow and is tracked separately.

Apply from a matching tvsign source checkout with:

```sh
git apply --check /path/to/tvsign-1.0.2-app-groups.patch
git apply /path/to/tvsign-1.0.2-app-groups.patch
```

Build a binary for tvsign's Debian runtime with its official Dockerfile's
`rust-build` stage, then preserve the original signer before deploying the new
one. A CachyOS native binary must not be assumed compatible with that runtime.
Local Docker requires administrator access here. After explicit authorization,
the owner built the binary and ran the deployment block on Unraid. The patched
binary has SHA-256
`762c5b1beaac69594e4484ca5273924415dee237ce5c8bf425658c3215f0fabd`.
Replacing the Docker container from its upstream image may restore the original
signer; this manual replacement does not modify the upstream container image.

Any Unraid deployment and subsequent installation require specific owner
authorization. Preserve all existing files and the installed Apple TV app.
The already-built Plezy IPA can be used after a compatible signer is prepared;
changing this signer does not itself require rebuilding Plezy.
