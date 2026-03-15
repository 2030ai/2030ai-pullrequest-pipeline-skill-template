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
  ┌──────────────────────┐
  │ 4. Trigger both      │
  │    Codex + Copilot   │
  └──────┬───────────────┘
         ▼
  ┌──────────────────────┐
  │ 5. Unified poll loop │
  │    (wait for BOTH)   │
  └──────┬───────────────┘
         ▼
  ┌──────────────────────┐
  │ 6. Process comments  │◄──┐
  │    (Codex + Copilot) │   │ fix + push + re-poll
  └──────┬───────────────┘   │
         │ new comments ────►┘
         ▼
  ┌─────────────┐
  │ 7. Report &  │
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

### 4. Trigger both reviewers

Launch Codex and Copilot reviews **simultaneously**. Skip either if unavailable.

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

If `@codex` is unknown — set `CODEX_AVAILABLE=0`, skip Codex tracking.

**4b. Request Copilot review:**
```bash
gh pr edit $PR_NUM --add-reviewer copilot-pull-request-reviewer 2>/dev/null || true
```

If this fails (Copilot not enabled) — set `COPILOT_AVAILABLE=0`, skip Copilot tracking.

### 5. Unified polling loop (wait for BOTH bots)

Poll every 60 seconds, up to 15 attempts (max ~15 minutes).

Track each bot independently: `CODEX_FOUND=0`, `COPILOT_FOUND=0`.

**On each poll attempt, check ALL channels:**

```bash
# ── Codex detection ──
# Codex login pattern: "codex" or "chatgpt-codex" (varies by GitHub App version)

# 1. Issue comments (PRIMARY channel — Codex replies here most often):
gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | {id: .id, body: .body}'

# 2. Reviews (formal verdict):
gh api "repos/${REPO}/pulls/${PR_NUM}/reviews" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | {id: .id, state: .state, body: .body}'

# 3. Inline PR comments (code-specific suggestions):
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | {id: .id, path: .path, line: .line, body: .body}'

# If ANY of the above returns results → CODEX_FOUND=1

# ── Copilot detection ──
# Copilot uses TWO different usernames — check BOTH:

# 1. Reviews (verdict):
gh api "repos/${REPO}/pulls/${PR_NUM}/reviews" \
  --jq '.[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {id: .id, state: .state, body: .body}'

# 2. Inline comments (code-specific):
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login == "Copilot") | {id: .id, path: .path, line: .line, body: .body}'

# If ANY of the above returns results → COPILOT_FOUND=1
```

**Exit polling when:**
- `(CODEX_FOUND || !CODEX_AVAILABLE) && (COPILOT_FOUND || !COPILOT_AVAILABLE)` — both responded (or unavailable)
- OR all 15 attempts exhausted → continue with whatever was found

**Do NOT exit when only one bot responded — keep polling for the other.**

### 6. Process comments (after polling completes)

Process comments from **both bots** after the unified polling loop.

**6a. Process Codex comments (up to 10 iterations):**

Track processed comment IDs to avoid re-processing.

Codex can respond via **issue comments**, **reviews**, or **inline PR comments**. Check all three:
```bash
# Issue comments from Codex (primary channel):
gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | {id: .id, body: .body}'

# Inline PR comments from Codex:
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | {id: .id, path: .path, line: .line, body: .body}'
```

For inline PR comments, find **unprocessed** ones — those whose `id` does NOT appear as `in_reply_to_id`:
```bash
# All Codex inline comment IDs
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("codex|chatgpt-codex")) | .id'

# All reply-to IDs (from anyone)
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.in_reply_to_id != null) | .in_reply_to_id'
```

A comment is **unprocessed** if its `id` is not in the reply-to list.

**6b. Process Copilot comments (up to 10 iterations):**

Same logic as 6a but for Copilot comments (`copilot-pull-request-reviewer[bot]` for reviews, `Copilot` for inline comments). Track unprocessed by `in_reply_to_id`.

**6c. Comment evaluation — for both bots:**

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

**6d. Re-poll after fixes:**

After each push, re-poll **only for the bot whose comments were fixed**:
- If Codex comments were fixed → poll for new Codex responses (all 3 channels)
- If Copilot comments were fixed → re-request Copilot review + poll:
  ```bash
  gh pr edit $PR_NUM --add-reviewer copilot-pull-request-reviewer 2>/dev/null || true
  ```

**Exit loop when:**
- Bot says "no major issues" / LGTM / 👍
- No new unprocessed comments after last push
- Max 10 iterations reached (per bot)

### 7. Report & merge

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
| ✅ | ✅ | Full pipeline: trigger both, unified poll, process both |
| ✅ | ❌ | Trigger Codex only, poll for Codex only |
| ❌ | ✅ | Trigger Copilot only, poll for Copilot only |
| ❌ | ❌ | Self-check only, create PR, skip to merge |

Never fail because a reviewer bot is unavailable. Always continue the pipeline.
