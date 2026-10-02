# Notification Relay

A macOS menu bar app that reads Notification Center, filters notifications, and
passes matching items to a script or executable you choose. No account or network
service is built in.

## Setup

1. Open **Notification Relay.app**. On a fresh installation, Settings opens and
   monitoring stays paused.
2. In **Settings**, choose your executable relay script. It must be executable and
   have a valid shebang, or select an interpreter and supply the script as an argument.
3. Configure include/exclude rules. No include rules means all applications are
   eligible; exclusions always win. Review this before enabling monitoring.
4. Grant the installed app **Full Disk Access** in System Settings → Privacy &
   Security, then quit and reopen it.
5. Enable monitoring and save Settings. The bell menu shows status, the last
   successful check, errors, and Quit.

Full Disk Access cannot be granted by the app itself. Signing is ad hoc for local
use; no paid developer account is needed. A rebuilt app may need its permission
removed and re-added.

## Settings and storage

The Settings window edits a draft; Save validates and writes it atomically.
Closing or cancelling without saving leaves the active configuration unchanged.
Settings cover monitoring, polling interval, lookback, batch size, relay executable,
arguments, stdin format, working directory, environment, rules, summary formatting,
and advanced database/checkpoint paths.

Configuration and checkpoint state live outside the app bundle:

- `~/Library/Application Support/Notification Relay/config.json`
- `~/Library/Application Support/Notification Relay/state.json`

An existing `~/.config/mac-notifications/config.json` is imported on first use if
the new configuration does not exist. The legacy default checkpoint is copied to
the new location; an explicitly configured custom checkpoint is preserved.
Legacy files remain untouched as backups. Once the new configuration exists, it
takes precedence. Corrupt or unreadable existing data produces an error rather
than silently resetting forwarding history.

Defaults: monitoring paused, no relay selected, JSON stdin, no arguments, 60-second
polling, 30-minute lookback, and batches of up to 50 matching notifications.
A lookback of zero scans all stored notifications. There are no default app-specific
filters. Existing configurations retain their settings.

The app reloads saved settings between polling passes. Changes may take up to the
current polling interval to apply; an already-running relay is not cancelled.

## How it works

Each pass opens macOS Notification Center's SQLite store read-only, scans the
lookback window oldest first, skips already-forwarded IDs, and applies filters.
The batch limit applies after filtering and deduplication. Matching items are sent
to one configured relay. IDs are checkpointed only after the relay exits successfully.
IDs for notifications no longer in the database are pruned.

This uses a private database schema and payload format, not a supported API for
reading other applications' notifications. macOS updates may break compatibility.
It does not read email inboxes or chat histories directly, and cannot retrieve
notifications that are no longer stored.

The menu bar remains responsive while the database and relay work runs off the
UI thread. Run only one monitor against a checkpoint to avoid duplicate delivery.
A crash, partial relay success, or failed checkpoint write can cause retries.

## Rule semantics

Include rules are ORed. Exclusion rules are ORed and take precedence.
Within one rule, configured fields are ANDed; matchers within a field are ORed.

- Bundle identifiers match exactly, including case.
- Title, subtitle, body, category, and thread ID each support multiple matchers.
- Any field searches title, subtitle, and body.
- Matcher types: contains, equals, prefix, suffix, regex.
- Text matching defaults to case-insensitive contains.
- Invalid regexes prevent saving.
- A rule with no conditions matches everything. An empty include list includes all.

## Relay interface

The relay is generic and selected in Settings. No assistant-specific integration
is required or shipped in the source export.

Arguments are passed directly without shell parsing. Each argument can contain
`{{summary}}`, `{{json}}`, or `{{count}}`. Stdin can be JSON, summary, or none.
JSON stdin is recommended. Optional working directory and environment values
can be configured. Finder does not load shell profiles; the app adds standard
Homebrew executable directories to PATH. Other interpreter locations require
a configured PATH or an absolute interpreter path.

For compatibility, the process also receives:

- `MAC_NOTIFICATIONS_JSON`
- `MAC_NOTIFICATIONS_SUMMARY`
- `MAC_NOTIFICATIONS_COUNT`

JSON is an array containing recordID, bundleIdentifier, and optional title, subtitle,
body, category, threadIdentifier, sourceIdentifier, systemUUID, deliveredAt, and
requestedAt. Missing fields are omitted; dates are ISO 8601. Empty batches do not
invoke the relay. Exit code zero means success.

Stdout/stderr are inherited. Relay stdin uses an immediately unlinked file in a
private temporary directory to avoid broken pipes. Large payloads can still exceed
the OS environment/argument size limit; reduce the batch size if that occurs.
The relay should implement its own network timeouts and idempotency.

## Build and command line

Requires macOS and Swift 6.3 or later. macOS 13 is the deployment target; the private
Notification Center schema must be verified on each OS version.

```bash
swift test
bash scripts/build-app.sh
mkdir -p ~/Applications
ditto "dist/Notification Relay.app" "$HOME/Applications/Notification Relay.app"
open "$HOME/Applications/Notification Relay.app"
```

CLI commands share the app's default configuration, including migration:

```bash
swift run notification-relay help
swift run notification-relay sample-config
swift run notification-relay print-json
swift run notification-relay run --once
swift run notification-relay run --config /absolute/path/to/config.json
```

The sample config is paused with a blank executable. CLI run respects monitoring
enabled; print-json previews without invoking the relay or advancing state.
`--reset-state` deliberately clears history and may cause duplicate delivery,
including when supplied to print-json. Do not run CLI polling alongside the app.

## Troubleshooting

- **Needs Full Disk Access:** grant it to the installed app and restart it.
- **Paused:** select a relay script and enable monitoring in Settings.
- **Relay not executable:** check its permissions and interpreter/shebang.
- **No matches:** check filters, time window, and checkpoint history.
- **Configuration error:** correct invalid regexes or values. Migration errors preserve
  original files; do not delete checkpoints without considering duplicate sends.
- **Database query error:** the macOS private schema may have changed.

## Privacy and sharing source

Notification text can contain private messages. The app reads locally; your relay
determines where it goes. Treat configurations, output, logs, screenshots, and
relay environments as private. Checkpoints store identities, not message bodies.
Configuration files use owner-only permissions.

Keep personal relay integrations outside the source tree, for example under
`~/Library/Application Support/Notification Relay/Relays/`.

```bash
bash scripts/export-source.sh
tar -tvf dist/notification-relay-source.tar.gz
```

The source export uses an explicit allowlist and generic ownership metadata. Never
upload the entire working directory or compiler artifacts, which can include local
paths and private files. No license has been selected; the repository is private.
See [review notes](docs/REVIEW.md) for remaining limitations and validation.
