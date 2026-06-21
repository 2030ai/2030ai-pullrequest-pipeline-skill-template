# [2026-06-16 12:49] Атомарные событийные документы

## Что сделано

- История разработки переведена с общего файла на директорию `agent_docs/development-history/` с отдельным файлом на итерацию.
- Для ADR закреплена timestamp-slug схема вместо ручной сквозной нумерации.
- Добавлен общий guide `agent_docs/guides/atomic-documents.md` для событийных документов.
- Обновлены ссылки в `AGENTS.md`, `README.md`, `agent_docs/index.md`, DoD и шаблонах.

## Зачем

Снизить merge-конфликты между агентами и worktree: новые записи должны создаваться независимыми файлами, а не правками одного общего журнала или ручного индекса.

## Обновлено

- [x] `AGENTS.md`
- [x] `README.md`
- [x] `agent_docs/index.md`
- [x] `agent_docs/adr/README.md`
- [x] `agent_docs/guides/atomic-documents.md`
- [x] `agent_docs/guides/dod.md`
- [x] `agent_docs/templates/adr.md`
- [x] `agent_docs/templates/development-history.md`

## Связанные решения

- `agent_docs/adr/2026-06-16-1249-atomic-event-documents.md`
