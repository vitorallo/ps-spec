# ps-spec — epic-driven development on OpenSpec, for Claude Code

`ps-spec` is a Claude Code skill that drives a software project from an idea or a PRD to shipped, tested, documented features — **one epic at a time**. Every epic becomes one [OpenSpec](https://github.com/Fission-AI/OpenSpec) change, one git branch, and one feature doc, and the human steers at four checkpoints while the agent runs the loop in between.

```
PRD → [CP1] → EPICS (stories) → [CP2] → plan epic → [CP3] → git branch → code
      → test / fix loop → doc → [CP4] → archive + merge → next epic
```

Why it exists: on long projects, "propose the whole app" drifts — epic numbers stop matching change names, branches get ad-hoc prefixes, status lives in someone's head, tests and docs become "later". ps-spec fixes the unit of work (one epic = one change = one branch = one doc), makes every unit closable only when its test plan passes and its doc is written, and leaves enough memory on disk (`EPICS.md`, `doc/`, `openspec/`) that a cold session — human or AI — can pick up exactly where the last one stopped.

## Two loops, four checkpoints

| Checkpoint | When | The human decides |
|------------|------|-------------------|
| **CP1 · PRD** | after `prd` | this is what we're building |
| **CP2 · Epics** | after `epics` | the epic list, order and stories are right |
| **CP3 · Plan & tasks** | after `plan` | this change's proposal, specs, tasks and test plan are right — go code |
| **CP4 · Validate** | after `doc`, before `close` | tests + docs prove it; archive and merge |

Between CP3 and CP4 the **agentic coding loop** runs autonomously: code → run tests → interactive cases (Playwright / Chrome / http / console) → read logs → fix → re-test → review & clean up (`/code-review`, `/simplify`) → write the doc. Approvals are recorded (`Reviewed:` in `EPICS.md`; `.ps-spec.yaml` per change) so a resumed session knows which checkpoint was passed. An optional hook hard-blocks `openspec archive` / `git merge` until CP4 is recorded.

Rules are enforced, not hoped for: a **rules guard** hook makes sure every artifact is written with the project's `config.yaml` rules in front of the model, and **secure-coding rule packs** are installed where Claude Code reads them — see [Secure coding, built in](#secure-coding-built-in).

## What ps-spec adds on top of OpenSpec

ps-spec **wraps** the stock `openspec` CLI (≥ 1.13) — it does not fork it. It ships a custom schema, `ps-spec`, installed into the project's `openspec/schemas/`:

- a fifth artifact per change, **`test-plan.md`** — automated tests, interactive cases with the tool that runs them (`playwright | chrome | http | console | manual`), observability checks, exit criteria
- **`design.md` gets an Observability section** (logger names, boundary log lines, correlation ids, DEBUG switch) so logging is designed with the feature, not bolted on
- **`tasks.md` always ends with Observability → Tests → Docs** groups
- `proposal.md` names its epic and carries the user stories
- `config.yaml` rules and apply/archive guidance that OpenSpec injects into every `openspec instructions` call
- **`design.md` gets a Security section** naming which secure-coding rules apply to the change and how; the Tests group has to verify each item

### Secure coding, built in

Rules a model never reads are decoration. ps-spec makes them reach the model at the two moments that matter — planning and coding — on every session:

- **Secure-coding rule packs.** `init` infers the stack from `ARCHITECTURE.md`, asks you which packs to install, and pulls them from [TikiTribe/claude-secure-coding-rules](https://github.com/TikiTribe/claude-secure-coding-rules) (OWASP Top 10 2025, MCP / AI / agent / RAG security, and per-language and per-framework rules) into `.claude/rules/security/`. Claude Code loads that folder by itself: `core` (OWASP) in every session, language and framework packs only when a matching file is touched — the installer adds a `paths:` frontmatter so a 40 KB Python rule set never sits in a TypeScript project's context. `.manifest` records source, commit and packs; `--update` re-pulls.

  ```bash
  bash scripts/ps-spec-security-rules.sh --list                                 # every pack, with size
  bash scripts/ps-spec-security-rules.sh --packs core,typescript,express,react  # or: ps-spec-init.sh --security-rules ...
  bash scripts/ps-spec-security-rules.sh --update
  ```

  Add your own `project.md` next to the upstream files for overrides; never edit theirs. `references/security-rules.md` has the stack → packs table.

- **Rules guard.** No OpenSpec command writes an artifact — the model authors proposal, specs, design, tasks and test-plan itself — and the only channel that carries your `config.yaml` `rules:` and `context:` to it is `openspec instructions <artifact> --change <change>`. `init` installs a hook that blocks the first Write/Edit of any artifact whose instructions were not fetched in the current session and hands the instructions back; the retry passes. Shell writes into artifacts are refused. Skipping the rules by accident is no longer possible (`--no-rules-guard` if you really want to).

- **Security is a design decision, then a test.** The `design` rule in `config.yaml` makes every `design.md` say which rule files apply and how each is honoured (input validation, authn/authz, secrets, injection, data exposure). Each item becomes a check in the tasks Tests group and a row in the test plan, and CP4's summary reports them.

Its vocabulary is deliberately different from OpenSpec's (`plan / code / close` instead of `propose / apply / archive`) so both can be installed side by side.

| ps-spec | does | OpenSpec equivalent |
|---------|------|---------------------|
| `init` | bootstrap: openspec, schema, docs index, CLAUDE.md block, git | `openspec init` |
| `prd` | write `PRD.md` + `ARCHITECTURE.md` from an idea, or audit existing ones | — |
| `epics` | generate / refresh `EPICS.md` | — |
| `plan E0N` | create the change + 5 artifacts, then CP3 | `propose` |
| `code` | branch `epic/<change>`, implement tasks, tick them as they land | `apply-change` |
| `test` | run `test-plan.md`, fix loop until every row passes, then `/code-review` + `/simplify` | `verify-change` |
| `doc` | finalize `doc/<feature>.md`, index, context | — |
| `close` | CP4 → validate, archive, merge `--no-ff`, tag, delete branch | `archive-change` |
| `next` | detect the phase from repo state and run it | — |

## Install

Requirements: Claude Code, Node ≥ 20.19, git. The `openspec` CLI is installed by `init` if missing (`npm i -g @fission-ai/openspec@latest`).

**As a user-level skill (any project):**

```bash
git clone <this-repo> ~/src/skills/ps-spec        # or wherever you keep skills
ln -s ~/src/skills/ps-spec ~/.claude/skills/ps-spec
```

**Per project:** copy or symlink the folder to `<project>/.claude/skills/ps-spec`.

**Via the Peach Studio marketplace (when published):** `/plugin marketplace add vitorallo/peach-studio-marketplace` then `/plugin install ps-spec@peach-studio`.

Start a new Claude Code session afterwards; skills load at session start.

## Use

In the project folder, in Claude Code:

```
ps-spec, I have an idea: <one paragraph>      # no PRD yet → prd phase, stops at CP1
ps-spec next                                   # detect the phase and run it
ps-spec plan E02                               # explicit phase + epic
ps-spec init with the gate hook                # init + PreToolUse hook that enforces CP4 (the rules guard is always installed)
ps-spec init, security rules for this stack    # init asks which packs (core + language + framework) and installs them
```

Every invocation starts by running `scripts/ps-spec-status.sh` and prints one line — "Detected: `test` phase for E02 `e02-task-api` — 2 cases still todo" — before acting, so you can redirect cheaply.

At a checkpoint the agent presents a short summary and **stops**. Reply `ok` to approve, or give notes; it applies them and presents again. It never assumes approval.

### What lands in your repo

```
PRD.md · ARCHITECTURE.md · EPICS.md          planning memory (root)
CLAUDE.md                                    "## ps-spec" block pointing at the memory files
doc/README.md · doc/<feature>.md             feature memory (one doc per epic; docs/ if it already exists)
openspec/config.yaml                         schema: ps-spec + context + rules + guidance
openspec/schemas/ps-spec/                    the schema and templates
openspec/changes/<e0N-slug>/                 proposal, specs/, design, tasks, test-plan, .ps-spec.yaml
openspec/changes/archive/<date>-<e0N-slug>/  after close
openspec/specs/<capability>/spec.md          accumulated behavior contract (merged by archive)
```

Naming is fixed and never renumbered: epic `E0N` ⇒ change `e0N-<slug>` ⇒ branch `epic/e0N-<slug>` ⇒ doc `doc/<slug>.md` ⇒ tag `e0N-<slug>-done-YYYYMMDD`. `E00` is always scaffolding & environment (toolchain, logging baseline, test harness, CI).

### Definition of done for an epic

- every task in `tasks.md` ticked
- automated tests green; every interactive row in `test-plan.md` `pass`; observability checks visible in the logs
- code review + clean-up done and recorded (findings fixed or explicitly deferred)
- `doc/<feature>.md` `status: final` and indexed
- CP4 approved and recorded → archived, merged into main with `--no-ff`, tagged, branch deleted, `EPICS.md` → `done`

## Layout of this skill

```
ps-spec/
├── SKILL.md                     the workflow: checkpoints, phase detection, phases, delegation, guardrails
├── scripts/
│   ├── ps-spec-status.sh        repo state dump the skill reads to pick the phase (always exit 0)
│   ├── ps-spec-security-rules.sh  installs secure-coding rule packs into .claude/rules/security/ (--list, --packs, --update)
│   └── ps-spec-init.sh          idempotent bootstrap; --with-openspec-skills, --with-gate-hook, --no-rules-guard, --docs-dir, --allow-dirty
├── assets/
│   ├── schema/ps-spec/          schema.yaml + templates (proposal, spec, design, tasks, test-plan)
│   ├── config.snippet.yaml      rules + operations guidance appended to openspec/config.yaml
│   ├── EPICS.template.md        status board, legend, naming rule, E00, per-epic section
│   ├── doc-feature.template.md  doc/<feature>.md skeleton
│   ├── doc-README.template.md   doc/README.md index skeleton
│   ├── claude-md.snippet.md     block appended to the project's CLAUDE.md
│   ├── hooks/ps-spec-rules-guard.sh  default hook: artifact writes need `openspec instructions` first (rules + context)
│   └── hooks/ps-spec-gate-guard.sh   optional PreToolUse hook (blocks archive/merge until CP4)
├── references/                  loaded by phase, not all at once
│   ├── prd-authoring.md         idea → PRD flow + the "well-defined PRD" checklist
│   ├── epics-format.md          EPICS.md format, milestones→epics, E00, stories, sizing
│   ├── openspec-formats.md      exact artifact formats + CLI for OpenSpec 1.13 / ps-spec schema
│   ├── test-plan.md             test-plan format, tool recipes, the fix loop, subagent prompt
│   ├── observability.md         logging principles + starter modules (Python, Node, Go, Rust)
│   ├── docs-format.md           the /doc memory contract
│   ├── git-flow.md              branch / commit / tag / merge / rollback, checkpoint records, hook
│   └── security-rules.md        stack → rule packs, install/update, how rules reach the model on each harness
└── evals/evals.json             test prompts used to benchmark the skill
```

## Design notes

- **Wrap, don't fork.** OpenSpec ships weekly; its custom-schema mechanism (`openspec schema fork`), per-artifact `rules:` and `operations:` guidance cover everything ps-spec needs with zero CLI code to maintain.
- **Milestone = epic = change.** The PRD's milestone list is the epic list. Splitting is the exception and is written down in `EPICS.md → Assumptions`.
- **Logging is a deliverable.** Both an AI reading logs and a human on call must be able to follow one request through a feature; the test plan checks that the designed log lines actually appear.
- **Docs are memory, not paperwork.** `doc/<feature>.md` is written for the next session that has never seen the code — usually a future Claude — and is built to be *found*, not read: its header lists `files`, `entrypoints`, `loggers`, `events`, `env`, `specs`, `keywords`, so one `grep -l` across `doc/` answers "which doc owns this file / route / log event?". Behavior itself stays in `openspec/specs/`; docs link to it and never restate it.
- **Subagents where they add independence, not round trips.** A fresh subagent runs the interactive test cases (it doesn't share the implementer's blind spots, and keeps browser output out of the main context); a reviewer runs before CP4; research fans out in `prd`. Checkpoints always stay in the main session.

## Benchmark

Three evals (PRD → epics, plan one epic, finish + stop at CP4) on a sample todo-app fixture, Claude with the skill vs. without: **100% vs 71%** of checks passed, at similar time and tokens. The largest gap is PRD → epics (15/15 vs 4/15); once a repo carries the ps-spec memory files, even a skill-less session behaves mostly correctly — which is the point.

## Status

v0.1 — built with `skill-creator`; being validated on real projects. Feedback welcome via issues.

## License

MIT (skill). OpenSpec is MIT, © Fission AI.
