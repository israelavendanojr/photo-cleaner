#!/usr/bin/env bash
# Claude Code PostToolUse hook (Edit|Write): runs SwiftFormat on the one .swift file just edited.
#
# Only files that were already formatted at HEAD, or are new, get formatted. Reformatting a legacy
# file on its first edit would bury the real change in format noise; for those it prints a hint.
# Never fails the edit: a missing tool or a SwiftFormat error just prints a line and exits 0.
# Off for a session: BRISTLE_HOOKS_OFF=1 (all hooks) or BRISTLE_FORMAT_OFF=1 (this one).

[ -n "${BRISTLE_HOOKS_OFF:-}${BRISTLE_FORMAT_OFF:-}" ] && exit 0
command -v jq >/dev/null || exit 0

path=$(jq -r '.tool_input.file_path // empty')
[[ "$path" == *.swift && -f "$path" && "$path" != */photo-swiper-context/* ]] || exit 0

if ! command -v swiftformat >/dev/null; then
    echo "format-edited: swiftformat not installed (brew install swiftformat); $path not formatted" >&2
    exit 0
fi

dir=$(dirname "$path")
rel=$(git -C "$dir" ls-files --full-name -- "$path" 2>/dev/null)
if [ -n "$rel" ] && git -C "$dir" cat-file -e "HEAD:$rel" 2>/dev/null; then
    if ! git -C "$dir" show "HEAD:$rel" | swiftformat --lint --quiet --stdin-path "$path" >/dev/null 2>&1; then
        echo "format-edited: $rel wasn't formatted at HEAD, so it was left alone. Run 'swiftformat $rel' only if this PR should reformat it." >&2
        exit 0
    fi
fi

swiftformat --quiet "$path" >/dev/null 2>&1 || echo "format-edited: swiftformat failed on $path" >&2
exit 0
