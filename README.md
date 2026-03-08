# `/pullrequest` — PR Pipeline Skill for Claude Code

A [Claude Code](https://claude.com/claude-code) skill that automates the entire PR lifecycle: **self-check → create PR → AI code review → merge**.

It runs two independent review loops — **Codex** and **Copilot** — validates each comment, auto-fixes real issues, declines noise, and merges when ready.

```
/pullrequest          # auto-merge after review
/pullrequest wait     # ask before merge
```

---

## How it works

```
  ┌──────────────────┐
  │  1. Self-check    │  Run tests, lint, scan for secrets
  └────────┬─────────┘
           ▼
  ┌──────────────────┐
  │  2. Branch &      │  Squash commits, push
  │     Squash        │
  └────────┬─────────┘
           ▼
  ┌──────────────────┐
  │  3. Create PR     │  Or reuse existing one
  └────────┬─────────┘
           ▼
  ┌──────────────────┐
  │  4. Codex review  │◄──┐
  │     loop (poll)   │   │ fix + push
  └────────┬─────────┘   │
           │ comments ───►┘
           ▼
  ┌──────────────────┐
  │  5. Copilot review│◄──┐
  │     loop (poll)   │   │ fix + push
  └────────┬─────────┘   │
           │ comments ───►┘
           ▼
  ┌──────────────────┐
  │  6. Report &      │  Summary table + merge
  │     Merge         │
  └──────────────────┘
```

### Review loop details

Each review loop uses **polling** (every 60s, up to 15 attempts) instead of a blind `sleep`. Comments are tracked by `in_reply_to_id` — only truly unprocessed comments are handled:

- **Valid comment** (bug, vulnerability, side effect) → fix code, push, reply `Fixed: ...`
- **Invalid comment** (subjective, over-engineering) → reply `Declined: ...`
- After each push → poll for new comments, up to 10 fix iterations

### Graceful degradation

| Codex | Copilot | What happens |
|:-----:|:-------:|:-------------|
| ✅ | ✅ | Full pipeline — both review loops |
| ✅ | ❌ | Codex review only |
| ❌ | ✅ | Copilot review only |
| ❌ | ❌ | Self-check only → create PR → merge |

The skill **never fails** because a reviewer bot is unavailable.

---

## Install

### Per-project (recommended for teams)

```bash
# From repo root
mkdir -p .claude/commands .claude/skills/pullrequest

curl -sL https://raw.githubusercontent.com/2030ai/pullrequest-pipeline-skill-template/main/.claude/commands/pullrequest.md \
  -o .claude/commands/pullrequest.md

curl -sL https://raw.githubusercontent.com/2030ai/pullrequest-pipeline-skill-template/main/.claude/skills/pullrequest/SKILL.md \
  -o .claude/skills/pullrequest/SKILL.md
```

### Global (available in all projects)

```bash
mkdir -p ~/.claude/commands ~/.claude/skills/pullrequest

curl -sL https://raw.githubusercontent.com/2030ai/pullrequest-pipeline-skill-template/main/.claude/commands/pullrequest.md \
  -o ~/.claude/commands/pullrequest.md

curl -sL https://raw.githubusercontent.com/2030ai/pullrequest-pipeline-skill-template/main/.claude/skills/pullrequest/SKILL.md \
  -o ~/.claude/skills/pullrequest/SKILL.md
```

### Manual

Copy these two files into your `.claude/` directory:

```
.claude/
├── commands/
│   └── pullrequest.md      # slash command entry point
└── skills/
    └── pullrequest/
        └── SKILL.md         # full pipeline logic
```

---

## Requirements

| Requirement | Required | Notes |
|-------------|:--------:|-------|
| [Claude Code](https://claude.com/claude-code) | ✅ | CLI agent |
| [GitHub CLI (`gh`)](https://cli.github.com/) | ✅ | Must be authenticated (`gh auth login`) |
| [Codex GitHub App](https://github.com/apps/openai-codex-connector) | Optional | Install on your repo for AI review |
| [Copilot Code Review](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review) | Optional | Enable in repo settings |

---

## What the self-check does

Before creating a PR, the skill automatically:

1. Reads `CLAUDE.md` / `AGENTS.md` project rules
2. Recalls the original task and checks completeness
3. Detects and runs your project's test suite (`npm test`, `pytest`, `go test`, `cargo test`, etc.)
4. Runs linter if available
5. Scans for hardcoded secrets, leftover debug output, unresolved TODOs

---

## Comment validation rules

The skill doesn't blindly accept every reviewer suggestion. It applies consistent criteria:

| Always fix | Always decline |
|:-----------|:---------------|
| Security vulnerabilities | "Consider X instead of Y" without reasoning |
| Logic bugs | Patterns the project explicitly avoids |
| Data loss / corruption risks | Premature optimization |
| Race conditions | Abstraction layers for single-use code |
| Missing null checks at boundaries | Style contradicting project conventions |

---

## FAQ

**Q: What if I don't have Codex or Copilot?**
A: The skill works without either. It will self-check, create the PR, and proceed to merge.

**Q: Can I use this with a fork-based workflow?**
A: This template is designed for direct-push workflows (you push to origin). For fork-based workflows, you'll need to adjust the remote names and PR creation commands.

**Q: What merge strategy does it use?**
A: Squash merge (`--squash --delete-branch`) by default.

**Q: What if a review comment is wrong?**
A: The skill evaluates each comment against validation rules and declines invalid suggestions with a reason. You'll see a report of what was fixed vs declined.

---

## License

[MIT](LICENSE)
