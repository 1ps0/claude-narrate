# narrate

Speak what Claude Code just did, through the `say` that ships with macOS.
Every tool call, every failure, the first line of every reply. No cloud, no
API keys, nothing leaves the machine.

Built for following an agent by ear while looking elsewhere — the intent
line of each command is what gets spoken, not the command.

## Install

```
/plugin marketplace add alexevers/claude-narrate
/plugin install narrate@claude-narrate
```

Needs `jq` (`brew install jq`). Works on macOS only; Linux would swap `say`
for `spd-say` (one line in `hooks/narrate.sh`, untested).

## What it says

| Event | Spoken |
|---|---|
| Bash | the tool call's `description` — the one-line intent Claude writes for every command |
| Edit / Write / Read | `edited guard.rs` |
| Grep / Glob | `searched` |
| Agent | `spawned <description>` |
| a tool failure | `Bash failed: <first 80 chars of the error>` |
| Stop | first line of the reply, up to 200 chars, markdown stripped |

Utterances are serialized; one that has waited more than 3 seconds is
dropped as stale rather than spoken late.

## Off switch, tuning, audit

- Off for a project: `touch .claude/narrate.off`. Off for a shell: `CLAUDE_NARRATE=0`.
- Voice and speed: `NARRATE_VOICE=Daniel NARRATE_RATE=150` (`say -v '?'` lists voices).
- Every utterance is appended to `.claude/narrate.log` in the project, so
  what was said is always checkable against what happened.
- `NARRATE_DRY=1` prints instead of speaking, for testing.

## Test it without a session

```
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"description":"Run the tests"}}' \
  | NARRATE_DRY=1 hooks/narrate.sh
# [dry] Run the tests
```

MIT.
