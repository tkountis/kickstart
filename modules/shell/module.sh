# shell -- wire kickstart's shell integration into bash and zsh.
#
# This is the one module every profile needs. It owns exactly one guarded
# block per rc file and never touches anything outside it, so your existing
# oh-my-bash / oh-my-zsh setup is left alone. The block is appended last so
# kickstart's aliases and functions win over framework defaults.
DESC="Shell integration for bash and zsh (khelp, knew, kreload)"
TAGS="core"

# Nothing to install: bash and zsh are already there. On a Linux box where zsh
# is wanted, add it to a profile via a separate module.
ks_check() { return 0; }
ks_install() { return 0; }

ks_configure() {
  local root_expr block rc rc_found=0

  # Write $HOME rather than the expanded path so the same rc file works if the
  # home directory ever moves (containers, NFS, different usernames).
  case "$KS_ROOT" in
    "$HOME"/*) root_expr="\$HOME/${KS_ROOT#"$HOME"/}" ;;
    *)         root_expr="$KS_ROOT" ;;
  esac

  block="export KICKSTART_ROOT=\"$root_expr\"
[ -r \"\$KICKSTART_ROOT/shell/init.sh\" ] && . \"\$KICKSTART_ROOT/shell/init.sh\""

  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    # Create .bashrc/.zshrc if absent -- a bare box often has neither.
    if [ ! -f "$rc" ]; then
      ks_debug "creating $(ks_relpath "$rc")"
      [ "${KS_DRY_RUN:-0}" = 1 ] || : >"$rc"
    fi
    if ks_ensure_block "$rc" shell "$block"; then
      ks_chg "wired $(ks_relpath "$rc")"
      ks_touched
    fi
    rc_found=1
  done
  [ "$rc_found" = 1 ] || ks_warn "no rc files were wired"

  # macOS login shells read .bash_profile and ignore .bashrc unless told.
  if [ -f "$HOME/.bash_profile" ] &&
     ! grep -qE '(\.|source)[[:space:]]+.*\.bashrc' "$HOME/.bash_profile"; then
    # shellcheck disable=SC2016  # this text is evaluated later, by bash itself
    if ks_ensure_block "$HOME/.bash_profile" bash_profile \
      '[ -n "$BASH_VERSION" ] && [ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"'; then
      ks_chg "made .bash_profile source .bashrc"
      ks_touched
    fi
  fi

  # Standard directories, and a place for machine-local secrets/exports that
  # must never be committed.
  ks_mkdir "$HOME/.local/bin"
  ks_mkdir "$KS_CONFIG_DIR"
  if [ ! -f "$KS_CONFIG_DIR/env" ] && [ "${KS_DRY_RUN:-0}" != 1 ]; then
    cat >"$KS_CONFIG_DIR/env" <<'EOF'
# Machine-local shell environment. Sourced by every interactive shell.
# NOT tracked by kickstart -- put API keys and host specific exports here.
#   export SOME_APP_KEY=...
EOF
    chmod 600 "$KS_CONFIG_DIR/env"
    ks_chg "created $(ks_relpath "$KS_CONFIG_DIR/env")"
    ks_touched
  fi

  # Put the CLI on PATH even before the shell integration is loaded.
  if ks_link_file "$KS_ROOT/bin/kickstart" "$HOME/.local/bin/kickstart"; then
    ks_touched
  fi
  return 0
}
