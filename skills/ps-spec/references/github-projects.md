# GitHub Projects sync (optional)

Mirrors the `EPICS.md` status board into a GitHub Project (Projects v2) linked to the repo, so epics can
be watched, filtered and discussed on GitHub while ps-spec keeps working exactly as before.

**Methodology in one line:** `EPICS.md` is the source of truth; the project is a mirror; the skill pushes
every epic-status transition it already makes to the project; a sync failure warns and never blocks a phase.

## Prerequisites

- `gh` ≥ 2.40 (Projects v2 commands; tested with 2.88) and `jq`.
- The token needs the `project` scope, which the default `gh auth login` does **not** grant:
  `gh auth refresh -s project,read:project` (interactive; the user runs it). Without it the script exits 3
  with that exact hint.
- A git remote `origin` pointing at the repo (used to find `<owner>/<repo>` offline), or pass `--repo`.

## Enable

```bash
bash <skill-dir>/scripts/ps-spec-gh-sync.sh init --owner <owner> --repo <owner>/<repo> [--title "<Project>"]
```

`init` is idempotent: reuses a project with that title or creates one, links it to the repo, ensures a
`SINGLE_SELECT` field **Epic Status** (todo, planned, in-progress, verifying, review, done, dropped) and the
`epic` label, then prints the header line to add to `EPICS.md`:

```
**GitHub-Project:** <owner>/<number>
```

Put it next to `Reviewed:`. That line is the switch — when it is absent, nothing in ps-spec changes.
(Fallback location: `github_project: <owner>/<number>` under a `ps-spec:` key in `openspec/config.yaml`.)

Then, once the board is approved (CP2): `ps-spec-gh-sync.sh sync-epics` creates one issue per epic
(title `E0N: <title>`, label `epic`, body = the epic's section from `EPICS.md`), adds it to the project and
sets its Epic Status from the board. Re-running is safe and also refreshes each issue's title and body from `EPICS.md`: issues are matched by the `E0N:` title prefix and
never duplicated.

## Status mapping (`EPICS.md` → project field "Epic Status")

| ps-spec phase boundary | EPICS.md status | Project field | Issue |
|------------------------|-----------------|---------------|-------|
| `epics` (CP2 approved) | `todo`          | todo          | created, open |
| `plan` (artifacts done) | `planned`      | planned       | open |
| `code` (first task)    | `in-progress`   | in-progress   | open |
| `test`                 | `verifying`     | verifying     | open |
| `doc`                  | `review`        | review        | open |
| `close` (CP4 ok, merged) | `done`        | done          | **closed** |
| descoped               | `dropped`       | dropped       | closed |

The skill calls `set-status <E0N> <status>` at each of these boundaries when the header line is present.
The project's built-in *Status* column (Todo / In Progress / Done) is left alone; "Epic Status" carries the
ps-spec legend 1:1 so nothing is lost in translation.

## Disable / dispose

Delete the `GitHub-Project:` line from `EPICS.md`. The script then refuses to run (exit 2) and the phases skip
the hook. The project and issues stay on GitHub as history; delete them by hand if you want them gone.

## Resuming in a cold session

`scripts/ps-spec-status.sh` prints `github_project: <owner>/<number>` (or `none`). If set, a resumed session
may run `ps-spec-gh-sync.sh status` to compare the mirror with the board; on any mismatch, `sync-epics`
re-asserts `EPICS.md` onto the project (the board wins, always).

## `--dry-run`

Prints every `gh` command instead of executing it and performs **no network calls** (lookups return
placeholders like `<item-id>`, the scope check is skipped). Use it to review what a phase would push.

## gh CLI limitations that shaped the script

- `gh project item-edit` needs node IDs (`--project-id PVT_…`, `--field-id`, `--single-select-option-id`),
  not names. The script resolves them each run from `project view` / `field-list` JSON — no IDs are stored.
- Single-select options cannot be edited after creation via the CLI (`field-create` only). If a status is
  missing from the field, delete the field in the UI and re-run `init` (or add the option in the UI).
- `item-list --format json` exposes custom fields keyed by their lowercased name (`"epic status"`); the
  script reads both spellings.
- `item-add` is idempotent on GitHub's side (re-adding returns the existing item); issue lookup uses
  `issue list --search 'in:title "E0N:"'`, so keep the `E0N:` prefix in issue titles.
- `project link` must be rerun if the repo is renamed; `gh project` has no "unlink by number" symmetry worth
  wrapping. Everything here works with an unlinked project too — linking is for the repo's Projects tab.
