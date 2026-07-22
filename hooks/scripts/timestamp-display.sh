#!/usr/bin/env bash
# MessageDisplay hook — user-facing, display-only.
#
# Prepends a local-time [HH:MM:SS] marker to each assistant message on screen.
# This is purely cosmetic: MessageDisplay never changes the transcript or what
# Claude sees, so the marker cannot confuse the model.
#
# MessageDisplay fires once per streamed batch of an assistant message, with a
# zero-based `index`. We stamp only the first batch (index == 0) so the marker
# appears exactly once per message, not before every chunk.
#
# Invoked as `bash <this script>` (see hooks.json), so it does not depend on the
# executable bit being preserved across clones/zips/Windows.
#
# Time is computed with `date` (local TZ, or a pinned one — see
# CLAUDE_TIMESTAMPS_TZ below). We do NOT use jq's `now|strftime`, which
# renders in UTC.
set -euo pipefail

# Fail safe: if jq is unavailable, emit nothing and exit 0. Claude Code then
# displays the original message text unchanged — never swallow assistant output.
command -v jq >/dev/null 2>&1 || exit 0

# Pin a timezone with CLAUDE_TIMESTAMPS_TZ (e.g. "KST", "America/Denver").
# Unset = machine local time, same as before.
if [ -n "${CLAUDE_TIMESTAMPS_TZ:-}" ]; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-tz.sh"
  export TZ="$(resolve_tz "$CLAUDE_TIMESTAMPS_TZ")"
fi

# Format override: CLAUDE_TIMESTAMPS_FORMAT is any `date` format string
# (default %H:%M:%S). Lets users drop seconds, switch to a 12-hour clock, etc.
# without editing this file.
ts="$(date "+${CLAUDE_TIMESTAMPS_FORMAT:-%H:%M:%S}")"

# Optional color. CLAUDE_TIMESTAMPS_COLOR holds SGR parameters (e.g. 2 for dim,
# 90 for gray, "1;36" for bold cyan). Unset or empty means no color, so the marker
# stays byte-for-byte identical to before. A set NO_COLOR always wins, per the
# convention at no-color.org (presence disables color regardless of its value).
#
# The reset (ESC[0m) goes after the trailing space, not right after "]". Claude
# Code's renderer drops the color on whichever character precedes the reset, so
# letting it eat the space keeps every digit and bracket colored.
marker="[${ts}] "
if [ -n "${CLAUDE_TIMESTAMPS_COLOR:-}" ] && [ -z "${NO_COLOR+set}" ]; then
  esc="$(printf '\033')"
  marker="${esc}[${CLAUDE_TIMESTAMPS_COLOR}m${marker}${esc}[0m"
fi

jq --arg marker "$marker" '
  if .index == 0 then
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: ($marker + .delta)}}
  else
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: .delta}}
  end
'
