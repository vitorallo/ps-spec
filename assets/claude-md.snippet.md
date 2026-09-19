
## ps-spec (epic-driven development)

This project is developed with the `ps-spec` skill: one epic = one OpenSpec change = one git branch = one feature doc.

- Planning memory: `PRD.md`, `ARCHITECTURE.md`, `EPICS.md` (status board + naming rule), `openspec/` (schema `ps-spec`).
- Feature memory: `<docs-dir>/README.md` index and `<docs-dir>/<feature>.md` per epic — read the relevant doc before touching a feature. Find it by grepping the doc headers: `grep -l "<file | route | logger | event | env var>" <docs-dir>/*.md`. Behavior contract: `openspec/specs/<capability>/spec.md`.
- Vocabulary: `ps-spec next` (detect and run the next phase) · `prd` · `epics` · `plan E0N` · `code` · `test` · `doc` · `close`. OpenSpec's own `propose/apply/archive` words are not used here.
- Rules: never code on `main` (branch `epic/<change>`); tick `tasks.md` as tasks land; every change has a `test-plan.md` that must fully pass; two human gates (after `plan`, before `close`); logging is part of every feature.
- Security: secure-coding rules live in `.claude/rules/security/` (installed by `ps-spec init` from TikiTribe/claude-secure-coding-rules; `.manifest` lists the packs). Claude Code loads them by itself; any other agent must read the files for the stack before `plan` and `code`. Every `design.md` has a Security section naming which apply.
