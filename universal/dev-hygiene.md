---
module: dev-hygiene
tier: universal
summary: Working agreements — minimal focused diffs, root-cause over symptom, no unrequested API-shape changes, small functions, tests for behaviour changes, keep docs current, use the canonical project env (never a stray venv), short plan first, file refs in hand-off.
requires: []
---

# Development Hygiene & Working Agreements

## Code Quality Rules

- Keep functions small and naming explicit.
- Add/adjust tests for all behavior changes.
- Prefer clear errors (especially for access/permission failures).
- Keep docs/comments concise and useful.
- **Never create a stray virtualenv.** Always use the canonical project environment;
  make sure tooling targets it and never falls back to silently creating a second
  environment that diverges from CI.

## Working Agreements

- Make focused, minimal diffs tied to the requested task.
- Favor fixing root causes over patching symptoms.
- Do not change public API shapes unless explicitly asked.
- If a behavior tradeoff is non-obvious, pause and present options.
- Preserve existing user changes in the working tree.
- Keep project documentation updated whenever code changes affect behavior, contracts,
  or architecture. Documentation must describe the new **current state**, not plans or
  intentions — once a change lands, the docs read as if it was always so.

## Preferred Change Style

- Start with a short plan for non-trivial edits.
- Keep commits easy to review (small, coherent units).
- Include file references in hand-off notes.
