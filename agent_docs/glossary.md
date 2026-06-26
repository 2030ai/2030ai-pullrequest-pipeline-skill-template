# Глоссарий проекта

Термины, которые используются в этом public skill template.

## Термины

| Термин | Значение | Контекст |
|--------|----------|----------|
| public template | Этот репозиторий как переносимый source для установки skills в другие репозитории | README, AGENTS, release/packaging changes |
| downstream repository | Репозиторий пользователя, куда копируются skills из template | Install flow, support/debugging |
| project-local skill | Skill, который хранится внутри конкретного репозитория, а не глобально в пользовательском home directory | `.agents/skills/<name>/` |
| canonical source | Единственная редактируемая копия skill файлов | `.agents/skills/<name>/` |
| platform mirror | Symlink, через который Claude, Codex или Cursor видят canonical skill source | `.claude/skills/`, `.codex/skills/`, `.cursor/skills/` |
| reviewer mode | Набор AI reviewers и ultrareview-поведение для `/pullrequest` | `medium`, `max` в `reviewers.yaml` |
| maintainership config | Optional markdown table, определяющая можно ли auto-merge для medium mode | `.agents/pullrequest-maintainership.md`, `.github/pullrequest-maintainership.md` |
| ultrareview | Cost-bearing/user-run Claude Code review handoff для `max` mode | `/pullrequest max` |

## Аббревиатуры

| Сокращение | Расшифровка |
|------------|-------------|
| PR | Pull request |
| CI | Continuous integration |
| CLI | Command-line interface |
| NWO | GitHub `nameWithOwner`, например `owner/repo` |

## Кодовые названия и нейминги

- **Codex:** GitHub app/bot reviewer triggered by `@codex`.
- **Copilot:** GitHub Copilot pull request reviewer.
- **Cursor Bugbot:** Cursor PR reviewer triggered by `@cursor review` or `cursor review`.
- **Claude Code Review:** Claude GitHub review integration triggered by `@claude review once`.
