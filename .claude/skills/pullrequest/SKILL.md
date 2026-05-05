---
name: pullrequest
description: Use when creating PR with automated review levels - simple uses Codex + Copilot, medium adds Claude Code Review, max adds Claude ultrareview; self-validates work, creates branch, opens PR, triggers reviews, validates and fixes comments iteratively
---

# PR Pipeline: self-check → PR → review level → merge

## Modes

| Mode | Invocation | Behavior |
|------|-----------|----------|
| **Auto (default)** | `/pullrequest` | Uses simple review level and auto-merges after successful review |
| **Wait** | `/pullrequest wait` | Uses selected review level and asks user before merge |
| **Medium** | `/pullrequest medium` or `/pullrequest claude` | Adds Claude Code Review |
| **Max** | `/pullrequest max`, `/pullrequest ultra`, or `/pullrequest ultrareview` | Adds Claude ultrareview and asks before merge |

Treat invocation arguments as `$ARGUMENTS` where the host exposes them. Modes can be combined, e.g. `/pullrequest wait medium`.

## Review levels

| Level | Aliases | Reviewers |
|---|---|---|
| **Simple (default)** | none, `simple` | Codex + Copilot |
| **Medium** | `medium`, `claude` | Codex + Copilot + Claude Code Review |
| **Max** | `max`, `ultra`, `ultrareview` | Codex + Copilot + Claude Code Review + one Claude ultrareview |

Parse `$ARGUMENTS` once before triggering reviewers. If several level aliases are present, use the highest level: `max > medium > simple`. `wait` controls merge confirmation only; it does not change review level.

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
  │ 4. Trigger selected  │
  │ review level         │
  └──────┬───────────────┘
         ▼
  ┌──────────────────────┐
  │ 5. Monitor/review    │
  │ selected reviewers   │
  └──────┬───────────────┘
         ▼
  ┌──────────────────────┐
  │ 6. Process comments  │◄──┐
  │ selected outputs     │   │ fix + push + re-poll
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

**1e. Docs consistency** — if `src/lib/` or module structure changed, check that `agent_docs/architecture.md` (or equivalent) reflects the changes. Flag if stale.

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

### 4. Trigger selected review level

Determine `REVIEW_LEVEL` once, then launch only the selected reviewers. Codex and Copilot run for every level; Claude Code Review runs only for `medium` and `max`; Claude ultrareview runs only once for `max`.

```bash
REVIEW_LEVEL=simple
if printf '%s\n' "$ARGUMENTS" | rg -qi '\b(max|ultra|ultrareview)\b'; then
  REVIEW_LEVEL=max
elif printf '%s\n' "$ARGUMENTS" | rg -qi '\b(medium|claude)\b'; then
  REVIEW_LEVEL=medium
fi
echo "Review level: $REVIEW_LEVEL"
```

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

**4c. Trigger Claude Code Review (`medium` / `max` only):**

Use `review once` by default to avoid subscribing the PR to paid review on every later push. The command must be the first line of a top-level PR comment.

```bash
if [ "$REVIEW_LEVEL" != "simple" ]; then
  gh pr comment "$PR_NUM" --body "@claude review once

Focus on actionable correctness, security, regression, and project-rule issues introduced by this PR. Avoid style-only feedback unless it reflects an explicit repo rule."
fi
```

If `REVIEW_LEVEL=simple`, set `CLAUDE_SKIPPED_BY_LEVEL=1` and do not track Claude. If `REVIEW_LEVEL` is `medium` or `max` and no Claude Code Review check, Claude comment, review, or reaction appears after the wait window — set `CLAUDE_AVAILABLE=0`, skip Claude tracking, and continue. Do not fail the PR pipeline solely because Claude is not enabled for the repository.

**4d. Claude ultrareview (`max` only):**

Ultrareview is separate from GitHub Code Review. It must be explicitly requested through max level because it uses Claude Code on the web, may consume free runs or extra usage, and `claude ultrareview` counts as consent for the launch prompt. Run it at most once per max invocation; do not auto-rerun after fixes unless the user explicitly asks.

```bash
if [ "$REVIEW_LEVEL" = "max" ]; then
  if command -v claude >/dev/null 2>&1; then
    ULTRA_ERR=$(mktemp)
    ULTRA_OUT=$(mktemp)
    claude ultrareview "$PR_NUM" --timeout 30 >"$ULTRA_OUT" 2>"$ULTRA_ERR"
    ULTRA_STATUS=$?
    ULTRA_SESSION=$(rg -o 'https://claude\.ai/code/session_[A-Za-z0-9]+' "$ULTRA_ERR" | tail -1 || true)
    [ -n "$ULTRA_SESSION" ] && gh pr comment "$PR_NUM" --body "Claude ultrareview: $ULTRA_SESSION"
    cat "$ULTRA_OUT"
    cat "$ULTRA_ERR" >&2
    [ "$ULTRA_STATUS" -eq 0 ] || echo "Claude ultrareview failed or timed out; continue only after reporting this to the user."
  else
    echo "Claude CLI is not available; skipping ultrareview and reporting this to the user."
  fi
fi
```

In max level, do not merge until the ultrareview output has been evaluated and included in the final report.

### 5. Wait for bot reviews

**CRITICAL**: Reviewers typically respond in 3-5 minutes. Do NOT give up early.

**NEVER use one-shot waits like `sleep N && gh api ...`.** Use `/wait-bot-review`, a Monitor/background task if the host supports it, or a bounded polling loop with a timeout. Polling loops are allowed for bot review because they keep checking until a real reviewer response appears.

Track selected reviewers independently: `CODEX_FOUND=0`, `COPILOT_FOUND=0`, and `CLAUDE_FOUND=0` only for `medium`/`max`.

**5a. Codex Monitor** (skip if `CODEX_AVAILABLE=0`):

```
Monitor(
  description: "Codex review on PR #${PR_NUM}",
  timeout_ms: 1800000,
  persistent: false,
  command: "REPO='${REPO}'; PR=${PR_NUM}; while true; do \
    I=$(gh api \"repos/$REPO/issues/$PR/comments\" --jq '[.[] | select(.user.login == \"chatgpt-codex-connector[bot]\")] | length' 2>/dev/null || echo 0); \
    R=$(gh api \"repos/$REPO/pulls/$PR/reviews\" --jq '[.[] | select(.user.login == \"chatgpt-codex-connector[bot]\")] | length' 2>/dev/null || echo 0); \
    L=$(gh api \"repos/$REPO/pulls/$PR/comments\" --jq '[.[] | select(.user.login == \"chatgpt-codex-connector[bot]\")] | length' 2>/dev/null || echo 0); \
    if [ \"$((I + R + L))\" -gt 0 ]; then echo \"Codex responded: issues=$I reviews=$R inline=$L\"; exit 0; fi; \
    sleep 30; done"
)
```

**5b. Copilot Monitor** (skip if `COPILOT_AVAILABLE=0`):

Copilot uses TWO logins: `copilot-pull-request-reviewer[bot]` for reviews, `Copilot` for inline comments. One Monitor checks both:

```
Monitor(
  description: "Copilot review on PR #${PR_NUM}",
  timeout_ms: 1800000,
  persistent: false,
  command: "REPO='${REPO}'; PR=${PR_NUM}; while true; do \
    R=$(gh api \"repos/$REPO/pulls/$PR/reviews\" --jq '[.[] | select(.user.login == \"copilot-pull-request-reviewer[bot]\")] | length' 2>/dev/null || echo 0); \
    L=$(gh api \"repos/$REPO/pulls/$PR/comments\" --jq '[.[] | select(.user.login == \"Copilot\")] | length' 2>/dev/null || echo 0); \
    if [ \"$((R + L))\" -gt 0 ]; then echo \"Copilot responded: reviews=$R inline=$L\"; exit 0; fi; \
    sleep 30; done"
)
```

**5c. Claude Monitor** (skip if `REVIEW_LEVEL=simple` or `CLAUDE_AVAILABLE=0`):

Claude can surface results as PR comments/reviews, inline comments, or a `Claude Code Review` check run. Check all channels:

```
Monitor(
  description: "Claude review on PR #${PR_NUM}",
  timeout_ms: 1800000,
  persistent: false,
  command: "REPO='${REPO}'; PR=${PR_NUM}; while true; do \
    I=$(gh api \"repos/$REPO/issues/$PR/comments\" --jq '[.[] | select(.user.login | test(\"claude\"; \"i\"))] | length' 2>/dev/null || echo 0); \
    R=$(gh api \"repos/$REPO/pulls/$PR/reviews\" --jq '[.[] | select(.user.login | test(\"claude\"; \"i\"))] | length' 2>/dev/null || echo 0); \
    L=$(gh api \"repos/$REPO/pulls/$PR/comments\" --jq '[.[] | select(.user.login | test(\"claude\"; \"i\"))] | length' 2>/dev/null || echo 0); \
    C=$(gh pr view $PR --repo \"$REPO\" --json statusCheckRollup --jq '[.statusCheckRollup[]? | select((.name // \"\" | test(\"Claude\"; \"i\")) or (.workflowName // \"\" | test(\"Claude\"; \"i\")))] | length' 2>/dev/null || echo 0); \
    if [ \"$((I + R + L + C))\" -gt 0 ]; then echo \"Claude responded: issues=$I reviews=$R inline=$L checks=$C\"; exit 0; fi; \
    sleep 30; done"
)
```

**5d. Continue when notifications arrive:**

Each Monitor sends a notification on first detection or timeout. If Monitor is unavailable, use equivalent bounded polling loops. After receiving notification(s) for all selected reviewers, proceed to step 6.

**Re-poll after fixes** — when you push corrections in step 6, start a NEW Monitor with `INITIAL_R/INITIAL_L` baselines (compare new counts against the count before the fix), so the Monitor exits when the bot leaves a NEW review/comment, not the old one.

**Alternative**: invoke `/wait-bot-review <PR> <bot-login>` for one reviewer at a time. For Claude Code Review, also inspect the `Claude Code Review` check run because findings may live in check output/annotations even if GitHub rejects an inline comment.

### 6. Process comments (after polling completes)

Process comments from selected reviewers after Monitor/poll notifications arrive.

**6a. Process Codex comments (up to 10 iterations):**

Track processed comment IDs to avoid re-processing.

Codex can respond via **issue comments**, **reviews**, or **inline PR comments**. Check all three:
```bash
# Issue comments from Codex (primary channel):
gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login == "chatgpt-codex-connector[bot]") | {id: .id, body: .body}'

# Inline PR comments from Codex:
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login == "chatgpt-codex-connector[bot]") | {id: .id, path: .path, line: .line, body: .body}'
```

For inline PR comments, find **unprocessed** ones — those whose `id` does NOT appear as `in_reply_to_id`:
```bash
# All Codex inline comment IDs
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login == "chatgpt-codex-connector[bot]") | .id'

# All reply-to IDs (from anyone)
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.in_reply_to_id != null) | .in_reply_to_id'
```

A comment is **unprocessed** if its `id` is not in the reply-to list.

**6b. Process Copilot comments (up to 10 iterations):**

Same logic as 6a but for Copilot comments (`copilot-pull-request-reviewer[bot]` for reviews, `Copilot` for inline comments). Track unprocessed by `in_reply_to_id`.

**6c. Process Claude comments/checks (medium/max only, up to 10 iterations):**

Claude Code Review may post inline comments, reviews, top-level comments, and a neutral check run. Check all sources:

```bash
# Claude top-level comments:
gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("claude"; "i")) | {id: .id, body: .body}'

# Claude inline PR comments:
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("claude"; "i")) | {id: .id, path: .path, line: .line, body: .body, in_reply_to_id: .in_reply_to_id}'

# Claude review/check run summary:
gh pr view "$PR_NUM" --repo "$REPO" --json statusCheckRollup \
  --jq '.statusCheckRollup[]? | select((.name // "" | test("Claude"; "i")) or (.workflowName // "" | test("Claude"; "i"))) | {name, status, conclusion, detailsUrl}'
```

If the `Claude Code Review` check run says issues were found but inline comments are missing, open/use the Details URL and process the findings from the check output.

**6d. Process ultrareview output (max only):**

Treat `claude ultrareview` findings like reviewer comments. Fix real bugs and push; decline only with a concrete technical reason. Because ultrareview is explicit and cost-bearing, include its status, session URL, and findings count in the final report even if it finds nothing. Do not rerun ultrareview automatically after fixes.

**6e. Comment evaluation — for selected reviewers:**

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

**6f. Re-poll after fixes (Monitor with baseline):**

After each push, start a NEW Monitor for **only the bot whose comments were fixed**. The Monitor must compare against the count BEFORE the fix (baseline), so it exits on the NEXT bot response, not the existing ones.

For Copilot, also re-request the review first:
```bash
gh pr edit $PR_NUM --add-reviewer copilot-pull-request-reviewer 2>/dev/null || true
```

For Claude Code Review, request a one-shot re-review only when `REVIEW_LEVEL` is `medium` or `max`:
```bash
if [ "$REVIEW_LEVEL" != "simple" ]; then
  gh pr comment "$PR_NUM" --body "@claude review once

Re-review after fixes. Focus only on remaining actionable correctness, security, regression, and explicit project-rule issues."
fi
```

Then start a new Monitor or bounded polling loop with count baselines for the fixed reviewer only. Use the same channels as step 5: Codex issue/review/inline, Copilot review/inline, Claude issue/review/inline/check run.

**Do NOT** use `sleep 240 && gh api` after a fix — same blocking-thread issue as step 5.

**Exit loop when:**
- Bot says "no major issues" / LGTM / 👍
- No new unprocessed comments after last push
- Max 10 iterations reached (per bot)

### 7. Report & merge

**7a. Final report:**

```markdown
## PR Review Summary
| | Count |
|---|---|
| **Review level** | simple / medium / max |
| **Codex iterations** | N |
| **Codex comments fixed** | M |
| **Codex comments declined** | K |
| **Copilot iterations** | N |
| **Copilot comments fixed** | M |
| **Copilot comments declined** | K |
| **Claude Code Review iterations** | N |
| **Claude comments/check findings fixed** | M |
| **Claude comments/check findings declined** | K |
| **Claude Code Review** | skipped by level / unavailable / clean / findings fixed |
| **Claude ultrareview** | skipped by level / clean / findings fixed / failed |
| **Status** | ✅ Ready to merge / ⚠️ Needs attention |
```

Show the PR URL.

**7b. Merge (depends on mode):**

**Auto mode (default) AND status is "ready":**
```bash
gh pr merge $PR_NUM --squash --delete-branch
```
Tell user: PR merged automatically.

**Wait mode:**
Ask user: "PR is ready to merge. Merge now?"
- Yes → `gh pr merge $PR_NUM --squash --delete-branch`
- No → leave PR open

**Max level:** never auto-merge without explicitly reporting ultrareview status and asking the user to merge, even if auto mode was otherwise selected.

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

This skill works with any subset of reviewers:

| Reviewer | Levels | Trigger | Detection |
|---|---|---|---|
| Codex | all levels | `@codex ...` PR comment | `chatgpt-codex-connector[bot]` issue comments, reviews, inline comments |
| Copilot | all levels | `--add-reviewer copilot-pull-request-reviewer` | `copilot-pull-request-reviewer[bot]` reviews, `Copilot` inline comments |
| Claude Code Review | medium/max only | `@claude review once` top-level PR comment | Claude issue comments, reviews, inline comments, `Claude Code Review` check runs |
| Claude ultrareview | max only | `claude ultrareview <PR>` | CLI output and session URL |

Never fail because a selected reviewer is unavailable. Continue with the remaining selected reviewers, but be explicit in the final report about anything skipped by level or unavailable.
