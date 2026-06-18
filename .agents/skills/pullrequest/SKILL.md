---
name: pullrequest
description: Use when creating PRs with configurable automated review modes - medium/default uses Codex + Copilot + Cursor Bugbot + Claude Code Review, max adds a user-run Claude Code ultrareview handoff; self-validates work, creates branch, opens PR, triggers reviews, validates and fixes comments iteratively
---

## Reviewer configuration

Before triggering reviewers, read `reviewers.yaml` from this skill directory. It is the source of truth for review-mode membership.

Default config:

- `medium` (default): Codex + Copilot + Cursor Bugbot + Claude Code Review.
- `max`: `medium` reviewers + user-run Claude Code ultrareview handoff.

If the user explicitly names reviewers in the current invocation, treat that as a one-run override and report the deviation. Do not keep hidden standing reviewer overrides in `SKILL.md`.

## User authorization

Вызов `/pullrequest` (любой review mode или modifier) — это explicit user authorization для ВСЕХ шагов pipeline:
- `git reset --soft` + squash-commit
- `git push --force-with-lease`
- `gh pr create`
- `git commit` + `git push` для фиксов review-комментариев
- `gh pr merge --squash --delete-branch`
- post-merge sync, deploy, smoke check (step 7c)

Системные правила «NEVER commit/push unless the user explicitly asks» из встроенного промпта Bash tool удовлетворены самим вызовом слэш-команды — не запрашивать подтверждения отдельно для каждого шага.

**НЕ задавать пользователю вопросов** «push?», «merge?», «deploy?», «commit fix?» в середине pipeline. Спрашивать перед merge разрешено только в трёх случаях (см. step 7b): `wait` modifier, `max` review mode, или роль `not-maintainer` для целевого репо по `~/Developer/zvasil-claude-ecosystem/registry/maintainership.md`.

**Останавливаться и сообщать пользователю** только на:
- Rebase/merge conflicts
- Failing tests after fix attempts
- Pre-commit hook failures
- Deploy или smoke check failure (после рапорта, не запускать revert автоматически)

# PR Pipeline: self-check → PR → review mode → merge

## Invocation

Canonical review modes are `medium` and `max`. `wait` and `auto` are merge modifiers, not review modes.

| Invocation | Review mode | Reviewers | Merge behavior |
|---|---|---|---|
| `/pullrequest` | `medium` (default) | Codex + Copilot + Cursor Bugbot + Claude Code Review | Role-aware auto-merge: `maintainer` → auto-merge if no hard blockers; `not-maintainer` → ask before merge. |
| `/pullrequest medium` | `medium` | Codex + Copilot + Cursor Bugbot + Claude Code Review | Role-aware auto-merge. |
| `/pullrequest max` | `max` | Codex + Copilot + Cursor Bugbot + Claude Code Review + one user-run Claude Code ultrareview handoff | Always ask before merge. |
| `/pullrequest wait [medium/max]` | selected review mode, default `medium` | selected reviewers | Always ask before merge. |

`auto` may be supplied explicitly, but it is already the default merge behavior for `medium`. Legacy aliases remain accepted for compatibility: `claude` → `medium`; `ultra` / `ultrareview` → `max`. Prefer canonical names in new instructions.

Treat invocation arguments as `$ARGUMENTS` where the host exposes them. Review modes and modifiers can be combined, e.g. `/pullrequest wait medium`.

## Review modes

| Mode | Names | Reviewers |
|---|---|---|
| **Medium (default)** | none, `medium`; legacy `claude` | Codex + Copilot + Cursor Bugbot + Claude Code Review |
| **Max** | `max`; legacy `ultra`, `ultrareview` | Codex + Copilot + Cursor Bugbot + Claude Code Review + one user-run Claude Code ultrareview handoff |

Parse `$ARGUMENTS` once before triggering reviewers. If several review-mode tokens are present, use the highest mode: `max > medium`. `wait` controls merge confirmation only; it does not change review mode.

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
  │ review mode          │
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
# Pick one matching test runner. If the selected runner fails, stop and fix it;
# do not fall through to another runner or hide the failure with `|| true`.
if [ -f package.json ] && command -v pnpm >/dev/null 2>&1 && pnpm run | rg -q '^  test\b'; then
  pnpm test
elif [ -f package.json ] && command -v npm >/dev/null 2>&1 && npm run | rg -q '^  test\b'; then
  npm test
elif [ -f package.json ] && command -v yarn >/dev/null 2>&1 && yarn run | rg -q '^  test\b'; then
  yarn test
elif [ -f Makefile ] && rg -q '^test:' Makefile; then
  make test
elif [ -f pyproject.toml ] || [ -d tests ]; then
  pytest
elif rg --files -g 'go.mod' | rg -q .; then
  go test ./...
elif [ -f Cargo.toml ]; then
  cargo test
else
  echo "No test runner found"
fi
```

Also try lint if available:
```bash
if [ -f package.json ] && command -v pnpm >/dev/null 2>&1 && pnpm run | rg -q '^  lint\b'; then
  pnpm lint
elif [ -f package.json ] && command -v npm >/dev/null 2>&1 && npm run | rg -q '^  lint\b'; then
  npm run lint
elif [ -f Makefile ] && rg -q '^lint:' Makefile; then
  make lint
else
  echo "No lint runner found"
fi
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
BASE_REF="origin/$DEFAULT_BRANCH"
COMMIT_COUNT=$(git rev-list --count ${BASE_REF}..HEAD)
if [ "$COMMIT_COUNT" -gt 1 ]; then
  git reset --soft ${BASE_REF}
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

### 4. Trigger selected review mode

Determine `REVIEW_LEVEL` once. Then read `reviewers.yaml` and launch only the reviewers configured for that mode. If `reviewers.yaml` is missing or cannot be parsed, stop and report that the skill install is incomplete; do not silently fall back to hidden reviewer defaults.

```bash
REVIEW_LEVEL=medium
if printf '%s\n' "$ARGUMENTS" | rg -qi '\b(max|ultra|ultrareview)\b'; then
  REVIEW_LEVEL=max
elif printf '%s\n' "$ARGUMENTS" | rg -qi '\b(medium|claude)\b'; then
  REVIEW_LEVEL=medium
fi
echo "Review mode: $REVIEW_LEVEL"
```

After reading `reviewers.yaml`, set reviewer flags before triggering anything:

```text
RUN_CODEX=1 only when `codex` is listed for REVIEW_LEVEL.
RUN_COPILOT=1 only when `copilot` is listed for REVIEW_LEVEL.
RUN_CURSOR=1 only when `cursor_bugbot` is listed for REVIEW_LEVEL.
RUN_CLAUDE=1 only when `claude_code_review` is listed for REVIEW_LEVEL.
ULTRAREVIEW_MODE is the configured `ultrareview` value for REVIEW_LEVEL.
```

Current default config:

- `medium`: all four reviewer flags `1`; `ULTRAREVIEW_MODE=none`.
- `max`: all four reviewer flags `1`; `ULTRAREVIEW_MODE=user_run_handoff`.

**4a. Trigger Codex review if selected:**
```bash
PR_NUM=<number>
if [ "${RUN_CODEX:-0}" = "1" ]; then
  gh pr comment $PR_NUM --body "@codex Please review this PR:

## Checklist
- [ ] **Bugs & Security**: logic errors, vulnerabilities, edge cases
- [ ] **Side Effects**: unintended changes in other parts of codebase
- [ ] **Consistency**: follows project patterns and code style
- [ ] **Documentation**: README, comments, docs updated if needed

Reply with 👍 if no issues found."
else
  CODEX_SKIPPED_BY_CONFIG=1
fi
```

If `@codex` is unknown — set `CODEX_AVAILABLE=0`, skip Codex tracking.

**4b. Request Copilot review if selected:**
```bash
if [ "${RUN_COPILOT:-0}" = "1" ]; then
  gh pr edit $PR_NUM --add-reviewer copilot-pull-request-reviewer 2>/dev/null || true
else
  COPILOT_SKIPPED_BY_CONFIG=1
fi
```

If this fails (Copilot not enabled) — set `COPILOT_AVAILABLE=0`, skip Copilot tracking.

**4c. Trigger Claude Code Review if selected:**

Use `review once` by default to avoid subscribing the PR to paid review on every later push. The command must be the first line of a top-level PR comment.

```bash
if [ "${RUN_CLAUDE:-0}" = "1" ]; then
  gh pr comment "$PR_NUM" --body "@claude review once

Focus on actionable correctness, security, regression, and project-rule issues introduced by this PR. Avoid style-only feedback unless it reflects an explicit repo rule."
else
  CLAUDE_SKIPPED_BY_CONFIG=1
fi
```

If `RUN_CLAUDE=0`, do not track Claude. If Claude is selected and no Claude Code Review check, Claude comment, review, or reaction appears after the wait window — set `CLAUDE_AVAILABLE=0`, skip Claude tracking, and continue. Do not fail the PR pipeline solely because Claude is not enabled for the repository.

**4d. Trigger Cursor Bugbot if selected:**

Use `@cursor review` as a top-level PR comment. The command must be the first line so GitHub routes it to Cursor/Bugbot reliably. If this mention-style trigger does not get any Cursor/Bugbot signal, use documented Bugbot fallback `cursor review` once before marking Cursor unavailable.

```bash
if [ "${RUN_CURSOR:-0}" = "1" ]; then
  CURSOR_REVIEW_COMMAND="@cursor review"
  gh pr comment "$PR_NUM" --body "@cursor review

Focus on actionable correctness, security, regression, and project-rule issues introduced by this PR. Avoid style-only feedback unless it reflects an explicit repo rule."
else
  CURSOR_SKIPPED_BY_CONFIG=1
fi
```

If `RUN_CURSOR=0`, do not track Cursor. If Cursor is selected and no Cursor/Bugbot comment, review, check, or reaction appears after the primary wait window, post a second top-level PR comment whose first line is `cursor review`, set `CURSOR_REVIEW_COMMAND="cursor review"`, and monitor once more. If the fallback also produces no Cursor/Bugbot signal, set `CURSOR_AVAILABLE=0`, skip Cursor tracking, and continue. Do not fail the PR pipeline solely because Cursor Bugbot is not enabled for the repository.

**4e. Claude Code ultrareview handoff if configured:**

Ultrareview is separate from GitHub Code Review. It must be explicitly requested through `max` review mode because it may consume free runs or extra usage.

Do not launch cost-bearing ultrareview from the agent shell. Use the `user_run_handoff` flow from `reviewers.yaml`:

1. Verify the target before preparing the handoff.
2. Give the user Prompt 1: a prep prompt for Claude Code CLI that verifies worktree, branch, head SHA, base SHA, clean status, and diff, and prints `READY_FOR_ULTRAREVIEW` without launching review.
3. Give the user Prompt 2: the clean slash command only, with no prose appended to the command arguments.
4. Wait for user-provided launch output, task notification, or findings before claiming ultrareview ran.
5. Process findings like max-level review feedback. Do not rerun ultrareview automatically after fixes unless the user explicitly asks.

```bash
if [ "${ULTRAREVIEW_MODE:-none}" = "user_run_handoff" ]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  BRANCH=$(git branch --show-current)
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
  BASE_REF="origin/$DEFAULT_BRANCH"
  LOCAL_HEAD="$(git rev-parse HEAD)"
  PR_HEAD="$(gh pr view "$PR_NUM" --repo "$REPO" --json headRefOid -q .headRefOid)"
  BASE_SHA="$(git rev-parse "$BASE_REF")"
  git status --short --branch
  test -z "$(git status --porcelain)"
  test "$LOCAL_HEAD" = "$PR_HEAD"
  git merge-base --is-ancestor "$BASE_REF" HEAD
  git diff --shortstat "$BASE_REF"...HEAD
  git diff --name-only "$BASE_REF"...HEAD | wc -l
fi
```

Preferred Prompt 2 is branch/base mode from the current PR worktree:

```text
/ultrareview origin/<default-branch>
```

Alternate if the CLI lacks `/ultrareview`:

```text
/code-review ultra origin/<default-branch>
```

Use PR-number mode only when the target repo, PR number, head SHA, and base are verified for the Claude Code session:

```text
/ultrareview <PR_NUM>
```

Do not append review instructions to `/ultrareview` or `/code-review ultra` arguments. Claude Code parses the whole argument string as the target and can fail if prose is appended.

Handoff template:

```text
Claude Code ultrareview handoff is ready.
Paste Prompt 1 into Claude Code CLI:

Use EnterWorktree to enter this existing worktree: <absolute worktree path>. Verify:
- pwd equals <absolute worktree path>
- branch equals <branch>
- HEAD equals <LOCAL_HEAD>
- base ref <BASE_REF> equals <BASE_SHA>
- git status --porcelain is empty
- git diff --shortstat <BASE_REF>...HEAD equals: <shortstat>

Do not launch ultrareview. If all checks pass, print READY_FOR_ULTRAREVIEW. If anything differs, stop and report the mismatch.

If Prompt 1 prints READY_FOR_ULTRAREVIEW, paste Prompt 2 into Claude Code CLI:

/ultrareview <BASE_REF>

Important: run the second prompt only after Prompt 1 prints READY_FOR_ULTRAREVIEW. Do not append any scope note to the slash command.
```

In `max` review mode, do not merge until ultrareview status has been reported and any findings have been evaluated.

### 5. Wait for bot reviews

**CRITICAL**: Reviewers typically respond in 3-5 minutes. Do NOT give up early.

**NEVER use one-shot waits like `sleep N && gh api ...`.** Use `/wait-bot-review`, a Monitor/background task if the host supports it, or a bounded polling loop with a timeout. Polling loops are allowed for bot review because they keep checking until a real reviewer response appears.

Track selected reviewers independently according to `reviewers.yaml`: initialize `*_FOUND=0` only for reviewers selected by the current config/mode.

**5a. Codex Monitor** (skip if not selected or `CODEX_AVAILABLE=0`):

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

**5b. Copilot Monitor** (skip if not selected or `COPILOT_AVAILABLE=0`):

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

**5c. Claude Monitor** (skip if not selected or `CLAUDE_AVAILABLE=0`):

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

**5d. Cursor Monitor** (skip if not selected or `CURSOR_AVAILABLE=0`):

Cursor/Bugbot can surface results as issue comments, PR reviews, inline comments, or checks. Check all channels and match either `cursor` or `bugbot` in the bot/check identity:

```
Monitor(
  description: "Cursor Bugbot review on PR #${PR_NUM}",
  timeout_ms: 1800000,
  persistent: false,
  command: "REPO='${REPO}'; PR=${PR_NUM}; while true; do \
    I=$(gh api \"repos/$REPO/issues/$PR/comments\" --jq '[.[] | select(.user.login | test(\"cursor|bugbot\"; \"i\"))] | length' 2>/dev/null || echo 0); \
    R=$(gh api \"repos/$REPO/pulls/$PR/reviews\" --jq '[.[] | select(.user.login | test(\"cursor|bugbot\"; \"i\"))] | length' 2>/dev/null || echo 0); \
    L=$(gh api \"repos/$REPO/pulls/$PR/comments\" --jq '[.[] | select(.user.login | test(\"cursor|bugbot\"; \"i\"))] | length' 2>/dev/null || echo 0); \
    C=$(gh pr view $PR --repo \"$REPO\" --json statusCheckRollup --jq '[.statusCheckRollup[]? | select((.name // \"\" | test(\"Cursor|Bugbot\"; \"i\")) or (.workflowName // \"\" | test(\"Cursor|Bugbot\"; \"i\")))] | length' 2>/dev/null || echo 0); \
    if [ \"$((I + R + L + C))\" -gt 0 ]; then echo \"Cursor Bugbot responded: issues=$I reviews=$R inline=$L checks=$C\"; exit 0; fi; \
    sleep 30; done"
)
```

If this monitor times out after the primary `@cursor review` trigger, post the documented fallback and run the Cursor Monitor once more:

```bash
if [ "${RUN_CURSOR:-0}" = "1" ] && [ "${CURSOR_FALLBACK_TRIED:-0}" != "1" ]; then
  CURSOR_FALLBACK_TRIED=1
  CURSOR_REVIEW_COMMAND="cursor review"
  gh pr comment "$PR_NUM" --body "cursor review

Focus on actionable correctness, security, regression, and project-rule issues introduced by this PR. Avoid style-only feedback unless it reflects an explicit repo rule."
fi
```

**5e. Continue when notifications arrive:**

Each Monitor sends a notification on first detection or timeout. If Monitor is unavailable, use equivalent bounded polling loops. After receiving notification(s) for all selected reviewers, proceed to step 6.

**Re-poll after fixes** — when you push corrections in step 6, start a NEW Monitor with `INITIAL_R/INITIAL_L` baselines (compare new counts against the count before the fix), so the Monitor exits when the bot leaves a NEW review/comment, not the old one.

**Alternative**: invoke `/wait-bot-review <PR> <bot-login>` for one reviewer at a time. For Claude Code Review and Cursor Bugbot, also inspect their check runs because findings may live in check output/annotations even if GitHub rejects an inline comment.

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

**6c. Process Claude comments/checks (selected only, up to 10 iterations):**

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

**6d. Process Cursor Bugbot comments/checks (selected only, up to 10 iterations):**

Cursor Bugbot may post inline comments, reviews, top-level comments, and checks. Check all sources:

```bash
# Cursor/Bugbot top-level comments:
gh api "repos/${REPO}/issues/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("cursor|bugbot"; "i")) | {id: .id, body: .body}'

# Cursor/Bugbot inline PR comments:
gh api "repos/${REPO}/pulls/${PR_NUM}/comments" \
  --jq '.[] | select(.user.login | test("cursor|bugbot"; "i")) | {id: .id, path: .path, line: .line, body: .body, in_reply_to_id: .in_reply_to_id}'

# Cursor/Bugbot review/check run summary:
gh pr view "$PR_NUM" --repo "$REPO" --json statusCheckRollup \
  --jq '.statusCheckRollup[]? | select((.name // "" | test("Cursor|Bugbot"; "i")) or (.workflowName // "" | test("Cursor|Bugbot"; "i"))) | {name, status, conclusion, detailsUrl}'
```

If a Cursor/Bugbot check says issues were found but inline comments are missing, open/use the Details URL and process the findings from the check output.

**6e. Process ultrareview output (configured `user_run_handoff` only):**

Treat user-provided Claude Code ultrareview findings like reviewer comments. Fix real bugs and push; decline only with a concrete technical reason. Because ultrareview is explicit and cost-bearing, include its status and findings count in the final report even if it finds nothing. Do not rerun ultrareview automatically after fixes.

**6f. Comment evaluation — for selected reviewers:**

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

**6g. Re-poll after fixes (Monitor with baseline):**

After each push, start a NEW Monitor for **only the bot whose comments were fixed**. The Monitor must compare against the count BEFORE the fix (baseline), so it exits on the NEXT bot response, not the existing ones.

For Copilot, also re-request the review first:
```bash
gh pr edit $PR_NUM --add-reviewer copilot-pull-request-reviewer 2>/dev/null || true
```

For Claude Code Review, request a one-shot re-review only when `claude_code_review` is selected:
```bash
if [ "${RUN_CLAUDE:-0}" = "1" ]; then
  gh pr comment "$PR_NUM" --body "@claude review once

Re-review after fixes. Focus only on remaining actionable correctness, security, regression, and explicit project-rule issues."
fi
```

For Cursor Bugbot, request a re-review only when `cursor_bugbot` is selected and the fixed comment came from Cursor:
```bash
if [ "${RUN_CURSOR:-0}" = "1" ]; then
  CURSOR_REVIEW_COMMAND=${CURSOR_REVIEW_COMMAND:-"@cursor review"}
  gh pr comment "$PR_NUM" --body "$CURSOR_REVIEW_COMMAND

Re-review after fixes. Focus only on remaining actionable correctness, security, regression, and explicit project-rule issues."
fi
```

Then start a new Monitor or bounded polling loop with count baselines for the fixed reviewer only. Use the same channels as step 5: Codex issue/review/inline, Copilot review/inline, Claude issue/review/inline/check run, Cursor issue/review/inline/check run.

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
| **Review mode** | medium / max |
| **Codex iterations** | N |
| **Codex comments fixed** | M |
| **Codex comments declined** | K |
| **Copilot iterations** | N |
| **Copilot comments fixed** | M |
| **Copilot comments declined** | K |
| **Cursor Bugbot iterations** | N |
| **Cursor comments/check findings fixed** | M |
| **Cursor comments/check findings declined** | K |
| **Claude Code Review iterations** | N |
| **Claude comments/check findings fixed** | M |
| **Claude comments/check findings declined** | K |
| **Codex** | skipped by config / unavailable / clean / findings fixed |
| **Copilot** | skipped by config / unavailable / clean / findings fixed |
| **Cursor Bugbot** | skipped by config / unavailable / clean / findings fixed |
| **Claude Code Review** | skipped by config / unavailable / clean / findings fixed |
| **Claude ultrareview** | skipped by config / pending user-run / clean / findings fixed / failed |
| **Squash commit on main** | ✅ verified / ❌ missing / ⏭️ project override |
| **Deploy** | ✅ green / ❌ failed / ⏭️ no workflow / ⏭️ project override |
| **Post-deploy smoke/e2e** | ✅ pass / ❌ fail / ⏭️ no suite / ⏭️ project override |
| **Status** | ✅ Ready to merge / ⚠️ Needs attention |
```

Show the PR URL.

**7b. Merge (depends on mode and maintainership role):**

**Determine maintainership role first.**

Read role from ecosystem registry — `~/Developer/zvasil-claude-ecosystem/registry/maintainership.md`:

```bash
REGISTRY="$HOME/Developer/zvasil-claude-ecosystem/registry/maintainership.md"
NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
OWNER="${NWO%%/*}"

# Repo-level override (line: `| owner/repo | role | ...`)
ROLE=$(awk -F'|' -v key="$NWO" 'NR>1 && $2 ~ "^[[:space:]]*"key"[[:space:]]*$" {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3; exit}' "$REGISTRY" 2>/dev/null)

# Owner-level rule fallback (line: `| owner | role | ...`)
[ -z "$ROLE" ] && ROLE=$(awk -F'|' -v key="$OWNER" 'NR>1 && $2 ~ "^[[:space:]]*"key"[[:space:]]*$" {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3; exit}' "$REGISTRY" 2>/dev/null)

# Conservative default — never auto-merge if role unknown
ROLE=${ROLE:-not-maintainer}
echo "maintainership: $NWO → $ROLE"
```

If `gh repo view` fails (no remote, custom git host, no GitHub auth) → `ROLE=not-maintainer`.

**Hard blockers — check before any merge.**

```bash
gh pr view "$PR_NUM" --json mergeable,mergeStateStatus,reviewDecision,statusCheckRollup
```

A merge is blocked if any of:
- `mergeable == "CONFLICTING"` or `mergeStateStatus == "DIRTY"` (rebase conflict).
- `reviewDecision == "CHANGES_REQUESTED"` (reviewer explicitly requested changes).
- Any required check has `conclusion != "SUCCESS"` and `conclusion != "NEUTRAL"`.

Declined-but-acknowledged review comments, optional CI workflows, or `⏭️ project override` cells in the 7a table do **not** block.

**Medium without `wait` AND `ROLE=="maintainer"` AND no hard blockers:**
```bash
gh pr merge $PR_NUM --squash --delete-branch
```
Tell user: `PR merged automatically (maintainer of $NWO).`

**Medium without `wait` AND `ROLE=="not-maintainer"`:**
Ask user: `"PR ready to merge. You're not the sole maintainer of $NWO per registry. Merge now?"`
- Yes → `gh pr merge $PR_NUM --squash --delete-branch`
- No → leave PR open with explicit handoff in the final report.

**`wait` modifier (any role):**
Ask user: `"PR is ready to merge. Merge now?"`
- Yes → `gh pr merge $PR_NUM --squash --delete-branch`
- No → leave PR open.

**Max review mode (any role):** never auto-merge without explicitly reporting ultrareview status and asking the user to merge, even if `ROLE=="maintainer"`. Auto-merge protection is intentional for the costly ultrareview path.

**If merge fails** (conflicts, checks not passed) — report error, do NOT retry blindly.

### 7c. Post-merge verification

После успешного `gh pr merge` — проверить, что изменения попали на main, деплой прошёл и сервис работает.

**Pre-check (project override):** прочитать `CLAUDE.md` / `AGENTS.md` проекта. Если там явная инструкция типа `post-merge verification: skip` или указан собственный deploy/release pipeline (как в markpad, fresco) — **пропустить весь step 7c** и упомянуть override в финальном отчёте.

**7c.1. Sync default branch и verify squash-commit landed:**
```bash
git checkout $DEFAULT_BRANCH
git pull origin $DEFAULT_BRANCH
LANDED=$(git log -1 --pretty='%s')
echo "Last commit on $DEFAULT_BRANCH: $LANDED"
# ожидаем PR title в LANDED
```

Если последний коммит не совпадает с PR title — сообщить пользователю «squash-commit not found on main» и остановиться.

**7c.2. Deploy:**

Детектировать deploy workflow в порядке приоритета:
1. **GitHub Actions deploy workflow** — `gh run list --workflow=deploy.yml --branch=$DEFAULT_BRANCH -L1 --json databaseId -q '.[0].databaseId'` → `gh run watch <id>`. Ждать success/failure через `gh run watch` или `/wait-ci` (per global CLAUDE.md CI/CD polling rule, БЕЗ `sleep N`).
2. **Makefile target** — `make deploy` если есть `deploy:` в Makefile.
3. **package.json script** — `npm run deploy` / `pnpm deploy` / `yarn deploy` если есть в `scripts`.
4. **Custom deploy command** в `CLAUDE.md` / `AGENTS.md` проекта — следовать инструкции; для ожидания готовности использовать `/wait-deploy`.
5. **Если deploy не найден** — сообщить «No deploy workflow detected» и перейти к 7c.3.

**7c.3. Smoke / e2e check:**

В порядке приоритета:
1. **HTTP healthcheck** из `CLAUDE.md` / `AGENTS.md` (например, `curl -fsS https://app.example.com/healthz`).
2. **e2e suite:**
   ```bash
   npm run e2e 2>/dev/null || pnpm e2e 2>/dev/null || make e2e 2>/dev/null || \
   pytest tests/e2e 2>/dev/null || \
   make smoke 2>/dev/null || npm run smoke 2>/dev/null || \
   echo "No smoke/e2e suite detected"
   ```
3. **Если ни healthcheck, ни e2e не найдены** — сообщить «No post-deploy verification available» в финальном отчёте.

**7c.4. Failure handling:**

- Deploy упал → сообщить пользователю с output, **НЕ revertить автоматически**, ждать решения.
- Smoke/e2e упали → сообщить пользователю с output, **НЕ revertить**.
- В обоих случаях пометить итог как ⚠️ Needs attention в final report.

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
| Codex | configured in `reviewers.yaml` for medium/max | `@codex ...` PR comment | `chatgpt-codex-connector[bot]` issue comments, reviews, inline comments |
| Copilot | configured in `reviewers.yaml` for medium/max | `--add-reviewer copilot-pull-request-reviewer` | `copilot-pull-request-reviewer[bot]` reviews, `Copilot` inline comments |
| Cursor Bugbot | configured in `reviewers.yaml` for medium/max | `@cursor review` top-level PR comment; fallback `cursor review` if no signal | Cursor/Bugbot issue comments, reviews, inline comments, checks |
| Claude Code Review | configured in `reviewers.yaml` for medium/max | `@claude review once` top-level PR comment | Claude issue comments, reviews, inline comments, `Claude Code Review` check runs |
| Claude ultrareview | configured in `reviewers.yaml` for max as `user_run_handoff` | two-prompt user-run Claude Code CLI handoff; preferred command `/ultrareview <base-ref>` | user-provided launch output, task notification, or pasted findings |

Never fail because a selected reviewer is unavailable. Continue with the remaining selected reviewers, but be explicit in the final report about anything skipped by mode or unavailable.
