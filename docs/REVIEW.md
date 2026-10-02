# Review and release preparation

## Changes from the local prototype

- Generic bundle identifier (`local.notification-relay.app`), without a person's name.
- Local art-generation runs, private relay helpers, test configuration, build products,
  environment files, and logs excluded from version control.
- Explicit source-export allowlist, avoiding accidental inclusion of local binaries or data.
- Batch limit applies after filtering and deduplication. Previously an early page of
  already-forwarded or excluded records could indefinitely hide later matching records.
- Checkpoint corruption or read errors fail visibly instead of silently replaying notifications.
- Relay output inherits stdout/stderr instead of filling unconsumed pipes and blocking.
- Relay stdin uses an immediately unlinked temporary file in a private directory,
  avoiding broken pipes when a relay exits without reading its input.
- Invalid filter regexes reject configuration instead of silently disabling exclusions.
- Source archive owner/group metadata is normalized to generic values.
- Synthetic regression tests cover checkpoint handling and batch progression without real notifications.
- Settings edits relay, rules, polling, summary, and storage options without JSON editing.
- Configuration/state migrate non-destructively to Application Support; fresh installs
  are paused until a relay is configured and monitoring enabled.
- Personal relay integrations are stored outside the project tree.

## Remaining improvements

1. Relay timeout and cancellation: a relay that never exits still blocks its polling pass.
   The menu remains responsive, but quitting the app does not guarantee termination of
   a relay's child processes. Use a relay that has its own network timeouts.
2. Cross-process locking: run one monitor per checkpoint. The CLI and app must not poll
   simultaneously; currently they could both forward the same notification.
3. Delivery semantics: checkpoint updates follow successful relay execution. Partial relay
   success, crashes, or a checkpoint write failure can cause retries. A relay should deduplicate
   using `systemUUID` (or the bundle identifier and record ID when unavailable).
4. Diagnostics: relay stderr is not captured in the menu's error details. A synthetic
   relay test button and installed-app picker for bundle IDs would improve setup.
5. Notification Center compatibility: schema and payload formats are private implementation
   details. Test each supported macOS version; malformed payloads can yield empty text fields.
6. Query cost: the reader streams rows until enough unsent matches are found; it may scan
   the entire lookback window. It also scans existing IDs to prune the checkpoint.
7. Payload size: JSON and summary are exported in environment variables even with file-backed
   stdin. Large batches can exceed the OS process-launch argument/environment limit. A future
   stdin-only relay mode should omit those variables; meanwhile reduce the batch size.

## Before public release

- Test Finder launch, menu status, Quit, permission denial, and granting Full Disk Access
  on an actual desktop session. These checks are still pending for the menu bar build.
- Test a real relay separately, with non-sensitive test notifications.
- Choose a license before publishing; no license has been selected on the owner's behalf.
- Review the exact staged files and commit author/email before creating public commits.
  `.gitignore` does not remove secrets already committed or sanitize Git author metadata.
- Export source with `bash scripts/export-source.sh` and inspect the archive. Do not upload
  a zip of the working directory, `.build`, `dist` app binaries, or the installed app.
  Compiler artifacts can contain local paths even when source is generic.
- Review any additional relay scripts, configurations, logs, screenshots, or generated
  assets separately. Local exclusions are not a claim that those files are anonymous.
- Ad hoc signing is for local builds. A public downloadable app needs a separate distribution
  and signing decision; the source export makes no notarization claims.

The source repository is private. Public release remains deferred.

## Validation status

The Settings update passed all 14 migration and regression tests. The release app
build and ad hoc signature verification passed, and the installed app launched.
Local migration preserved rules and checkpoint IDs and relocated the private relay.
Settings interaction, Full Disk Access, and real forwarding still need desktop validation.
Shell syntax and source export were checked. The source archive was inspected for
local username/hostname, absolute home paths, email addresses, and ownership metadata;
that scan found no matches. This check covers the source archive, not ignored private
files, existing installed apps, or old build artifacts.
