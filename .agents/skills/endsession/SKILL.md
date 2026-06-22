---
name: endsession
description: "/endsession — Close a coding session cleanly: verify the task reached a safe stopping point, inspect real repo state, update required project documentation, preserve handoff context, and report remaining risks. Use when the user asks to finish, wrap up, close the session, end the day, or follow project closeout rules."
---

# /endsession

Close the session without leaving avoidable ambiguity or unfinished agent work.

## Workflow

### 1. Re-read Closeout Rules

Check local project instructions before finalizing:

- `AGENTS.md`
- `CLAUDE.md`
- any closeout documents explicitly referenced from those files

If the project requires specific closing actions, complete them before the final response.

### 2. Confirm The Stop Point

Make sure the work is at one of these states:

- the requested task is complete;
- there is a concrete blocker;
- the next session has a clear handoff.

Do not close while checks, edits, or needed background processes are still running.

### 3. Verify Real State

Before the final response, inspect:

- what changed;
- whether there are uncommitted changes;
- whether checks are still running or failed;
- whether temporary files or generated artifacts should be removed.

Do not alter unrelated user changes. Remove temporary artifacts only when you created them in this session and cleanup is safe.

Minimum check:

```bash
git status --short
```

### 4. Update Required Documentation

Update only documentation that is required by the project or directly useful for handoff, such as:

- project changelog or development history;
- ADR or design notes when a durable decision was made;
- source-of-truth config or inventory docs when the project explicitly uses them;
- `todo.md` or equivalent when task state changed.

Avoid adding process paperwork that the project does not ask for.

### 5. Record External Follow-up Only When Required

If local rules require a separate change log, tracker, issue, or release note, update it. If no such rule exists, skip this step.

Do not write to external systems unless the user or project rules explicitly authorize it.

### 6. Preserve Handoff Quality

The final response should make the session closable:

- what was done;
- what changed;
- what was verified;
- what remains, if anything;
- any blocker or follow-up.

If nothing remains, say so directly.

### 7. Commit Only When Appropriate

Do not commit automatically.

Commit only when:

- the user explicitly requested it;
- the project workflow requires it;
- this session already includes a commit/PR workflow that expects the changes to be committed.

### 8. Close Cleanly

Final answer shape:

- short summary;
- important paths, PRs, or artifacts;
- verification status;
- unresolved risk or explicit "nothing left".

## Default Checklist

1. Check `AGENTS.md` and `CLAUDE.md`.
2. Check `git status`.
3. Update required docs.
4. Record required external follow-up only if project rules say so.
5. Mention checks, risks, and follow-up.
6. End with a concise handoff.
