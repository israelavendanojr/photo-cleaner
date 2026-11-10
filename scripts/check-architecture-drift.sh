#!/usr/bin/env bash
# Warns (never fails) when a branch changes the app's structure without touching ARCHITECTURE.md:
# Swift files added, removed or renamed under Services/, ViewModels/ or Models/, or any change to
# BristleSchema.swift. In GitHub Actions the warning is an annotation on the PR.
# Usage: scripts/check-architecture-drift.sh [base]   (default origin/main)

base=${1:-origin/main}
range="$(git merge-base "$base" HEAD 2>/dev/null)...HEAD" || exit 0
app=photo-swiper/photo-swiper

structural=$(git diff --name-only --diff-filter=ADR "$range" -- \
    "$app/Services/*.swift" "$app/ViewModels/*.swift" "$app/Models/*.swift")
schema=$(git diff --name-only "$range" -- "$app/Services/Persistence/BristleSchema.swift")
changed=$(printf '%s\n%s' "$structural" "$schema" | sed '/^$/d' | sort -u)

[ -n "$changed" ] || exit 0
git diff --quiet "$range" -- ARCHITECTURE.md || exit 0

msg="Structural change without an ARCHITECTURE.md update: $(echo "$changed" | tr '\n' ' ')- update it, or say in the PR why it isn't needed."
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::warning title=ARCHITECTURE.md may be stale::$msg"
else
    echo "warning: $msg"
fi
exit 0
