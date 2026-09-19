## Automated tests

<!-- Which suites/files cover which scenarios, and the exact command that runs them. -->
- Command: `<test command>`
- `<test file>` → covers <capability> / <scenario names>

## Interactive cases

<!-- Tool ∈ playwright | chrome | http | console | manual. Result ∈ todo | pass | fail (note). -->
| ID | Scenario | Steps | Expected | Tool | Result |
|----|----------|-------|----------|------|--------|
| T1 | <capability>: <scenario> | 1. ... 2. ... | ... | console | todo |

## Observability checks

<!-- Log lines / metrics / trace ids that must be visible while running the cases above. -->
- [ ] `<logger>` emits `<event>` with `<fields>` when <case>

## Exit criteria

- [ ] Automated tests green
- [ ] All interactive cases `pass`
- [ ] Observability checks visible
- [ ] No known regressions in previously closed epics
