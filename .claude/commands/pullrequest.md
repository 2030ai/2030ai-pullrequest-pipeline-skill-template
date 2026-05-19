---
description: "Create PR with review levels: simple=Codex+Copilot, medium adds Cursor+Claude, max adds ultrareview. Add wait to ask before merge."
arguments:
  - name: mode
    description: "Optional: wait, medium/claude, max/ultra/ultrareview, or combinations"
    required: false
---

Invoke the `pullrequest` skill and follow it exactly.

**Arguments received:** `$ARGUMENTS`

- `wait` controls merge confirmation only.
- Review level defaults to `simple`.
- `medium` / `claude` adds Cursor Bugbot and Claude Code Review.
- `max` / `ultra` / `ultrareview` adds one Claude ultrareview on top of medium.
- If several level aliases are present, use the strongest level: `max > medium > simple`.
- In max mode, report ultrareview status and ask before merge even when auto mode would otherwise merge.
