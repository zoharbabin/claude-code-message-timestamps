# Configurable Timestamp Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the three timestamp hook scripts format-configurable via `CLAUDE_TIMESTAMPS_*` environment variables, defaulting to current behavior except a newline display separator.

**Architecture:** Pure-bash hook scripts read optional env vars with shell parameter defaults; no new dependencies. A dependency-free `test/run.sh` harness pipes JSON into each script and asserts output structure. README documents the config surface and a non-plugin (plain `settings.json`) setup path.

**Tech Stack:** Bash, `jq` 1.7, `date` (local TZ), Claude Code hooks (`MessageDisplay`, `UserPromptSubmit`).

## Global Constraints

- Env var prefix is `CLAUDE_TIMESTAMPS_` (matches existing `CLAUDE_TIMESTAMPS_INJECT_CONTEXT`).
- Defaults reproduce current output EXCEPT display separator defaults to a newline (`\n`).
- No new runtime dependencies — `bash`, `date`, `jq` only.
- Preserve `set -euo pipefail`, the `jq`-missing fail-safe (emit nothing, exit 0), and `index == 0` gating in the display hook.
- Scripts invoked as `bash <script>` — no executable-bit dependency.
- Local time via `date` only; never `jq`'s `now | strftime` (UTC).
- Config vars and their defaults:
  - `CLAUDE_TIMESTAMPS_DISPLAY_FORMAT` → `[%H:%M:%S]`
  - `CLAUDE_TIMESTAMPS_SEPARATOR` → newline (`\n`); interpreted via `printf '%b'`; a *set-but-empty* value is honored
  - `CLAUDE_TIMESTAMPS_CONTEXT_FORMAT` → `%H:%M:%S %Z`
  - `CLAUDE_TIMESTAMPS_CONTEXT_PREFIX` → `Message sent at local time ` (trailing space)
  - `CLAUDE_TIMESTAMPS_INJECT_CONTEXT` → `true` (existing; unchanged)

## File Structure

- `hooks/scripts/timestamp-display.sh` — modify: read display format + separator from env.
- `hooks/scripts/timestamp-context.sh` — modify: read context format + prefix from env.
- `test/run.sh` — create: dependency-free assertion harness for both scripts.
- `README.md` — modify: replace the "Customize" section with a "Configuration" section + env table; expand "Prefer not to install a plugin?" with a concrete plain-hooks example.
- `.claude-plugin/plugin.json` — modify: version bump.

---

### Task 1: Configurable display hook + test harness

**Files:**
- Create: `test/run.sh`
- Modify: `hooks/scripts/timestamp-display.sh`
- Test: `test/run.sh`

**Interfaces:**
- Consumes: nothing (entry task).
- Produces:
  - `test/run.sh` — runnable as `bash test/run.sh`; defines shell helpers `check NAME EXPECTED ACTUAL` (exact match) and `matches NAME REGEX ACTUAL` (bash `[[ =~ ]]`); increments `pass`/`fail`; final line `"<p> passed, <f> failed"`; exits nonzero if any fail. Later tasks append assertions to this file.
  - `hooks/scripts/timestamp-display.sh` — `MessageDisplay` hook. On stdin JSON with `.index` and `.delta`. For `.index == 0` emits `displayContent = <marker><sep><delta>` where `marker = date "+$CLAUDE_TIMESTAMPS_DISPLAY_FORMAT"` (default `[%H:%M:%S]`) and `sep` = `printf '%b'` of `CLAUDE_TIMESTAMPS_SEPARATOR` (default real newline; honors set-but-empty). Otherwise `displayContent = .delta`.

> **Field-name confirmation:** the `.index`/`.delta` payload shape is the contract shipped by upstream 1.2.0's working `timestamp-display.sh` and is what's running in this very session. Treat it as confirmed; do not change field names.

- [ ] **Step 1: Write the failing test harness with display assertions**

Create `test/run.sh`:

```bash
#!/usr/bin/env bash
# Dependency-free test harness for the message-timestamps hook scripts.
# Run: bash test/run.sh   (needs bash + jq; exercises a no-jq path via PATH="")
set -uo pipefail
cd "$(dirname "$0")/.."
SCRIPTS="hooks/scripts"
pass=0; fail=0
nl=$'\n'

# check NAME EXPECTED ACTUAL  — exact string match
check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass+1)); printf 'ok   - %s\n' "$1"
  else
    fail=$((fail+1)); printf 'FAIL - %s\n      expected: %q\n      actual:   %q\n' "$1" "$2" "$3"
  fi
}

# matches NAME REGEX ACTUAL  — bash ERE match
matches() {
  if [[ "$3" =~ $2 ]]; then
    pass=$((pass+1)); printf 'ok   - %s\n' "$1"
  else
    fail=$((fail+1)); printf 'FAIL - %s\n      regex:  %s\n      actual: %q\n' "$1" "$2" "$3"
  fi
}

dc() { jq -r '.hookSpecificOutput.displayContent'; }  # extract displayContent

# --- display: defaults (marker + newline separator) ---
out="$(printf '{"index":0,"delta":"hello"}' | bash "$SCRIPTS/timestamp-display.sh" | dc)"
matches "display default = [HH:MM:SS] + newline + delta" \
  "^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]${nl}hello$" "$out"

# --- display: index != 0 passes delta through untouched ---
out="$(printf '{"index":1,"delta":"world"}' | bash "$SCRIPTS/timestamp-display.sh" | dc)"
check "display index!=0 passthrough" "world" "$out"

# --- display: custom format + space separator ---
out="$(printf '{"index":0,"delta":"hi"}' | \
  CLAUDE_TIMESTAMPS_DISPLAY_FORMAT="<%H>" CLAUDE_TIMESTAMPS_SEPARATOR=" " \
  bash "$SCRIPTS/timestamp-display.sh" | dc)"
matches "display custom format + space sep" "^<[0-9][0-9]> hi$" "$out"

# --- display: literal '\n' separator is interpreted as a real newline ---
out="$(printf '{"index":0,"delta":"hi"}' | \
  CLAUDE_TIMESTAMPS_SEPARATOR='\n' bash "$SCRIPTS/timestamp-display.sh" | dc)"
matches "display backslash-n sep -> newline" \
  "^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]${nl}hi$" "$out"

# --- display: fail-safe when jq is absent (emit nothing) ---
out="$(printf '{"index":0,"delta":"hi"}' | PATH="" bash "$SCRIPTS/timestamp-display.sh")"
check "display fail-safe no-jq = empty" "" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the harness to verify display tests fail**

Run: `bash test/run.sh`
Expected: FAIL — the default-separator test fails because the shipped script emits `[ts] ` (space), not `[ts]\n`; e.g. `FAIL - display default = [HH:MM:SS] + newline + delta`. Exit code nonzero.

- [ ] **Step 3: Rewrite the display hook to read env config**

Replace `hooks/scripts/timestamp-display.sh` with:

```bash
#!/usr/bin/env bash
# MessageDisplay hook — user-facing, display-only.
#
# Prepends a configurable local-time marker to each assistant message on screen.
# This is purely cosmetic: MessageDisplay never changes the transcript or what
# Claude sees, so the marker cannot confuse the model.
#
# MessageDisplay fires once per streamed batch of an assistant message, with a
# zero-based `index`. We stamp only the first batch (index == 0) so the marker
# appears exactly once per message, not before every chunk.
#
# Config (env vars; unset = documented defaults):
#   CLAUDE_TIMESTAMPS_DISPLAY_FORMAT  date(1) format for the marker. Default
#                                     "[%H:%M:%S]" — brackets are part of the
#                                     format, so they can be changed or removed.
#   CLAUDE_TIMESTAMPS_SEPARATOR       text between marker and message. Default a
#                                     newline. Interpreted with printf '%b', so
#                                     "\n"/"\t" work from a settings.json env
#                                     block; a set-but-empty value is honored.
#
# Invoked as `bash <this script>` (see hooks.json), so it does not depend on the
# executable bit being preserved across clones/zips/Windows.
#
# Time is computed with `date` (local TZ). We do NOT use jq's `now|strftime`,
# which renders in UTC.
set -euo pipefail

# Fail safe: if jq is unavailable, emit nothing and exit 0. Claude Code then
# displays the original message text unchanged — never swallow assistant output.
command -v jq >/dev/null 2>&1 || exit 0

marker="$(date "+${CLAUDE_TIMESTAMPS_DISPLAY_FORMAT:-[%H:%M:%S]}")"

# Default to a real newline when unset; honor a set-but-empty separator.
if [ -n "${CLAUDE_TIMESTAMPS_SEPARATOR+set}" ]; then
  sep="$(printf '%b' "$CLAUDE_TIMESTAMPS_SEPARATOR")"
else
  sep=$'\n'
fi

jq --arg marker "$marker" --arg sep "$sep" '
  if .index == 0 then
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: ($marker + $sep + .delta)}}
  else
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: .delta}}
  end
'
```

- [ ] **Step 4: Run the harness to verify display tests pass**

Run: `bash test/run.sh`
Expected: all five display assertions `ok`; final line `5 passed, 0 failed`; exit 0.

- [ ] **Step 5: Commit**

```bash
git add test/run.sh hooks/scripts/timestamp-display.sh
git commit -m "feat: configurable display format + separator via env vars"
```

---

### Task 2: Configurable context hook

**Files:**
- Modify: `hooks/scripts/timestamp-context.sh`
- Test: `test/run.sh` (append context assertions)

**Interfaces:**
- Consumes: `test/run.sh` helpers `check`/`matches` and `pass`/`fail` counters from Task 1.
- Produces: `hooks/scripts/timestamp-context.sh` — `UserPromptSubmit` hook emitting `additionalContext = <prefix><time>` where `prefix = CLAUDE_TIMESTAMPS_CONTEXT_PREFIX` (default `Message sent at local time `, honors set-but-empty) and `time = date "+$CLAUDE_TIMESTAMPS_CONTEXT_FORMAT"` (default `%H:%M:%S %Z`). Existing `CLAUDE_TIMESTAMPS_INJECT_CONTEXT=false` opt-out still short-circuits with no output.

- [ ] **Step 1: Append failing context assertions to the harness**

Insert these lines into `test/run.sh` immediately before the final `printf '\n%d passed...'` summary block:

```bash
ac() { jq -r '.hookSpecificOutput.additionalContext'; }  # extract additionalContext

# --- context: defaults (prefix + HH:MM:SS TZ) ---
out="$(printf '{}' | bash "$SCRIPTS/timestamp-context.sh" | ac)"
matches "context default prefix + time" \
  "^Message sent at local time [0-9][0-9]:[0-9][0-9]:[0-9][0-9] .+$" "$out"

# --- context: custom prefix + format ---
out="$(printf '{}' | \
  CLAUDE_TIMESTAMPS_CONTEXT_PREFIX="t=" CLAUDE_TIMESTAMPS_CONTEXT_FORMAT="%H" \
  bash "$SCRIPTS/timestamp-context.sh" | ac)"
matches "context custom prefix + format" "^t=[0-9][0-9]$" "$out"

# --- context: INJECT_CONTEXT=false suppresses all output ---
out="$(printf '{}' | CLAUDE_TIMESTAMPS_INJECT_CONTEXT=false bash "$SCRIPTS/timestamp-context.sh")"
check "context inject=false = empty" "" "$out"

# --- context: fail-safe when jq is absent ---
out="$(printf '{}' | PATH="" bash "$SCRIPTS/timestamp-context.sh")"
check "context fail-safe no-jq = empty" "" "$out"
```

- [ ] **Step 2: Run the harness to verify the new context tests fail**

Run: `bash test/run.sh`
Expected: the custom prefix/format test fails (shipped script hardcodes `Message sent at local time ` + `%H:%M:%S %Z`), e.g. `FAIL - context custom prefix + format`. Exit nonzero. (The default and inject=false and no-jq context tests already pass against the current script.)

- [ ] **Step 3: Rewrite the context hook to read env config**

Replace `hooks/scripts/timestamp-context.sh` with:

```bash
#!/usr/bin/env bash
# UserPromptSubmit hook — model-facing.
#
# Gives Claude the local time each prompt was sent, wrapped by Claude Code in a
# <system-reminder> so the model treats it as passive metadata (never as part of
# the user's typed text). The system prompt already supplies today's date, so we
# send time + timezone only — no redundant date, fewer tokens.
#
# Config (env vars; unset = documented defaults):
#   CLAUDE_TIMESTAMPS_CONTEXT_FORMAT  date(1) format for the time. Default
#                                     "%H:%M:%S %Z".
#   CLAUDE_TIMESTAMPS_CONTEXT_PREFIX  prose before the time. Default
#                                     "Message sent at local time " (trailing
#                                     space); a set-but-empty value is honored.
#   CLAUDE_TIMESTAMPS_INJECT_CONTEXT  set to "false" for display-only mode
#                                     (suppress this hook entirely).
#
# Invoked as `bash <this script>` (see hooks.json), so it does not depend on the
# executable bit being preserved across clones/zips/Windows.
#
# Time is computed with `date` (local TZ). We do NOT use jq's `now|strftime`,
# which renders in UTC.
set -euo pipefail

# Fail safe: if jq is unavailable, add no context rather than erroring the prompt.
command -v jq >/dev/null 2>&1 || exit 0

# Opt out of model-facing context injection (display-only mode).
[ "${CLAUDE_TIMESTAMPS_INJECT_CONTEXT:-true}" = "false" ] && exit 0

ts="$(date "+${CLAUDE_TIMESTAMPS_CONTEXT_FORMAT:-%H:%M:%S %Z}")"
prefix="${CLAUDE_TIMESTAMPS_CONTEXT_PREFIX-Message sent at local time }"

jq -n --arg s "${prefix}${ts}" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $s}}'
```

- [ ] **Step 4: Run the harness to verify all tests pass**

Run: `bash test/run.sh`
Expected: all nine assertions `ok`; final line `9 passed, 0 failed`; exit 0.

- [ ] **Step 5: Commit**

```bash
git add test/run.sh hooks/scripts/timestamp-context.sh
git commit -m "feat: configurable context format + prefix via env vars"
```

---

### Task 3: Document configuration + non-plugin path + version bump

**Files:**
- Modify: `README.md`
- Modify: `.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: the env-var contract from Tasks 1–2.
- Produces: user-facing docs; no code consumed downstream.

- [ ] **Step 1: Replace the "Customize" section with a "Configuration" section**

In `README.md`, replace the entire block from the `## Customize` heading through the line ending `...would show the wrong time.` (the timezone note `>` blockquote, just before the `---` that precedes `## Prefer not to install a plugin?`) with:

````markdown
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
````

- [ ] **Step 2: Expand the "Prefer not to install a plugin?" section with a concrete example**

In `README.md`, replace the paragraph under `## Prefer not to install a plugin?` (the single paragraph beginning `You can paste the same hooks...`) with:

````markdown
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
````

- [ ] **Step 3: Bump the plugin version**

In `.claude-plugin/plugin.json`, change `"version": "1.2.0",` to `"version": "1.3.0",`.

- [ ] **Step 4: Verify docs render and reference real vars**

Run: `grep -c "CLAUDE_TIMESTAMPS_" README.md && grep '"version"' .claude-plugin/plugin.json`
Expected: a count of at least 10 `CLAUDE_TIMESTAMPS_` mentions, and `"version": "1.3.0",`.

- [ ] **Step 5: Commit**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: document CLAUDE_TIMESTAMPS_* config and non-plugin setup; bump to 1.3.0"
```

---

## Self-Review notes

- **Spec coverage:** display format/separator (Task 1), context format/prefix (Task 2), `printf '%b'` escape + set-but-empty handling (Task 1 Step 3 / tests), fail-safe preserved (both tasks' tests), README Configuration + `settings.json` example + non-plugin path (Task 3), field-name confirmation (Task 1 note). All spec sections mapped.
- **Placeholder scan:** none — every code/step is concrete.
- **Type/name consistency:** env var names identical across tasks and README; `displayContent`/`additionalContext` jq paths match the helpers `dc`/`ac`.
- **Deviation from spec:** spec's testing item #4 (literal `\n`) and the harness use bash regex shape matching for time fields to avoid clock-boundary flakiness, as the spec's testing section permits ("or a regex shape").
