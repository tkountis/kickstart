# ssh -- client configuration.
#
# We never take over ~/.ssh/config, because that file usually has years of
# accumulated host entries and work-specific bastion rules. Instead kickstart
# owns ~/.ssh/config.d/00-kickstart.conf and adds a single Include line at the
# TOP of ~/.ssh/config.
#
# ssh uses first-match-wins, so anything kickstart sets is authoritative. Put
# your own overrides in ~/.ssh/config.d/99-local.conf, which is never touched.
DESC="ssh client defaults via ~/.ssh/config.d"
TAGS="core net"

PROVIDES="ssh"
# ssh is present on every box we care about; nothing to install.
ks_check() { return 0; }
ks_install() { return 0; }

ks_configure() {
  local cfg="$HOME/.ssh/config"
  local line="Include ~/.ssh/config.d/*.conf"

  ks_mkdir "$HOME/.ssh"
  [ "${KS_DRY_RUN:-0}" = 1 ] || chmod 700 "$HOME/.ssh"
  ks_mkdir "$HOME/.ssh/config.d"
  # ControlPath in 00-kickstart.conf lives here; ssh will not create it.
  ks_mkdir "$HOME/.ssh/control"

  # A place for host entries kickstart must never overwrite.
  if [ ! -f "$HOME/.ssh/config.d/99-local.conf" ] && [ "${KS_DRY_RUN:-0}" != 1 ]; then
    printf '%s\n' \
      "# Host entries local to this machine. Not tracked by kickstart." >"$HOME/.ssh/config.d/99-local.conf"
    ks_touched
  fi

  if [ -f "$cfg" ] && grep -qF "$line" "$cfg"; then
    return 0
  fi

  if [ "${KS_DRY_RUN:-0}" = 1 ]; then
    ks_run "prepend '$line' to ~/.ssh/config"
    return 0
  fi

  # Prepend, not append: Include has to come first for these defaults to win.
  local tmp
  tmp=$(ks_mktemp)
  {
    printf '# >>> kickstart:ssh >>>\n%s\n# <<< kickstart:ssh <<<\n\n' "$line"
    [ -f "$cfg" ] && cat "$cfg"
  } >"$tmp"
  cat "$tmp" >"$cfg"
  rm -f "$tmp"
  chmod 600 "$cfg"
  ks_chg "added Include to ~/.ssh/config"
  ks_touched
  return 0
}
