#!/usr/bin/env bash
# Claude Code PreToolUse hook (Edit|Write): the first edit in a session to a file on the deletion,
# privacy, persistence, purchase or project-config paths is blocked once (exit 2). The message tells
# the agent to load the privacy-destructive-guard skill and flag the PR. Later edits in the same
# session pass. Nothing else is ever blocked.
#
# The acknowledgement is a file per session in .claude/hook-state/ (gitignored).
# Off for a session: BRISTLE_HOOKS_OFF=1 (all hooks) or BRISTLE_GUARD_OFF=1 (this one).

[ -n "${BRISTLE_HOOKS_OFF:-}${BRISTLE_GUARD_OFF:-}" ] && exit 0
command -v jq >/dev/null || { echo "guard-sensitive-paths: jq not found; guard skipped" >&2; exit 0; }

input=$(cat)
path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
session=$(jq -r '.session_id // "unknown"' <<<"$input" | tr -cd 'A-Za-z0-9_-')
[ -n "$path" ] || exit 0

base=${path##*/}
case "$path" in
    */Services/PhotoKit/* | */Services/Persistence/* | */PendingPileView.swift | */FeedViewModel.swift | \
    */CardStackView.swift | */SwipeDeck.swift | */FrontLoad.swift | */PlaceNamer.swift | */ProgressModels.swift | \
    */AssetFeatureRecord.swift | */BristleSchema.swift | */DevMode.swift | */Info.plist | */project.pbxproj) ;;
    *) [[ "$base" == *Entitlement*.swift ]] || exit 0 ;;
esac

state="${CLAUDE_PROJECT_DIR:-$(git -C "$(dirname "$path")" rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/hook-state"
ack="$state/guard-$session.ack"
[ -f "$ack" ] && exit 0
mkdir -p "$state" && echo "$path" >"$ack"

cat >&2 <<EOF
Blocked once: $base is on a sensitive path (deletion, privacy, persistence, purchases or project config).
Before editing it, load the privacy-destructive-guard skill (.claude/skills/privacy-destructive-guard/SKILL.md)
and keep its checklist. The PR must say "Needs human review" with a one-sentence risk.
Then retry the edit; the rest of this session's edits to sensitive paths go through.
EOF
exit 2
