#!/usr/bin/env bash
# Shared timezone resolver — sourced by the timestamp hooks.
#
# `date` reads the TZ env var, but TZ does NOT reliably accept short
# abbreviations — `TZ=KST` is not a valid POSIX TZ and silently renders as
# UTC. So resolve_tz maps common abbreviations to IANA zone names, and passes
# anything else (IANA names like America/Denver) straight through. The
# abbreviation shown on screen still comes from `date '+%Z'`, so a resolved
# zone displays its own current abbreviation (e.g. America/Denver shows MST
# or MDT correctly, depending on daylight saving).
#
# resolve_tz RAW prints the resolved TZ value on stdout. It never errors.

resolve_tz() {
  local raw="$1"
  local key
  key="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"

  case "$key" in
    UTC|GMT|ZULU|Z)  printf 'UTC' ;;
    # North America
    EST|EDT|ET)      printf 'America/New_York' ;;
    CST|CDT|CT)      printf 'America/Chicago' ;;
    MST|MDT|MT)      printf 'America/Denver' ;;
    PST|PDT|PT)      printf 'America/Los_Angeles' ;;
    # Europe
    BST|WET|WEST)    printf 'Europe/London' ;;
    CET|CEST)        printf 'Europe/Paris' ;;
    EET|EEST)        printf 'Europe/Athens' ;;
    # Asia / Oceania
    IST)             printf 'Asia/Kolkata' ;;
    SGT)             printf 'Asia/Singapore' ;;
    HKT)             printf 'Asia/Hong_Kong' ;;
    JST)             printf 'Asia/Tokyo' ;;
    KST)             printf 'Asia/Seoul' ;;
    AEST|AEDT)       printf 'Australia/Sydney' ;;
    NZST|NZDT)       printf 'Pacific/Auckland' ;;
    # Not a known abbreviation: pass the raw value through (IANA name, or a
    # POSIX TZ string). Preserves original case, which IANA names require.
    *)               printf '%s' "$raw" ;;
  esac
}
