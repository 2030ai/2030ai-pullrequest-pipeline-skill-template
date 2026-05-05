# Pullrequest Skill Template

Claude Code PR workflow for repositories that want an automated review loop before merge.

It creates or reuses a PR, runs project checks, asks selected AI reviewers, processes actionable comments, pushes fixes, and reports the result before merge.

## Review Levels

| Level | Command | Reviewers |
|---|---|---|
| Simple | `/pullrequest` | Codex + Copilot |
| Medium | `/pullrequest medium` or `/pullrequest claude` | Codex + Copilot + Claude Code Review |
| Max | `/pullrequest max`, `/pullrequest ultra`, `/pullrequest ultrareview` | Medium + one Claude ultrareview |

`wait` is independent:

```bash
/pullrequest wait medium
```

If several level aliases are present, the strongest wins: `max > medium > simple`. Max always reports ultrareview status and asks before merge.

## Install

From your repository root:

```bash
mkdir -p .claude/commands .claude/skills/pullrequest

curl -sL https://raw.githubusercontent.com/2030ai/2030ai-pullrequest-pipeline-skill-template/main/.claude/commands/pullrequest.md \
  -o .claude/commands/pullrequest.md

curl -sL https://raw.githubusercontent.com/2030ai/2030ai-pullrequest-pipeline-skill-template/main/.claude/skills/pullrequest/SKILL.md \
  -o .claude/skills/pullrequest/SKILL.md
```

For global install, use the same files under `~/.claude/`.

## Requirements

| Requirement | Needed for |
|---|---|
| Claude Code | Running the skill |
| GitHub CLI (`gh auth login`) | PR creation, review requests, merge |
| Codex GitHub App | Codex review |
| GitHub Copilot Code Review | Copilot review |
| Claude Code Review integration | Medium/max review |
| Claude CLI | Max ultrareview |

Missing reviewers do not fail the pipeline. The skill records them as unavailable and continues with the reviewers that are configured.

## Workflow

1. Read project rules from `AGENTS.md` / `CLAUDE.md`.
2. Run available tests and lint commands.
3. Sync and rebase the feature branch.
4. Create or reuse the PR.
5. Trigger the selected review level.
6. Fix or decline reviewer comments with reasons.
7. Report review status and merge according to mode.

## Notes

- Default mode is intentionally cheaper: Codex + Copilot only.
- Use `medium` when Claude Code Review is worth the extra cost.
- Use `max` only for important PRs; ultrareview runs once per invocation and is not rerun automatically after fixes.
- The default merge strategy is squash merge.
- Fork-based repositories may need to adapt remote names and PR creation commands.

## License

[MIT](LICENSE)
