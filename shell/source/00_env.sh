# shellcheck shell=sh
# Environment. Loaded first, before anything that might depend on it.

# XDG base directories -- a lot of tools respect these, and it keeps $HOME sane.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-$LANG}"

# Editor: prefer nvim, fall back sanely on a bare remote box.
if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim VISUAL=nvim
elif command -v vim >/dev/null 2>&1; then
  export EDITOR=vim VISUAL=vim
else
  export EDITOR=vi VISUAL=vi
fi

export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"

# Generous, deduplicated, timestamped history in both shells.
export HISTSIZE=100000
if [ -n "${ZSH_VERSION:-}" ]; then
  export SAVEHIST=100000
  export HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
  setopt HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY EXTENDED_HISTORY 2>/dev/null
elif [ -n "${BASH_VERSION:-}" ]; then
  export HISTFILESIZE=100000
  export HISTCONTROL=ignoreboth:erasedups
  export HISTTIMEFORMAT='%F %T  '
  # shellcheck disable=SC3044  # guarded: bash only
  shopt -s histappend 2>/dev/null
fi

# Homebrew on Linux is a user-space install; make it visible if it exists.
# `brew shellenv` costs ~30ms, which is most of a shell startup, so cache it.
if [ -z "${HOMEBREW_PREFIX:-}" ]; then
  for _ks_brew in /opt/homebrew/bin/brew /usr/local/bin/brew \
                  /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
    if [ -x "$_ks_brew" ]; then
      _ks_eval_cached brew-shellenv.sh "$_ks_brew" "$_ks_brew" shellenv ||
        eval "$("$_ks_brew" shellenv)"
      break
    fi
  done
  unset _ks_brew
fi
