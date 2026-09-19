#!/usr/bin/env bash
# ps-spec-init.sh — idempotent bootstrap of a project for the ps-spec workflow.
#
#   bash ps-spec-init.sh [project-dir] [--with-openspec-skills] [--with-gate-hook] [--no-rules-guard]
#                        [--security-rules <packs>] [--docs-dir <dir>] [--allow-dirty]
#
# What it does (each step skipped if already done):
#   1. installs the openspec CLI if missing (npm, global)
#   2. openspec init --tools none   (or --tools claude with --with-openspec-skills)
#   3. installs the ps-spec schema into openspec/schemas/ps-spec/ and sets schema: ps-spec
#   4. appends the ps-spec rules/operations block to openspec/config.yaml
#   5. creates <docs-dir>/README.md from the template
#   6. appends the ps-spec block to CLAUDE.md
#   7. makes sure the project is a git repo
#   8. installs the rules-guard hook (artifact writes require `openspec instructions` first; --no-rules-guard to skip)
#      and, with --with-gate-hook, the gate hook that blocks archive/merge until CP4 is recorded
#   9. (--security-rules core,typescript,...) installs secure-coding rule packs into .claude/rules/security/
#      via ps-spec-security-rules.sh (TikiTribe/claude-secure-coding-rules)
# It never touches PRD.md / ARCHITECTURE.md / EPICS.md — those are the skill's job.

set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"

PROJECT="."
TOOLS="none"
DOCS_DIR=""
ALLOW_DIRTY=0
GATE_HOOK=0
RULES_GUARD=1
SECURITY_RULES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --with-openspec-skills) TOOLS="claude" ;;
    --with-gate-hook) GATE_HOOK=1 ;;
    --no-rules-guard) RULES_GUARD=0 ;;
    --security-rules) SECURITY_RULES="$2"; shift ;;
    --docs-dir) DOCS_DIR="$2"; shift ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) PROJECT="$1" ;;
  esac
  shift
done
cd "$PROJECT"
PROJECT="$(pwd)"
log() { printf '  %s\n' "$*"; }
echo "ps-spec init in $PROJECT"

# 7 (first, so later steps can check cleanliness) — git
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init -q
  log "git: initialized repository"
else
  if [ "$ALLOW_DIRTY" = 0 ] && [ -n "$(git status --porcelain)" ]; then
    echo "ps-spec init: working tree is dirty. Commit or stash first (or pass --allow-dirty)." >&2
    exit 1
  fi
  log "git: ok ($(git branch --show-current 2>/dev/null || echo detached))"
fi

# 1 — openspec CLI
if ! command -v openspec >/dev/null 2>&1; then
  log "openspec: installing @fission-ai/openspec@latest (needs Node >= 20.19)"
  npm install -g @fission-ai/openspec@latest
fi
log "openspec: $(openspec --version | head -1)"

# 2 — openspec init
if [ ! -f openspec/config.yaml ]; then
  openspec init --tools "$TOOLS" --force --no-animation >/dev/null
  log "openspec: initialized (tools=$TOOLS)"
else
  log "openspec: already initialized"
  if [ "$TOOLS" = "claude" ] && [ ! -d .claude/skills/openspec-propose ]; then
    openspec init --tools claude --force --no-animation >/dev/null
    log "openspec: added stock Claude skills"
  fi
fi

# 3 — schema
if [ ! -f openspec/schemas/ps-spec/schema.yaml ]; then
  mkdir -p openspec/schemas
  cp -R "$ASSETS/schema/ps-spec" openspec/schemas/ps-spec
  log "schema: installed openspec/schemas/ps-spec/"
else
  log "schema: already present (not overwritten; diff against $ASSETS/schema/ps-spec to update)"
fi
openspec schema validate ps-spec >/dev/null 2>&1 && log "schema: valid" || { echo "schema validation failed" >&2; openspec schema validate ps-spec; exit 1; }
if ! grep -qE '^schema:[[:space:]]*ps-spec' openspec/config.yaml; then
  python3 - <<'PY'
import re,io
p='openspec/config.yaml'
s=open(p).read()
s=re.sub(r'^schema:.*$', 'schema: ps-spec', s, count=1, flags=re.M)
open(p,'w').write(s)
PY
  log "config: schema set to ps-spec"
fi

# 4 — rules / operations block
if ! grep -q 'ps-spec (managed by ps-spec-init.sh' openspec/config.yaml; then
  if grep -qE '^(rules|operations):' openspec/config.yaml; then
    log "config: rules/operations already defined by hand — NOT appending; merge $ASSETS/config.snippet.yaml manually"
  else
    printf '\n' >> openspec/config.yaml
    cat "$ASSETS/config.snippet.yaml" >> openspec/config.yaml
    log "config: appended ps-spec rules + operations guidance"
  fi
fi

# 5 — docs dir
if [ -z "$DOCS_DIR" ]; then
  if [ -d docs ]; then DOCS_DIR=docs; else DOCS_DIR=doc; fi
fi
mkdir -p "$DOCS_DIR"
if [ ! -f "$DOCS_DIR/README.md" ]; then
  sed "s|<docs-dir>|$DOCS_DIR|g" "$ASSETS/doc-README.template.md" > "$DOCS_DIR/README.md"
  log "docs: created $DOCS_DIR/README.md (index)"
else
  log "docs: $DOCS_DIR/README.md exists"
fi

# 6 — CLAUDE.md block
if [ ! -f CLAUDE.md ] || ! grep -q '## ps-spec' CLAUDE.md; then
  sed "s|<docs-dir>|$DOCS_DIR|g" "$ASSETS/claude-md.snippet.md" >> CLAUDE.md
  log "CLAUDE.md: appended ps-spec block"
else
  log "CLAUDE.md: ps-spec block present"
fi

# 8 — Claude Code hooks: rules guard (default) + optional gate guard
#   rules guard: no OpenSpec command writes an artifact, the model does — and `openspec instructions`
#   is the only step that carries config.yaml rules/context (security rules included) to it. The hook
#   blocks the first write of an artifact whose instructions were not fetched in this session and
#   hands the instructions back. Also refuses shell writes (>, tee, cp, sed -i) into artifacts.
#   gate guard: blocks `openspec archive` / `git merge epic/*` until CP4 is recorded.
if [ "$RULES_GUARD" = 1 ] || [ "$GATE_HOOK" = 1 ]; then
  mkdir -p .claude/hooks
  [ "$RULES_GUARD" = 1 ] && cp "$ASSETS/hooks/ps-spec-rules-guard.sh" .claude/hooks/ps-spec-rules-guard.sh && chmod +x .claude/hooks/ps-spec-rules-guard.sh
  [ "$GATE_HOOK" = 1 ] && cp "$ASSETS/hooks/ps-spec-gate-guard.sh" .claude/hooks/ps-spec-gate-guard.sh && chmod +x .claude/hooks/ps-spec-gate-guard.sh
  RULES_GUARD="$RULES_GUARD" GATE_HOOK="$GATE_HOOK" python3 - <<'PY'
import json, os
p = '.claude/settings.json'
s = json.load(open(p)) if os.path.exists(p) else {}
hooks = s.setdefault('hooks', {})
changed = False
def ensure(event, matcher, script):
    global changed
    cmd = 'bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/%s' % script
    lst = hooks.setdefault(event, [])
    for h in lst:
        if h.get('matcher') == matcher and any(x.get('command') == cmd for x in h.get('hooks', [])):
            return
    lst.append({'matcher': matcher, 'hooks': [{'type': 'command', 'command': cmd}]})
    changed = True
if os.environ.get('RULES_GUARD') == '1':
    ensure('PreToolUse', 'Write|Edit|MultiEdit', 'ps-spec-rules-guard.sh')
    ensure('PreToolUse', 'Bash', 'ps-spec-rules-guard.sh')
    ensure('PostToolUse', 'Bash', 'ps-spec-rules-guard.sh')
    print('  hook: rules guard (openspec instructions before every artifact write)')
if os.environ.get('GATE_HOOK') == '1':
    ensure('PreToolUse', 'Bash', 'ps-spec-gate-guard.sh')
    print('  hook: gate guard (archive/merge need CP4)')
if changed:
    json.dump(s, open(p, 'w'), indent=2)
    print('  hook: .claude/settings.json updated (restart the Claude Code session to load hooks)')
else:
    print('  hook: .claude/settings.json already configured')
PY
fi

# 9 — secure-coding rule packs (optional; the skill asks the user which packs fit the stack)
if [ -n "$SECURITY_RULES" ]; then
  bash "$SKILL_DIR/scripts/ps-spec-security-rules.sh" . --packs "$SECURITY_RULES"
else
  [ -d .claude/rules/security ] && log "security rules: $(ls .claude/rules/security/*.md 2>/dev/null | wc -l | tr -d ' ') pack(s) present" || log "security rules: none (scripts/ps-spec-security-rules.sh --packs core,<lang>,<framework>)"
fi

# EPICS.md hint (not created here — the skill writes it from the PRD)
[ -f EPICS.md ] || log "EPICS.md: absent — run the epics phase after the PRD is ready"

echo "done. Next: fill the context: block in openspec/config.yaml, then run scripts/ps-spec-status.sh"
