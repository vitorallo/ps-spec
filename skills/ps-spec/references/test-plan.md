# test-plan.md — format, tool recipes, debug loop

`test-plan.md` is the fifth artifact of every ps-spec change. It is written in `plan` (from the spec scenarios and story acceptance criteria), executed in `test`, and must be fully `pass` before CP4 (Validate). It's the evidence the human reviewer looks at, and it's how the next session knows how this feature was proven.

## Format

```markdown
## Automated tests

- Command: `npm test` (or `pytest -q`, `go test ./...`, `cargo test`)
- `tests/task_api.test.ts` → task-crud: create, get, list, update, delete, validation errors
- `tests/e2e/tasks.spec.ts` → task-list-ui: add task, complete task (Playwright, runs in CI)

## Interactive cases

| ID | Scenario | Steps | Expected | Tool | Result |
|----|----------|-------|----------|------|--------|
| T1 | task-crud: create task | POST /tasks {"title":"a"} | 201, body has id + createdAt; log `task.create` with id | http | todo |
| T2 | task-list-ui: add task | open /, type "a", Enter | row appears; no console errors | playwright | todo |
| T3 | task-list-ui: DevTools check | open / in real session, check Network tab | one POST, no 4xx/5xx | chrome | todo |
| T4 | cli: import file | `app import fixtures/tasks.csv` | exit 0; "imported 3 tasks" in stdout and in logs/app.log | console | todo |
| T5 | email digest received | trigger digest, check inbox | mail arrives | manual | todo |

## Observability checks

- [ ] `task.api` logs `task.create id=<uuid> duration_ms=<n>` at INFO on T1
- [ ] a failing validation logs at WARN with the field name, not a stack trace
- [ ] `LOG_LEVEL=DEBUG` shows the SQL/query for T1

## Exit criteria

- [ ] Automated tests green
- [ ] All interactive cases `pass`
- [ ] Observability checks visible
- [ ] No known regressions in previously closed epics
```

`Result` values: `todo`, `pass`, `fail (short note)`. The status script counts them, so keep the last cell to exactly those forms.

Coverage rule: every `#### Scenario:` in the change's specs maps to at least one automated test or one interactive row; every story acceptance criterion maps to at least one row. A scaffolding epic may be 3 console rows; don't pad.

## Choosing the tool

| Tool | Use for | Don't use for |
|------|---------|---------------|
| `playwright` | Web UI flows: navigation, forms, assertions on rendered text, screenshots, console errors. Repeatable, headless, can be promoted to an automated e2e test. | Anything needing the user's real logged-in session or extensions |
| `chrome` | Web UI in the user's real Chrome via the Claude Chrome extension: authenticated sessions, DevTools console/network reading, visual checks on the real deployment | Bulk repetitive flows (use playwright) |
| `http` | APIs, webhooks, health endpoints: curl/httpie, assert status + JSON body, then read the server log for the expected lines | UI behavior |
| `console` | CLIs, scripts, workers, cron jobs: run, assert stdout/stderr/exit code, tail the log file | Anything interactive in a browser |
| `manual` | Only what no tool can drive (physical devices, third-party UIs, email/SMS receipt). Listed for the human at CP4. | Anything a tool could do — manual rows hide bugs |

## Tool recipes

**playwright (MCP)** — load the tools once (`ToolSearch "select:mcp__plugin_playwright_playwright__browser_navigate,...browser_snapshot,...browser_click,...browser_type,...browser_take_screenshot,...browser_console_messages"`), then per row: `browser_navigate` → `browser_snapshot` (get element refs) → act (`browser_click`, `browser_type`, `browser_fill_form`) → `browser_snapshot` again and assert the expected text/element → on failure `browser_take_screenshot` and `browser_console_messages` and attach to the row's note. Start the dev server first (background Bash) and wait for the port.

**chrome (extension)** — call `mcp__claude-in-chrome__tabs_context_mcp` first, open a new tab (`tabs_create_mcp`), `navigate`, use `read_page`/`find` to locate elements, `computer` to interact, `read_console_messages` (with a `pattern`) and `read_network_requests` to verify. Never trigger `alert()/confirm()` dialogs — they block the extension.

**http** — `curl -s -w '\n%{http_code}\n' -X POST localhost:3000/tasks -H 'content-type: application/json' -d '{"title":"a"}'`; assert the code and body (`jq`), then `grep 'task.create' logs/app.log` (or the stdout capture) for the observability check.

**console** — run the command with output captured (`cmd > out.txt 2> err.txt; echo $?`), assert on the files, then check the log file. For long-running workers, run in the background, wait for the log line, then stop it.

## Executing the plan (the `test` phase loop)

1. Start whatever the cases need (dev server, database, fixtures) — reuse E00's run scripts.
2. Run the automated command. Red → fix first; nothing else is meaningful until it's green.
3. Walk the interactive rows in order, one tool session per tool. Record `pass` or `fail (note)` immediately after each row — don't batch results in your head.
4. Tick the observability checks while doing the rows; a missing log line is a failure of that row.
5. On any failure: **read the logs before the code** (with `LOG_LEVEL=DEBUG` if needed). Fix, commit `fix(<change>): ...`, re-run the failing row(s) and the automated suite.
6. All rows `pass` and the exit criteria checked → **review & clean up**: `/code-review` on `main...epic/<change>` for correctness, then `/simplify` for cleanups; fix, re-run the suite and the rows the fix touched; record `review: { done, findings, fixed, deferred }` in `.ps-spec.yaml` → move to `doc`.

Never change an expectation just to turn a row green. If the spec was wrong, say so, fix the spec and the test together, and mention it in the CP4 summary.

## Delegating the interactive rows

Once the automated suite is green, the interactive rows are a good job for a fresh subagent — it verifies without the implementer's assumptions and keeps screenshots/snapshots out of the main context. Prompt shape:

```
Execute the interactive test cases in <repo>/openspec/changes/<change>/test-plan.md.
- Start the app with: <command>; logs are in <path>; LOG_LEVEL=debug shows more.
- For every row whose Result is todo or fail: run it with the tool named in the Tool column
  (playwright = Playwright MCP, chrome = Claude Chrome extension, http = curl, console = run the command).
- Also verify the "Observability checks" list while doing the rows.
- Edit the file: set Result to `pass` or `fail (short note)`. Don't change Steps/Expected.
- Report: a table of results, and for each failure the exact log lines or console errors you saw.
Do not modify source code.
```

The main session reads the report, fixes, commits, and re-delegates only the failing rows.

## Promoting interactive cases

If a `playwright` or `http` row is stable and valuable, add it to the automated suite before closing the epic (an e2e spec, an integration test) and note "promoted → tests/..." in the row. Each epic should leave the automated suite stronger than it found it.
