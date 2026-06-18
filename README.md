# Pullrequest Skill Template

Claude Code PR workflow for repositories that want an automated review loop before merge.

It creates or reuses a PR, runs project checks, asks selected AI reviewers, processes actionable comments, pushes fixes, and reports the result before merge.

## Review Modes

| Mode | Command | Reviewers |
|---|---|---|
| Medium | `/pullrequest` or `/pullrequest medium` or `/pullrequest claude` | Codex + Copilot + Cursor Bugbot + Claude Code Review |
| Max | `/pullrequest max`, `/pullrequest ultra`, or `/pullrequest ultrareview` | Medium + one user-run Claude Code ultrareview handoff |

`wait` is independent:

```bash
/pullrequest wait medium
```

If several mode aliases are present, the strongest wins: `max > medium`. Max always reports ultrareview status and asks before merge.

## Install

From your repository root:

```bash
mkdir -p .agents/skills/pullrequest .agents/skills/endsession .claude/skills .codex/skills .cursor/skills

curl -sL https://raw.githubusercontent.com/2030ai/2030ai-pullrequest-pipeline-skill-template/main/.agents/skills/pullrequest/SKILL.md \
  -o .agents/skills/pullrequest/SKILL.md

curl -sL https://raw.githubusercontent.com/2030ai/2030ai-pullrequest-pipeline-skill-template/main/.agents/skills/pullrequest/reviewers.yaml \
  -o .agents/skills/pullrequest/reviewers.yaml

curl -sL https://raw.githubusercontent.com/2030ai/2030ai-pullrequest-pipeline-skill-template/main/.agents/skills/endsession/SKILL.md \
  -o .agents/skills/endsession/SKILL.md

ln -s ../../.agents/skills/pullrequest .claude/skills/pullrequest
ln -s ../../.agents/skills/pullrequest .codex/skills/pullrequest
ln -s ../../.agents/skills/pullrequest .cursor/skills/pullrequest

ln -s ../../.agents/skills/endsession .claude/skills/endsession
ln -s ../../.agents/skills/endsession .codex/skills/endsession
ln -s ../../.agents/skills/endsession .cursor/skills/endsession
```

For global install, copy the skill directory under `~/.claude/skills/`. Project-local installs should keep `.agents/skills/<name>/SKILL.md` as the source and use platform mirrors.

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
- Use `max` only for important PRs; ultrareview is handed off to the user and is not rerun automatically after fixes.
- The default merge strategy is squash merge.
- Fork-based repositories may need to adapt remote names and PR creation commands.

## License

[MIT](LICENSE)
