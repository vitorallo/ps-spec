# Documentation contract — `<docs-dir>/` as project memory

The docs folder is how a project survives context loss. A new session — human or AI — should be able to read `<docs-dir>/README.md`, open the doc for the feature it's touching, and be productive without reading the whole codebase. Treat docs as a deliverable of every epic, on the same footing as tests.

`<docs-dir>` is `docs/` if the project already had it, otherwise `doc/` (the init script decides and `ps-spec-status.sh` reports it).

## The index — `<docs-dir>/README.md`

Created at `init` from `assets/doc-README.template.md`. Keep it short; it's a map, not a manual.

- Planning links: PRD, ARCHITECTURE, EPICS, specs
- **Quick start**: setup, run, test commands; where logs go; the debug switch (E00 fills these in)
- **Features table**: `| Doc | Epic | Status | Entrypoints | Files | One-liner |` — one row per feature doc; status mirrors the doc's frontmatter (`draft` / `final`); entrypoints and the top-level file paths are copied from the doc's header so the index alone answers "which doc for this route / this folder"
- **Conventions**: logging, branches/commits, definition of done

Update the table row in `plan` (row added, `draft`) and `doc` (`final`).

## The feature doc — `<docs-dir>/<slug>.md`

One per epic, named by the epic slug (so `e02-task-api` → `task-api.md`). Created as a skeleton in `plan` from `assets/doc-feature.template.md`; finalized in `doc`. Frontmatter:

```yaml
---
feature: task-api
epic: E02
change: e02-task-api
status: draft      # → final at doc phase
updated: 2026-09-14
files: [src/tasks/routes.js, src/tasks/service.js, src/tasks/store.js, tests/tasks.api.test.js]
entrypoints: ["POST /api/tasks", "GET /api/tasks", "PATCH /api/tasks/:id", "DELETE /api/tasks/:id"]
loggers: [app.tasks, app.tasks.store]
events: [task.create, task.update, task.done, task.delete, task.validation_failed]
env: [DATA_FILE, LOG_LEVEL]
specs: [task-crud]
depends_on: [scaffold]
keywords: [todo, crud, sqlite, validation]
---
```

The findability fields are the part an agent actually uses. Docs are consulted by `grep`, not read cover to cover: "which doc owns `src/tasks/store.js`?", "where is `task.validation_failed` emitted?", "what reads `DATA_FILE`?" each become one `grep -l` across `<docs-dir>/`. Keep the lists exact and complete — every file the feature owns, every logger and event name it emits, every env var it reads — and update them in the same commit as the code. `keywords` is for synonyms a searcher might type that don't appear elsewhere in the header.

Fill `files`, `entrypoints`, `specs`, `depends_on` at `plan` (from design/tasks); fill `loggers`, `events`, `env` at `doc` (from what was actually implemented — copy the names from the code, don't paraphrase).

Sections and what belongs in each:

| Section | Content | Written when |
|---------|---------|--------------|
| What it does | 2–4 sentences + story list | plan (from the proposal) |
| How it works | entry points, modules, data model, flow; Mermaid `sequenceDiagram` for the key path | doc |
| Files | table of paths and roles — the map for the next session | doc |
| Configuration | env vars, config keys, flags, defaults | doc |
| Logs & debugging | logger names, happy-path events, trouble events, DEBUG switch, log file, which test-plan tool reproduces a request | doc (from design.md Observability + what you learned in test) |
| How to run & test | run command, automated test command, pointer to the test-plan interactive rows | doc |
| Known gaps / follow-ups | deferred items and the epic they moved to | doc |
| References | specs (the behavior contract — link, never restate), change folder (active or archive path), PRD sections | plan, fixed up at close |

The doc explains *how it's built and how to debug it*; `openspec/specs/<capability>/spec.md` says *what it does*. Don't duplicate requirements or scenarios into the doc — they'd drift, and the specs are already greppable (`### Requirement:`, `#### Scenario:`).

Write for someone who has never seen the code. Prefer concrete names (`app.tasks.api`, `POST /tasks`, `tests/task_api.test.ts`) over descriptions. Anything that surprised you during `code` or cost time during `test` belongs in *How it works* or *Logs & debugging* — that's exactly the knowledge a future session lacks.

## Other memory files touched by ps-spec

- `EPICS.md` status board — updated at every phase boundary.
- `openspec/config.yaml` `context:` — refresh in `doc` if stack/conventions changed (new logger, new test tool, new service). It's injected into every future artifact instruction.
- `CLAUDE.md` `## ps-spec` block — added at init; keep it, and add project-specific notes under it if the user wants (run commands, gotchas). Don't let it grow into a status board — that's EPICS.md's job.
- `openspec/specs/` — updated automatically by `openspec archive`; it's the accumulated behavior contract. Point to it from docs rather than restating requirements.

## Staleness

A doc with `status: final` whose feature later changes in another epic: that epic's `Docs` task group updates the affected doc(s) and bumps `updated:`. If a doc is out of date and you notice it while working, fix it in the same commit — a wrong doc is worse than none because the next session will trust it.
