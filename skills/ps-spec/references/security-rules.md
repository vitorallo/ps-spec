# Secure-coding rules — choosing, installing, and making sure they are read

ps-spec installs security rules from [TikiTribe/claude-secure-coding-rules](https://github.com/TikiTribe/claude-secure-coding-rules) (MIT): OWASP Top 10 2025, MCP/AI/agent/RAG security, and per-language / per-framework rule files written for Claude Code. This page is about the part that matters more than the copy: **getting the rules in front of the model at the moments it writes code and plans**.

## Where rules reach the model — the three channels

| Channel | What it carries | Who reads it |
|---|---|---|
| `.claude/rules/security/*.md` | the rule files themselves | Claude Code, automatically: files without `paths:` frontmatter at session start, files with `paths:` when a matching file is read or edited. pi and other agents do **not** load this folder — they are pointed at it from `CLAUDE.md` and must read the files |
| `openspec/config.yaml` → `rules.design` / `rules.tasks` | "design.md has a Security section naming which rule files apply; the Tests group verifies each item" | any agent, via `openspec instructions <artifact>` — the rules guard makes sure that call happens before an artifact is written |
| `CLAUDE.md` `## ps-spec` block | pointer to the folder + the instruction to read the stack's files before `plan` and `code` | Claude Code and pi both read `CLAUDE.md` |

So on Claude Code the rules are in context when code is written; on pi they are one `read` away and the design Security section forces the question "which rules apply?" at plan time on both.

## Choosing packs

Infer from `ARCHITECTURE.md` / `PRD.md`, or from the code (`package.json`, `pyproject.toml`, `go.mod`, Dockerfiles, `.github/workflows`). Then confirm with the user — it adds files to their repo and context to their sessions.

| Situation | Packs |
|---|---|
| every project | `core` (OWASP Top 10 2025, 15 KB, always loaded) |
| TypeScript API + React UI | `typescript`, `express` (or `nestjs`), `react` |
| Python service | `python`, `fastapi` / `django` / `flask` |
| Go / Rust / Java / C# | `go` / `rust` / `java` / `csharp` |
| ships containers / k8s | `docker`, `kubernetes` or `helm` (`containers-core` for the group's generic rules) |
| has CI | `github-actions` or `gitlab-ci` (`cicd-core`) |
| infra as code | `terraform` / `pulumi` (`iac-core`) |
| calls LLMs | `ai-security` |
| is or hosts an agent | `agent-security` |
| exposes or consumes MCP servers | `mcp-security` (61 KB — only when MCP is really in scope) |
| RAG pipeline | `rag-security` (50 KB) + `rag-core` + the specific `rag/<area>/<tool>` packs (e.g. `rag/vector-managed/pinecone`) |
| graph database | `graph-database-security` |

`core-all` installs every `_core` file (~220 KB, all always-loaded). Don't — pick.

`bash scripts/ps-spec-security-rules.sh --list` prints every pack with its size. Ambiguous names take the `group/name` form.

## Installing

```bash
bash <skill>/scripts/ps-spec-security-rules.sh --packs core,typescript,express,react
bash <skill>/scripts/ps-spec-security-rules.sh --update        # re-pull upstream, reinstall the packs in .manifest
bash <skill>/scripts/ps-spec-security-rules.sh --packs ... --src ~/src/claude-secure-coding-rules   # local checkout instead of the GitHub clone
```

or through init: `ps-spec-init.sh --security-rules core,typescript,express,react`.

The source is cloned to `~/.cache/ps-spec/claude-secure-coding-rules` and pulled on every run (`PS_SPEC_SECURITY_RULES_SRC` overrides the source). Files are written to `.claude/rules/security/<pack>.md`; language and framework packs get a `paths:` frontmatter so Claude Code loads them only when relevant (`--always` disables that). `.claude/rules/security/.manifest` records source, commit, packs and date.

Commit the folder — the rules are part of the project, and a teammate's session must see the same ones.

## Customizing

Do not edit the upstream files (`--update` overwrites them). Add `.claude/rules/security/project.md` with the project's own rules and overrides, in the same format:

```markdown
### Rule: Allow eval() in the sandboxed REPL module

**Level**: `advisory`
**When**: `src/repl/sandbox.ts` only.
**Why**: the REPL runs user code by design inside an isolated worker; the OWASP injection rule is satisfied by the sandbox boundary, documented in doc/repl.md.
```

## Using them in the loop

- **`plan`**: while writing `design.md`, read the rule files relevant to the change (path-scoped packs are not in context yet at plan time — open them). Fill the Security section: which files apply, and how each is honoured. Every item becomes a check in the `tasks.md` Tests group and a row in `test-plan.md` (tool `http` for authz/injection probes, `console` for secrets/log-leak checks).
- **`code`**: Claude Code has the rules loaded when it edits matching files. On pi, read the files named in the design Security section before the first task that touches them.
- **`test`**: run the security rows like any other; the review & clean-up pass (`/code-review`) is a second pair of eyes on the same list.
- **`close`**: CP4's summary includes the Security section status — items verified, items deferred (with a reason the user accepted).

## Why not paste the rules into `config.yaml` `rules:`?

`openspec instructions` injects `rules:` into every artifact instruction. Security rule files are 6–60 KB each; putting them there would make every proposal/spec/design/tasks instruction carry the whole set, on every artifact, on every session. The design-section rule (one line) is enough to force the question; the files themselves are loaded once per session by Claude Code, or read on demand by other agents.
