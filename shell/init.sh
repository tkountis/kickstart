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

KICKSTART_ROOT="${KICKSTART_ROOT:-$HOME/.kickstart}"
export KICKSTART_ROOT

KICKSTART_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kickstart"
KICKSTART_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kickstart"
export KICKSTART_DATA_DIR KICKSTART_CONFIG_DIR

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
_ks_source_files() {
  _ks_source_dirs | while IFS= read -r _ksdir; do
    [ -d "$_ksdir" ] || continue
    for _ksf in "$_ksdir"/*.sh; do
      [ -f "$_ksf" ] || continue
      printf '%s\t%s\n' "${_ksf##*/}" "$_ksf"
    done
  done | LC_ALL=C sort -k1,1 | cut -f2-
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
