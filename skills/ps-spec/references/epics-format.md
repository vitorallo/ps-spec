# EPICS.md format

`EPICS.md` lives at the repo root and is the project's status board and the single source of truth for naming. Start from `assets/EPICS.template.md`.

## Header

- Links to `PRD.md`, `ARCHITECTURE.md`, `openspec/changes/`, `<docs-dir>/`.
- **Naming rule**, verbatim: epic `E0N` ⇒ change `e0N-<slug>` ⇒ branch `epic/e0N-<slug>` ⇒ doc `<docs-dir>/<slug>.md`. Never renumber; append new epics at the end (`E12`, `E13`, ...). Ids are two digits minimum (`E00`–`E99`); use three if the project is that big.
  Why: on long projects the epic list and the change folders drift apart (numbers reused, slugs renamed, changes created that no epic mentions). Fixing the rule once and making the board the only place ids are minted keeps PRD → epic → change → branch → doc traceable years later.
- **Status legend**: `todo` → `planned` → `in-progress` → `verifying` → `review` → `done`; `dropped` for descoped epics. The skill moves the status at each phase boundary; the status script reads it.
- Optional *Assumptions* list for PRD items the user chose not to resolve.

## Status board (table)

```
| ID | Epic | Change | Depends on | Status | Doc |
|----|------|--------|------------|--------|-----|
| E00 | Scaffolding & environment | `e00-scaffold` | — | todo | — |
| E01 | Task API | `e01-task-api` | E00 | todo | — |
```

Column rules: `ID` is `E` + digits; `Change` is the change name in backticks; `Depends on` is a comma-separated list of ids or `—`; `Status` is one legend word; `Doc` becomes a link to `<docs-dir>/<slug>.md` once the doc skeleton exists. Keep the columns in this order — `scripts/ps-spec-status.sh` parses them by position.

## Milestones → epics

The PRD's milestones (M0, M1, …) are the epic list: M0 → E00, M1 → E01, and so on. Same names, same order. A milestone that is genuinely more than one change gets split into `E0N` and `E0N+1` with a note in *Assumptions*; two tiny milestones may be merged the same way. Don't re-slice a PRD that already has a sensible delivery order — the user wrote it that way on purpose, and keeping the mapping obvious is what makes PRD → epic → change traceable.

## E00 — Scaffolding & environment (always first)

E00 exists so every later epic starts from something that runs, tests and logs. Typical content:

- repo layout, toolchain + lockfile, formatter/linter, editor config
- **logging baseline**: the logger module every feature will import (named loggers, level switch via env, stdout + file, request/run id helper) — see `references/observability.md`
- **test harness**: framework, one example test, the single test command; Playwright (or the Chrome extension) set up if there's a UI
- run/debug scripts (`make dev`, `npm run dev`, `just test`, ...), `.env.example`
- CI running lint + tests on push
- `<docs-dir>/README.md` quick-start filled in

If E00 is pure tooling, set `skip_specs: true` in its `.openspec.yaml` and make its test plan console cases (fresh clone → setup → run → test → log line visible). If the PRD's M0 includes small behavior — a health endpoint, the request log line, a startup banner — keep it in E00 and write a small spec for it (e.g. capability `service-health`); don't create an extra epic just to keep E00 spec-less.

## Per-epic section

```
## E01 — <title>

**Goal:** one sentence.

**User stories**
- **US-1** As a <role>, I want <capability>, so that <benefit>.
  - Acceptance: <observable, testable criterion>
  - Acceptance: ...
- **US-2** ...

**Scope:** bullets of what is in.
**Out of scope:** bullets, each with the epic it's deferred to (or "never").
**Depends on:** E00
**Notes:** PRD refs (FR-x, NFR-y), capability spec names you expect (`task-crud`, `task-list-ui`), key ARCHITECTURE.md decisions that apply, risks.
```

Story ids are local to the epic (`US-1` in E01 and `US-1` in E02 are different); reference them across files as `E01/US-1`.

## Sizing epics

An epic is one change: a few days of focused work, one branch, one review. Split when: > ~30 tasks, more than 3–4 capabilities, two independent UIs/services, or the test plan needs two different tools for unrelated flows. Merge when an epic would be < 5 tasks and has no independent value. Vertical slices (API + UI for one story) usually beat horizontal layers (all APIs, then all UIs) because each epic then ships something testable end-to-end.

## Footer

- **Dependency graph** — ASCII or Mermaid; must agree with the `Depends on` column.
- **Parallelization** — waves of epics that could run in parallel; ps-spec runs one at a time by default, but the user may open several branches.
- Optional **Success metrics** from the PRD.

## Refreshing EPICS.md

When the PRD changes after epics exist (`prd_newer_than_epics: yes` in the status output), re-read both and: add new epics at the end, mark descoped ones `dropped` (don't delete rows — the ids stay reserved), adjust dependencies. Never edit epics that are `in-progress` or later without saying so; their change artifacts are already derived from the old text.
