# [2026-06-26 23:09] Public template packaging

Файл: `agent_docs/development-history/2026-06-26-2309-public-template-packaging.md`

## Что сделано

- README install flow обновлен для полного копирования shipped skill files, включая `agents/openai.yaml`, и для безопасного повторного запуска.
- Project context в `AGENTS.md`, `agent_docs/index.md`, `agent_docs/architecture.md` и `agent_docs/glossary.md` приведен к реальному public template repository.
- Добавлены reviewer configuration examples и maintainership table example.
- Добавлен `.agents/pullrequest-maintainership.example.md` как copyable starting point без включения auto-merge по умолчанию.
- Добавлен template validation script и GitHub Actions workflow.
- Удален устаревший markdownlint exclude для несуществующего локального пути.

## Зачем

Публичный template должен быть самодостаточным для внешних пользователей: install-инструкция должна копировать все нужные файлы, документация не должна ссылаться на другой template-проект, а CI должен проверять структурные инварианты skills и symlink mirrors.

## Обновлено

- [x] agent_docs/architecture.md
- [ ] agent_docs/adr/YYYY-MM-DD-HHMM-title.md (не применимо)
- [x] Тесты
- [x] Документация

## Связанные решения

- Не применимо.

## Следующие шаги

- Не требуется.
