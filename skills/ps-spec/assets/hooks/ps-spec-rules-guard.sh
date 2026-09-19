#!/usr/bin/env bash
# ps-spec rules guard — Claude Code hook. Installed by ps-spec-init.sh (default; --no-rules-guard to skip).
#
# Why: no OpenSpec command writes an artifact — the model authors proposal.md, specs, design.md, tasks.md
# and test-plan.md itself. The only step that carries the project's `rules:` and `context:` from
# openspec/config.yaml (coding and security rules included) to the model is
# `openspec instructions <artifact> --change <change>`. Skip it and the rules exist but are never read.
#
# What: one script, three hook events (it branches on hook_event_name / tool_name):
#   PostToolUse Bash              — records that instructions for <change>/<artifact> were fetched
#                                   (marker per session, so a new session must fetch them again).
#   PreToolUse Write|Edit|MultiEdit — if the target is a change artifact and no marker exists: runs
#                                   `openspec instructions` itself, prints the result on stderr (shown to
#                                   Claude), sets the marker and exits 2. The write is blocked ONCE; the
#                                   retry, now with the rules in context, passes.
#   PreToolUse Bash               — blocks shell writes into change artifacts (`> file`, `tee`, `cp`, `mv`,
#                                   `sed -i`) so the guard cannot be bypassed via the shell.
# Exit 2 + stderr = block; exit 0 = allow. Never blocks anything outside openspec/changes/<change>/.

set -u
input="$(cat)"
eval "$(printf '%s' "$input" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
ti = d.get("tool_input") or {}
files = []
if isinstance(ti.get("file_path"), str): files.append(ti["file_path"])
for e in ti.get("edits") or []:
    if isinstance(e, dict) and isinstance(e.get("file_path"), str): files.append(e["file_path"])
print("EVENT=%s" % shlex.quote(d.get("hook_event_name", "")))
print("TOOL=%s" % shlex.quote(d.get("tool_name", "")))
print("SESSION=%s" % shlex.quote(d.get("session_id", "") or "default"))
print("CMD=%s" % shlex.quote(ti.get("command", "") if isinstance(ti.get("command"), str) else ""))
print("FILES=%s" % shlex.quote("\n".join(files)))
' 2>/dev/null)" || exit 0

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[ -d "$root/openspec" ] || exit 0
markers="${TMPDIR:-/tmp}/ps-spec-rules/$SESSION"
mkdir -p "$markers" 2>/dev/null || exit 0

# artifact id for a path inside openspec/changes/<change>/ (archive excluded); prints "<change> <artifact>"
artifact_of() {
  local p="$1" rel
  case "$p" in /*) rel="${p#"$root"/}" ;; *) rel="$p" ;; esac
  rel="${rel#./}"
  case "$rel" in openspec/changes/archive/*) return 1 ;; openspec/changes/*/*) ;; *) return 1 ;; esac
  local change="${rel#openspec/changes/}"; change="${change%%/*}"
  local file="${rel#openspec/changes/"$change"/}"
  case "$file" in
    proposal.md)  echo "$change proposal" ;;
    design.md)    echo "$change design" ;;
    tasks.md)     echo "$change tasks" ;;
    test-plan.md) echo "$change test-plan" ;;
    specs/*.md)   echo "$change specs" ;;
    *) return 1 ;;
  esac
}

# ---- PostToolUse Bash: remember fetched instructions --------------------------------------------
if [ "$EVENT" = "PostToolUse" ] && [ "$TOOL" = "Bash" ]; then
  printf '%s' "$CMD" | grep -oE 'openspec[[:space:]]+instructions[[:space:]]+[a-z-]+[^;&|]*--change[= ][[:space:]]*"?[A-Za-z0-9._-]+' |
  while read -r one; do
    art="$(printf '%s' "$one" | sed -nE 's/.*instructions[[:space:]]+([a-z-]+).*/\1/p')"
    chg="$(printf '%s' "$one" | sed -nE 's/.*--change[= ][[:space:]]*"?([A-Za-z0-9._-]+).*/\1/p')"
    [ -n "$art" ] && [ -n "$chg" ] && : > "$markers/${chg}__${art}"
  done
  exit 0
fi

[ "$EVENT" = "PreToolUse" ] || exit 0

# ---- PreToolUse Bash: no shell writes into artifacts -----------------------------------------------
if [ "$TOOL" = "Bash" ]; then
  [ -n "$CMD" ] || exit 0
  printf '%s' "$CMD" | grep -qE 'openspec/changes/' || exit 0
  if printf '%s' "$CMD" | grep -qE '(>>?[[:space:]]*|\btee[[:space:]]+(-a[[:space:]]+)?|\b(cp|mv)[[:space:]]+[^;&|]*[[:space:]]|\bsed[[:space:]]+-i[^;&|]*[[:space:]])"?[^[:space:]"]*openspec/changes/[^[:space:]"]+\.md'; then
    echo "ps-spec rules guard: don't write change artifacts from the shell. Use the Write/Edit tool so the guard can check that 'openspec instructions <artifact> --change <change>' (config.yaml rules + context) was fetched first." >&2
    exit 2
  fi
  exit 0
fi

# ---- PreToolUse Write/Edit/MultiEdit: instructions fetched this session? ---------------------------
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
[ -n "$FILES" ] || exit 0
while read -r f; do
  [ -n "$f" ] || continue
  pair="$(artifact_of "$f")" || continue
  chg="${pair% *}"; art="${pair#* }"
  [ -f "$markers/${chg}__${art}" ] && continue
  out="$(cd "$root" && openspec instructions "$art" --change "$chg" 2>&1)"; rc=$?
  if [ $rc -ne 0 ]; then
    echo "ps-spec rules guard: '$f' is the '$art' artifact of change '$chg', but 'openspec instructions $art --change $chg' failed (rc=$rc). Create the change with 'openspec new change $chg' first, then fetch the instructions, then write." >&2
    printf '%s\n' "$out" | tail -20 >&2
    exit 2
  fi
  : > "$markers/${chg}__${art}"
  {
    echo "ps-spec rules guard: you are writing the '$art' artifact of change '$chg' without having fetched its instructions in this session."
    echo "They carry the project's config.yaml rules and context — including any security or coding rules — and the template to follow. Read them, then retry the write applying them (never copy <rules>/<project_context> into the file):"
    echo
    printf '%s\n' "$out"
  } >&2
  exit 2
done <<< "$FILES"
exit 0
