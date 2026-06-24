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
