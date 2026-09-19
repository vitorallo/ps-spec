# OpenSpec artifact formats (ps-spec schema, OpenSpec ≥ 1.13)

Authoritative format reference for authoring a ps-spec change. The `ps-spec` schema is a fork of the built-in `spec-driven` with one extra artifact: **proposal → specs → design → tasks → test-plan**. Formats are strict and some failures are silent — read this before writing any artifact, and run `openspec instructions <artifact> --change <name>` for the CLI's own tailored guidance (it includes the project's `context:` and `rules:`). That command is the only way `config.yaml` rules reach you — no OpenSpec command writes artifacts, you do — so run it before writing or editing each artifact, in every session. The rules guard hook installed by `init` blocks a Write/Edit to an artifact whose instructions were not fetched in the current session and returns them; shell writes into artifacts are refused.

Examples use placeholder capabilities (`task-crud`, `data-export`); use the project's real kebab-case names.

## Table of contents

1. [Command reference](#1-command-reference)
2. [config.yaml: schema, context, rules, operations](#2-configyaml)
3. [Change layout and .openspec.yaml](#3-change-layout)
4. [proposal.md](#4-proposalmd)
5. [specs/<capability>/spec.md](#5-specs)
6. [design.md](#6-designmd)
7. [tasks.md](#7-tasksmd)
8. [test-plan.md](#8-test-planmd)
9. [Validation gotchas](#9-validation-gotchas)

---

## 1. Command reference

```bash
openspec init --tools none --force --no-animation   # scaffold openspec/ (ps-spec-init.sh does this)
openspec schema validate ps-spec                    # check the project schema in openspec/schemas/ps-spec/
openspec templates --schema ps-spec --json          # resolve template paths (project > user > package)

openspec new change <name> --description "<goal>"   # creates openspec/changes/<name>/{README.md,.openspec.yaml}
openspec status --change <name> [--json]            # artifact completion + build order (ready/blocked/done)
openspec status --all --json                        # same for every active change
openspec instructions <artifact> --change <name>    # proposal | specs | design | tasks | test-plan
openspec instructions apply --change <name>         # apply context + ps-spec operations guidance
openspec validate <name> --strict                   # after authoring; fix until clean
openspec validate --changes --strict                # all active changes
openspec list [--specs] [--json]                    # changes (or capabilities) with task counts
openspec show <id> --type spec|change [--json] [--no-scenarios]
openspec archive <name> -y [--skip-specs]           # move to changes/archive/YYYY-MM-DD-<name>/, merge deltas into specs/
openspec view                                       # TUI dashboard
```

Schema resolution: `openspec/schemas/<name>/` in the project → `~/.local/share/openspec/schemas/` → package built-ins. A project schema named `ps-spec` is what `config.yaml`'s `schema: ps-spec` points at. Existing changes keep the schema recorded in their `.openspec.yaml`.

---

## 2. config.yaml

```yaml
schema: ps-spec

context: |
  Domain: <one line>
  Tech stack: <languages, frameworks, key libs>
  Deployment: <where it runs, how it's packaged>
  Logging: <logger module, namespace scheme, LOG_LEVEL switch, file location>
  Tests: <framework, single command, UI tool (playwright|chrome)>
  Conventions: <commit style, layout, naming>

rules:                 # per-artifact constraints, injected into `openspec instructions`
  tasks:
    - "End with three groups in this order - Observability, Tests, Docs"
operations:            # advisory guidance for apply / archive
  apply:
    guidance:
      - "Never code on main"
```

`context:` (≤ 50 KB) is injected into every artifact instruction — fill it at init and refresh it in the `doc` phase. `rules:` keys are artifact ids (custom ones like `test-plan` are valid). YAML gotcha: quote any rule/guidance string containing `: ` or `#`, or the whole config silently falls back to defaults.

---

## 3. Change layout

`openspec new change <name>` creates:

```
openspec/changes/<name>/
├── README.md          # title + description
└── .openspec.yaml     # schema: ps-spec / created: <date>   (+ skip_specs: true for no-behavior changes)
```

Authoring completes it to:

```
openspec/changes/<name>/
├── proposal.md
├── specs/<capability-path>/spec.md   # one per capability in the proposal
├── design.md
├── tasks.md
└── test-plan.md
```

`skip_specs: true` in `.openspec.yaml` is the escape hatch for changes with no spec-level behavior (E00 scaffolding, tooling, pure refactors, docs). `openspec validate` rejects a zero-delta change without it. Don't invent requirements to satisfy validation.

---

## 4. proposal.md

WHY the change exists (the HOW is design.md). 1–2 pages. ps-spec sections:

- `## Epic` — `E0N — <title>` (link to EPICS.md)
- `## Why` — 1–2 sentences: problem, why now
- `## What Changes` — bullets; mark **BREAKING**
- `## User Stories` — copied from the epic with acceptance criteria (specs and test-plan derive from these)
- `## Capabilities`
  - `### New Capabilities` — `- \`kebab-name\`: description` → becomes `specs/<kebab-name>/spec.md`
  - `### Modified Capabilities` — existing names from `openspec list --specs` whose *requirements* change; empty if none
- `## Impact` — code, APIs, dependencies, systems affected

Before filling Capabilities: `openspec list --specs`, then `openspec show <id> --type spec` for anything related; reuse existing paths rather than near-duplicates.

---

## 5. specs

`specs/<capability-path>/spec.md` — WHAT the system does, as a delta against `openspec/specs/`. One file per capability, exact name from the proposal.

```markdown
## Purpose
Lets users manage their tasks through a small JSON API.   ← NEW capabilities only, ≥ 50 chars; omit for existing ones

## ADDED Requirements

### Requirement: Create task
The system SHALL create a task from a non-empty title and return it with an id and creation time.

#### Scenario: Valid title
- **WHEN** a client POSTs `{"title": "a"}`
- **THEN** the system responds 201 with the task including `id` and `createdAt`

#### Scenario: Empty title
- **WHEN** a client POSTs an empty title
- **THEN** the system responds 400 naming the `title` field and creates nothing

## MODIFIED Requirements
### Requirement: <exact existing header>       ← paste the ENTIRE existing block, then edit

## REMOVED Requirements
### Requirement: <name>
**Reason**: ...
**Migration**: ...

## RENAMED Requirements
- FROM: `### Requirement: Old name`
- TO: `### Requirement: New name`
```

Rules: requirements use SHALL/MUST; every requirement has ≥ 1 scenario; scenarios use **exactly four hashtags** (`#### Scenario:`) with `- **WHEN**` / `- **THEN**` bullets — three hashtags or plain bullets fail *silently*. Specs describe observable behavior, not class names or libraries. Each scenario becomes a test-plan row.

---

## 6. design.md

HOW to implement. Keep short for simple changes, full for cross-cutting ones.

- `## Context` — current state and constraints (reference ARCHITECTURE.md; don't restate the proposal)
- `## Goals / Non-Goals` — design-level boundaries
- `## Decisions` — choice, rationale, alternatives considered
- `## Observability` — **ps-spec addition**: logger names, boundary log events with fields, correlation id, DEBUG switch, metrics/health if a service (see `references/observability.md`)
- `## Risks / Trade-offs` — `[Risk] → Mitigation`
- `## Migration Plan` — optional
- `## Open Questions` — only deferrable ones; anything that changes specs/tasks gets asked now

---

## 7. tasks.md

The checklist the `code` phase executes; checkbox format is parsed literally.

```markdown
## 1. Setup
- [ ] 1.1 Add task module skeleton; verify files exist and app boots

## 2. Core implementation
- [ ] 2.1 Implement create/get/list/update/delete in the store; verify unit tests pass
- [ ] 2.2 Wire `/tasks` routes with validation; verify http cases T1–T4

## 3. Observability
- [ ] 3.1 Add `app.tasks.api` logger with `task.*` events incl. id + duration_ms; verify lines appear in a manual run

## 4. Tests
- [ ] 4.1 Unit + integration tests for every scenario in specs/task-crud; verify `npm test` green

## 5. Docs
- [ ] 5.1 Finalize doc/task-api.md, update doc/README.md row, refresh config.yaml context if needed
```

Rules: numbered `## N. Group` headings; `- [ ] N.M description` with the space inside the brackets; ordered by dependency; each task says how it is verified; the final three groups are always **Observability, Tests, Docs** in that order. Tick `- [x]` as each task lands.

---

## 8. test-plan.md

The ps-spec artifact: sections `## Automated tests`, `## Interactive cases` (table `ID | Scenario | Steps | Expected | Tool | Result`, tool ∈ `playwright | chrome | http | console | manual`, result ∈ `todo | pass | fail (note)`), `## Observability checks`, `## Exit criteria`. Full format, tool recipes and the execution loop: `references/test-plan.md`.

---

## 9. Validation gotchas

- **Four-hashtag scenarios** — `#### Scenario:` exactly; wrong count = silent failure.
- **Every requirement needs ≥ 1 scenario.**
- **`## Purpose` ≥ 50 chars for new capabilities**, absent for existing ones.
- **MODIFIED needs the full block** — partial content loses detail at archive.
- **REMOVED needs Reason + Migration.**
- **Capabilities ↔ spec files must match** in both directions.
- **Zero deltas needs `skip_specs: true`** in `.openspec.yaml`.
- **Checkboxes are literal** — `- [ ] N.M ...`; numbered group headings.
- **Unquoted `: ` in config.yaml rules/guidance** breaks the config silently — quote the strings.
- Always `openspec validate <name> --strict` after authoring and before archive.
