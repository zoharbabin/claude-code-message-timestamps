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
# The trailing 'x' sentinel keeps command substitution from stripping a
# separator that ends in newline(s) (e.g. the common "\n").
if [ -n "${CLAUDE_TIMESTAMPS_SEPARATOR+set}" ]; then
  sep="$(printf '%b' "$CLAUDE_TIMESTAMPS_SEPARATOR"; printf x)"
  sep="${sep%x}"
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
