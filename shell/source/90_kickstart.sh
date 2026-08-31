# shellcheck shell=sh
# kickstart's own shell interface. Loaded last so it can see everything else.
#
# Five things to remember, all starting with k:
#   khelp    what can I do here?
#   knew     add a new helper
#   kedit    edit an existing helper
#   kreload  load my changes into this shell
#   kup      pull and re-apply everything

#: khelp [pattern] -- list every documented shell helper
khelp() { "$KICKSTART_ROOT/shell/khelp.sh" "$@"; }

#: knew <topic> -- create a new helper file and open it in $EDITOR
knew() {
  [ -n "${1:-}" ] || { echo "usage: knew <topic>      e.g. knew kube" >&2; return 2; }
  "$KICKSTART_ROOT/bin/kickstart" new helper "$1" || return 1
  kedit "$1"
}

#: kedit [topic] -- open a helper file in $EDITOR (fzf picker with no argument)
kedit() {
  _f=$(_ks_helper_path "${1:-}") || return 1
  [ -n "$_f" ] || return 1
  "${EDITOR:-vi}" "$_f"
  unset _f
  kreload
}

#: kreload -- re-source kickstart's shell files into the current shell
kreload() {
  # shellcheck disable=SC1091
  . "$KICKSTART_ROOT/shell/init.sh" && echo "kickstart: reloaded"
}

#: kup -- pull kickstart plus overlays and re-apply this host's profile
kup() { "$KICKSTART_ROOT/bin/kickstart" update "$@" && kreload; }

#: ks <args...> -- the kickstart CLI
ks() { "$KICKSTART_ROOT/bin/kickstart" "$@"; }

#: kcd -- cd into the kickstart checkout
kcd() { cd "$KICKSTART_ROOT" || return 1; }

#: kwhich <name> -- show which helper file defines a function or alias
kwhich() {
  [ -n "${1:-}" ] || { echo "usage: kwhich <name>" >&2; return 2; }
  _ks_helper_files | while IFS= read -r f; do
    if grep -qE "^[[:space:]]*(function[[:space:]]+)?$1[[:space:]]*\(\)|^alias $1=" "$f"; then
      printf '%s\n' "$f"
    fi
  done
}

# ---- internals -------------------------------------------------------------

_ks_helper_files() {
  printf '%s\n' "$KICKSTART_ROOT"/shell/source/*.sh
  if [ -d "$KICKSTART_DATA_DIR/overlays" ]; then
    for _d in "$KICKSTART_DATA_DIR/overlays"/*/shell/source/*.sh; do
      [ -f "$_d" ] && printf '%s\n' "$_d"
    done
    unset _d
  fi
}

# Resolve a topic name to a helper file path, prompting when ambiguous.
_ks_helper_path() {
  _q=${1:-}
  if [ -n "$_q" ]; then
    _matches=$(_ks_helper_files | grep -i -- "$_q")
  else
    _matches=$(_ks_helper_files)
  fi
  _n=$(printf '%s\n' "$_matches" | grep -c .)

  if [ "$_n" -eq 0 ]; then
    echo "no helper matching '$_q'. create it with: knew $_q" >&2
    unset _q _matches _n; return 1
  elif [ "$_n" -eq 1 ]; then
    printf '%s\n' "$_matches"
  elif command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "$_matches" | fzf --height 40% --reverse
  else
    echo "several helpers match '$_q':" >&2
    printf '%s\n' "$_matches" | sed 's|.*/|  |' >&2
    unset _q _matches _n; return 1
  fi
  unset _q _matches _n
}
