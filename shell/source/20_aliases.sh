# shellcheck shell=sh
# Aliases. Keep these boring and universal; anything with logic belongs in a
# function in the 30+ band so it can be documented and reused in scripts.

# ls: prefer eza, fall back to ls with the right colour flag per platform.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -l --group-directories-first --git'
  alias la='eza -la --group-directories-first --git'
  alias lt='eza --tree --level=2'
else
  case "$(uname -s)" in
    Darwin) alias ls='ls -G' ;;
    *)      alias ls='ls --color=auto --group-directories-first' ;;
  esac
  alias ll='ls -lh'
  alias la='ls -lah'
fi

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias mkdir='mkdir -p'

# Guard rails on the destructive ones.
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never --style=plain'
command -v batcat >/dev/null 2>&1 && alias bat='batcat'

alias g='git'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
alias gp='git pull --ff-only'

alias k='kubectl'
alias tf='terraform'

# Ask before a reboot typo ruins the afternoon.
alias please='sudo'
