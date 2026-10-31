#!/usr/bin/env bash
# ps-spec-gh-sync.sh — OPTIONAL mirror of EPICS.md into a GitHub Project (Projects v2), gh CLI only.
#
# EPICS.md is the source of truth; the project is a mirror. Every command is idempotent.
# Enable by adding a header line to EPICS.md:   GitHub-Project: <owner>/<number>
# (fallback: `github_project: <owner>/<number>` under `ps-spec:` in openspec/config.yaml).
#
# Usage:
#   ps-spec-gh-sync.sh [--dry-run] init --owner <o> --repo <owner/repo> [--title <t>]
#   ps-spec-gh-sync.sh [--dry-run] sync-epics [EPICS.md]
#   ps-spec-gh-sync.sh [--dry-run] set-status <E0N> <status> [EPICS.md]
#   ps-spec-gh-sync.sh [--dry-run] status [EPICS.md]
#
# --dry-run prints the gh commands instead of running them and NEVER touches the network
# (lookups return placeholders such as <item-id>). Sync failures WARN and the script exits 0,
# so a ps-spec phase is never blocked by the mirror. Hard exits: 2 = misconfiguration,
# 3 = gh token lacks the `project` scope (fix: gh auth refresh -s project,read:project).
set -u

DRY=0
ARGS=()
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; *) ARGS+=("$a") ;; esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

STATUSES="todo planned in-progress verifying review done dropped"
FIELD_NAME="Epic Status"
LABEL="epic"
WARNED=0

log()  { printf 'gh-sync: %s\n' "$*"; }
warn() { printf 'gh-sync: WARN %s\n' "$*" >&2; WARNED=1; }
die()  { printf 'gh-sync: ERROR %s\n' "$*" >&2; exit "${2:-2}"; }
have() { command -v "$1" >/dev/null 2>&1; }

# fd 3 = the original stdout, so dry-run echoes survive call-site redirections like `>/dev/null 2>&1`.
exec 3>&1
# run <gh args...> — execute (or print in dry-run). Mutating calls go through here.
run() {
  if [ "$DRY" = 1 ]; then printf '[dry-run] gh %s\n' "$*" >&3; return 0; fi
  gh "$@"
}
# q <gh args...> — read-only query; in dry-run prints the command and returns empty output.
q() {
  if [ "$DRY" = 1 ]; then printf '[dry-run] gh %s\n' "$*" >&3; return 0; fi
  gh "$@" 2>/dev/null
}

check_prereqs() {
  have gh || die "gh CLI not found (https://cli.github.com)"
  have jq || die "jq not found (needed to read gh JSON)"
  [ "$DRY" = 1 ] && { log "dry-run: skipping gh auth/scope check (no network)"; return 0; }
  local scopes
  scopes="$(gh auth status 2>&1 | grep -i 'Token scopes' | head -1)"
  if ! printf '%s' "$scopes" | grep -qE "(^|[^:a-z_])'?project'?([^a-z_]|$)"; then
    die "gh token lacks the 'project' scope. Run:  gh auth refresh -s project,read:project" 3
  fi
}

# ---- project / repo resolution --------------------------------------------------------------
EPICS="EPICS.md"; OWNER=""; NUM=""; REPO=""

read_project_ref() {
  local line=""
  if [ -f "$EPICS" ]; then
    line="$(grep -m1 -E '^\*?\*?GitHub-Project:?\*?\*?' "$EPICS" | sed -E 's/^\*?\*?GitHub-Project:?\*?\*?[[:space:]]*//; s/[[:space:]].*$//')"
  fi
  if [ -z "$line" ] && [ -f openspec/config.yaml ]; then
    line="$(awk '/^ps-spec:/{f=1;next} f&&/^[^[:space:]]/{f=0} f&&/github_project:/{sub(/.*github_project:[[:space:]]*/,"");gsub(/["'"'"']/,"");print;exit}' openspec/config.yaml)"
  fi
  [ -n "$line" ] || return 1
  OWNER="${line%%/*}"; NUM="${line##*/}"
  [ -n "$OWNER" ] && [[ "$NUM" =~ ^[0-9]+$ ]] || die "bad GitHub-Project reference '$line' (want <owner>/<number>)"
}

repo_from_git() {
  local url; url="$(git remote get-url origin 2>/dev/null)" || return 1
  url="${url%.git}"
  case "$url" in
    git@*:*) REPO="${url#*:}" ;;
    http*://*/*/*) REPO="$(printf '%s' "$url" | sed -E 's#^[a-z]+://[^/]+/##')" ;;
    *) return 1 ;;
  esac
  [ -n "$REPO" ]
}

require_project() { read_project_ref || die "no GitHub-Project set. Add 'GitHub-Project: <owner>/<number>' to the $EPICS header (run: $0 init --owner <o> --repo <owner/repo>)"; }
require_repo()    { [ -n "$REPO" ] || repo_from_git || die "cannot determine repo; pass --repo <owner/repo>"; }

# ---- lookups (empty in dry-run) --------------------------------------------------------------
PROJECT_ID=""; FIELD_ID=""; declare -A OPTION_ID=()

load_project_ids() {
  if [ "$DRY" = 1 ]; then PROJECT_ID="<project-id>"; FIELD_ID="<field-id>"; for s in $STATUSES; do OPTION_ID[$s]="<opt-$s>"; done; return 0; fi
  PROJECT_ID="$(q project view "$NUM" --owner "$OWNER" --format json | jq -r '.id // empty')"
  [ -n "$PROJECT_ID" ] || { warn "cannot read project $OWNER/$NUM"; return 1; }
  local fjson; fjson="$(q project field-list "$NUM" --owner "$OWNER" -L 100 --format json)"
  FIELD_ID="$(printf '%s' "$fjson" | jq -r --arg n "$FIELD_NAME" '.fields[]? | select(.name==$n) | .id // empty')"
  [ -n "$FIELD_ID" ] || { warn "field '$FIELD_NAME' missing on project $OWNER/$NUM (run init)"; return 1; }
  while IFS=$'\t' read -r oname oid; do [ -n "$oname" ] && OPTION_ID[$oname]="$oid"; done < <(
    printf '%s' "$fjson" | jq -r --arg n "$FIELD_NAME" '.fields[]? | select(.name==$n) | .options[]? | [.name,.id] | @tsv')
}

# find_issue <E0N> -> prints "number<TAB>url" or nothing
find_issue() {
  local id="$1"
  [ "$DRY" = 1 ] && { q issue list --repo "$REPO" --state all --label "$LABEL" -L 200 --search "in:title \"$id:\"" --json number,title,url >/dev/null; return 0; }
  q issue list --repo "$REPO" --state all --label "$LABEL" -L 200 --search "in:title \"$id:\"" --json number,title,url \
    | jq -r --arg p "$id:" '[.[] | select(.title | startswith($p))] | sort_by(.number) | .[0] | select(.) | "\(.number)\t\(.url)"'
}

# find_item <issue-url> -> item id or nothing
find_item() {
  local url="$1"
  [ "$DRY" = 1 ] && { q project item-list "$NUM" --owner "$OWNER" -L 500 --format json >/dev/null; printf '<item-id>'; return 0; }
  q project item-list "$NUM" --owner "$OWNER" -L 500 --format json \
    | jq -r --arg u "$url" '.items[]? | select(.content.url==$u) | .id' | head -1
}

# ---- EPICS.md parsing ------------------------------------------------------------------------
# board_rows -> lines "E0N<TAB>title<TAB>change<TAB>status"
board_rows() {
  awk -F'|' '
    /^\|[[:space:]]*E[0-9]+[[:space:]]*\|/ {
      id=$2; title=$3; change=$4; status=$6;
      gsub(/[[:space:]`]/,"",id); gsub(/[[:space:]`]/,"",change);
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",title); gsub(/^[[:space:]]+|[[:space:]]+$/,"",status);
      printf "%s\t%s\t%s\t%s\n", id, title, change, status
    }' "$EPICS"
}
# epic_section <E0N> -> the "## E0N — …" section body
epic_section() {
  awk -v id="$1" '
    /^## /{ if(on){exit}; if($0 ~ "^## "id"([^0-9]|$)"){on=1} }
    on{print}' "$EPICS"
}
valid_status() { for s in $STATUSES; do [ "$s" = "$1" ] && return 0; done; return 1; }

# ---- set_item_status <E0N> <status> -----------------------------------------------------------
set_item_status() {
  local id="$1" st="$2" found num url item oid
  valid_status "$st" || { warn "$id: unknown status '$st' (allowed: $STATUSES)"; return 1; }
  found="$(find_issue "$id")"
  [ "$DRY" = 1 ] && found="<issue-number>	https://github.com/$REPO/issues/<n>"
  [ -n "$found" ] || { warn "$id: no issue titled '$id: …' with label '$LABEL' in $REPO (run sync-epics)"; return 1; }
  num="${found%%	*}"; url="${found#*	}"
  item="$(find_item "$url")"
  if [ -z "$item" ]; then
    log "$id: adding issue #$num to project $OWNER/$NUM"
    run project item-add "$NUM" --owner "$OWNER" --url "$url" --format json >/dev/null || { warn "$id: item-add failed"; return 1; }
    item="$(find_item "$url")"; [ -n "$item" ] || { warn "$id: item not found after add"; return 1; }
  fi
  oid="${OPTION_ID[$st]:-}"
  [ -n "$oid" ] || { warn "$id: option '$st' missing on field '$FIELD_NAME' (recreate the field with all statuses)"; return 1; }
  run project item-edit --project-id "$PROJECT_ID" --id "$item" --field-id "$FIELD_ID" --single-select-option-id "$oid" --format json >/dev/null \
    || { warn "$id: item-edit failed"; return 1; }
  log "$id → $st"
  if [ "$st" = done ] || [ "$st" = dropped ]; then
    run issue close "$num" --repo "$REPO" --comment "ps-spec: epic $id is $st (mirrored from EPICS.md)" >/dev/null 2>&1 \
      || warn "$id: could not close issue #$num"
  fi
}

# ---- subcommands -----------------------------------------------------------------------------
cmd_init() {
  local title="" existing
  while [ $# -gt 0 ]; do
    case "$1" in
      --owner) OWNER="$2"; shift 2 ;;
      --repo)  REPO="$2";  shift 2 ;;
      --title) title="$2"; shift 2 ;;
      *) die "init: unknown arg '$1'" ;;
    esac
  done
  [ -n "$OWNER" ] || die "init: --owner required"
  require_repo
  [ -n "$title" ] || title="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

  # 1. project: reuse one with this title (linked or not), else create
  existing="$(q project list --owner "$OWNER" -L 100 --format json | jq -r --arg t "$title" '.projects[]? | select(.title==$t) | .number' | head -1)"
  if [ -n "$existing" ]; then
    NUM="$existing"; log "reusing project '$title' (#$NUM)"
  else
    if [ "$DRY" = 1 ]; then run project create --owner "$OWNER" --title "$title" --format json; NUM="<number>"
    else
      NUM="$(gh project create --owner "$OWNER" --title "$title" --format json | jq -r '.number')" || die "project create failed"
      log "created project '$title' (#$NUM)"
    fi
  fi
  # 2. link to repo (idempotent: linking twice is a no-op)
  run project link "$NUM" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 || warn "project link failed (already linked?)"
  # 3. ensure the status field
  local has=""
  [ "$DRY" = 0 ] && has="$(q project field-list "$NUM" --owner "$OWNER" -L 100 --format json | jq -r --arg n "$FIELD_NAME" '.fields[]? | select(.name==$n) | .id' | head -1)"
  if [ -n "$has" ]; then log "field '$FIELD_NAME' present"
  else run project field-create "$NUM" --owner "$OWNER" --name "$FIELD_NAME" --data-type SINGLE_SELECT \
         --single-select-options "$(printf '%s' "$STATUSES" | tr ' ' ',')" --format json >/dev/null || warn "field-create failed"
  fi
  # 4. ensure the label
  run label create "$LABEL" --repo "$REPO" --description "ps-spec epic (mirrors EPICS.md)" --color 5319E7 --force >/dev/null 2>&1 || warn "label create failed"
  echo
  echo "Add this line to the $EPICS header (next to Reviewed:):"
  echo "GitHub-Project: $OWNER/$NUM"
}

cmd_sync_epics() {
  [ $# -ge 1 ] && EPICS="$1"
  [ -f "$EPICS" ] || die "$EPICS not found"
  require_project; require_repo; load_project_ids || { [ "$DRY" = 1 ] || exit 0; }
  run label create "$LABEL" --repo "$REPO" --force >/dev/null 2>&1 || true
  local n=0
  while IFS=$'\t' read -r id title change st; do
    [ -n "$id" ] || continue; n=$((n+1))
    local found num url body
    found="$(find_issue "$id")"
    if [ -z "$found" ] && [ "$DRY" = 0 ]; then
      body="$(mktemp)"; { epic_section "$id"; printf '\n\n---\n_Mirrored from EPICS.md by ps-spec. Change: `%s`. Edit EPICS.md, not this issue._\n' "$change"; } > "$body"
      url="$(gh issue create --repo "$REPO" --title "$id: $title" --label "$LABEL" --body-file "$body" 2>/dev/null)"; rm -f "$body"
      [ -n "$url" ] && log "$id: created issue $url" || { warn "$id: issue create failed"; continue; }
    elif [ -z "$found" ]; then
      run issue create --repo "$REPO" --title "$id: $title" --label "$LABEL" --body-file "<section of $id>"
    else
      log "$id: issue exists (#${found%%	*})"
    fi
    [ -n "$st" ] && set_item_status "$id" "$st" || true
  done < <(board_rows)
  log "synced $n epic(s) from $EPICS to project $OWNER/$NUM"
}

cmd_set_status() {
  [ $# -ge 2 ] || die "usage: set-status <E0N> <status> [EPICS.md]"
  local id="$1" st="$2"; [ $# -ge 3 ] && EPICS="$3"
  [[ "$id" =~ ^E[0-9]+$ ]] || die "bad epic id '$id'"
  require_project; require_repo; load_project_ids || { [ "$DRY" = 1 ] || exit 0; }
  set_item_status "$id" "$st" || true
}

cmd_status() {
  [ $# -ge 1 ] && EPICS="$1"
  require_project
  if [ "$DRY" = 1 ]; then q project item-list "$NUM" --owner "$OWNER" -L 500 --format json >/dev/null; return 0; fi
  echo "project: $OWNER/$NUM  ($(gh project view "$NUM" --owner "$OWNER" --format json 2>/dev/null | jq -r '.url // "?"'))"
  q project item-list "$NUM" --owner "$OWNER" -L 500 --format json \
    | jq -r '.items[]? | "  \(.content.number // "-")\t\(.["epic status"] // .["Epic Status"] // "-")\t\(.title // .content.title // "?")"' \
    | sort -t$'\t' -k3 | column -t -s$'\t' 2>/dev/null || true
}

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    init|sync-epics|set-status|status) check_prereqs ;;
  esac
  case "$cmd" in
    init)        cmd_init "$@" ;;
    sync-epics)  cmd_sync_epics "$@" ;;
    set-status)  cmd_set_status "$@" ;;
    status)      cmd_status "$@" ;;
    help|-h|--help) usage ;;
    *) die "unknown command '$cmd' (init | sync-epics | set-status | status)" ;;
  esac
  [ "$WARNED" = 1 ] && log "finished with warnings (mirror only; EPICS.md is authoritative)"
  exit 0
}
main "$@"
