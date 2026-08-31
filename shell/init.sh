# shellcheck shell=sh
# shell/init.sh -- the single line your ~/.bashrc and ~/.zshrc source.
#
# It sources every shell/source/NN_*.sh from kickstart and from each overlay,
# ordered by filename across all of them. That interleaving is the point: a
# work overlay can ship 15_work_path.sh and it lands between core's 10_path.sh
# and 20_aliases.sh without either repo knowing about the other.
#
# Number bands (same convention as the old dotfiles-apple repo):
#   00-09  environment and exports
#   10-19  PATH
#   20-29  aliases
#   30-49  general purpose functions
#   50-79  tool and domain specific functions
#   80-89  prompt and theming
#   90-99  completions, and anything that must load last
#
# Portability rule: these files are sourced by BOTH bash and zsh. Stick to
# POSIX syntax. No arrays, no [[ ]], no ${x^^}, no `local -n`.
#
# When that is not practical -- a big pile of existing bash, a completion
# script -- name the file NN_topic.bash (or .zsh) and it is only sourced by
# that shell. `.sh` means both.

KICKSTART_ROOT="${KICKSTART_ROOT:-$HOME/.kickstart}"
export KICKSTART_ROOT

KICKSTART_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kickstart"
KICKSTART_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kickstart"
export KICKSTART_DATA_DIR KICKSTART_CONFIG_DIR

KICKSTART_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kickstart"
export KICKSTART_CACHE_DIR

# _ks_eval_cached <key> <binary> <command...>
#
# Source the output of a slow generator (shell completions, `brew shellenv`),
# caching it under ~/.cache/kickstart. Regenerated when the binary that
# produced it is newer than the cache, so upgrading a tool refreshes it.
#
# The cache is plain shell you can read, and `kcache clear` throws it away, so
# a stale cache is a 5 second problem rather than a mystery.
_ks_eval_cached() {
  _kskey=$1
  _ksbin=$2
  shift 2
  _ksfile="$KICKSTART_CACHE_DIR/$_kskey"
  _ksbinpath=$(command -v "$_ksbin" 2>/dev/null) || { unset _kskey _ksbin _ksfile _ksbinpath; return 1; }

  if [ ! -s "$_ksfile" ] || [ "$_ksbinpath" -nt "$_ksfile" ]; then
    mkdir -p "$KICKSTART_CACHE_DIR" 2>/dev/null
    if "$@" >"$_ksfile.new" 2>/dev/null && [ -s "$_ksfile.new" ]; then
      mv "$_ksfile.new" "$_ksfile"
    else
      rm -f "$_ksfile.new"
    fi
  fi
  # shellcheck disable=SC1090
  [ -s "$_ksfile" ] && . "$_ksfile"
  unset _kskey _ksbin _ksfile _ksbinpath
}

# Host-local settings written by `kickstart profile <name>`.
if [ -r "$KICKSTART_CONFIG_DIR/config" ]; then
  . "$KICKSTART_CONFIG_DIR/config"
fi
KICKSTART_PROFILE="${KICKSTART_PROFILE:-personal}"
export KICKSTART_PROFILE

# Machine-local, never-committed environment (API keys, work URLs, ...).
# See docs/secrets.md.
if [ -r "$KICKSTART_CONFIG_DIR/env" ]; then
  . "$KICKSTART_CONFIG_DIR/env"
fi

# _ks_source_dirs -- kickstart's own helpers plus every overlay's, one per line.
_ks_source_dirs() {
  printf '%s\n' "$KICKSTART_ROOT/shell/source"
  if [ -d "$KICKSTART_DATA_DIR/overlays" ]; then
    for _ksd in "$KICKSTART_DATA_DIR/overlays"/*/shell/source; do
      [ -d "$_ksd" ] && printf '%s\n' "$_ksd"
    done
    unset _ksd
  fi
}

# _ks_source_files -- all helper files, sorted by basename across every dir.
#
# `.sh` is sourced by every shell; `.bash` and `.zsh` only by the shell they
# name. `sort -s` (stable) matters: when core and an overlay both ship a file
# with the same name, the tie is broken by input order, which is core first
# and overlays after. So the overlay's copy is sourced last and wins.
#
# `find` rather than a glob on purpose: zsh treats an unmatched glob as an
# error, so `for f in dir/*.bash` blows up on any directory without one.
_ks_source_files() {
  _ks_source_dirs | while IFS= read -r _ksdir; do
    [ -d "$_ksdir" ] || continue
    find "$_ksdir" -maxdepth 1 -type f \
      \( -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \) -print 2>/dev/null
  done | while IFS= read -r _ksf; do
    case "$_ksf" in
      *.bash) [ -n "${BASH_VERSION:-}" ] || continue ;;
      *.zsh)  [ -n "${ZSH_VERSION:-}" ] || continue ;;
    esac
    printf '%s\t%s\n' "${_ksf##*/}" "$_ksf"
  done | LC_ALL=C sort -s -k1,1 | cut -f2-
}

# Source them. fd 3 keeps stdin free for anything a helper file might read,
# and a here-document (rather than a pipe) keeps the loop in this shell.
_ks_load() {
  while IFS= read -r _ksfile <&3; do
    [ -n "$_ksfile" ] || continue
    if [ -n "${KICKSTART_TRACE:-}" ]; then
      printf 'kickstart: sourcing %s\n' "$_ksfile" >&2
    fi
    # shellcheck disable=SC1090
    . "$_ksfile"
  done 3<<EOF
$(_ks_source_files)
EOF
  unset _ksfile
}

_ks_load
