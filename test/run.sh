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

# Run a hook script (reading stdin) with jq absent but bash/date still present,
# to exercise the jq-missing fail-safe regardless of where jq lives on PATH.
run_no_jq() {  # SCRIPT
  local bindir; bindir="$(mktemp -d)"
  ln -s "$(command -v bash)" "$bindir/bash"
  ln -s "$(command -v date)" "$bindir/date"
  PATH="$bindir" bash "$1"
  rm -rf "$bindir"
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
out="$(printf '{"index":0,"delta":"hi"}' | run_no_jq "$SCRIPTS/timestamp-display.sh")"
check "display fail-safe no-jq = empty" "" "$out"

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
out="$(printf '{}' | run_no_jq "$SCRIPTS/timestamp-context.sh")"
check "context fail-safe no-jq = empty" "" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
