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

# All helper files across kickstart and every overlay. `find` rather than a
# glob: zsh errors on an unmatched glob.
_ks_helper_files() {
  {
    printf '%s\n' "$KICKSTART_ROOT/shell/source"
    if [ -d "$KICKSTART_DATA_DIR/overlays" ]; then
      find "$KICKSTART_DATA_DIR/overlays" -maxdepth 3 -type d \
        -path '*/shell/source' -print 2>/dev/null
    fi
  } | while IFS= read -r _d; do
    [ -d "$_d" ] || continue
    find "$_d" -maxdepth 1 -type f \
      \( -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \) -print 2>/dev/null | sort
  done
  unset _d
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
