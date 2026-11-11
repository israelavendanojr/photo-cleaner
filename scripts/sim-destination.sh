#!/usr/bin/env bash
# Prints an xcodebuild destination for the first available iPhone simulator, the same one CI picks,
# so a new Xcode or runner image doesn't break a hard-coded device name.
# Set DEST to use another one, e.g. DEST='platform=iOS Simulator,name=iPhone 16'.
set -euo pipefail

if [[ -n "${DEST:-}" ]]; then
    echo "$DEST"
    exit 0
fi

command -v jq >/dev/null || { echo "sim-destination: jq not found (brew install jq)" >&2; exit 1; }

udid=$(xcrun simctl list -j devices available \
    | jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .value[] | select(.name | startswith("iPhone"))][0].udid')

if [[ -z "$udid" || "$udid" == "null" ]]; then
    echo "sim-destination: no available iPhone simulator (xcrun simctl list devices available)" >&2
    exit 1
fi

echo "platform=iOS Simulator,id=$udid"
