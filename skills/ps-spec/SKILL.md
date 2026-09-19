---
name: ps-spec
description: Drive a software project from an idea or a PRD to shipped, tested, documented features with OpenSpec, one epic per change. Writes or audits PRD.md and ARCHITECTURE.md, generates EPICS.md with user stories, plans each epic as an OpenSpec change (proposal, specs, design, tasks, test-plan), creates a git branch before any code, implements with logging and observability built in, runs the test plan with interactive debugging (Playwright, Chrome extension, http, console), writes a doc/<feature>.md memory file, pauses for human review, then archives and merges. Use this skill whenever the user says "ps-spec", "next epic", "plan/code/test/doc/close epic N", "what's next on this project", "continue the project", mentions EPICS.md, PRD.md, epics, user stories, OpenSpec changes, or wants to build or continue a project epic by epic — even if they don't name OpenSpec or ps-spec explicitly. Also use it when someone has only an idea and wants to turn it into a PRD and a buildable plan.
---

# ps-spec — epic-driven development on OpenSpec

You are driving a project through a fixed loop, one epic at a time:

```
PRD → [CP1] → EPICS (stories) → [CP2] → plan epic → [CP3] → git branch → code
      → test / fix loop → doc → [CP4] → archive + merge → next epic
```

Every epic becomes one OpenSpec change, one git branch, one feature doc. The
project stays controllable because each unit is bounded, tested, documented and
archived before the next starts — and a cold session (human or AI) can always
resume from `EPICS.md`, `<docs-dir>/`, and `openspec/`.

This skill wraps the stock `openspec` CLI (v1.13+) with a custom schema named
`ps-spec` that adds a `test-plan` artifact and observability/test/doc rules.
It does not replace OpenSpec's own skills; it uses its own vocabulary so both
can coexist.

## Two loops, four checkpoints

The workflow is two nested loops. The **developer feedback loop** is the
outer ring: the human steers at four checkpoints, and everything between
them is yours to run. The **agentic coding loop** is the inner ring: you
plan, act, observe (tests, logs, browser), and fix — autonomously, as many
rounds as it takes — until the exit criteria are met, then hand back.

| Checkpoint | When | What the human decides |
|------------|------|------------------------|
| **CP1 · PRD** | end of `prd` | the PRD (and the gaps you patched) is what we're building |
| **CP2 · Epics** | end of `epics` | the epic list, order and stories are right |
| **CP3 · Plan & tasks** | end of `plan` | this change's proposal, specs, tasks and test plan are right — go code |
| **CP4 · Validate** | end of `doc`, before `close` | tests + docs prove it; archive and merge |

Between CP3 and CP4 the inner loop runs: `code` → `test` (automated, then
interactive with the tool each case names, then the observability checks)
→ read logs → fix → re-test → **review & clean up** (`/code-review`, then
`/simplify`, fix, re-test) → `doc`. Don't come back to the human mid-loop
for things the test plan can answer; do come back when a spec turns out
wrong, a decision would change the tasks, or you're stuck after several
rounds.

How a checkpoint works in Claude Code — nothing exotic, but be strict:

- Present a compact summary (what was produced, what to look at, open
  questions), then **end your turn** and wait. Prefer `AskUserQuestion`
  with options like "approve" / "changes needed" / "show me X" so the answer
  is unambiguous. Never simulate, assume, or infer approval; silence is not
  a yes. If the user's reply is feedback, apply it and present again.
- **Record the approval** once given, so a resumed session knows where it
  stands: CP2 as `Reviewed: <date>` in the `EPICS.md` header; CP3 and CP4
  in the change's `openspec/changes/<change>/.ps-spec.yaml`:

  ```yaml
  checkpoints:
    plan:     { approved: 2026-09-14, notes: "ok, use node:sqlite" }
    validate: { approved: 2026-09-14 }
  ```

  The status script prints these, and the phase table below keys off them.
  (CP1 needs no marker — an `EPICS.md` existing means the PRD was accepted.)
- Hard enforcement: `ps-spec-init.sh` installs a **rules guard** hook by
  default (see `plan`) and, with `--with-gate-hook`, a `PreToolUse` hook
  that blocks `openspec archive` / `git merge epic/*` unless the change's
  `validate` checkpoint is recorded. Useful when several sessions or agents
  work the same repo.
- The inner loop needs nothing special: keep working inside the turn until
  the exit criteria hold. If the user wants a condition-driven run they can
  wrap it with Claude Code's `/goal` (e.g. `/goal "every row in
  test-plan.md is pass and npm test is green"`); `/loop` is interval-based
  and not what this is.

## Vocabulary

| Word | Does | OpenSpec equivalent |
|------|------|---------------------|
| `init` | bootstrap: openspec, ps-spec schema, docs index, CLAUDE.md block, git | `openspec init` |
| `prd` | write `PRD.md` + `ARCHITECTURE.md` from an idea, or audit existing ones | — |
| `epics` | generate / refresh `EPICS.md` | — |
| `plan E0N` | create the change + all five artifacts, then **CP3** | `propose` / `ff-change` |
| `code` | branch `epic/<change>` and implement tasks | `apply-change` |
| `test` | run `test-plan.md`, debug loop until all pass | `verify-change` |
| `doc` | finalize `<docs-dir>/<feature>.md`, index, context | — |
| `close` | **CP4** → validate, archive, merge, tag | `archive-change` |
| `next` | detect state, run the next phase | — |

If the user names a phase, do that phase. Otherwise detect it.

## Step 0 — detect the phase

Run the status script first, every time. It prints one block describing the
repo (openspec/schema state, planning docs, docs dir, EPICS board and its
`Reviewed:` date, active changes with task/test-plan counters and checkpoint
records, git branch/dirtiness):

```bash
bash <this-skill-dir>/scripts/ps-spec-status.sh
```

Map the block to a phase with this table, top to bottom (first match wins):

| Observed state | Phase |
|----------------|-------|
| `openspec: MISSING`, `openspec_init: no`, `schema` ≠ ps-spec, `docs_dir: none`, or `claude_md_block: no` | `init` |
| `prd: no` — or PRD exists but fails the checklist in `references/prd-authoring.md` | `prd` |
| `epics: no`, or `prd_newer_than_epics: yes` | `epics` |
| `EPICS.md` exists but `epics_reviewed: no` | `epics` — present the board for **CP2**, don't plan yet |
| an epic in the board is `todo` and has no change folder (take the first one whose dependencies are `done`) | `plan` |
| a change has all five artifacts but `cp_plan=pending` | **CP3** — present the plan summary and wait |
| `cp_plan` approved, git not on `epic/<change>` | `code` (open the branch) |
| on `epic/<change>` and `open_non_docs>0` (implementation tasks still open) | `code` (continue) |
| implementation tasks done and test-plan has `todo>0` or `fail>0` | `test` |
| test-plan all pass and `review=pending` | `test` — the review & clean-up step |
| test-plan all pass, review done, feature doc missing / `status=draft` / Docs tasks still open | `doc` |
| doc `status=final`, `cp_validate=pending` | **CP4** — present the review summary and wait |
| `cp_validate` approved, change still active (not archived) | `close` (execute archive + merge) |
| everything `done` | report and ask what's next |

State the detected phase and epic in one line before acting ("Detected: `test`
phase for E02 `e02-task-api` — 2 interactive cases still todo"). The user can
redirect you; that line is what makes the redirect cheap.

## Phase `init`

```bash
bash <this-skill-dir>/scripts/ps-spec-init.sh [project-dir] [--with-openspec-skills] [--docs-dir docs]
```

The script is idempotent: installs the CLI if missing, `openspec init --tools
none` (add `--with-openspec-skills` if the user also wants OpenSpec's stock
`/opsx:*` skills — they coexist fine because the vocabularies differ), copies
the `ps-spec` schema into `openspec/schemas/ps-spec/`, sets `schema: ps-spec`,
appends rules/operations guidance to `openspec/config.yaml`, creates
`<docs-dir>/README.md` and the `## ps-spec` block in `CLAUDE.md`. It refuses a
dirty git tree, so commit first.

It picks `docs/` if that folder already exists, else `doc/`. Use whichever it
chose everywhere below (`<docs-dir>`).

After the script: if `PRD.md`/`ARCHITECTURE.md` exist, fill the `context:` block
in `openspec/config.yaml` from them (stack, deployment, conventions, logging
convention, test command, domain one-liner). This block is injected into every
artifact instruction, so it's the cheapest way to keep artifacts grounded.

**Secure-coding rules.** Rules the model never reads are decoration, so `init`
installs them where they are read. Infer the packs from `ARCHITECTURE.md` /
`PRD.md` (or the code): always `core` (OWASP Top 10 2025), one per language
and framework (`typescript`, `express`, `react`, `python`, `fastapi`, `go`,
`docker`, `github-actions`, …), and `ai-security` / `agent-security` /
`mcp-security` / `rag-security` only when the product uses LLMs, agents, MCP
or RAG. Ask the user before installing (AskUserQuestion: "Install
secure-coding rules for this stack? Suggested: core, typescript, express,
react" with approve / edit the list / skip) — it adds files to their repo and
context to every session. Then:

```bash
bash <this-skill-dir>/scripts/ps-spec-security-rules.sh --packs core,typescript,express,react   # --list shows all packs
```

They land in `.claude/rules/security/` (Claude Code loads core packs every
session and language packs when matching files are touched; the `design`
rule in `config.yaml` then makes every `design.md` name which ones apply).
No stack known yet → do this right after `prd`. If the status later shows
`security_rules: none` on a project that has an `ARCHITECTURE.md`, offer it
once at the next checkpoint instead of blocking. Details:
`references/security-rules.md`.

Commit as `chore(ps-spec): init workflow`.

## Phase `prd`

Two situations:

- **No PRD yet** — the user has an idea. Follow `references/prd-authoring.md`
  (scope the concept, research fast-moving tech, ask a few sharp questions,
  lock architecture, write `PRD.md` and `ARCHITECTURE.md`). Don't
  over-produce for a small tool; a PRD's job is to make the epics obvious.
- **PRD exists** — audit it against the "well-defined" checklist in the same
  reference (goals/non-goals, personas, user stories, functional + non-functional
  requirements, architecture, data, API, environments, testing strategy,
  observability expectations, milestones). Ask the user only about gaps that
  would change the epics; patch the PRD with the answers.

A well-defined PRD is what lets the next phase produce epics that don't need
re-planning halfway. Commit `docs(prd): ...`.

**CP1.** Show what you changed or concluded (the checklist verdict, the
patches, the assumptions) and stop. The PRD is the human's document; you
move on only when they say it's the one to build.

## Phase `epics`

Write `EPICS.md` at the repo root following `references/epics-format.md`
(template in `assets/EPICS.template.md`):

- **One milestone = one epic = one change.** If the PRD already has a
  milestone / phase list, that is the epic list — keep its numbering order
  and names recognizable. Only split a milestone when it is clearly more
  than one change (see sizing in the reference), and say so in *Assumptions*.
- **E00 is always scaffolding & environment**: repo layout, toolchain, lint,
  logging baseline, test harness, run/debug scripts, CI. It exists so every
  later epic starts from something runnable and observable. If the PRD's
  first milestone also includes small behavior (a health endpoint, a startup
  banner), keep it in E00 and give E00 a spec — don't invent a second epic
  just to keep E00 spec-less.
- Then feature epics in dependency order, each small enough to be one change
  (a few days of work at most; split if bigger).
- Per epic: id, goal, user stories with acceptance criteria, scope,
  out-of-scope, depends-on, notes. The status board table at the top is the
  project's status source of truth.
- The **naming rule** — `E0N` ⇒ change `e0N-<slug>` ⇒ branch `epic/e0N-<slug>`
  ⇒ doc `<docs-dir>/<slug>.md` — is fixed in the header. Never renumber;
  append. This is what prevents epic ids and change names drifting apart on
  long projects.

Commit `docs(epics): ...`.

**CP2.** Show the board (ids, changes, dependencies) plus the one or two
places where you made a judgment call (a split milestone, an assumption),
and stop. On approval write `Reviewed: <date>` in the `EPICS.md` header and
commit; that line is what tells a later session it may start planning.
When epics are added or changed later, clear the line and re-review.

## Phase `plan E0N`

Planning only — no code, no branch. Read the epic in `EPICS.md`, then:

```bash
openspec new change e0N-<slug> --description "<epic goal>"
openspec status --change e0N-<slug>          # build order: proposal → specs → design → tasks → test-plan
openspec instructions <artifact> --change e0N-<slug>   # for each artifact, in that order
openspec validate e0N-<slug> --strict
```

Read `references/openspec-formats.md` before authoring — the formats are strict
and some failures are silent (4-hashtag scenarios, literal checkboxes,
capability ↔ spec file match). Then for each artifact run `openspec
instructions`, re-read the dependency files from disk, and write the file.

No OpenSpec command writes an artifact — you author every file (that is
also what OpenSpec's own `/opsx:propose` does under the hood). The one step
that matters is `openspec instructions <artifact> --change <change>`: it is
the only channel through which the project's `config.yaml` `rules:` and
`context:` — coding and security rules included — reach you. Run it for
every artifact, before writing or editing it, in every session; write from
the template it returns, never from the skill's own
`assets/schema/ps-spec/templates/` (those are the schema source that `init`
copies into the repo). The **rules guard** hook installed by `init` enforces
this: a Write/Edit to an artifact whose instructions you haven't fetched in
this session is blocked once and the instructions are handed to you — read
them and retry. It also refuses shell writes (`>`, `tee`, `cp`, `sed -i`)
into artifacts, so use the Write/Edit tools for them.

What ps-spec adds on top of stock OpenSpec:
- `proposal.md` names the epic and copies its user stories.
- `design.md` has an **Observability** section (logger names, boundary log
  lines, correlation ids, DEBUG switch). Decide it here so it's implemented
  with the code, not bolted on.
- `tasks.md` ends with **Observability → Tests → Docs** groups.
- `test-plan.md` (see `references/test-plan.md`) turns every spec scenario
  into a test — automated where possible, else an interactive case that
  names its tool: `playwright`, `chrome`, `http`, `console`, `manual`.
- Create the feature doc skeleton `<docs-dir>/<slug>.md` from
  `assets/doc-feature.template.md` with `status: draft`, fill the header
  fields you already know (`files`, `entrypoints`, `specs`, `depends_on`,
  `keywords`) and add its row to the docs index. The doc is born with the
  plan and finalized after the code.
- A change with no spec-level behavior (pure tooling, refactor, docs) sets
  `skip_specs: true` in its `.openspec.yaml` instead of inventing
  requirements. E00 often qualifies — but if it ships a health endpoint or a
  request log line, that is behavior: spec it.
- If the code you find disagrees with `ARCHITECTURE.md` / `config.yaml`
  (the stack drifted in an earlier epic), plan against the **code**, and
  raise the drift as an open question at CP3 so the user decides whether
  to realign the docs or the code.

Set the epic to `planned` in `EPICS.md`, commit `plan(e0N-<slug>): ...` on
main (planning artifacts are safe on main; code is not).

**CP3.** Summarize the plan in ~10 lines (what changes, capabilities,
number of tasks, how it will be tested, open questions) and stop. If they
change things, update the artifacts, re-validate, present again. On
approval record it in `openspec/changes/e0N-<slug>/.ps-spec.yaml`
(`checkpoints.plan.approved: <date>`, plus their notes) and commit — then
`code` may begin.

## Phase `code`

```bash
git status --porcelain            # must be clean
git checkout -b epic/e0N-<slug> main
```

Then implement `tasks.md` in order (`openspec instructions apply --change
e0N-<slug>` prints the change context and the ps-spec apply guidance):

- **Tick `- [x]` in `tasks.md` the moment a task lands**, and set the epic to
  `in-progress` in `EPICS.md` on the first one. A stale tasks file is the
  single most common way a resumed session loses its place, and the status
  script reads those checkboxes.
- Commit per task group: `feat(e0N-<slug>): <group>`; `fix`, `test`, `docs`,
  `chore` as appropriate. Small commits make the CP4 review and any
  rollback cheap.
- Logging is part of the implementation. Follow `references/observability.md`:
  named loggers per module, log at boundaries (entry/exit/error/external
  call) with ids and durations, a DEBUG switch, stdout + file, never a
  swallowed exception. Both an AI reading logs and a human on call must be
  able to follow one request through the feature.
- Reuse what exists (E00's logger, test harness, scripts) instead of
  re-inventing per epic.
- Blocked or unsure about something that changes the specs? Stop and ask —
  don't bake an assumption into code.

When the last task is checked, move straight to `test`.

## Phase `test`

Execute `openspec/changes/e0N-<slug>/test-plan.md` and record the results in
it (`Result` column: `pass` / `fail (note)`):

1. **Automated tests** first — run the command from the plan; must be green.
2. **Interactive cases** with the tool each row names (details and tool
   recipes in `references/test-plan.md`):
   - `playwright` — Playwright MCP: navigate, snapshot, click/fill, assert,
     screenshot on failure.
   - `chrome` — Claude Chrome extension: real browser session, read console /
     network, drive the UI.
   - `http` — curl/httpie against the running service; assert status + body
     and check the server log for the expected lines.
   - `console` — run the CLI/script; assert stdout, exit code, log file.
   - `manual` — leave for the human reviewer; list them in the CP4 summary.
3. **Observability checks** — confirm the log lines from design.md actually
   appear while the cases run. Missing logs are a failing test.

Set `EPICS.md` to `verifying`. On a failure: read the logs first (that's why
they exist), fix, commit `fix(e0N-<slug>): ...`, re-run the failing rows and
the automated suite. This is the inner loop — keep going until every row is
`pass`, without asking permission for each round. Don't edit expectations
to make a test pass; if a spec was wrong, say so and update the spec + test
together. Come back to the human early only if a failure reveals the plan
was wrong or you've looped several times on the same failure.

4. **Review & clean up** — once every row passes, give the branch a
   machine review before the human sees it. Run `/code-review` on the
   branch diff (`main...epic/e0N-<slug>`) for correctness bugs, then
   `/simplify` for reuse/simplification cleanups. Fix what's real
   (`fix(...)` / `refactor(...)` commits), re-run the automated suite and
   any interactive rows the fix touches, and note findings you deliberately
   defer. If those skills aren't available in the session, delegate the
   review to a subagent (see *Delegation*). Record the outcome in
   `.ps-spec.yaml` so a resumed session doesn't repeat it:

   ```yaml
   review: { done: 2026-09-14, findings: 5, fixed: 4, deferred: "N+1 query in list() → E03" }
   ```

   Why here and not at CP4: the human's time is the scarce resource. They
   should review a branch that has already had its obvious bugs and
   duplication removed, and see the reviewer's findings in the CP4 summary
   rather than discover them.

## Phase `doc`

Finalize `<docs-dir>/<slug>.md` per `references/docs-format.md`: what it
does, how it works (files, flow, data), configuration, **logs & debugging**
(logger names, lines to look for, how to enable DEBUG, which tool to use to
poke at it), how to run and test, known gaps, references. Complete the
**findability header** (`files`, `entrypoints`, `loggers`, `events`, `env`,
`specs`, `depends_on`, `keywords`) by copying the exact names from the code
— agents locate docs by grepping those lists, so a missing logger name is a
doc nobody finds. Behavior stays in `openspec/specs/`; link, don't restate.
Flip `status: final`, update the row in `<docs-dir>/README.md`, and refresh
`openspec/config.yaml` `context:` if the stack or conventions changed during
the epic. Commit `docs(e0N-<slug>): ...`. `EPICS.md` → `review`.

This doc is the project's memory. Write it for the next session that has
never seen this code — that session is often you.

## Phase `close`

**CP4 · Validate.** Present a review summary and stop:

- `git diff --stat main...epic/e0N-<slug>` and the commit list
- the test-plan table (all rows, results), plus any `manual` rows the human
  should try, and how to run the app themselves if they want to poke at it
- the review & clean-up outcome: findings fixed, findings deferred and why
- link to the feature doc and to the change folder
- anything deferred, and the proposed next epic

Wait for an explicit OK. Rejection → back to `code`/`test` with their notes
(the inner loop runs again; present CP4 again when green).

On OK, record `checkpoints.validate.approved: <date>` in
`openspec/changes/e0N-<slug>/.ps-spec.yaml`, then (see
`references/git-flow.md` for the exact sequence and rollback):

```bash
openspec validate e0N-<slug> --strict
openspec archive e0N-<slug> -y          # --skip-specs if .openspec.yaml has skip_specs: true
git add -A && git commit -m "chore(e0N-<slug>): archive change"
git checkout main && git merge --no-ff epic/e0N-<slug> -m "merge(e0N-<slug>): <epic title>"
git tag e0N-<slug>-done-$(date +%Y%m%d)
git branch -d epic/e0N-<slug>
```

Set `EPICS.md` to `done` (commit `docs(epics): E0N done`), then announce the
next epic in dependency order.

## Delegation — when subagents help

Checkpoints, EPICS.md status, `.ps-spec.yaml` records and `tasks.md` ticks
stay in the main session: a subagent can't talk to the human, so it must
never own a gate. Between checkpoints, three delegations are worth it:

- **Independent verification in `test`.** After the automated suite is
  green, hand the interactive cases to a fresh `general-purpose` subagent
  with: the path to `test-plan.md`, how to start the app, the docs dir,
  and the instruction to execute every `todo`/`fail` row with its named
  tool, record `pass` / `fail (note)` in the file, and report failures with
  the log lines it saw. Two reasons: the implementer grading its own work
  shares its own blind spots, and browser/console output is bulky — keeping
  it out of the main context matters on a long epic. Fix in the main
  session, re-delegate the failing rows.
- **The review & clean-up step when `/code-review` isn't available.** Ask
  a subagent to review `main...epic/<change>` for correctness bugs, missing
  or misleading log lines, unhandled errors, and duplication that an
  existing module already covers; fold its findings — fixed or deferred —
  into `.ps-spec.yaml` and the CP4 summary.
- **Parallel research in `prd`.** Independent tech questions go to Explore
  agents at once; you synthesize.

Don't split coder and tester across agents *inside* the fix loop (each
round trip costs more than it saves), and run epics in parallel only when
the user asks — then one subagent per epic with `isolation: worktree`, each
on its own `epic/<change>` branch, with the main session holding all four
checkpoints.

## Guardrails

- Never write feature code on `main`; never archive or merge without the
  CP4 OK recorded. Planning artifacts and docs may be committed on main.
- Checkpoints are the human's; the loops between them are yours. Don't stop
  for permission inside the inner loop, and don't roll through a checkpoint.
- One epic in flight at a time unless the user explicitly asks for parallel
  epics (then one branch each, and be clear about which one you're on).
- Proportionality: E00 might be 8 tasks and 3 console cases; a user-facing
  feature might be 30 tasks and 15 cases. Don't pad, don't skip the three
  closing task groups.
- Never write or edit a change artifact without `openspec instructions
  <artifact> --change <change>` from this session in front of you; the
  rules guard blocks it anyway. Don't copy `context:`/`rules:` text into
  artifacts; they are constraints.
- If a `docs/` folder exists, it is the docs dir; otherwise `doc/`.
- Keep the user informed in short status lines, not walls of text; the
  artifacts and docs carry the detail.

## References

Read the one that matches the phase you're in:

- `references/prd-authoring.md` — idea → PRD flow and the well-defined checklist (`prd`)
- `references/epics-format.md` — EPICS.md structure, E00, stories, status legend, naming (`epics`)
- `references/openspec-formats.md` — exact artifact formats + CLI for OpenSpec 1.13 / ps-spec schema (`plan`)
- `references/test-plan.md` — test-plan format, tool recipes, debug loop (`plan`, `test`)
- `references/observability.md` — logging conventions per stack (`plan`, `code`)
- `references/docs-format.md` — feature doc + index contract (`plan`, `doc`)
- `references/git-flow.md` — branch/commit/merge/tag/rollback and the four checkpoints (`code`, `close`)
- `references/security-rules.md` — secure-coding rule packs: choosing, installing, how they reach the model (`init`, `plan`)
