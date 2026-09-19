#!/usr/bin/env bash
# ps-spec-security-rules.sh — install secure-coding rules from claude-secure-coding-rules into a project.
#
#   bash ps-spec-security-rules.sh [project-dir] --packs core,typescript,express,react [--src <dir|git-url>]
#   bash ps-spec-security-rules.sh [project-dir] --list          # packs available in the source
#   bash ps-spec-security-rules.sh [project-dir] --update        # reinstall the packs in the manifest from a fresh pull
#
# Source: https://github.com/TikiTribe/claude-secure-coding-rules (public, MIT). Cloned into
# ~/.cache/ps-spec/claude-secure-coding-rules and pulled on every run, unless --src (or
# PS_SPEC_SECURITY_RULES_SRC) points to a local checkout or another git URL.
#
# Packs (comma-separated):
#   core                 rules/_core/owasp-2025.md — OWASP Top 10 2025, for every project
#   core-all             every rules/_core/*.md (owasp, ai, agent, mcp, rag, graph — ~220 KB, heavy on context)
#   <core-file>          one _core file: ai-security, agent-security, mcp-security, rag-security, graph-database-security
#   <name>               a directory under rules/ by its name: python, typescript, go, fastapi, express, django,
#                        react, nextjs, docker, kubernetes, helm, github-actions, gitlab-ci, terraform, pulumi,
#                        langchain, crewai, chunking, embeddings, ... (its CLAUDE.md is copied)
#   <group>/<name>       same, disambiguated (rag/graph vs containers/...)
#   <group>-core         a group's _core folder: cicd-core, containers-core, iac-core, rag-core
#
# Destination: .claude/rules/security/<pack>.md. Claude Code loads .claude/rules/**/*.md: core packs into
# every session, language/framework packs only when a matching file is touched (the script prepends a
# `paths:` frontmatter; --always disables that). CLAUDE.md and openspec/config.yaml (written by
# ps-spec-init.sh) point other agents at the folder and make design.md name which rules apply per change.
# Rule bodies are copied verbatim — the repo is the source of truth; add your own file next to them and
# re-run --update to refresh the upstream ones. .claude/rules/security/.manifest records source, commit,
# packs and date.

set -euo pipefail
DEFAULT_URL="https://github.com/TikiTribe/claude-secure-coding-rules"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ps-spec/claude-secure-coding-rules"
DEST_REL=".claude/rules/security"

PROJECT="."
PACKS=""
SRC="${PS_SPEC_SECURITY_RULES_SRC:-}"
LIST=0
UPDATE=0
ALWAYS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --packs) PACKS="$2"; shift ;;
    --src) SRC="$2"; shift ;;
    --list) LIST=1 ;;
    --update) UPDATE=1 ;;
    --always) ALWAYS=1 ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) PROJECT="$1" ;;
  esac
  shift
done
cd "$PROJECT"
PROJECT="$(pwd)"
DEST="$PROJECT/$DEST_REL"
log() { printf '  %s\n' "$*"; }

# ---- resolve the source checkout ----------------------------------------------------------------
if [ -z "$SRC" ]; then SRC="$DEFAULT_URL"; fi
if [ -d "$SRC" ]; then
  RULES_ROOT="$SRC"
  log "source: local checkout $SRC"
else
  mkdir -p "$(dirname "$CACHE")"
  if [ -d "$CACHE/.git" ]; then
    git -C "$CACHE" pull -q --ff-only 2>/dev/null || log "source: pull failed, using cached copy"
  else
    log "source: cloning $SRC"
    git clone -q --depth 1 "$SRC" "$CACHE"
  fi
  RULES_ROOT="$CACHE"
fi
[ -d "$RULES_ROOT/rules/_core" ] || { echo "ps-spec security rules: $RULES_ROOT has no rules/_core — not a claude-secure-coding-rules checkout" >&2; exit 1; }
COMMIT="$(git -C "$RULES_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# ---- --list ---------------------------------------------------------------------------------------
if [ "$LIST" = 1 ]; then
  echo "core packs (rules/_core):"
  for f in "$RULES_ROOT"/rules/_core/*.md; do printf '  %-28s %4s KB\n' "$(basename "${f%.md}")" "$(( $(wc -c <"$f") / 1024 ))"; done
  echo "  core = owasp-2025 only; core-all = all of the above"
  for g in "$RULES_ROOT"/rules/*/; do
    g="${g%/}"; gname="$(basename "$g")"; [ "$gname" = "_core" ] && continue
    echo "$gname packs:"
    [ -d "$g/_core" ] && printf '  %-28s %s\n' "$gname-core" "($(ls "$g"/_core/*.md 2>/dev/null | wc -l | tr -d ' ') files)"
    find "$g" -mindepth 1 -maxdepth 3 -name CLAUDE.md | sort | while read -r f; do
      d="$(dirname "$f")"; printf '  %-28s %4s KB\n' "${d#"$g"/}" "$(( $(wc -c <"$f") / 1024 ))"
    done
  done
  exit 0
fi

# ---- --update: packs from the manifest ------------------------------------------------------------
if [ "$UPDATE" = 1 ] && [ -z "$PACKS" ]; then
  [ -f "$DEST/.manifest" ] || { echo "ps-spec security rules: no $DEST_REL/.manifest to update from; pass --packs" >&2; exit 1; }
  PACKS="$(sed -nE 's/^packs=//p' "$DEST/.manifest")"
fi
[ -n "$PACKS" ] || { echo "ps-spec security rules: --packs is required (try --list)" >&2; exit 1; }

# ---- resolve packs → files -----------------------------------------------------------------------
# prints "src|dest-name" lines for one pack
resolve_pack() {
  local p="$1" hits
  case "$p" in
    core)     echo "$RULES_ROOT/rules/_core/owasp-2025.md|owasp-2025" ;;
    core-all) for f in "$RULES_ROOT"/rules/_core/*.md; do echo "$f|$(basename "${f%.md}")"; done ;;
    *-core)   local g="${p%-core}"
              [ -d "$RULES_ROOT/rules/$g/_core" ] || { echo "ps-spec security rules: no group '$g' with a _core folder" >&2; return 1; }
              for f in "$RULES_ROOT"/rules/"$g"/_core/*.md; do echo "$f|$g-$(basename "${f%.md}")"; done ;;
    */*)      [ -f "$RULES_ROOT/rules/$p/CLAUDE.md" ] || { echo "ps-spec security rules: rules/$p/CLAUDE.md not found" >&2; return 1; }
              echo "$RULES_ROOT/rules/$p/CLAUDE.md|$(basename "$p")" ;;
    *)        if [ -f "$RULES_ROOT/rules/_core/$p.md" ]; then echo "$RULES_ROOT/rules/_core/$p.md|$p"; return 0; fi
              hits="$(find "$RULES_ROOT/rules" -type d -name "$p" -not -path '*/_core*' | sort)"
              case "$(printf '%s\n' "$hits" | grep -c .)" in
                0) echo "ps-spec security rules: unknown pack '$p' (see --list)" >&2; return 1 ;;
                1) [ -f "$hits/CLAUDE.md" ] || { echo "ps-spec security rules: $hits has no CLAUDE.md" >&2; return 1; }
                   echo "$hits/CLAUDE.md|$p" ;;
                *) echo "ps-spec security rules: '$p' is ambiguous, use group/name:" >&2
                   printf '%s\n' "$hits" | sed "s|$RULES_ROOT/rules/|    |" >&2; return 1 ;;
              esac ;;
  esac
}

FILES=""
IFS=',' read -r -a PACK_ARR <<< "$PACKS"
for p in "${PACK_ARR[@]}"; do
  p="$(printf '%s' "$p" | tr -d '[:space:]')"; [ -n "$p" ] || continue
  out="$(resolve_pack "$p")" || exit 1
  FILES="$FILES$out"$'\n'
done

# ---- install ------------------------------------------------------------------------------------
# Claude Code loads a rule with `paths:` frontmatter only when it touches a matching file, so
# language/framework packs are scoped to their file types and cost context only when relevant.
# Core packs (owasp, ai, agent, mcp, rag, graph) have no natural file scope and load always.
# --always disables scoping. pi ignores the frontmatter (it's plain text to it) — harmless.
paths_for() {
  case "$1" in
    python|fastapi|django|flask)        echo '"**/*.py"' ;;
    typescript|nestjs)                  echo '"**/*.{ts,tsx}"' ;;
    javascript|express)                 echo '"**/*.{js,jsx,mjs,cjs,ts,tsx}"' ;;
    react)                              echo '"**/*.{jsx,tsx}"' ;;
    nextjs|vue|svelte|angular)          echo '"**/*.{ts,tsx,js,jsx,vue,svelte}"' ;;
    go)                                 echo '"**/*.go"' ;;
    rust)                               echo '"**/*.rs"' ;;
    java)                               echo '"**/*.java"' ;;
    csharp)                             echo '"**/*.cs"' ;;
    ruby)                               echo '"**/*.rb"' ;;
    cpp)                                echo '"**/*.{c,cc,cpp,h,hpp}"' ;;
    sql)                                echo '"**/*.sql"' ;;
    julia)                              echo '"**/*.jl"' ;;
    r)                                  echo '"**/*.{r,R}"' ;;
    docker)                             echo '"**/Dockerfile*", "**/docker-compose*.y*ml", "**/compose*.y*ml"' ;;
    kubernetes|helm)                    echo '"**/*.y*ml"' ;;
    github-actions)                     echo '".github/workflows/**"' ;;
    gitlab-ci)                          echo '".gitlab-ci.yml", ".gitlab/**"' ;;
    terraform)                          echo '"**/*.tf", "**/*.tfvars"' ;;
    *) echo "" ;;
  esac
}
mkdir -p "$DEST"
total=0; n=0
while IFS='|' read -r src name; do
  [ -n "$src" ] || continue
  scope="$( [ "$ALWAYS" = 1 ] && echo "" || paths_for "$name")"
  if [ -n "$scope" ]; then
    { printf -- '---\npaths: [%s]\n---\n' "$scope"; cat "$src"; } > "$DEST/$name.md"
    how="scoped to $scope"
  else
    cp "$src" "$DEST/$name.md"
    how="always loaded"
  fi
  size=$(( $(wc -c <"$src") / 1024 )); total=$(( total + size )); n=$(( n + 1 ))
  log "installed $DEST_REL/$name.md (${size} KB, $how)"
done <<< "$FILES"
{
  echo "source=$SRC"
  echo "commit=$COMMIT"
  echo "date=$(date +%Y-%m-%d)"
  echo "packs=$PACKS"
} > "$DEST/.manifest"
log "manifest: $DEST_REL/.manifest (commit $COMMIT)"
echo "done: $n rule file(s), ~${total} KB in $DEST_REL/. Core packs load into every Claude Code session, scoped packs when matching files are touched — keep it to what the stack needs."
