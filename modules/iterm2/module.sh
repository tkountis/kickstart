# iterm2 -- shell integration and the it2* utilities.
#
# Gives you marks, command status in the sidebar, and imgcat. The integration
# script is sourced by shell/source/50_iterm2.sh once it exists.
DESC="iTerm2 shell integration and utilities"
TAGS="terminal"

REQUIRES_OS="darwin"
NET=1

ks_check() {
  [ -f "$HOME/.iterm2_shell_integration.bash" ] &&
  [ -f "$HOME/.iterm2_shell_integration.zsh" ]
}

ks_install() {
  local sh
  for sh in bash zsh; do
    [ -f "$HOME/.iterm2_shell_integration.$sh" ] && continue
    ks_chg "fetching iTerm2 integration for $sh"
    ks_run curl -fsSL "https://iterm2.com/shell_integration/$sh" \
      -o "$HOME/.iterm2_shell_integration.$sh" || return 1
  done
  # The it2* helper scripts live in ~/.iterm2 and are added to PATH by
  # shell/source/50_iterm2.sh.
  return 0
}
