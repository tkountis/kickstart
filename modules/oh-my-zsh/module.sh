# oh-my-zsh -- same story as oh-my-bash, for zsh.
DESC="oh-my-zsh framework"
TAGS="shell"

NET=1

ks_check() { [ -d "$HOME/.oh-my-zsh" ]; }

ks_install() {
  ks_step "cloning oh-my-zsh"
  ks_run git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git \
    "$HOME/.oh-my-zsh" || return 1
}

ks_configure() {
  if grep -q 'oh-my-zsh.sh' "$HOME/.zshrc" 2>/dev/null; then
    return 0
  fi
  # shellcheck disable=SC2016  # expanded later, by the rc file itself
  if ks_ensure_block "$HOME/.zshrc" oh-my-zsh \
'export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="${ZSH_THEME:-robbyrussell}"
plugins=(git)
[ -r "$ZSH/oh-my-zsh.sh" ] && . "$ZSH/oh-my-zsh.sh"'; then
    ks_chg "wired oh-my-zsh into .zshrc"
    ks_touched
  fi
  return 0
}
