# neovim -- editor. The config here is deliberately small: settings and
# keymaps only, no plugin manager. Plugins pull from the network at startup,
# which is exactly what you do not want on an air-gapped box. If you want a
# full IDE setup, add it as a separate module that requires the personal
# profile.
DESC="Neovim with a minimal, offline-safe config"
TAGS="core editor"

PROVIDES="nvim"
PKG_BREW="neovim"
PKG_APT="neovim"
PKG_DNF="neovim"

ks_configure() {
  # vi/vim users land here too.
  local bin="$HOME/.local/bin"
  ks_mkdir "$bin"
  if ks_have nvim && [ ! -e "$bin/vim" ]; then
    ks_chg "alias vim -> nvim"
    ks_run ln -sfn "$(command -v nvim)" "$bin/vim"
    ks_touched
  fi
  return 0
}
