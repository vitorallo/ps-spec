# Git flow — branch per epic, four checkpoints, merge after archive

Why: the branch is the safety net that lets the inner agentic loop (`code` → `test` → fix → `doc`) run autonomously — nothing lands on `main` until a human has looked at tests + docs. Small conventional commits make that review, and any rollback, cheap.

## The developer feedback loop and where git meets it

| Checkpoint | Human decides | Recorded as | Git state |
|------------|---------------|-------------|-----------|
| CP1 · PRD | this is what we build | (none; EPICS.md existing implies it) | `main` |
| CP2 · Epics | list, order, stories | `Reviewed: <date>` in EPICS.md header | `main` |
| CP3 · Plan & tasks | this change is right, go code | `.ps-spec.yaml` → `checkpoints.plan.approved` | `main` (planning committed) → branch opened after |
| CP4 · Validate | tests + docs prove it, ship | `.ps-spec.yaml` → `checkpoints.validate.approved` | on `epic/<change>` → archive, merge, tag after |

`.ps-spec.yaml` lives in the change folder next to `.openspec.yaml` and travels with it into the archive, so the approval history is kept:

```yaml
checkpoints:
  plan:     { approved: 2026-09-14, notes: "ok; use node:sqlite" }
  validate: { approved: 2026-09-15 }
review:     { done: 2026-09-15, findings: 5, fixed: 4, deferred: "N+1 query in list() → E03" }
```

`review` is the agent's own record of the review & clean-up step (`/code-review` + `/simplify` after the test plan passes) — not a human checkpoint, but written to the same file so a resumed session sees the whole history of the change in one place.

Record an approval only when the user gave it in the conversation. Commit the record with the checkpoint (`chore(<change>): CP3 approved`). If the user later withdraws or changes scope, delete the key — the status script will route back to the checkpoint.

### Optional hard gate (hook)

`ps-spec-init.sh --with-gate-hook` installs `.claude/hooks/ps-spec-gate-guard.sh` and a `PreToolUse` entry in `.claude/settings.json` that blocks any Bash command matching `openspec archive <change>` or `git merge … epic/<change>` unless that change's `validate` checkpoint is recorded. Advisory guidance in `config.yaml` already says the same; the hook makes it impossible to skip by accident when several sessions or agents share the repo.

## Naming

- Branch: `epic/<change-name>` → `epic/e02-task-api`
- Commits: `<type>(<change-name>): <what>` — types `plan`, `feat`, `fix`, `test`, `docs`, `chore`, `refactor`. Examples: `plan(e02-task-api): proposal, specs, design, tasks, test-plan`, `feat(e02-task-api): store + create/get endpoints`, `fix(e02-task-api): validation on empty title`, `docs(e02-task-api): finalize task-api.md`.
- Tag at close: `<change-name>-done-YYYYMMDD` — a rollback point per epic.
- Main branch: whatever the repo uses (`main` or `master`); the status script prints it as `git_main`.

## What lives on main vs the branch

| On `main` directly | On `epic/<change>` |
|--------------------|--------------------|
| `init` output (openspec/, schema, docs index, CLAUDE.md block) | all feature code |
| `PRD.md`, `ARCHITECTURE.md`, `EPICS.md` edits from `prd`/`epics` | `tasks.md` checkbox ticks |
| planning artifacts from `plan` (the change folder) and the doc skeleton | test-plan results, feature doc finalization |
| EPICS status `planned` | EPICS status `in-progress` / `verifying` / `review` |
| archive commit is made on the branch, then merged | `openspec archive` commit |

Planning on main is safe (it's markdown) and means CP3 reviews happen against main. Everything from `code` onwards is on the branch.

## Phase `code` — opening the branch

```bash
git status --porcelain                 # empty, or stop and ask the user what to do with the changes
git checkout <main>
git pull --ff-only 2>/dev/null || true # if there's a remote
git checkout -b epic/<change> <main>
```

If `epic/<change>` already exists (resumed session), `git checkout epic/<change>` and continue from the first unchecked task. If another `epic/*` branch is unmerged (`git_epic_branches_unmerged` in the status output), tell the user — running two epics at once is allowed but should be deliberate.

## During `code` / `test` / `doc`

- Commit per task group as soon as the group's tasks are ticked; include the `tasks.md` tick in the same commit so the checklist and the code never disagree.
- `EPICS.md` status changes are committed with the work (`docs(epics): E02 in-progress` is fine as part of the first feat commit).
- Never rewrite history on the branch once the CP4 summary has been shown; the reviewer's diff must stay stable.

## CP4 summary (before `close`)

```bash
git log --oneline <main>..epic/<change>
git diff --stat <main>...epic/<change>
```
Show these, the test-plan table, the review & clean-up outcome (fixed / deferred findings), the doc link, manual rows for the human, deferred items. Then stop and wait for an explicit OK.

## Phase `close` — after the OK

```bash
# record CP4 first (checkpoints.validate.approved: <date> in openspec/changes/<change>/.ps-spec.yaml), then:
openspec validate <change> --strict
openspec archive <change> -y            # add --skip-specs when .openspec.yaml has skip_specs: true
git add -A && git commit -m "chore(<change>): archive change"
git checkout <main>
git merge --no-ff epic/<change> -m "merge(<change>): <epic title>"
git tag <change>-done-$(date +%Y%m%d)
git branch -d epic/<change>
# EPICS.md → done
git add EPICS.md && git commit -m "docs(epics): <E0N> done"
git push --follow-tags 2>/dev/null || true   # only if a remote exists; never create one without asking
```

`--no-ff` keeps one merge commit per epic on main, so `git log --first-parent <main>` reads as the epic history, and `git revert -m 1 <merge-sha>` undoes a whole epic in one step.

If archive fails validation: fix the artifacts (usually a spec delta or an unchecked task), re-run. Don't use `--no-validate`.

## Rollback

- Undo a whole epic after merge: `git revert -m 1 <merge-commit>` on main, then re-open the epic in EPICS.md (`todo`, with a note) and un-archive by moving the folder back from `openspec/changes/archive/<date>-<change>/` if the work will be redone; the spec deltas merged into `openspec/specs/` must be reverted by hand in that case.
- Abandon an epic mid-flight: `git checkout <main> && git branch -D epic/<change>`; set EPICS status back to `planned` (artifacts survive on main) or `dropped`.

## Remotes and PRs

ps-spec merges locally by default (user's choice). If the user prefers PRs: after `doc`, `git push -u origin epic/<change>` and `gh pr create --fill`; CP4 becomes the PR review; run `close` after the PR merges (archive on main, tag). Never create a remote repository or push to a new remote without confirming with the user — that's an outward-facing action.
