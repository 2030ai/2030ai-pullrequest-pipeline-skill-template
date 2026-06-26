# Архитектура

## Обзор

`2030ai-pullrequest-pipeline-skill-template` — публичный source repository для двух project-local skills:

- `/pullrequest` — PR pipeline: self-check, branch/PR preparation, AI reviewer triggering, comment processing, merge/reporting.
- `/endsession` — clean closeout workflow for agent sessions.

Репозиторий не содержит прикладного runtime. Основной пользовательский артефакт — переносимая файловая структура skills и документация установки.

## Контекст

Пользователь устанавливает template в свой репозиторий из `README.md`. После установки `.agents/skills/<name>/` остается canonical source, а platform-specific директории `.claude/`, `.codex/`, `.cursor/` содержат symlink mirrors на этот source.

`/pullrequest` читает `.agents/skills/pullrequest/reviewers.yaml` как source of truth для состава reviewer modes. Это позволяет проекту отключить неподключенных, нежелательных или платных reviewers без редактирования `SKILL.md`.

## Ключевые компоненты

- Project-local skills source: `.agents/skills/<name>/SKILL.md`.
- Reviewer config: `.agents/skills/pullrequest/reviewers.yaml`.
- Optional maintainership example: `.agents/pullrequest-maintainership.example.md`.
- OpenAI/Codex display metadata: `.agents/skills/<name>/agents/openai.yaml`.
- Platform skill mirrors: `.claude/skills/`, `.codex/skills/`, `.cursor/skills/`.
- Public install and configuration guide: `README.md`.
- Template validation: `scripts/check-template.sh` and `.github/workflows/template-validation.yml`.

## Потоки данных

1. User copies skill files from this template into a downstream repository.
2. Platform mirrors expose the same skill directory to Claude, Codex, and Cursor surfaces.
3. `/pullrequest` reads project rules, runs project checks, syncs with the GitHub default branch, creates/reuses a PR, and triggers reviewers configured in `reviewers.yaml`.
4. Reviewer outputs are monitored through GitHub comments, reviews, inline comments, or checks.
5. Actionable findings are fixed or declined with reasons; merge behavior is controlled by review mode and optional maintainership config.

## Технологии и зависимости

- Markdown skill manifests and documentation.
- YAML reviewer/display metadata.
- Git, GitHub CLI, and GitHub Actions.
- Shell validation script using POSIX-ish shell plus Ruby YAML parsing.

## Нефункциональные требования и ограничения

- Public template files must be portable: no local absolute paths, private usernames, machine-specific setup, or internal-only assumptions.
- Missing external reviewers must degrade gracefully and be reported, not fail the entire pipeline.
- Cost-bearing ultrareview must remain user-run and explicit.
- Medium-mode auto-merge is allowed only when maintainership is configured.

## Roadmap

- Keep install snippets synchronized with shipped files.
- Keep validation checks close to template invariants instead of adding app-runtime assumptions.
- Add reviewer presets only when they reduce public setup friction.
