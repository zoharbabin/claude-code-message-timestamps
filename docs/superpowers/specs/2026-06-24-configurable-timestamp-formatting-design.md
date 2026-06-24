# Configurable timestamp formatting — design

**Date:** 2026-06-24
**Status:** Approved (brainstorming)
**Repo:** fork of `zoharbabin/claude-code-message-timestamps` (forked at upstream `1.2.0`)

## Goal

Make the `message-timestamps` plugin's timestamp formatting configurable via
environment variables, while defaulting to the existing 1.2.0 behavior with one
deliberate exception (the display separator defaults to a newline, per the fork
owner's preference). No new runtime dependencies — `date` and `jq` only.

## Background / investigation findings

- The plugin is purely hooks (`hooks/hooks.json`), wiring three events:
  - `SessionStart` → `dependency-check.sh` (one-time `jq`-missing notice)
  - `UserPromptSubmit` → `timestamp-context.sh` (model-facing context injection)
  - `MessageDisplay` → `timestamp-display.sh` (display-only on-screen marker)
- **`MessageDisplay` is NOT plugin-only.** It is a standard hook event that is
  also delivered to hooks registered in a plain `~/.claude/settings.json` (or
  project `.claude/settings.json`). Local Claude Code is 2.1.190; the event was
  added in 2.1.152. Therefore the fork can be used either as an installable
  plugin OR as plain hooks in dotfiles — both paths will be documented.
- Upstream `main` is at **1.2.0** (installed cache was 1.1.1). 1.2.0 already
  introduced one env var, `CLAUDE_TIMESTAMPS_INJECT_CONTEXT` (display-only mode),
  establishing a `CLAUDE_TIMESTAMPS_` naming convention this fork will follow.
- 1.2.0's display marker is `"[" + ts + "] "` (bracket + trailing space). This
  fork's default separator is a **newline** instead (owner preference).
- **Open verification item:** the working display script keys the
  `MessageDisplay` stdin payload off `.index` and `.delta`. A docs summary
  instead listed `message_text`/`is_partial`. The proven-working plugin code is
  trusted, but the exact field names will be confirmed empirically (temporary
  logging hook observing one real payload) before finalizing.

## Configuration surface

All env vars optional; unset reproduces documented defaults.

| Var | Default | Hook | Effect |
|---|---|---|---|
| `CLAUDE_TIMESTAMPS_DISPLAY_FORMAT` | `[%H:%M:%S]` | display | `date` format for the whole on-screen marker (brackets are part of the format string, so they are customizable/removable) |
| `CLAUDE_TIMESTAMPS_SEPARATOR` | newline (`\n`) | display | text inserted between the marker and the message |
| `CLAUDE_TIMESTAMPS_CONTEXT_FORMAT` | `%H:%M:%S %Z` | context | `date` format for the injected model-facing time |
| `CLAUDE_TIMESTAMPS_CONTEXT_PREFIX` | `Message sent at local time ` | context | prose placed before the formatted time |
| `CLAUDE_TIMESTAMPS_INJECT_CONTEXT` | `true` | context | (existing, unchanged) `false` disables context injection |

### Separator escape handling

`CLAUDE_TIMESTAMPS_SEPARATOR` is passed through `printf '%b'` so escape
sequences typed in a JSON `env` block are interpreted: `"\n"` → newline,
`"\t"` → tab, `" "` → literal space. When the var is unset the default is a
real newline (`$'\n'`). Use `${VAR-default}` (preserve-empty) rather than
`${VAR:-default}` so a user can intentionally set an empty separator.

## Component changes

### `hooks/scripts/timestamp-display.sh`

Replace the hardcoded marker/separator. Preserve `set -euo pipefail`, the
`jq`-missing fail-safe (emit nothing, exit 0), and the `index == 0` gating.

```bash
command -v jq >/dev/null 2>&1 || exit 0

marker="$(date "+${CLAUDE_TIMESTAMPS_DISPLAY_FORMAT:-[%H:%M:%S]}")"
sep="$(printf '%b' "${CLAUDE_TIMESTAMPS_SEPARATOR-$'\n'}")"

jq --arg marker "$marker" --arg sep "$sep" '
  if .index == 0 then
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: ($marker + $sep + .delta)}}
  else
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: .delta}}
  end
'
```

### `hooks/scripts/timestamp-context.sh`

Keep `set -euo pipefail`, the `jq` fail-safe, and the existing
`CLAUDE_TIMESTAMPS_INJECT_CONTEXT` opt-out. Make format + prefix configurable.

```bash
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_TIMESTAMPS_INJECT_CONTEXT:-true}" = "false" ] && exit 0

ts="$(date "+${CLAUDE_TIMESTAMPS_CONTEXT_FORMAT:-%H:%M:%S %Z}")"
prefix="${CLAUDE_TIMESTAMPS_CONTEXT_PREFIX-Message sent at local time }"

jq -n --arg s "${prefix}${ts}" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $s}}'
```

`dependency-check.sh` is unchanged.

## Testing

Add `test/run.sh` (no extra deps; bash + jq). Pipe representative JSON into the
scripts and assert exact output:

1. Display, defaults — `index:0` input → marker `[HH:MM:SS]`, newline, then delta.
2. Display, `index:1` — passthrough (`displayContent == delta`).
3. Display, custom `CLAUDE_TIMESTAMPS_DISPLAY_FORMAT` + `CLAUDE_TIMESTAMPS_SEPARATOR=" "`.
4. Display, `CLAUDE_TIMESTAMPS_SEPARATOR="\n"` literal → verify it becomes a real newline.
5. Context, defaults — `additionalContext` starts with `Message sent at local time `.
6. Context, custom `CLAUDE_TIMESTAMPS_CONTEXT_PREFIX` + `_CONTEXT_FORMAT`.
7. Context, `CLAUDE_TIMESTAMPS_INJECT_CONTEXT=false` → no output.
8. Fail-safe — simulate missing `jq` (PATH shadow) → both scripts emit nothing, exit 0.

Time-format assertions match against `date`-derived expected values (or a regex
shape) rather than hardcoded clock values, to avoid flakiness.

## Documentation

README gains a **Configuration** section:
- The env-var table above.
- A `settings.json` `env`-block example showing newline separator and a reworded
  context prefix.
- The **plain-hooks (non-plugin)** setup path: registering the two scripts under
  a `hooks` block in `~/.claude/settings.json`, given `MessageDisplay` works
  outside plugins.

## Out of scope (YAGNI)

- Making the `[ ]` brackets a separate var (folded into the format string).
- Per-project vs per-message config beyond what env vars already allow.
- Changing `dependency-check.sh` or `hooks.json` wiring.
