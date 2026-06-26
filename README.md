# Pullrequest Skill Template

Public template for installing project-local `/pullrequest` and `/endsession` skills into repositories that want an automated PR review loop before merge.

`/pullrequest` creates or reuses a PR, runs project checks, asks selected AI reviewers, processes actionable comments, pushes fixes, and reports the result before merge. `/endsession` closes an agent session with clean status, documentation, and handoff checks.

## Review Modes

| Mode | Command | Reviewers |
|---|---|---|
| Medium | `/pullrequest` or `/pullrequest medium` or `/pullrequest claude` | Codex + Copilot + Cursor Bugbot + Claude Code Review |
| Max | `/pullrequest max`, `/pullrequest ultra`, or `/pullrequest ultrareview` | Medium + one user-run Claude Code ultrareview handoff |

If several mode aliases are present, the strongest wins: `max > medium`. Max always reports ultrareview status and asks before merge.

## Install

From your repository root:

```bash
set -eu

BASE_URL="https://raw.githubusercontent.com/2030ai/2030ai-pullrequest-pipeline-skill-template/main"

mkdir -p \
  .agents/skills/pullrequest/agents \
  .agents/skills/endsession/agents \
  .claude/skills \
  .codex/skills \
  .cursor/skills

curl -fsSL "$BASE_URL/.agents/skills/pullrequest/SKILL.md" \
  -o .agents/skills/pullrequest/SKILL.md

curl -fsSL "$BASE_URL/.agents/skills/pullrequest/reviewers.yaml" \
  -o .agents/skills/pullrequest/reviewers.yaml

curl -fsSL "$BASE_URL/.agents/skills/pullrequest/agents/openai.yaml" \
  -o .agents/skills/pullrequest/agents/openai.yaml

curl -fsSL "$BASE_URL/.agents/skills/endsession/SKILL.md" \
  -o .agents/skills/endsession/SKILL.md

curl -fsSL "$BASE_URL/.agents/skills/endsession/agents/openai.yaml" \
  -o .agents/skills/endsession/agents/openai.yaml

curl -fsSL "$BASE_URL/.agents/pullrequest-maintainership.example.md" \
  -o .agents/pullrequest-maintainership.example.md

link_skill() {
  platform_dir="$1"
  skill_name="$2"
  target="../../.agents/skills/$skill_name"
  link="$platform_dir/skills/$skill_name"

  if [ -e "$link" ] || [ -L "$link" ]; then
    current_target="$(readlink "$link" 2>/dev/null || true)"
    if [ "$current_target" != "$target" ]; then
      echo "Refusing to overwrite existing $link" >&2
      exit 1
    fi
    rm "$link"
  fi

  ln -s "$target" "$link"
}

for platform_dir in .claude .codex .cursor; do
  link_skill "$platform_dir" pullrequest
  link_skill "$platform_dir" endsession
done
```

Verify the project-local install:

```bash
test -f .agents/skills/pullrequest/SKILL.md
test -f .agents/skills/pullrequest/reviewers.yaml
test -f .agents/skills/pullrequest/agents/openai.yaml
test -f .agents/skills/endsession/SKILL.md
test -f .agents/skills/endsession/agents/openai.yaml
test -f .agents/pullrequest-maintainership.example.md
test "$(readlink .claude/skills/pullrequest)" = "../../.agents/skills/pullrequest"
test "$(readlink .codex/skills/pullrequest)" = "../../.agents/skills/pullrequest"
test "$(readlink .cursor/skills/pullrequest)" = "../../.agents/skills/pullrequest"
test "$(readlink .claude/skills/endsession)" = "../../.agents/skills/endsession"
test "$(readlink .codex/skills/endsession)" = "../../.agents/skills/endsession"
test "$(readlink .cursor/skills/endsession)" = "../../.agents/skills/endsession"
```

For global install, copy the full skill directory under `~/.claude/skills/`. Project-local installs should keep `.agents/skills/<name>/` as the source and use platform mirrors.

## Requirements

| Requirement | Needed for |
|---|---|
| Claude Code | Running the skill |
| GitHub CLI (`gh auth login`) | PR creation, review requests, merge |
| Codex GitHub App | Codex review |
| GitHub Copilot Code Review | Copilot review |
| Cursor Bugbot GitHub App | Medium/max Cursor review (`@cursor review`, with `cursor review` fallback) |
| Claude Code Review integration | Medium/max review |
| Claude Code CLI access | Max ultrareview user-run handoff |

Missing reviewers do not fail the pipeline. The skill records them as unavailable and continues with the reviewers that are configured.

## Public Template Defaults

The default `/pullrequest` mode is `medium`, so it attempts to trigger every reviewer listed for `medium` in `reviewers.yaml`: Codex, Copilot, Cursor Bugbot, and Claude Code Review. Before using this in a team or public repository, edit `.agents/skills/pullrequest/reviewers.yaml` to remove reviewers you have not installed, do not trust, or do not want to pay for.

For merge safety, this template treats maintainership as unknown unless the repository defines an optional project-local maintainership table at `.agents/pullrequest-maintainership.md` or `.github/pullrequest-maintainership.md`. Without that file, medium-mode PRs ask before merge instead of auto-merging.

Max mode never launches ultrareview from the agent shell. It prepares a user-run Claude Code handoff so the human can decide whether to spend that review run.

## Reviewer Configuration Examples

Edit `.agents/skills/pullrequest/reviewers.yaml` after installation.

Minimal Codex-only mode:

```yaml
review_modes:
  medium:
    reviewers:
      - codex
    ultrareview: none

  max:
    reviewers:
      - codex
    ultrareview: user_run_handoff
```

Copilot-only mode:

```yaml
review_modes:
  medium:
    reviewers:
      - copilot
    ultrareview: none

  max:
    reviewers:
      - copilot
    ultrareview: user_run_handoff
```

No auto-merge by default: do nothing. Without a maintainership file, `/pullrequest` treats the repository as `not-maintainer` and asks before merge.

Allow medium-mode auto-merge for a maintained repository by adding `.agents/pullrequest-maintainership.md` or `.github/pullrequest-maintainership.md`:

```markdown
| target | role | notes |
|---|---|---|
| owner/repo | maintainer | auto-merge allowed for medium mode |
| owner | not-maintainer | ask before merge |
```

Use the repository-level row for exact control. The owner-level row is a fallback for all repositories under that owner.

This repository also ships `.agents/pullrequest-maintainership.example.md` as a copyable starting point. Do not rename it to `pullrequest-maintainership.md` until you have replaced the example targets with your real GitHub owner or repository.

## Workflow

1. Read project rules from `AGENTS.md` / `CLAUDE.md`.
2. Run available tests and lint commands.
3. Sync and rebase the feature branch.
4. Create or reuse the PR.
5. Trigger the selected review mode from `reviewers.yaml`.
6. Fix or decline reviewer comments with reasons.
7. Report review status and merge according to mode.

## Notes

- Default mode is `medium`: Codex + Copilot + Cursor Bugbot + Claude Code Review.
- `reviewers.yaml` is the source of truth for which reviewers participate in each mode.
- `agents/openai.yaml` files provide display metadata for Codex/OpenAI skill surfaces and should be copied with each skill directory.
- Use `max` only for important PRs; ultrareview is handed off to the user and is not rerun automatically after fixes.
- The default merge strategy is squash merge.
- Fork-based repositories may need to adapt remote names and PR creation commands.

## License

[MIT](LICENSE)
