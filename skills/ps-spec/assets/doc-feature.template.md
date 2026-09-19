---
feature: <slug>
epic: E0N
change: e0N-<slug>
status: draft            # draft while the epic is in flight, final at close
updated: YYYY-MM-DD
# --- findability: keep these lists exact; agents grep them ---
files: []                # source files this feature owns, e.g. [src/tasks/routes.js, src/tasks/store.js]
entrypoints: []          # how it is reached: routes, commands, jobs, e.g. ["POST /api/tasks", "cli: app import"]
loggers: []              # logger names, e.g. [app.tasks, app.tasks.store]
events: []               # log event names, e.g. [task.create, task.validation_failed]
env: []                  # env vars / config keys, e.g. [DATA_FILE, LOG_LEVEL]
specs: []                # capability specs, e.g. [task-crud]
depends_on: []           # other feature slugs, e.g. [scaffold]
keywords: []             # synonyms a searcher might use, e.g. [todo, crud, sqlite]
---

# <Feature title>

## What it does

<!-- 2-4 sentences a newcomer (human or AI) needs to understand this feature. Link the user stories (E0N/US-n). -->

## How it works

<!-- Flow through the code: entry points, main modules, data model, external calls. A short Mermaid sequence/flow diagram is welcome. -->

## Files

| Path | Role |
|------|------|
| `src/...` | ... |

## Configuration

<!-- Env vars, config keys, feature flags, defaults. -->

## Logs & debugging

<!-- Logger names, the log lines to look for on the happy path and on failure, how to turn on DEBUG, where the log file is.
     Which interactive tool to use (playwright / chrome / http / console) and a one-line example. -->

## How to run & test

<!-- Commands: run locally, run the automated tests, re-run the interactive cases in openspec/changes/<change>/test-plan.md. -->

## Known gaps / follow-ups

<!-- Deferred items and the epic they moved to. -->

## References

- Behavior contract: `openspec/specs/<capability>/spec.md` (the specs are the source of truth — don't restate requirements here)
- Change: `openspec/changes/archive/<date>-e0N-<slug>/` (or `openspec/changes/e0N-<slug>/` while active)
- PRD section: PRD.md#...
