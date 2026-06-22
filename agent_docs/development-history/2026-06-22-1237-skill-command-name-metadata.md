# [2026-06-22 12:37] Skill command-name metadata

Файл: `agent_docs/development-history/2026-06-22-1237-skill-command-name-metadata.md`

## Что сделано

- Skills `/pullrequest` и `/endsession` приведены к единой metadata-схеме.
- Первый H1 в каждом `SKILL.md` приведён к `# /command`.
- Добавлены `agents/openai.yaml` с `display_name: "/command"`.
- В `/pullrequest` прежний заголовок pipeline понижен до H2, чтобы сохранялся один H1 и проходил markdownlint.

## Зачем

Чтобы template показывал пользователю те же названия skills, что и вводимые slash-команды.

## Обновлено

- [ ] agent_docs/architecture.md (не применимо)
- [ ] agent_docs/adr/YYYY-MM-DD-HHMM-title.md (не применимо)
- [ ] Тесты (не применимо, metadata-only)
- [x] Документация

## Связанные решения

- Не применимо.

## Следующие шаги

- При добавлении новых skills сразу задавать `agents/openai.yaml display_name` в формате `/command`.
