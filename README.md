# 2030AI Pullrequest Template

Claude Code скилл: автоматизированное создание PR с итеративным code review от Codex.

## Что делает

1. Создаёт ветку и PR
2. Вызывает `@codex` для code review с чек-листом
3. Валидирует комментарии и автоматически исправляет / отклоняет
4. Итеративно повторяет review-цикл (до 10 итераций)
5. Мержит PR (автоматически или по запросу)

## Установка

Скопируйте содержимое `.claude/` в свой проект:

```bash
cp -r .claude/commands/pullrequest.md <ваш-проект>/.claude/commands/
cp -r .claude/skills/pullrequest/ <ваш-проект>/.claude/skills/
```

## Использование

| Команда | Поведение |
|---------|-----------|
| `/pullrequest` | Auto-merge после успешного review |
| `/pullrequest wait` | Спрашивает подтверждение перед merge |

## Требования

- [Claude Code](https://claude.com/claude-code)
- [GitHub CLI (`gh`)](https://cli.github.com/)
- Codex (GitHub App) для автоматического review
