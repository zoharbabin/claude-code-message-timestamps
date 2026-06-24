# ⏱ Message Timestamps for Claude Code

**See the time on every message in Claude Code — and let Claude know it too.**

![Demo: timestamps on each message, and Claude answering how long a task took](assets/demo.gif)

<sub>Illustration of the plugin in action — each reply is prefixed with the local time, and Claude can reason about elapsed time.</sub>

```
[09:12:54] Here's the plan: I'll start by …
```

Claude Code doesn't show *when* anything happened. Long sessions blur together: you
can't tell how long a build took, when you asked something, or point a teammate to
"the part around 09:15." This plugin fixes that in two ways, and installs in 15 seconds.

## Why this exists

Timestamps are one of the most-requested missing features in Claude Code. At least
**11 issues** ask for some form of it:

[#2441](https://github.com/anthropics/claude-code/issues/2441) · [#60711](https://github.com/anthropics/claude-code/issues/60711) · [#44763](https://github.com/anthropics/claude-code/issues/44763) · [#30745](https://github.com/anthropics/claude-code/issues/30745) · [#21051](https://github.com/anthropics/claude-code/issues/21051) · [#63488](https://github.com/anthropics/claude-code/issues/63488) · [#61672](https://github.com/anthropics/claude-code/issues/61672) · [#52944](https://github.com/anthropics/claude-code/issues/52944) · [#56855](https://github.com/anthropics/claude-code/issues/56855) · [#49084](https://github.com/anthropics/claude-code/issues/49084) · [#60492](https://github.com/anthropics/claude-code/issues/60492)

This plugin is a working solution today, while we wait to see if it ships natively.

---

## Why you want this (the 10-second version)

| Without it | With it |
| --- | --- |
| "How long did that step take?" — no idea | Read it off the timestamps |
| "When did I ask that?" — scroll and guess | It's right there on the message |
| "Look at the part around 9am" — good luck | Every message is time-labeled |
| Claude has no sense of elapsed time | Claude knows when each prompt was sent and can reason about it |

No tracking, no telemetry, no account, no network calls. It just reads your computer's
clock. Runs in a few milliseconds per message.

---

## Install (copy, paste, done)

In Claude Code, run these two lines:

```
/plugin marketplace add zoharbabin/claude-code-message-timestamps
/plugin install message-timestamps@zoharbabin-claude-tools
```

Restart Claude Code. That's it — timestamps now appear on every message, in every
project. ✅

> Prefer the terminal? `claude plugin marketplace add zoharbabin/claude-code-message-timestamps`
> then `claude plugin install message-timestamps@zoharbabin-claude-tools`.

To remove it: `/plugin uninstall message-timestamps@zoharbabin-claude-tools`.

### Requirements

- **Claude Code 2.1.152 or newer** — that version added the `MessageDisplay` hook
  used for the on-screen timestamps. (Older versions still get the "Claude knows the
  time" half.)
- **[`jq`](https://jqlang.github.io/jq/)** on your `PATH`:
  - macOS: `brew install jq`
  - Linux: `sudo apt-get install jq` / `sudo dnf install jq`
  - Windows: `winget install jqlang.jq` or `choco install jq`
- **Windows only:** the hooks are bash scripts, so you need **Git Bash** (bundled with
  [Git for Windows](https://gitforwindows.org/)). Claude Code runs `command` hooks via
  Git Bash automatically when it's installed.

If `jq` is missing the plugin **fails safe** — it adds no timestamp rather than breaking
anything, so you never lose a message. It also shows a one-time message at session start
telling you exactly how to install `jq`. Install it, restart, and timestamps light up.

---

## Platform support — what to expect on each OS

The hooks are small Bash scripts that call `date` (for local time) and `jq` (to build
JSON safely). Claude Code runs `command` hooks through a shell: `sh -c` on macOS/Linux,
and **Git Bash** on Windows (falling back to PowerShell if Git Bash isn't installed).
Here's exactly how that plays out:

| | **macOS** | **Linux** | **Windows** |
| --- | --- | --- | --- |
| Shell used for hooks | `sh` / system bash | `sh` / system bash | **Git Bash** (auto-detected) |
| `date` (local time) | built in | built in | provided by Git Bash |
| `jq` | `brew install jq` | `apt`/`dnf install jq` | `winget`/`choco install jq` |
| On-screen `[HH:MM:SS]` | ✅ (Claude Code 2.1.152+) | ✅ (2.1.152+) | ✅ (2.1.152+, with Git Bash) |
| Claude knows the time | ✅ | ✅ | ✅ (with Git Bash) |
| If Git Bash is absent | n/a | n/a | scripts can't run — install Git Bash |
| If `jq` is absent | one-time notice, no timestamps | one-time notice, no timestamps | one-time notice, no timestamps |

**Why it works without fuss:**

- **No executable-bit dependency.** The hooks are invoked as `bash <script>` (Claude
  Code's "exec form"), so they run even when a clone, a ZIP download, or
  `git config core.fileMode=false` drops the `+x` permission — common on Windows.
- **Local time, not UTC.** Time comes from your shell's `date`, so it matches your wall
  clock. (The scripts deliberately avoid `jq`'s `now | strftime`, which is UTC-only.)
- **Graceful, explained degradation.** Missing `jq` never breaks a message or errors the
  session; you get a one-time `SessionStart` notice with the exact install command for
  your OS, and normal output continues untouched.

**Windows, specifically:** install [Git for Windows](https://gitforwindows.org/) (this
provides Git Bash, `bash`, and `date`) plus `jq`. Claude Code then routes the hooks
through Git Bash automatically — no extra configuration. Native `cmd.exe`/PowerShell
without Git Bash is **not** supported, because the hooks are Bash scripts.

> **WSL / dev containers / SSH remotes:** these are Linux environments, so they behave
> exactly like the Linux column — just make sure `jq` is installed *inside* that
> environment, not only on the host.

---

## What you'll see

Each assistant reply is prefixed with the local time, once per message:

```
[09:12:54] Sure — here's how that works …
[09:13:48] Done. Tests pass.
```

The gap between two stamps tells you how long the work in between took.

---

## How it works

Three small [hooks](https://docs.claude.com/en/docs/claude-code/hooks), each on a
different Claude Code event:

1. **You see the time** (`MessageDisplay`) — prepends `[HH:MM:SS]` to each assistant
   message *on screen only*. It never touches the transcript or what Claude reads, so it
   can't confuse the model. It stamps just the first chunk of each streamed message, so
   you get exactly one timestamp per reply.

2. **Claude knows the time** (`UserPromptSubmit`) — adds `Message sent at local time
   09:12:54 EDT` to Claude's context when you send a prompt. Claude Code wraps this in a
   `<system-reminder>`, which the model is trained to treat as background metadata —
   *not* as text you typed. So Claude can answer "how long ago did I ask that?" without
   ever echoing or fixating on the clock.

3. **It tells you if something's missing** (`SessionStart`) — runs once when a session
   starts and, only if `jq` isn't installed, shows a one-time notice with the install
   command for your OS. When everything's present it stays silent.

This split is deliberate: the visible marker stays out of the model's context (zero
risk of confusion), and the model's time-awareness stays out of your view (zero visual
clutter). Both halves use a tiny, fixed token footprint and your machine's local
timezone.

### Files

```
claude-code-message-timestamps/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # lets you install straight from this repo
├── hooks/
│   ├── hooks.json           # wires up the three hooks
│   └── scripts/
│       ├── timestamp-context.sh   # UserPromptSubmit → tells Claude the time
│       ├── timestamp-display.sh   # MessageDisplay → shows you the time
│       └── dependency-check.sh    # SessionStart → warns once if jq is missing
└── README.md
```

---

## Configuration

Every part of the format is controlled by optional environment variables. Unset
means the defaults below — so doing nothing keeps the original behavior (with one
exception: the on-screen separator defaults to a newline, putting the marker on
its own line above each reply).

| Variable | Default | Controls |
| --- | --- | --- |
| `CLAUDE_TIMESTAMPS_DISPLAY_FORMAT` | `[%H:%M:%S]` | `date` format for the on-screen marker. The `[ ]` are part of the format string — change or drop them freely. |
| `CLAUDE_TIMESTAMPS_SEPARATOR` | newline | What goes between the marker and the message. Escapes like `\n` and `\t` are interpreted, so you can set them in JSON. |
| `CLAUDE_TIMESTAMPS_CONTEXT_FORMAT` | `%H:%M:%S %Z` | `date` format for the time injected into Claude's context. |
| `CLAUDE_TIMESTAMPS_CONTEXT_PREFIX` | `Message sent at local time ` | Wording placed before that time. |
| `CLAUDE_TIMESTAMPS_INJECT_CONTEXT` | `true` | Set to `false` for display-only mode (no time in Claude's context). |

All five use the standard [`date`](https://man7.org/linux/man-pages/man1/date.1.html)
format string. A few examples:

- **Marker on its own line (default):** leave `CLAUDE_TIMESTAMPS_SEPARATOR` unset.
- **Marker inline with the reply:** `CLAUDE_TIMESTAMPS_SEPARATOR=" "`.
- **Add the date:** `CLAUDE_TIMESTAMPS_DISPLAY_FORMAT="[%Y-%m-%d %H:%M:%S]"`.
- **12-hour clock:** `CLAUDE_TIMESTAMPS_DISPLAY_FORMAT="[%I:%M:%S %p]"`.
- **Shorter wording for Claude:** `CLAUDE_TIMESTAMPS_CONTEXT_PREFIX="time: "`.

### Setting them in `settings.json`

Put them in the `env` block of `~/.claude/settings.json` so they apply to every
session:

```json
{
  "env": {
    "CLAUDE_TIMESTAMPS_SEPARATOR": "\n",
    "CLAUDE_TIMESTAMPS_DISPLAY_FORMAT": "[%H:%M:%S]",
    "CLAUDE_TIMESTAMPS_CONTEXT_PREFIX": "Sent at "
  }
}
```

(You can also export them from your shell profile — `.bashrc`, `.zshrc`, etc.)

> **Note on timezones:** the scripts use the shell's `date` command, which respects
> your local timezone. They intentionally avoid `jq`'s `now | strftime`, which renders
> in **UTC** and would show the wrong time.

---

## Prefer not to install a plugin?

The `MessageDisplay` and `UserPromptSubmit` events are delivered to plain
`settings.json` hooks too — you don't need the plugin wrapper. Copy
`hooks/scripts/` somewhere stable (say `~/.claude/scripts/`) and register them in
`~/.claude/settings.json`. The same `CLAUDE_TIMESTAMPS_*` env vars apply:

```json
{
  "env": {
    "CLAUDE_TIMESTAMPS_SEPARATOR": "\n"
  },
  "hooks": {
    "MessageDisplay": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/scripts/timestamp-display.sh", "timeout": 10 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/scripts/timestamp-context.sh", "timeout": 5 } ] }
    ]
  }
}
```

The plugin is just a cleaner, updatable, no-clobber way to do the same thing — and
it won't overwrite hooks you already have.

---

## FAQ

**Does this send my data anywhere?** No. It reads your local clock and nothing else.

**Will it slow Claude Code down?** No — each hook runs in a few milliseconds.

**Can I timestamp my *own* messages on screen too?** Not currently — Claude Code's
`MessageDisplay` hook only renders assistant messages. Your send-times still reach
Claude via the other hook, so the elapsed-time math is intact.

**Does it work in every project?** Yes, once installed it's global across all
projects and sessions.

---

## License

[MIT](LICENSE) © Zohar Babin
