# narrate

Speak what Claude Code just did, through the `say` that ships with macOS.
Every tool call, every failure, the first line of every reply. No cloud, no
API keys, nothing leaves the machine.

Built for following an agent by ear while looking elsewhere — the intent
line of each command is what gets spoken, not the command.

## Install

```
/plugin marketplace add 1ps0/claude-narrate
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
| MessageDisplay | Claude's own lead-in sentence as it renders ("Fixing the strip bug, then firing the hook") — after one, the next command's description is skipped as redundant |

Utterances are serialized; one that has waited more than 3 seconds is
dropped as stale rather than spoken late.

## Control it live

`/narrate status` · `/narrate pause` · `/narrate resume` · `/narrate mute` (cuts
the current sentence) · `/narrate set RATE 150`. Same verbs from a shell:
`hooks/narrate.sh pause`.

Config is re-read on every event, so edits apply to the next utterance:

```
~/.config/claude-narrate/config      # global
<project>/.claude/narrate.conf       # per project, wins
```

| Key | Default | Meaning |
|---|---|---|
| `VOICE` | Samantha | `say -v '?'` lists them |
| `RATE` | 165 | words per minute |
| `VOLUME` | (system) | 0.0–1.0; when set, audio goes through `afplay -v` instead of the system level |
| `VERBOSITY` | 1 | 0 = failures and the final reply · 1 = + edits, writes, commands, lead-ins · 2 = + reads and searches |
| `MAX_WAIT` | 3 | seconds an utterance may queue behind another before it is dropped as stale; 0 = never queue |
| `MAX_CHARS` | 200 | cap per utterance |

Off for a project: `touch .claude/narrate.off`. Off for a shell: `CLAUDE_NARRATE=0`.
Every utterance is appended to `.claude/narrate.log`, so what was said is
always checkable against what happened. `NARRATE_DRY=1` prints instead of speaking.

## Test it without a session

```
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"description":"Run the tests"}}' \
  | NARRATE_DRY=1 hooks/narrate.sh
# [dry] Run the tests
```

MIT.
