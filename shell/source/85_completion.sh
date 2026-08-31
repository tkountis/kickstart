# shellcheck shell=sh
# Completion machinery. Runs before the 90-band files that register
# completions, and is a no-op when a framework (oh-my-zsh, oh-my-bash) has
# already done the work.
#
# Every shell-specific construct below is inside an `if [ -n "$ZSH_VERSION" ]`
# or bash equivalent, so it never runs in a shell that cannot handle it. The
# POSIX linter cannot see that, hence the blanket disable.
# shellcheck disable=SC3024,SC3030,SC3044,SC3046,SC3001,SC1090

if [ -n "${ZSH_VERSION:-}" ]; then
  # compdef exists once compinit has run.
  if ! command -v compdef >/dev/null 2>&1; then
    autoload -U +X compinit && compinit -u
  fi
  # Lets zsh consume bash completion scripts, which most tools still ship.
  command -v complete >/dev/null 2>&1 || { autoload -U +X bashcompinit && bashcompinit; }

  [ -d /opt/homebrew/share/zsh/site-functions ] && fpath+=(/opt/homebrew/share/zsh/site-functions)
  [ -d /opt/brew/share/zsh/site-functions ] && fpath+=(/opt/brew/share/zsh/site-functions)

elif [ -n "${BASH_VERSION:-}" ]; then
  if [ -n "${HOMEBREW_PREFIX:-}" ] && [ -r "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh" ]; then
    . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
  elif [ -r /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  fi
fi
