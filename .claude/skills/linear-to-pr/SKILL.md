---
name: linear-to-pr
description: Use when the owner says "take JUN-NN" (or names a Linear issue to do end to end). Fetches the issue, branches from the latest main, runs new-feature then pre-pr, opens the PR with gh, and comments the link on the issue. Never changes the issue's status, assignee or labels, and never merges.
argument-hint: "JUN-NN"
disable-model-invocation: true
---

# Linear issue to pull request

1. **Fetch** `$ARGUMENTS` with the Linear MCP: `get_issue`, plus `list_comments` for the discussion. If it's unclear or too big for one PR (~400 lines), stop and ask.
2. **Branch** from the latest main: `git fetch origin && git switch -c jun-NN-<short-slug> origin/main`. If the working tree has unrelated changes, leave them alone and say so.
3. **Build it** with the `new-feature` skill (plan mode first, then wait for approval).
4. **Check it** with the `pre-pr` skill.
5. **Open the PR:** `gh pr create --base main --title "feat|bug|chore|perf(scope): summary [JUN-NN]" --body-file <file>`, with the body from `pre-pr`. Don't merge or push to main.
6. **Comment** the PR link on the issue (Linear MCP `save_comment`), with one line on what it does and whether it needs human review.

Never change the issue's status, assignee, labels or project, and never create issues, unless the owner says so in this conversation.
