#!/bin/bash
# Explicit allowlist: do not copy the working directory or generated binaries.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
COPYFILE_DISABLE=1 /usr/bin/tar --uid 0 --gid 0 --uname root --gname wheel \
  -czf dist/notification-relay-source.tar.gz \
  Package.swift README.md .gitignore Sources/notification-relay/*.swift \
  Tests/notification-relayTests/*.swift \
  scripts/build-app.sh scripts/export-source.sh docs/REVIEW.md
printf 'Created dist/notification-relay-source.tar.gz (source only; not published)\n'
