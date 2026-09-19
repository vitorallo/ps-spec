# Epics — <Project name>

Source: [PRD.md](PRD.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · Changes: `openspec/changes/` · Docs: `<docs-dir>/`

**Naming rule (single source of truth):** epic `E0N` ⇒ OpenSpec change `e0N-<slug>` ⇒ branch `epic/e0N-<slug>` ⇒ doc `<docs-dir>/<slug>.md`. Never renumber; append new epics at the end.

**Status legend:** `todo` → `planned` (change artifacts done, CP3 pending/passed) → `in-progress` (on branch, coding) → `verifying` (running test-plan) → `review` (docs done, waiting for CP4) → `done` (archived + merged). `dropped` for epics descoped.

**Reviewed:** — <!-- set to the date the human approved this epic list (CP2); clear it when epics change -->


## Status board

| ID | Epic | Change | Depends on | Status | Doc |
|----|------|--------|------------|--------|-----|
| E00 | Scaffolding & environment | `e00-scaffold` | — | todo | — |
| E01 | <title> | `e01-<slug>` | E00 | todo | — |

## E00 — Scaffolding & environment

**Goal:** a runnable, testable, observable empty project so every later epic starts from a working baseline.

**User stories**
- **US-1** As a developer, I want a one-command setup and run (`<cmd>`), so that any session can start the app immediately.
  - Acceptance: fresh clone → setup → run works; documented in `<docs-dir>/README.md`.
- **US-2** As an AI agent or on-call human, I want a logging baseline (named loggers, level switch, stdout + file), so that any feature can be debugged from its logs.
  - Acceptance: `DEBUG`/`LOG_LEVEL` switch works; a smoke log line appears on startup.
- **US-3** As a developer, I want a test harness and a CI check, so that every epic ships with green tests.
  - Acceptance: `<test cmd>` runs an example test; CI runs it on push.

**Scope:** repo layout, toolchain + lockfile, lint/format, logging baseline, test harness, run/debug scripts, CI, `.env.example`.
**Out of scope:** any product feature.
**Notes:** `skip_specs: true` if pure tooling; if M0 includes a health endpoint / request logging, spec it here (`service-health`). Test plan: console (+ http) cases.

## E01 — <title>

**Goal:** <one sentence>

**User stories**
- **US-1** As a <role>, I want <capability>, so that <benefit>.
  - Acceptance: <observable criterion>
  - Acceptance: <observable criterion>

**Scope:** <bullets>
**Out of scope:** <bullets, with the epic they are deferred to>
**Depends on:** E00
**Notes:** <risks, key decisions from ARCHITECTURE.md, capability spec names>

## Dependency graph

```
E00 → E01 → E02
        └→ E03
```

## Parallelization

| Wave | Epics | Notes |
|------|-------|-------|
| 1 | E00 | must finish first |
| 2 | E01 | |
| 3 | E02, E03 | independent once E01 is done |
