#!/usr/bin/env bash
# ps-spec-status.sh — one-shot repo state dump used by the ps-spec skill to pick the next phase.
# Always exits 0. Run from anywhere inside the project; it walks up to the git root (or cwd).
# Usage: ps-spec-status.sh [project-dir]

set -u
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "ps-spec-status: cannot cd to $ROOT"; exit 0; }

have() { command -v "$1" >/dev/null 2>&1; }
yn() { [ -e "$1" ] && echo yes || echo no; }

echo "=== ps-spec status ==="
echo "root: $ROOT"

# --- openspec -------------------------------------------------------------
if have openspec; then
  echo "openspec: installed $(openspec --version 2>/dev/null | head -1)"
else
  echo "openspec: MISSING (npm i -g @fission-ai/openspec@latest)"
fi
echo "openspec_init: $(yn openspec/config.yaml)"
SCHEMA="$(grep -E '^schema:' openspec/config.yaml 2>/dev/null | head -1 | sed 's/schema:[[:space:]]*//')"
echo "schema: ${SCHEMA:-none}   (expected: ps-spec)"
echo "schema_dir: $(yn openspec/schemas/ps-spec/schema.yaml)"
if grep -qE '^context:' openspec/config.yaml 2>/dev/null; then echo "context_filled: yes"; else echo "context_filled: no"; fi

# --- planning docs --------------------------------------------------------
echo "prd: $(yn PRD.md)   architecture: $(yn ARCHITECTURE.md)   epics: $(yn EPICS.md)"
if [ -f PRD.md ] && [ -f EPICS.md ] && [ PRD.md -nt EPICS.md ]; then echo "prd_newer_than_epics: yes"; fi

# --- docs dir -------------------------------------------------------------
DOCS=""
for d in docs doc; do [ -d "$d" ] && { DOCS="$d"; break; }; done
if [ -n "$DOCS" ]; then
  echo "docs_dir: $DOCS   index: $(yn "$DOCS/README.md")"
  for f in "$DOCS"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "README.md" ] && continue
    st="$(grep -m1 -E '^status:' "$f" 2>/dev/null | sed 's/status:[[:space:]]*//; s/[[:space:]]*#.*//')"
    echo "  doc: $(basename "$f") status=${st:-?}"
  done
else
  echo "docs_dir: none"
fi
echo "claude_md_block: $( [ -f CLAUDE.md ] && grep -q '## ps-spec' CLAUDE.md && echo yes || echo no )"
if [ -d .claude/rules/security ] && ls .claude/rules/security/*.md >/dev/null 2>&1; then
  echo "security_rules: $(ls .claude/rules/security/*.md | wc -l | tr -d ' ') files ($(for f in .claude/rules/security/*.md; do b=$(basename "$f"); printf '%s ' "${b%.md}"; done))"
else
  echo "security_rules: none"
fi
echo "rules_guard_hook: $( [ -f .claude/hooks/ps-spec-rules-guard.sh ] && echo yes || echo no )"

# --- EPICS.md status board -----------------------------------------------
if [ -f EPICS.md ]; then
  REV="$(grep -m1 -E '^\*?\*?Reviewed:?\*?\*?' EPICS.md 2>/dev/null | sed -E 's/^\*?\*?Reviewed:?\*?\*?[[:space:]]*//')"
  if [ -n "$REV" ] && [ "$REV" != "—" ]; then echo "epics_reviewed: yes ($REV)"; else echo "epics_reviewed: no"; fi
  echo "epics_board:"
  # rows like: | E01 | title | `e01-slug` | E00 | status | doc |
  awk -F'|' '
    /^\|[[:space:]]*E[0-9]+[[:space:]]*\|/ {
      id=$2; change=$4; status=$6;
      gsub(/[[:space:]`]/,"",id); gsub(/[[:space:]`]/,"",change); gsub(/^[[:space:]]+|[[:space:]]+$/,"",status);
      printf "  %s change=%s status=%s\n", id, change, status
    }' EPICS.md
fi

# --- openspec changes -----------------------------------------------------
if [ -d openspec/changes ]; then
  echo "changes_active:"
  for c in openspec/changes/*/; do
    [ -d "$c" ] || continue
    n="$(basename "$c")"; [ "$n" = "archive" ] && continue
    arts=""
    for a in proposal.md design.md tasks.md test-plan.md; do [ -f "$c$a" ] && arts="$arts ${a%.md}"; done
    [ -d "$c/specs" ] && [ -n "$(find "$c/specs" -name '*.md' 2>/dev/null | head -1)" ] && arts="$arts specs"
    cnt() { local n; n="$(grep -ciE "$1" "$2" 2>/dev/null)"; echo "${n:-0}"; }
    open_t="$(cnt '^- \[ \]' "$c/tasks.md")"
    done_t="$(cnt '^- \[x\]' "$c/tasks.md")"
    # open tasks outside the closing Docs group (so "only docs left" can be told apart from "still coding")
    open_nondocs="$(awk '/^## /{docs=($0 ~ /Docs/)} /^- \[ \]/ && !docs {n++} END{print n+0}' "$c/tasks.md" 2>/dev/null)"
    tp=""
    if [ -f "$c/test-plan.md" ]; then
      todo="$(cnt '\|[[:space:]]*todo[[:space:]]*\|?[[:space:]]*$' "$c/test-plan.md")"
      fail="$(cnt '\|[[:space:]]*fail' "$c/test-plan.md")"
      pass="$(cnt '\|[[:space:]]*pass[[:space:]]*\|?[[:space:]]*$' "$c/test-plan.md")"
      tp="  test-plan: pass=$pass fail=$fail todo=$todo"
    fi
    cpf="$c/.ps-spec.yaml"
    cp_plan="pending"; cp_val="pending"; review="pending"
    if [ -f "$cpf" ]; then
      v="$(awk '/^[[:space:]]*plan:/{f=1} f && /approved:/{gsub(/.*approved:[[:space:]]*/,""); gsub(/[,}].*/,""); print; exit}' "$cpf")"; [ -n "$v" ] && cp_plan="$v"
      v="$(awk '/^[[:space:]]*validate:/{f=1} f && /approved:/{gsub(/.*approved:[[:space:]]*/,""); gsub(/[,}].*/,""); print; exit}' "$cpf")"; [ -n "$v" ] && cp_val="$v"
      v="$(awk '/^[[:space:]]*review:/{f=1} f && /done:/{gsub(/.*done:[[:space:]]*/,""); gsub(/[,}].*/,""); print; exit}' "$cpf")"; [ -n "$v" ] && review="$v"
    fi
    echo "  $n: artifacts=[${arts# }] tasks: done=$done_t open=$open_t open_non_docs=${open_nondocs:-0}$tp  cp_plan=$cp_plan review=$review cp_validate=$cp_val"
  done
  echo "changes_archived: $(find openspec/changes/archive -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
fi

# --- git ------------------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BR="$(git branch --show-current 2>/dev/null)"
  DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  echo "git: branch=${BR:-detached} dirty_files=$DIRTY"
  MAIN="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')"
  [ -z "$MAIN" ] && { git show-ref --verify --quiet refs/heads/main && MAIN=main || MAIN=master; }
  echo "git_main: $MAIN"
  UNMERGED="$(git branch --list 'epic/*' --no-merged "$MAIN" 2>/dev/null | sed 's/^[* ]*//' | tr '\n' ' ')"
  echo "git_epic_branches_unmerged: ${UNMERGED:-none}"
  echo "git_last_tag: $(git describe --tags --abbrev=0 2>/dev/null || echo none)"
else
  echo "git: NOT a repository"
fi
echo "=== end ==="
exit 0
