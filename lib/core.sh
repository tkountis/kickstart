#!/usr/bin/env bash
# lib/core.sh -- logging, error handling, dry-run execution.
#
# Everything here is bash 3.2 compatible (macOS /bin/bash) on purpose:
# no associative arrays, no `mapfile`, no `${x^^}`.

# ---------------------------------------------------------------- colours ---

ks_init_colors() {
  if [ -t 2 ] && [ "${KS_NO_COLOR:-0}" != 1 ] && [ "${NO_COLOR:-}" = "" ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
  else
    C_RESET=''; C_DIM=''; C_BOLD=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
  fi
}
ks_init_colors

# --------------------------------------------------------------- counters ---

KS_N_CHANGED=0
KS_N_OK=0
KS_N_SKIPPED=0
KS_N_FAILED=0
KS_FAILED_NAMES=""

# ---------------------------------------------------------------- logging ---
#
# All log output goes to stderr so that command substitution on kickstart
# subcommands stays clean.

# ks_scope is prefixed to every message; set it while a module runs.
KS_SCOPE=""

_ks_prefix() {
  if [ -n "$KS_SCOPE" ]; then printf '%s' "${C_DIM}[${KS_SCOPE}]${C_RESET} "; fi
}

ks_info()  { printf '%s%s\n' "$(_ks_prefix)" "$*" >&2; }
ks_step()  { printf '%s%s==>%s %s\n' "$(_ks_prefix)" "$C_BLUE" "$C_RESET" "$*" >&2; }
ks_ok()    { printf '%s%s  ok%s   %s\n' "$(_ks_prefix)" "$C_GREEN" "$C_RESET" "$*" >&2; }
ks_chg()   { printf '%s%s  +%s    %s\n' "$(_ks_prefix)" "$C_CYAN" "$C_RESET" "$*" >&2; }
ks_skip()  { printf '%s%s  skip%s %s\n' "$(_ks_prefix)" "$C_DIM" "$C_RESET" "$*" >&2; }
ks_warn()  { printf '%s%swarn%s  %s\n' "$(_ks_prefix)" "$C_YELLOW" "$C_RESET" "$*" >&2; }
ks_error() { printf '%s%serror%s %s\n' "$(_ks_prefix)" "$C_RED" "$C_RESET" "$*" >&2; }

ks_debug() {
  [ "${KS_VERBOSE:-0}" = 1 ] || return 0
  printf '%s%sdebug%s %s\n' "$(_ks_prefix)" "$C_DIM" "$C_RESET" "$*" >&2
}

ks_die() { ks_error "$*"; exit 1; }

# ------------------------------------------------------------- execution ----

# ks_dry <description> -- report an action under --dry-run that has no single
# command to echo (a file rewrite, a block insertion).
ks_dry() { printf '%s%sdry%s   %s\n' "$(_ks_prefix)" "$C_YELLOW" "$C_RESET" "$*" >&2; }

# ks_run <cmd> [args...] -- run a command, honouring --dry-run.
# Always logs what it is about to do, which is the whole debugging story.
ks_run() {
  if [ "${KS_DRY_RUN:-0}" = 1 ]; then
    ks_dry "$*"
    return 0
  fi
  ks_debug "run: $*"
  if [ "${KS_VERBOSE:-0}" = 1 ]; then
    "$@"
  else
    # Capture output; only surface it when the command fails.
    local out rc
    out=$("$@" 2>&1) || {
      rc=$?
      [ -n "$out" ] && printf '%s\n' "$out" >&2
      return $rc
    }
    return 0
  fi
}

# ks_have <cmd> -- is an executable on PATH?
ks_have() { command -v "$1" >/dev/null 2>&1; }

# ks_sudo <cmd> [args...] -- run as root when we are not already root.
ks_sudo() {
  if [ "$(id -u)" = 0 ]; then
    ks_run "$@"
  elif ks_have sudo; then
    ks_run sudo "$@"
  else
    ks_error "need root for: $*  (no sudo available)"
    return 1
  fi
}

ks_confirm() {
  [ "${KS_YES:-0}" = 1 ] && return 0
  [ -t 0 ] || return 1
  local reply
  printf '%s [y/N] ' "$*" >&2
  read -r reply
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ks_lower <string> -- bash 3.2 safe lowercase.
ks_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
ks_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# ks_contains <needle> <space separated haystack>
ks_contains() {
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

# --------------------------------------------------------------- fs bits ----

ks_mkdir() {
  [ -d "$1" ] && return 0
  ks_run mkdir -p "$1"
}

# ks_ensure_block <file> <marker> <content>
# Idempotently maintain a delimited block inside a file. Rewrites the block
# when its content changed; never touches anything outside the markers.
ks_ensure_block() {
  local file=$1 marker=$2 content=$3
  local begin="# >>> kickstart:${marker} >>>"
  local end="# <<< kickstart:${marker} <<<"
  local desired tmp

  desired="${begin}
${content}
${end}"

  if [ -f "$file" ] && grep -qF "$begin" "$file" 2>/dev/null; then
    local current
    current=$(awk -v b="$begin" -v e="$end" \
      'index($0,b){f=1} f{print} index($0,e){f=0}' "$file")
    if [ "$current" = "$desired" ]; then
      return 3 # unchanged
    fi
    if [ "${KS_DRY_RUN:-0}" = 1 ]; then
      ks_dry "update block ${marker} in ${file}"
      return 0
    fi
    tmp=$(ks_mktemp)
    awk -v b="$begin" -v e="$end" -v repl="$desired" '
      index($0,b) { print repl; skip=1; next }
      skip && index($0,e) { skip=0; next }
      skip { next }
      { print }
    ' "$file" >"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
    return 0
  fi

  if [ "${KS_DRY_RUN:-0}" = 1 ]; then
    ks_dry "append block ${marker} to ${file}"
    return 0
  fi
  ks_mkdir "$(dirname "$file")"
  [ -f "$file" ] || : >"$file"
  # Keep exactly one blank line before the block.
  [ -s "$file" ] && printf '\n' >>"$file"
  printf '%s\n' "$desired" >>"$file"
  return 0
}

ks_mktemp() { mktemp "${TMPDIR:-/tmp}/kickstart.XXXXXX"; }

# ks_relpath <path> -- render $HOME as ~ for readable logs.
# shellcheck disable=SC2088  # the ~ is display text, not a path to expand
ks_relpath() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}
