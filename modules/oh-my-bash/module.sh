# oh-my-bash -- the bash framework this laptop already runs.
#
# kickstart does not fight it: our shell block is appended to the END of
# ~/.bashrc, after oh-my-bash has loaded, so our aliases and functions win and
# its theme and completions still apply.
DESC="oh-my-bash framework"
TAGS="shell"

NET=1

ks_check() { [ -d "$HOME/.oh-my-bash" ]; }

ks_install() {
  ks_step "cloning oh-my-bash"
  ks_run git clone --depth 1 https://github.com/ohmybash/oh-my-bash.git \
    "$HOME/.oh-my-bash" || return 1
}

ks_configure() {
  # oh-my-bash's installer rewrites ~/.bashrc wholesale. We do not want that,
  # so wire it ourselves in a block we own -- and only if nothing already does.
  if grep -q 'oh-my-bash.sh' "$HOME/.bashrc" 2>/dev/null; then
    return 0
  fi
  # shellcheck disable=SC2016  # expanded later, by the rc file itself
  if ks_ensure_block "$HOME/.bashrc" oh-my-bash \
'export OSH="$HOME/.oh-my-bash"
OSH_THEME="${OSH_THEME:-robbyrussell}"
plugins=(git bashmarks)
[ -r "$OSH/oh-my-bash.sh" ] && . "$OSH/oh-my-bash.sh"'; then
    ks_chg "wired oh-my-bash into .bashrc"
    ks_touched
  fi
  return 0
}
