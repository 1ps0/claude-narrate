#!/bin/bash
# Narrate one Claude Code hook event through macOS `say`.
# stdin: hook JSON. Off switch: CLAUDE_NARRATE=0 or .claude/narrate.off.
# Audit: every utterance appended to .claude/narrate.log.
set -u
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ "${CLAUDE_NARRATE:-1}" = "0" ] && exit 0
[ -e "$root/.claude/narrate.off" ] && exit 0

in=$(cat)
ev=$(jq -r '.hook_event_name // ""' <<<"$in")
tool=$(jq -r '.tool_name // ""' <<<"$in")
base() { basename "$(jq -r "$1 // \"\"" <<<"$in")"; }

case "$ev" in
  PostToolUse)
    case "$tool" in
      Bash)   text=$(jq -r '.tool_input.description // ""' <<<"$in")
              [ -z "$text" ] && text="ran $(jq -r '.tool_input.command' <<<"$in" | cut -c1-60)";;
      Edit)   text="edited $(base .tool_input.file_path)";;
      Write)  text="wrote $(base .tool_input.file_path)";;
      Read)   text="read $(base .tool_input.file_path)";;
      Grep|Glob) text="searched";;
      Agent)  text="spawned $(jq -r '.tool_input.description // "an agent"' <<<"$in")";;
      *)      text="$tool";;
    esac;;
  PostToolUseFailure)
    text="$tool failed: $(jq -r '.error_message // ""' <<<"$in" | cut -c1-80)";;
  Stop)
    text=$(jq -r '.last_assistant_message // ""' <<<"$in" | sed -n '1p' | cut -c1-200);;
  *) exit 0;;
esac
[ -z "$text" ] && exit 0
text=$(sed -E 's/[][`*_#]//g' <<<"$text")

printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$ev" "$text" >> "$root/.claude/narrate.log"
[ "${NARRATE_DRY:-0}" = "1" ] && { echo "[dry] $text"; exit 0; }

# Serialize utterances; a narration that waits more than 3s is stale, drop it.
lock=/tmp/claude-narrate.lock; i=0
until mkdir "$lock" 2>/dev/null; do sleep 0.1; i=$((i+1)); [ $i -ge 30 ] && exit 0; done
say -v "${NARRATE_VOICE:-Samantha}" -r "${NARRATE_RATE:-165}" "$text"
rmdir "$lock"
