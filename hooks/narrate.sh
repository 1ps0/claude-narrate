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

# Nearest named thing in a snippet: a code definition or a markdown heading.
ident() {
  local s; s=$(cat)
  grep -m1 -oE '^#+ +.{1,40}' <<<"$s" | sed -E 's/^#+ +//' | grep . && return
  grep -m1 -oE '\b(pub fn|fn|def|class|struct|impl|enum|trait|func|function|const|let) +[A-Za-z_][A-Za-z0-9_]*' <<<"$s" | sed -E 's/^.* //'
}
nlines() { [ -z "$1" ] && echo 0 || printf '%s\n' "$1" | wc -l | tr -d ' '; }

# ", in observe, 3 lines became 5" — what an Edit did, from the old/new strings.
edit_shape() {
  local old new o n where shape
  old=$(jq -r '.tool_input.old_string // ""' <<<"$in"); new=$(jq -r '.tool_input.new_string // ""' <<<"$in")
  o=$(nlines "$old"); n=$(nlines "$new")
  where=$(ident <<<"$new"); [ -z "$where" ] && where=$(ident <<<"$old")
  if   [ "$o" = "$n" ]; then shape="$n line$([ "$n" != 1 ] && echo s) changed"
  elif [ "$o" -lt "$n" ]; then shape="$o became $n lines"
  else shape="$o cut to $n lines"; fi
  [ "$(jq -r '.tool_input.replace_all // false' <<<"$in")" = "true" ] && shape="$shape, everywhere"
  printf '%s%s' "${where:+, in $where}" ", $shape"
}
# ", 48 lines" or ", titled narrate" — what a Write produced.
write_shape() {
  local c t; c=$(jq -r '.tool_input.content // ""' <<<"$in")
  t=$(printf '%s\n' "$c" | grep -m1 -E '^#+ ' | sed -E 's/^#+ +//' | cut -c1-40)
  [ -n "$t" ] && printf ', titled %s' "$t" || printf ', %s lines' "$(nlines "$c")"
}

case "$ev" in
  PostToolUse)
    case "$tool" in
      Bash)   text=$(jq -r '.tool_input.description // ""' <<<"$in")
              [ -z "$text" ] && text="ran $(jq -r '.tool_input.command' <<<"$in" | cut -c1-60)";;
      Edit)   text="edited $(base .tool_input.file_path)$(edit_shape)";;
      Write)  text="wrote $(base .tool_input.file_path)$(write_shape)";;
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

mkdir -p "$root/.claude"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$ev" "$text" >> "$root/.claude/narrate.log"
[ "${NARRATE_DRY:-0}" = "1" ] && { echo "[dry] $text"; exit 0; }

# Serialize utterances; a narration that waits more than 3s is stale, drop it.
lock=/tmp/claude-narrate.lock; i=0
until mkdir "$lock" 2>/dev/null; do sleep 0.1; i=$((i+1)); [ $i -ge 30 ] && exit 0; done
say -v "${NARRATE_VOICE:-Samantha}" -r "${NARRATE_RATE:-165}" "$text"
rmdir "$lock"
