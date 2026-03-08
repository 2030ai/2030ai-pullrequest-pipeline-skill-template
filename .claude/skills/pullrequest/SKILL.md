---
name: pullrequest
description: Use when creating PR with automated Codex code review loop - self-validates work, creates branch, opens PR, triggers Codex review, validates and fixes comments iteratively
---

# PR с автоматическим code review от Codex

## Режимы

| Режим | Вызов | Поведение |
|-------|-------|-----------|
| **Auto (default)** | `/pullrequest` | Автоматически мержит после успешного review |
| **Wait** | `/pullrequest wait` | После review спрашивает пользователя о merge |

## Workflow

```dot
digraph pr_flow {
    rankdir=TB;

    start [label="Старт" shape=ellipse];
    selfcheck [label="0. Самопроверка\n• AGENTS.md\n• Задача пользователя"];
    branch [label="1. Создать/использовать ветку"];
    pr [label="2. Создать/найти PR"];
    codex [label="3. Вызвать @codex\nс чек-листом"];
    wait [label="4. sleep 300s"];
    check [label="5. Проверить комментарии" shape=diamond];
    done [label="Codex OK?" shape=diamond];
    validate [label="Комментарий валиден?" shape=diamond];
    fix [label="Исправить + push"];
    reject [label="Ответить в PR"];
    loop_check [label="iteration < 10?" shape=diamond];
    report [label="Финальный отчёт"];
    wait_check [label="wait mode?" shape=diamond];
    merge [label="10. gh pr merge"];
    ask_user [label="Спросить пользователя"];
    end [label="Готово" shape=ellipse];

    start -> selfcheck;
    selfcheck -> branch;
    branch -> pr;
    pr -> codex;
    codex -> wait;
    wait -> check;
    check -> done;
    done -> report [label="да"];
    done -> validate [label="нет"];
    validate -> fix [label="да"];
    validate -> reject [label="нет"];
    fix -> loop_check;
    reject -> loop_check;
    loop_check -> wait [label="да"];
    loop_check -> report [label="нет"];
    report -> wait_check;
    wait_check -> ask_user [label="да"];
    wait_check -> merge [label="нет (default)"];
    merge -> end;
    ask_user -> end;
}
```

## Шаги

### 0. Самопроверка

**Перед созданием PR убедись:**

1. Прочитай `AGENTS.md` (или `CLAUDE.md`) — правила проекта
2. Вспомни изначальную задачу пользователя
3. Проверь: всё ли сделано? нет ли лишнего?

### 1. Ветка

```bash
# Если на main — создать feature-ветку
git checkout -b feature/<название>
```

### 2. PR

```bash
# Создать PR
gh pr create --title "..." --body "..."
# или найти существующий
gh pr list
```

### 3. Вызов Codex

Добавь комментарий в PR:

```bash
gh pr comment <номер> --body "@codex Please review this PR:

## Checklist
- [ ] **Bugs & Security**: logic errors, vulnerabilities, edge cases
- [ ] **Side Effects**: unintended changes in other parts of codebase
- [ ] **Consistency**: follows project patterns and code style
- [ ] **Documentation**: README, comments, docs updated if needed

Reply with 👍 if no issues found."
```

### 4. Ожидание

```bash
sleep 300  # 5 минут на review
```

### 5. Проверка комментариев и reviews

```bash
# Получить комментарии PR
gh api repos/{owner}/{repo}/pulls/{pr}/comments
gh api repos/{owner}/{repo}/issues/{pr}/comments
# Получить PR reviews (для обнаружения 👍/LGTM от Codex)
gh api repos/{owner}/{repo}/pulls/{pr}/reviews
```

### 6. Валидация комментария

**Валидно (исправляем):**
- Баг, уязвимость, ошибка логики
- Реальный side effect
- Нарушение стиля проекта
- Отсутствие обработки ошибок
- Недостающая документация

**Не валидно (отклоняем):**
- Субъективное мнение без обоснования
- Over-engineering для простой задачи
- Противоречит архитектуре проекта
- Устаревший или неверный совет

### 7. Действие

**Если валидно:**
```bash
# Исправить код
# git add + commit + push
gh pr comment <номер> --body "Fixed: <описание>"
```
Сообщить пользователю: что было → почему исправили

**Если не валидно:**
```bash
gh pr comment <номер> --body "Declined: <причина>"
```
Сообщить пользователю: что было → почему отклонили

### 8. Условия выхода

- Codex написал 👍 или "LGTM" или "No issues"
- Достигнут лимит 10 итераций
- Нет новых комментариев после последней проверки

### 9. Финальный отчёт

```markdown
### Итог PR Review
- **Итераций:** N
- **Исправлено:** M
- **Отклонено:** K
- **Статус:** готов к merge / требует внимания
```

### 10. Merge (зависит от режима)

**По умолчанию (auto) И статус "готов к merge":**
```bash
gh pr merge <номер> --squash --delete-branch
```
Сообщить пользователю: PR автоматически смержен.

**Если `wait` режим:**
Спросить пользователя: "PR готов к merge. Смержить?"
- Если да → `gh pr merge <номер> --squash --delete-branch`
- Если нет → оставить PR открытым
