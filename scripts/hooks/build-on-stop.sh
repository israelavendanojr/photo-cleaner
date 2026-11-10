#!/usr/bin/env bash
# Claude Code Stop hook: when the agent finishes a turn with Swift changes, runs `make build`.
# If the build fails, the turn continues with the compiler errors as the reason, so the agent fixes them.
#
# - Exits at once when no .swift file differs from HEAD (staged, unstaged or untracked).
# - Skips the build when the Swift changes are exactly the ones that last built green.
# - Gives up after BRISTLE_BUILD_TIMEOUT seconds (default 240), and stops sending the agent back
#   after 3 failed builds in one session, so a turn can always end.
# Off for a session: BRISTLE_HOOKS_OFF=1 (all hooks) or BRISTLE_BUILD_OFF=1 (this one).

[ -n "${BRISTLE_HOOKS_OFF:-}${BRISTLE_BUILD_OFF:-}" ] && exit 0
command -v jq >/dev/null || exit 0

input=$(cat)
session=$(jq -r '.session_id // "unknown"' <<<"$input" | tr -cd 'A-Za-z0-9_-')
cwd=$(jq -r '.cwd // empty' <<<"$input")
repo=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo" || exit 0
[ -f Makefile ] || exit 0

swift_changes() {
    git diff HEAD -- '*.swift' ':!photo-swiper-context'
    git ls-files --others --exclude-standard -z -- '*.swift' ':!photo-swiper-context' | xargs -0 cat 2>/dev/null
}
[ -n "$(git diff --name-only HEAD -- '*.swift')$(git ls-files --others --exclude-standard -- '*.swift')" ] || exit 0

state=.claude/hook-state
mkdir -p "$state"
hash=$(swift_changes | shasum | cut -c1-40)
[ "$(cat "$state/build-green" 2>/dev/null)" = "$hash" ] && exit 0

fails_file="$state/build-fails-$session"
fails=$(cat "$fails_file" 2>/dev/null || echo 0)
if [ "$fails" -ge 3 ]; then
    echo "build-on-stop: the build still fails after 3 tries this session; not blocking again." >&2
    exit 0
fi

# Run make in its own process group so a timeout can stop xcodebuild too.
limit=${BRISTLE_BUILD_TIMEOUT:-240}
set -m
make build >/dev/null 2>&1 &
pid=$!
set +m
waited=0
while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
        kill -TERM -- "-$pid" 2>/dev/null
        echo "build-on-stop: make build took over ${limit}s; gave up. Run 'make build' yourself." >&2
        exit 0
    fi
    sleep 1
    waited=$((waited + 1))
done

if wait "$pid"; then
    echo "$hash" >"$state/build-green"
    rm -f "$fails_file"
    exit 0
fi

echo $((fails + 1)) >"$fails_file"
errors=$(grep -E "error:" build/logs/build.log 2>/dev/null | sort -u | head -20)
[ -n "$errors" ] || errors=$(tail -20 build/logs/build.log 2>/dev/null)
jq -n --arg errors "$errors" \
    '{decision: "block", reason: ("make build failed. Fix these before finishing (full log: build/logs/build.log):\n" + $errors)}'
exit 0
