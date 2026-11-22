#!/usr/bin/env bash
# Restack the open PRs above a PR that was just squash-merged.
#
# Squash merging puts a stacked PR's changes on main as one new commit, so the
# next PR's branch still carries the original commits and conflicts with main.
# This rebases each PR above the merged one onto its new base, dropping the
# merged commits, and force-pushes the branches with a lease.
#
# It pushes nothing unless every branch rebases cleanly and each PR's own diff
# is unchanged by the rebase (same patch ID as before). It only touches
# jun-NN branches, never main, and works in a temporary worktree, so your
# checkout is left alone.
#
# Usage: scripts/restack.sh <merged-PR-number> [--dry-run]
# People run this, not agents: CLAUDE.md forbids agents to force-push.
set -euo pipefail

die() { echo "restack: $*" >&2; exit 1; }

merged=${1:-}
dry_run=0
[ "${2:-}" = "--dry-run" ] && dry_run=1
[[ $merged =~ ^[0-9]+$ ]] || die "usage: scripts/restack.sh <merged-PR-number> [--dry-run]"
command -v gh >/dev/null && command -v jq >/dev/null || die "needs gh and jq"

main=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)

read -r state head tip < <(gh pr view "$merged" --json state,headRefName,headRefOid \
    --jq '"\(.state) \(.headRefName) \(.headRefOid)"')
[ "$state" = MERGED ] || die "#$merged is $state, not merged. Merge it first."

git fetch --quiet --prune origin
open_prs=$(gh pr list --state open --limit 200 --json number,headRefName,baseRefName)

# Walk the stack upwards: the PR based on the merged branch (GitHub may already
# have moved it to main), then the PR based on that one, and so on.
chain=()
numbers=()
parent=$head
while :; do
    if [ ${#chain[@]} -eq 0 ]; then
        candidates=$(jq -r --arg a "$head" --arg b "$main" \
            '.[] | select(.baseRefName == $a or .baseRefName == $b) | "\(.number) \(.headRefName)"' <<<"$open_prs" |
            while read -r n b; do
                git merge-base --is-ancestor "$tip" "origin/$b" 2>/dev/null && echo "$n $b"
            done)
    else
        candidates=$(jq -r --arg a "$parent" '.[] | select(.baseRefName == $a) | "\(.number) \(.headRefName)"' <<<"$open_prs")
    fi
    [ -z "$candidates" ] && break
    [ "$(wc -l <<<"$candidates")" -eq 1 ] || die "more than one PR is based on $parent; restack those by hand:
$candidates"
    read -r n b <<<"$candidates"
    [[ $b == *jun-[0-9]* && $b != "$main" ]] || die "$b isn't a jun-NN branch; restack it by hand"
    chain+=("$b")
    numbers+=("$n")
    parent=$b
done

[ ${#chain[@]} -gt 0 ] || { echo "restack: no open PR is stacked on #$merged. Nothing to do."; exit 0; }

work=$(mktemp -d "${TMPDIR:-/tmp}/restack.XXXXXX")
cleanup() { git worktree remove --force "$work" >/dev/null 2>&1 || true; rmdir "$work" 2>/dev/null || true; }
trap cleanup EXIT
git worktree add --quiet --detach "$work" "origin/$main"

old_base=$tip
new_base=$(git rev-parse "origin/$main")
refspecs=()
for i in "${!chain[@]}"; do
    b=${chain[$i]}
    old_tip=$(git rev-parse "origin/$b")
    before=$(git diff "$old_base" "$old_tip" | git patch-id --stable | cut -d' ' -f1)

    git -C "$work" checkout --quiet --detach "$old_tip"
    if ! git -C "$work" rebase --quiet --onto "$new_base" "$old_base" >/dev/null 2>&1; then
        git -C "$work" rebase --abort >/dev/null 2>&1 || true
        die "$b (#${numbers[$i]}) conflicts with its new base, so nothing was pushed. Rebase it by hand."
    fi
    new_tip=$(git -C "$work" rev-parse HEAD)
    after=$(git diff "$new_base" "$new_tip" | git patch-id --stable | cut -d' ' -f1)
    [ "$before" = "$after" ] || die "#${numbers[$i]}'s diff changed in the rebase, so nothing was pushed. Check $b by hand."

    echo "#${numbers[$i]} $b: $(git rev-parse --short "$old_tip") -> $(git rev-parse --short "$new_tip"), diff unchanged"
    refspecs+=("--force-with-lease=refs/heads/$b:$old_tip" "$new_tip:refs/heads/$b")
    old_base=$old_tip
    new_base=$new_tip
done

if [ $dry_run = 1 ]; then
    echo "restack: dry run, nothing pushed."
    exit 0
fi

git push --quiet --atomic origin "${refspecs[@]}"
first=${numbers[0]}
[ "$(gh pr view "$first" --json baseRefName --jq .baseRefName)" = "$main" ] || gh pr edit "$first" --base "$main" >/dev/null
echo "restack: pushed ${#chain[@]} branch(es); #$first is based on $main."
echo "Local copies of these branches are now stale. Update one with: git switch <branch> && git reset --keep origin/<branch>"
