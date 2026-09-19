# PRD authoring and the "well-defined" checklist

Used in the `prd` phase. Two entry points: (A) there is no PRD and the user has an idea; (B) a PRD exists and needs auditing before epics are cut from it.

The PRD's only job in ps-spec is to make the epics obvious and the architecture fixed enough that changes don't re-litigate it. Write to that bar — no more.

## A. From an idea to a PRD

Work these steps conversationally; compress or skip what doesn't fit the project size.

### 1. Scope the idea
Decompose the concept into its natural components / stages / capabilities (ingestion, processing, storage, interface, ...). Reflect the decomposition back to the user so you agree on the shape before formalizing.

### 2. Research when the tech moves fast
If the idea leans on unfamiliar or fast-changing tech (models, frameworks, third-party APIs, pricing, licensing), verify current options with web search or Context7 before recommending. Produce a decisive recommendation with a one-line rationale, not a survey. Research independent questions in parallel via subagents when available.

### 3. Ask a few sharp questions
Only decisions that genuinely require the user and materially change the design: form factor / packaging, target platform, v1 scope (in vs deferred), and any live tech-stack trade-off. Use `AskUserQuestion` with 2–4 options each; default everything else and say so. A few high-leverage questions beat a questionnaire.

Optional add-ons to offer up front (multi-select, "none" is fine):
- research similar OSS / products for inspiration (feeds Vision and Non-goals)
- discuss the tech stack per component (recommended pick + 1–2 alternatives with trade-offs)
- create a private git remote after the docs exist (confirm the repo name first; `gh repo create <name> --private --source=. --push`)

### 4. Lock architecture → `ARCHITECTURE.md`
Record the firm choices: where it runs, how it's packaged/deployed, components and how they talk, data stores, external services, key constraints (latency, offline, privacy, cost), the **logging/observability convention** (logger library, namespace scheme, log destinations, DEBUG switch, correlation id), and the **test strategy** (frameworks, how UI is tested, what runs in CI). Include a Mermaid `flowchart` of components and data flow; add a `sequenceDiagram` for the most important request path.

These same decisions go into `openspec/config.yaml` `context:` at init.

### 5. Write `PRD.md`
Adapt this template — drop sections that don't apply, expand the ones that matter:

- Overview & Vision
- Goals / Non-goals
- Personas & Use cases
- User stories & flows (As a / I want / So that — these become the epics' stories)
- Functional requirements (numbered, testable)
- Non-functional requirements (performance, security, privacy, reliability, accessibility)
- System architecture (summary + link to ARCHITECTURE.md)
- Data & storage
- API surface (if any)
- Environments & deployment (local, CI, staging/prod; secrets handling)
- Observability expectations (what must be visible in logs/metrics for support and debugging)
- Testing strategy (unit / integration / e2e / interactive; the tool for UI checks)
- Dependencies, models, licensing
- Risks & mitigations
- Milestones — the delivery order. **Each milestone becomes one epic and one
  OpenSpec change**, so size them accordingly (a few days each, one branch,
  one review). M0 is always scaffolding & environment. Give each milestone a
  name, the stories/requirements it covers, and its acceptance criteria.

Keep requirements numbered (`FR-12`, `NFR-3`) so epics, specs and tests can point back at them.

## B. Auditing an existing PRD — the well-defined checklist

Read `PRD.md`, `ARCHITECTURE.md`, and anything else at the root the user points to. Score each line; a "no" on a starred item blocks the `epics` phase until resolved.

| # | Check | Why it matters for epics |
|---|-------|--------------------------|
| 1* | Goals and explicit non-goals | Non-goals stop epic creep |
| 2* | Personas / roles named | Stories need an "As a" |
| 3* | User stories or use cases for each major capability | Stories are the unit specs and tests derive from |
| 4* | Functional requirements, numbered and testable | Each becomes ≥1 spec scenario |
| 5 | Non-functional requirements with numbers where possible | Shows up in specs and test plans |
| 6* | Architecture: components, runtime/deploy model, data stores, external services | Fixes what E00 scaffolds |
| 7 | Data model / storage sketch | Avoids re-design mid-epic |
| 8 | API surface (if the product has one) | Lets API epics be specified precisely |
| 9* | Environments: how it runs locally, in CI, in prod; secrets | E00 needs this |
| 10* | Logging / observability expectations | ps-spec builds logging into every epic; the convention must be decided once |
| 11* | Testing strategy incl. the UI tool (Playwright / Chrome) if there's a UI | test-plan.md needs it |
| 12 | Milestones or priority ordering | Milestones map 1:1 to epics/changes; they seed the dependency order |
| 13 | Risks & open questions listed | Better in the PRD than discovered in epic 4 |

Procedure: list the failing items, group them into the fewest questions that resolve them (AskUserQuestion, options with a recommended default), then patch `PRD.md` / `ARCHITECTURE.md` in place with the answers. Don't rewrite a PRD that's fine; add what's missing. Commit `docs(prd): fill gaps for epics`.

If the user says "the PRD is good enough, go", respect it — note the unresolved items at the top of `EPICS.md` under *Assumptions* so they're visible.
