---
description: "Create PR with automated Codex code review loop. Auto-merges by default. Use 'wait' to ask before merge."
arguments:
  - name: mode
    description: "Optional: 'wait' to ask user before merge (default: auto-merge)"
    required: false
---

Invoke the pullrequest skill and follow it exactly as presented to you.

## Mode Detection

**Arguments received:** `$ARGUMENTS`

- If `$ARGUMENTS` contains "wait" → set **auto-merge mode = OFF** (ask user before merge)
- Otherwise → set **auto-merge mode = ON** (default: auto-merge after successful review)

Remember this mode throughout the workflow and apply it in step 10.
