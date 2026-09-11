#!/bin/bash
# narrate — speak what Claude Code just did, through macOS `say`.
#
# As a hook: reads one event as JSON on stdin (PostToolUse, PostToolUseFailure,
# Stop, MessageDisplay, PreToolUse). As a CLI: narrate.sh <pause|resume|mute|status|set KEY VALUE>.
#
# Config, re-read on every event so edits take effect immediately:
#   ~/.config/claude-narrate/config   then   <project>/.claude/narrate.conf   (project wins)
#   VOICE=Samantha RATE=165 VOLUME=      (VOLUME 0.0–1.0; empty = system volume, no afplay hop)
#   VERBOSITY=1   0 failures + final reply · 1 + edits, writes, lead-ins, commands · 2 + reads, searches
#   MAX_WAIT=3    seconds an utterance may queue behind another before it is dropped as stale; 0 = never queue
#   MAX_CHARS=200
# Pause: `narrate.sh pause` (global) or `touch .claude/narrate.off` (project) or CLAUDE_NARRATE=0.
# Audit: every utterance → <project>/.claude/narrate.log
set -u
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cfgdir="$HOME/.config/claude-narrate"

VOICE=Samantha RATE=165 VOLUME="" VERBOSITY=1 MAX_WAIT=3 MAX_CHARS=200
load_cfg() {
  for f in "$cfgdir/config" "$root/.claude/narrate.conf"; do
    [ -r "$f" ] && while IFS='=' read -r k v; do
      case "$k" in VOICE|RATE|VOLUME|VERBOSITY|MAX_WAIT|MAX_CHARS) printf -v "$k" '%s' "${v//\"/}";; esac
    done < "$f"
  done
  : "${NARRATE_VOICE:=$VOICE}" "${NARRATE_RATE:=$RATE}"   # env still overrides
}
load_cfg

# ── CLI ───────────────────────────────────────────────────────────────────
case "${1:-}" in
  pause)  mkdir -p "$cfgdir"; : > "$cfgdir/paused"; echo "narrate: paused"; exit 0;;
  resume) rm -f "$cfgdir/paused"; echo "narrate: resumed"; exit 0;;
  mute)   pkill -x say 2>/dev/null; rm -rf /tmp/claude-narrate.lock; echo "narrate: cut current speech"; exit 0;;
  status) echo "paused: $([ -e "$cfgdir/paused" ] && echo yes || echo no) · project off: $([ -e "$root/.claude/narrate.off" ] && echo yes || echo no)"
          echo "voice=$NARRATE_VOICE rate=$NARRATE_RATE volume=${VOLUME:-system} verbosity=$VERBOSITY max_wait=${MAX_WAIT}s max_chars=$MAX_CHARS"
          echo "config: $cfgdir/config · $root/.claude/narrate.conf"; exit 0;;
  set)    [ $# -eq 3 ] || { echo "usage: narrate.sh set KEY VALUE"; exit 2; }
          mkdir -p "$cfgdir"; touch "$cfgdir/config"
          grep -v "^$2=" "$cfgdir/config" > "$cfgdir/config.tmp" || true; echo "$2=$3" >> "$cfgdir/config.tmp"; mv "$cfgdir/config.tmp" "$cfgdir/config"
          echo "narrate: $2=$3"; exit 0;;
  "") ;;
  *) echo "usage: narrate.sh [pause|resume|mute|status|set KEY VALUE]"; exit 2;;
esac

# ── hook ──────────────────────────────────────────────────────────────────
[ "${CLAUDE_NARRATE:-1}" = "0" ] && exit 0
[ -e "$cfgdir/paused" ] && exit 0
[ -e "$root/.claude/narrate.off" ] && exit 0

in=$(cat)
ev=$(jq -r '.hook_event_name // ""' <<<"$in")
tool=$(jq -r '.tool_name // ""' <<<"$in")
base() { basename "$(jq -r "$1 // \"\"" <<<"$in")"; }
nlines() { [ -z "$1" ] && echo 0 || printf '%s\n' "$1" | wc -l | tr -d ' '; }
ident() {
  local s; s=$(cat)
  grep -m1 -oE '^#+ +.{1,40}' <<<"$s" | sed -E 's/^#+ +//' | grep . && return
  grep -m1 -oE '\b(pub fn|fn|def|class|struct|impl|enum|trait|func|function|const|let) +[A-Za-z_][A-Za-z0-9_]*' <<<"$s" | sed -E 's/^.* //'
}
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
write_shape() {
  local c t; c=$(jq -r '.tool_input.content // ""' <<<"$in")
  t=$(printf '%s\n' "$c" | grep -m1 -E '^#+ ' | sed -E 's/^#+ +//' | cut -c1-40)
  [ -n "$t" ] && printf ', titled %s' "$t" || printf ', %s lines' "$(nlines "$c")"
}
# A lead-in was spoken for this turn; the next command's description is redundant.
lead="/tmp/claude-narrate.lead"

level=1
case "$ev" in
  MessageDisplay)
    # Claude's own words as they render — the lead-in before a tool call.
    [ "$(jq -r '.is_complete // false' <<<"$in")" = "true" ] || exit 0
    text=$(jq -r '.message_text // ""' <<<"$in" | grep -m1 . | cut -c1-400)
    [ -z "$text" ] && exit 0
    [ -f "$lead" ] && [ "$(cat "$lead")" = "$text" ] && exit 0
    printf '%s' "$text" > "$lead";;
  PreToolUse) exit 0;;   # lead-ins arrive via MessageDisplay; nothing to say here
  PostToolUse)
    case "$tool" in
      Bash)   [ -f "$lead" ] && { rm -f "$lead"; exit 0; }
              text=$(jq -r '.tool_input.description // ""' <<<"$in")
              [ -z "$text" ] && text="ran $(jq -r '.tool_input.command' <<<"$in" | cut -c1-60)";;
      Edit)   rm -f "$lead"; text="edited $(base .tool_input.file_path)$(edit_shape)";;
      Write)  rm -f "$lead"; text="wrote $(base .tool_input.file_path)$(write_shape)";;
      Read)   level=2; text="read $(base .tool_input.file_path)";;
      Grep|Glob) level=2; text="searched";;
      Agent)  text="spawned $(jq -r '.tool_input.description // "an agent"' <<<"$in")";;
      *)      level=2; text="$tool";;
    esac;;
  PostToolUseFailure)
    level=0; text="$tool failed: $(jq -r '.error_message // ""' <<<"$in" | cut -c1-80)";;
  Stop)
    level=0; rm -f "$lead"; text=$(jq -r '.last_assistant_message // ""' <<<"$in" | sed -n '1p');;
  *) exit 0;;
esac
[ -z "$text" ] && exit 0
[ "$level" -gt "$VERBOSITY" ] && exit 0
text=$(sed -E 's/[][`*_#]//g' <<<"$text" | cut -c1-"$MAX_CHARS")

mkdir -p "$root/.claude"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$ev" "$text" >> "$root/.claude/narrate.log"
[ "${NARRATE_DRY:-0}" = "1" ] && { echo "[dry] $text"; exit 0; }

# Serialize; an utterance that has queued longer than MAX_WAIT is stale, drop it.
lock=/tmp/claude-narrate.lock; i=0; limit=$(( ${MAX_WAIT%.*} * 10 ))
until mkdir "$lock" 2>/dev/null; do [ "$i" -ge "$limit" ] && exit 0; sleep 0.1; i=$((i+1)); done
trap 'rmdir "$lock" 2>/dev/null' EXIT
if [ -n "$VOLUME" ]; then
  f=$(mktemp /tmp/claude-narrate.XXXXXX).aiff
  say -v "$NARRATE_VOICE" -r "$NARRATE_RATE" -o "$f" "$text" && afplay -v "$VOLUME" "$f"; rm -f "$f"
else
  say -v "$NARRATE_VOICE" -r "$NARRATE_RATE" "$text"
fi
