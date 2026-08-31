#!/usr/bin/env bash
# lib/keys.sh -- ssh key management.
#
# The rule this file exists to enforce: private keys are generated per host and
# never travel. Only public keys are ever copied, committed, or pushed.
#
# `keys/` in the repo (or an overlay) holds one .pub per machine. That makes
# "this laptop is gone" a commit rather than an archaeology exercise across
# every authorized_keys you have ever touched.

KS_KEY_DEFAULT="$HOME/.ssh/id_ed25519"

# ks_keys_dir -- where public keys are tracked. Overlay wins, as always.
ks_keys_dir() {
  local d
  for d in $KS_SEARCH_DIRS; do
    [ -d "$d/keys" ] && { printf '%s' "$d/keys"; return 0; }
  done
  printf '%s' "$KS_ROOT/keys"
}

# ks_keys_status -- every key on this host, and whether the agent has it.
ks_keys_status() {
  local pub priv fp loaded agent_fps

  if [ ! -d "$HOME/.ssh" ]; then
    ks_info "no ~/.ssh on this host"
    return 0
  fi

  agent_fps=$(ssh-add -l 2>/dev/null | awk '{print $2}')

  printf '%slocal keys%s\n' "$C_BOLD" "$C_RESET"
  local found=0
  for pub in "$HOME"/.ssh/*.pub; do
    [ -f "$pub" ] || continue
    found=1
    priv=${pub%.pub}
    fp=$(ssh-keygen -lf "$pub" 2>/dev/null)
    loaded=" "
    case "$agent_fps" in
      *"$(printf '%s' "$fp" | awk '{print $2}')"*) loaded="+" ;;
    esac
    printf '  %s %-22s %s\n' "$loaded" "$(basename "$priv")" "$fp"
    if [ ! -f "$priv" ]; then
      ks_warn "  public key with no private half: $(ks_relpath "$pub")"
    elif [ "$(ks_file_mode "$priv")" != 600 ]; then
      ks_warn "  $(ks_relpath "$priv") is mode $(ks_file_mode "$priv"), should be 600"
    fi
  done
  [ "$found" = 1 ] || printf '  (none -- create one with: kickstart keys new)\n'
  printf '  %s+%s = loaded in ssh-agent\n' "$C_DIM" "$C_RESET"

  local kd
  kd=$(ks_keys_dir)
  printf '\n%stracked public keys%s  %s\n' "$C_BOLD" "$C_RESET" "$(ks_relpath "$kd")"
  if [ -d "$kd" ]; then
    for pub in "$kd"/*.pub; do
      [ -f "$pub" ] || continue
      printf '  %-22s %s\n' "$(basename "$pub" .pub)" "$(ssh-keygen -lf "$pub" 2>/dev/null)"
    done
  else
    printf '  (none -- run: kickstart keys track)\n'
  fi
}

ks_file_mode() {
  if [ "$KS_OS" = darwin ]; then stat -f '%OLp' "$1" 2>/dev/null
  else stat -c '%a' "$1" 2>/dev/null; fi
}

# ks_keys_new [name] -- generate this host's key.
ks_keys_new() {
  local name=${1:-id_ed25519}
  local key="$HOME/.ssh/$name"

  if [ -f "$key" ]; then
    ks_info "key already exists: $(ks_relpath "$key")"
    cat "$key.pub"
    return 0
  fi

  ks_mkdir "$HOME/.ssh"
  [ "${KS_DRY_RUN:-0}" = 1 ] || chmod 700 "$HOME/.ssh"

  # The comment is the audit trail: which machine, and when.
  local comment
  comment="$(id -un)@${KS_HOSTNAME}-$(date +%Y%m)"
  ks_step "generating ed25519 key for $comment"
  ks_run ssh-keygen -t ed25519 -a 100 -C "$comment" -f "$key" || return 1

  [ "${KS_DRY_RUN:-0}" = 1 ] && return 0
  chmod 600 "$key"
  chmod 644 "$key.pub"
  printf '\n'
  ks_ok "public key (register this where you need access):"
  cat "$key.pub"
  ks_info "track it in the repo with: kickstart keys track"
}

# ks_keys_track [name] -- copy this host's public key into keys/ for commit.
ks_keys_track() {
  local name=${1:-id_ed25519}
  local pub="$HOME/.ssh/$name.pub"
  [ -f "$pub" ] || ks_die "no such public key: $(ks_relpath "$pub")  (kickstart keys new)"

  local kd dest
  kd=$(ks_keys_dir)
  ks_mkdir "$kd"
  dest="$kd/${KS_HOSTNAME}.pub"

  if [ -f "$dest" ] && cmp -s "$pub" "$dest"; then
    ks_ok "already tracked: $(ks_relpath "$dest")"
    return 0
  fi
  ks_run cp "$pub" "$dest" || return 1
  ks_chg "tracked $(ks_relpath "$dest")"
  ks_info "commit it: git -C $(ks_relpath "$(dirname "$kd")") add keys && git commit"
}

# ks_keys_publish -- push the public key to GitHub via gh.
ks_keys_publish() {
  local name=${1:-id_ed25519}
  local pub="$HOME/.ssh/$name.pub"
  [ -f "$pub" ] || ks_die "no such public key: $(ks_relpath "$pub")"
  ks_have gh || ks_die "needs the GitHub CLI: kickstart apply gh"

  local title
  title="${KS_HOSTNAME} (kickstart $(date +%Y-%m-%d))"
  if gh ssh-key list 2>/dev/null | grep -qF "$(awk '{print $2}' <"$pub")"; then
    ks_ok "already registered with GitHub"
    return 0
  fi
  ks_step "adding key to GitHub as '$title'"
  ks_run gh ssh-key add "$pub" --title "$title"
}

# ks_keys_authorized -- rebuild ~/.ssh/authorized_keys from tracked keys.
#
# Anything outside the kickstart block is preserved, so a key your host
# provider or work tooling put there survives.
ks_keys_authorized() {
  local kd content pub
  kd=$(ks_keys_dir)
  [ -d "$kd" ] || ks_die "no tracked keys at $(ks_relpath "$kd")  (kickstart keys track)"

  content=""
  for pub in "$kd"/*.pub; do
    [ -f "$pub" ] || continue
    content="${content}$(cat "$pub")
"
  done
  [ -n "$content" ] || ks_die "no .pub files in $(ks_relpath "$kd")"

  # Trim the trailing newline the loop leaves behind.
  content=${content%
}

  ks_mkdir "$HOME/.ssh"
  if ks_ensure_block "$HOME/.ssh/authorized_keys" keys "$content"; then
    [ "${KS_DRY_RUN:-0}" = 1 ] || chmod 600 "$HOME/.ssh/authorized_keys"
    ks_chg "updated ~/.ssh/authorized_keys from $(ks_relpath "$kd")"
  else
    ks_ok "$(ks_relpath "$HOME/.ssh/authorized_keys") already up to date"
  fi
}
