# [2026-06-17 11:43] Template source cleanup

Файл: `agent_docs/development-history/2026-06-17-1143-template-source-cleanup.md`

## Что сделано

- Уточнено, что `agent_docs/setup-checklist.md` удаляется в проектах, созданных из шаблона, но хранится в `2030ai-project-template`.
- Заполнено описание самого template-репозитория в `AGENTS.md`.
- Добавлены shipped defaults `.cursorignore` и `.env.example`.
- Удалён сломанный gitlink `skill-andMCPupdater-zvasil` из индекса; локальная внешняя папка игнорируется через `.git/info/exclude` (не коммитится в переносимый шаблон).
- Убраны исторические provenance-комментарии из `.gitignore`.
- Заякорен root-level ignore-паттерн `/main` в `.gitignore`, чтобы не скрывать `src/main` или `cmd/main`.

### Правки по ultrareview-findings

- `.env.example` приведён к русскому двухстрочному шаблону из `agent_docs/guides/environment-setup.md` (был англоязычный однострочник).
- Заголовок секции `.gitignore` в `environment-setup.md` выровнен на «Проверить/обновить» — как соседние peer-секции `.cursorignore` и `.env.example`.
- Персональный namespace `skill-andMCPupdater-zvasil/` убран из коммитимого `.gitignore` (переносимость шаблона) в локальный `.git/info/exclude`.

### Правки по medium-review

- `.cursorignore`, `.gitignore` и `environment-setup.md` переведены с точечных `.env.local`/`.env.*.local` на `.env` + `.env.*`, чтобы скрывать `.env.production`, `.env.staging` и другие dotenv-варианты, сохраняя `!.env.example`.

## Зачем

Исправлены review findings, из-за которых template-репозиторий противоречил собственным bootstrap-правилам, обещал отсутствующие environment defaults и содержал некорректный submodule/gitlink без `.gitmodules`.

## Обновлено

- [ ] agent_docs/architecture.md (не применимо)
- [ ] agent_docs/adr/YYYY-MM-DD-HHMM-title.md (не применимо)
- [ ] Тесты (не применимо к коду; запущены проверки документации)
- [x] Документация

## Связанные решения

- Не применимо.

## Следующие шаги

- Не требуется.
