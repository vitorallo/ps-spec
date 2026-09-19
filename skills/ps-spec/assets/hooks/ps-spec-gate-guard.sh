#!/usr/bin/env bash
# ps-spec gate guard — Claude Code PreToolUse hook for Bash.
# Blocks `openspec archive <change>` and `git merge ... epic/<change>` unless the change's
# CP4 (validate) checkpoint is recorded in openspec/changes/<change>/.ps-spec.yaml.
# Installed by ps-spec-init.sh --with-gate-hook. Reads the tool call JSON on stdin.
# Exit 2 + stderr message = block (the message is shown to Claude); exit 0 = allow.

set -u
input="$(cat)"
cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

change=""
if printf '%s' "$cmd" | grep -qE 'openspec[[:space:]]+archive[[:space:]]'; then
  change="$(printf '%s' "$cmd" | sed -nE 's/.*openspec[[:space:]]+archive[[:space:]]+([A-Za-z0-9._-]+).*/\1/p' | head -1)"
elif printf '%s' "$cmd" | grep -qE 'git[[:space:]]+merge[[:space:]].*epic/'; then
  change="$(printf '%s' "$cmd" | sed -nE 's/.*epic\/([A-Za-z0-9._-]+).*/\1/p' | head -1)"
fi
[ -z "$change" ] && exit 0
case "$change" in -*|--*) exit 0 ;; esac   # a flag was captured, not a change name

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
f="$root/openspec/changes/$change/.ps-spec.yaml"
if [ -f "$f" ] && awk '/^[[:space:]]*validate:/{f=1} f && /approved:[[:space:]]*[0-9]/{found=1} END{exit !found}' "$f"; then
  exit 0
fi
echo "ps-spec gate: CP4 (validate) is not recorded for change '$change' ($f). Present the review summary, get the user's explicit OK, record checkpoints.validate.approved, then retry." >&2
exit 2
