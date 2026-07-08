#!/usr/bin/env bash
# UserPromptSubmit hook — model-facing.
#
# Gives Claude the local time each prompt was sent, wrapped by Claude Code in a
# <system-reminder> so the model treats it as passive metadata (never as part of
# the user's typed text). The system prompt already supplies today's date, so we
# send time + timezone only — no redundant date, fewer tokens.
#
# Invoked as `bash <this script>` (see hooks.json), so it does not depend on the
# executable bit being preserved across clones/zips/Windows.
#
# Time is computed with `date` (local TZ, or a pinned one — see
# CLAUDE_TIMESTAMPS_TZ below). We do NOT use jq's `now|strftime`, which
# renders in UTC.
set -euo pipefail

# Fail safe: if jq is unavailable, add no context rather than erroring the prompt.
command -v jq >/dev/null 2>&1 || exit 0

# Opt out of model-facing context injection (display-only mode).
[ "${CLAUDE_TIMESTAMPS_INJECT_CONTEXT:-true}" = "false" ] && exit 0

# Pin a timezone with CLAUDE_TIMESTAMPS_TZ (e.g. "KST", "America/Denver").
# Unset = machine local time, same as before.
if [ -n "${CLAUDE_TIMESTAMPS_TZ:-}" ]; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-tz.sh"
  export TZ="$(resolve_tz "$CLAUDE_TIMESTAMPS_TZ")"
fi

# Format override: CLAUDE_TIMESTAMPS_FORMAT is any `date` format string
# (default %H:%M:%S). The timezone (%Z) is always appended so the model keeps
# the offset regardless of the chosen format.
ts="$(date "+${CLAUDE_TIMESTAMPS_FORMAT:-%H:%M:%S} %Z")"
jq -n --arg ts "$ts" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: ("Message sent at local time " + $ts)}}'
