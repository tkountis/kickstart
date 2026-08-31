# shellcheck shell=sh
# iTerm2 shell integration (macOS). Installed by the `iterm2` module.

[ "$(uname -s)" = Darwin ] || return 0

# The it2* utilities: imgcat, it2copy, it2setcolor, ...
path_append "$HOME/.iterm2"

if [ -n "${ZSH_VERSION:-}" ]; then
  [ -r "$HOME/.iterm2_shell_integration.zsh" ] && . "$HOME/.iterm2_shell_integration.zsh"
elif [ -n "${BASH_VERSION:-}" ]; then
  [ -r "$HOME/.iterm2_shell_integration.bash" ] && . "$HOME/.iterm2_shell_integration.bash"
fi
