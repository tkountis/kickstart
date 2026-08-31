# shellcheck shell=sh
# PATH management.
#
# Use these instead of hand-rolling PATH= assignments in other helper files;
# they are idempotent, so re-sourcing your rc never duplicates entries.

#: path_prepend <dir> -- add a directory to the front of PATH if it exists
path_prepend() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in *":$1:"*) return 0 ;; esac
  PATH="$1:$PATH"
  export PATH
}

#: path_append <dir> -- add a directory to the end of PATH if it exists
path_append() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in *":$1:"*) return 0 ;; esac
  PATH="$PATH:$1"
  export PATH
}

#: path_remove <dir> -- drop a directory from PATH
path_remove() {
  PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$1" | paste -sd: -)
  export PATH
}

#: path -- print PATH one entry per line
path() { printf '%s\n' "$PATH" | tr ':' '\n'; }

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"
path_prepend "$KICKSTART_ROOT/bin"

# Language toolchains, only if present.
path_append "$HOME/.cargo/bin"
path_append "$HOME/go/bin"
path_append "${GOPATH:-$HOME/go}/bin"

# GNU coreutils on macOS, so scripts behave the same everywhere.
if [ -n "${HOMEBREW_PREFIX:-}" ]; then
  path_prepend "$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin"
  path_prepend "$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin"
  path_prepend "$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin"
fi
