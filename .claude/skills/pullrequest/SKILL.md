---
name: pullrequest
description: Use when creating PR with automated Codex + Copilot code review loop - self-validates work, creates branch, opens PR, triggers reviews, validates and fixes comments iteratively
---

# PR Pipeline: self-check → PR → Codex review → Copilot review → merge

## Modes

| Mode | Invocation | Behavior |
|------|-----------|----------|
| **Auto (default)** | `/pullrequest` | Auto-merges after successful review |
| **Wait** | `/pullrequest wait` | Asks user before merge |

## Workflow overview

```
  ┌─────────────┐
  │ 1. Self-check│
  └──────┬──────┘
         ▼
  ┌──────────────┐
  │ 1.5. Sync    │
  │   with remote│
  └──────┬───────┘
         ▼
  ┌─────────────┐
  │ 2. Branch &  │
  │    Squash    │
  └──────┬──────┘
         ▼
  ┌─────────────┐
  │ 3. Create PR │
  └──────┬──────┘
         ▼
  ┌─────────────────┐
  │ 4. Codex review  │◄──┐
  │    loop (poll)   │   │ fix + push
  └──────┬──────────┘   │
         │ comments ────►┘
         ▼
  ┌─────────────────┐
  │ 5. Copilot review│◄──┐
  │    loop (poll)   │   │ fix + push
  └──────┬──────────┘   │
         │ comments ────►┘
         ▼
  ┌─────────────┐
  │ 6. Report &  │
  │    Merge     │
  └─────────────┘
```

## Steps

### 1. Self-check

Before anything, validate the work is ready:

**1a. Read project rules:**
```bash
# Read both if they exist
cat CLAUDE.md 2>/dev/null || true
cat AGENTS.md 2>/dev/null || true
```

**1b. Recall the user's original task.** Check: is everything implemented? Is there anything extra that wasn't asked for?

**1c. Detect and run project checks:**
```bash
# Detect available checks from package.json / Makefile / pyproject.toml
# Try in order — run whatever exists:
npm test 2>/dev/null || pnpm test 2>/dev/null || yarn test 2>/dev/null || make test 2>/dev/null || pytest 2>/dev/null || go test ./... 2>/dev/null || cargo test 2>/dev/null || echo "No test runner found"
```

Also try lint if available:
```bash
npm run lint 2>/dev/null || pnpm lint 2>/dev/null || make lint 2>/dev/null || true
```

**If tests or lint fail** — fix the issues before proceeding. Do NOT skip this step.

**1d. Quick sanity scan** — no hardcoded secrets, no debug `console.log`/`print` left behind, no unresolved TODOs from current work.

### 1.5. Sync with remote

Before creating the PR, ensure your branch is up to date with the remote default branch:

1. **Guard**: determine the default branch via `origin/HEAD` resolution (same as step 2b). If the current branch matches the default branch, skip this step — step 2a will handle the error.
2. Fetch the latest changes from `origin`
3. Rebase your current branch onto the **remote-tracking** default branch from `origin` (e.g. `origin/main`), not the local copy
4. **If rebase conflicts occur** — stop and ask the user to resolve them manually before proceeding. Do NOT continue the pipeline with unresolved conflicts.

This prevents creating PRs on a stale base, which would lead to merge conflicts discovered only after review loops.

### 2. Branch & squash

**2a. Ensure you're on a feature branch:**
```bash
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "ERROR: on default branch, create a feature branch first"
  exit 1
fi
```

If on default branch — ask user for branch name, create it.

**2b. Squash commits into one** (clean history for the PR):
```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
COMMIT_COUNT=$(git rev-list --count ${DEFAULT_BRANCH}..HEAD)
if [ "$COMMIT_COUNT" -gt 1 ]; then
  git reset --soft ${DEFAULT_BRANCH}
  git commit -m "<conventional commit message matching PR title>"
fi
```

**2c. Push:**
```bash
git push origin $(git branch --show-current) -u --force-with-lease
```

`--force-with-lease` is needed because squash rewrites history.

### 3. Create or find PR

**3a. Check for existing PR:**
```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
BRANCH=$(git branch --show-current)
EXISTING_PR=$(gh pr list --head "$BRANCH" --state open --json number -q '.[0].number')
```

**3b. If PR exists** — use it, skip creation. Go to step 4.

**3c. If no PR — create one:**
```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
gh pr create \
  --base "$DEFAULT_BRANCH" \
  --title "<conventional commit, max 70 chars>" \
  --body "$(cat <<'EOF'
## Summary
- <what this PR does>
- <why>

## Test plan
- [ ] <verification step 1>
- [ ] <verification step 2>

## Self-check
- [x] Tests passing
- [x] Lint clean
- [x] No hardcoded secrets or debug output
EOF
)"
```

Save the PR number for subsequent steps.

### 4. Codex review loop

**Skip this step if Codex is not available** (check with a dry-run comment — if `@codex` is unknown, skip gracefully).

**4a. Trigger Codex review:**
```bash
PR_NUM=<number>
gh pr comment $PR_NUM --body "@codex Please review this PR:

## Checklist
- [ ] **Bugs & Security**: logic errors, vulnerabilities, edge cases
- [ ] **Side Effects**: unintended changes in other parts of codebase
- [ ] **Consistency**: follows project patterns and code style
- [ ] **Documentation**: README, comments, docs updated if needed

Reply with 👍 if no issues found."
```

**4b. Poll for response (NOT sleep):**

Poll every 60 seconds, up to 15 attempts (max ~15 minutes):

```bash
# Check BOTH response channels:

# 1. Issue comments (general verdict):
gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | {id: .id, body: .body}'

# 2. Inline PR comments (code-specific):
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | {id: .id, path: .path, line: .line, body: .body}'
```

**Exit polling when:**
- Issue comment contains "no major issues" / "looks good" / "LGTM" / 👍
- OR inline comments appeared (process them)
- OR max attempts reached (continue without error)

**4c. Process comments (up to 10 iterations):**

Track processed comment IDs to avoid re-processing.

Find **unprocessed** comments — those whose `id` does NOT appear as `in_reply_to_id` in any other comment:
```bash
# All Codex comment IDs
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | .id'

# All reply-to IDs (from anyone)
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.in_reply_to_id != null) | .in_reply_to_id'
```

A comment is **unprocessed** if its `id` is not in the reply-to list.

**Valid (fix):**
- Bug, vulnerability, logic error
- Real side effect in other parts of codebase
- Violation of project style/patterns
- Missing error handling at system boundary

```bash
# Fix code, then:
git add <files> && git commit -m "fix: <description>" && git push
gh pr comment $PR_NUM --body "Fixed: <what and why>"
```
Tell the user: what was found → why it was fixed.

**Invalid (decline):**
- Subjective opinion without technical justification
- Over-engineering for the task at hand
- Contradicts project architecture
- Outdated or incorrect advice

```bash
gh pr comment $PR_NUM --body "Declined: <reason>"
```
Tell the user: what was found → why it was declined.

**After each push** — poll again for new comments.

**Exit loop when:**
- Codex says "no major issues" / LGTM / 👍
- No new unprocessed comments after last push
- Max 10 iterations reached

### 5. Copilot review loop

**5a. Request Copilot review:**
```bash
gh pr edit $PR_NUM --add-reviewer copilot-pull-request-reviewer 2>/dev/null || true
```

If this fails (Copilot not enabled in repo) — **skip step 5 entirely, continue to step 6.**

**5b. Poll for Copilot response:**

Poll every 60 seconds, up to 15 attempts:

```bash
# Copilot uses TWO different usernames — check BOTH:

# 1. Reviews (verdict):
gh api "repos/${REPO}/pulls/${PR_NUM}/reviews" \
  --jq '.[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {id: .id, state: .state, body: .body}'

# 2. Inline comments (code-specific):
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login == "Copilot") | {id: .id, path: .path, line: .line, body: .body}'
```

**Exit polling when:**
- Review with state "COMMENTED" or "APPROVED" and no inline comments → no issues
- Inline comments appeared → process them
- Max attempts reached → continue without error

**5c. Process Copilot comments:**

Same logic as step 4c but for Copilot comments. Track unprocessed by `in_reply_to_id`.

**After each push** — re-request Copilot review:
```bash
gh pr edit $PR_NUM --add-reviewer copilot-pull-request-reviewer 2>/dev/null || true
```
Then poll again.

**Exit conditions:** same as step 4c.

### 6. Report & merge

**6a. Final report:**

```markdown
## PR Review Summary
| | Count |
|---|---|
| **Codex iterations** | N |
| **Codex comments fixed** | M |
| **Codex comments declined** | K |
| **Copilot iterations** | N |
| **Copilot comments fixed** | M |
| **Copilot comments declined** | K |
| **Status** | ✅ Ready to merge / ⚠️ Needs attention |
```

Show the PR URL.

**6b. Merge (depends on mode):**

**Auto mode (default) AND status is "ready":**
```bash
gh pr merge $PR_NUM --squash --delete-branch
```
Tell user: PR merged automatically.

**Wait mode:**
Ask user: "PR is ready to merge. Merge now?"
- Yes → `gh pr merge $PR_NUM --squash --delete-branch`
- No → leave PR open

**If merge fails** (conflicts, checks not passed) — report error, do NOT retry blindly.

## Comment validation rules

When evaluating reviewer comments, apply these criteria consistently:

**Always fix:**
- Security vulnerabilities (XSS, injection, auth bypass)
- Logic bugs that produce wrong results
- Data loss or corruption risks
- Race conditions in concurrent code
- Missing null/undefined checks at system boundaries

**Always decline:**
- "Consider using X instead of Y" without explaining why Y is wrong
- Suggesting patterns that the project explicitly doesn't use
- Performance optimization for code that isn't a bottleneck
- Adding abstraction layers for single-use code
- Style preferences that contradict the project's own style

**Use judgment:**
- Error handling suggestions — add if at system boundary, skip if internal
- Documentation suggestions — add if public API, skip if self-evident
- Test suggestions — add if covering a real edge case, skip if redundant

## Graceful degradation

This skill works with **zero, one, or both** review bots:

| Codex | Copilot | Behavior |
|-------|---------|----------|
| ✅ | ✅ | Full pipeline: both review loops |
| ✅ | ❌ | Codex review only, skip step 5 |
| ❌ | ✅ | Skip step 4, Copilot review only |
| ❌ | ❌ | Self-check only, create PR, skip to merge |

Never fail because a reviewer bot is unavailable. Always continue the pipeline.
