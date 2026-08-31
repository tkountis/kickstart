#!/usr/bin/env bash
# lib/secrets.sh -- an age-encrypted vault, keyed on your ssh keys.
#
# Why age: one static binary, no daemon, no keyring, no agent to debug at
# 11pm. And crucially it accepts ssh keys as recipients, so there is no new
# key material to manage -- the per-host ssh key from lib/keys.sh IS the
# decryption identity.
#
#   secrets/recipients.txt   one ssh public key per line, one per host
#   secrets/<name>.age       ciphertext, safe to commit
#
# Plaintext never touches the repo. Decryption writes straight to the final
# destination, or to a 0700 temp directory for `edit`.
#
# See docs/secrets.md for the threat model and what must never go in here.

KS_VAULT_IDENTITY_DEFAULT="$HOME/.ssh/id_ed25519"

# ks_vault_dir -- where the vault lives. An overlay's vault wins over core's.
ks_vault_dir() {
  local pinned d
  pinned=$(ks_config_get KICKSTART_VAULT "")
  [ -n "$pinned" ] && { printf '%s' "$pinned"; return 0; }
  for d in $KS_SEARCH_DIRS; do
    [ -d "$d/secrets" ] && { printf '%s' "$d/secrets"; return 0; }
  done
  printf '%s' "$KS_ROOT/secrets"
}

ks_vault_identity() {
  local id
  id=$(ks_config_get KICKSTART_AGE_IDENTITY "$KS_VAULT_IDENTITY_DEFAULT")
  printf '%s' "$id"
}

ks_vault_require() {
  ks_have age || ks_die "age is not installed -- run: kickstart apply age"
  ks_have age-keygen || true
  local vault
  vault=$(ks_vault_dir)
  [ -f "$vault/recipients.txt" ] ||
    ks_die "no vault at $(ks_relpath "$vault")  -- run: kickstart secrets init"
}

# ks_secrets_init [--in <dir>] -- create the vault and register this host.
ks_secrets_init() {
  local vault=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --in) shift; vault=${1:-} ;;
      *) ks_die "secrets init [--in <dir>]" ;;
    esac
    shift
  done
  [ -n "$vault" ] || vault=$(ks_vault_dir)

  ks_have age || ks_die "age is not installed -- run: kickstart apply age"

  local id
  id=$(ks_vault_identity)
  if [ ! -f "$id" ]; then
    ks_warn "no ssh key at $(ks_relpath "$id")"
    ks_confirm "generate one now?" || ks_die "need an identity to encrypt to"
    ks_keys_new "$(basename "$id")" || return 1
  fi
  [ -f "$id.pub" ] || ks_die "missing public half: $(ks_relpath "$id.pub")"

  case "$vault" in
    "$KS_ROOT"/*)
      ks_warn "this vault would live in the kickstart repo itself"
      ks_warn "if that repo is public, ciphertext is public forever"
      ks_info "prefer a private overlay: kickstart secrets init --in <overlay>/secrets"
      ks_confirm "continue anyway?" || return 1
      ;;
  esac

  ks_mkdir "$vault"
  local rec="$vault/recipients.txt"
  if [ ! -f "$rec" ] && [ "${KS_DRY_RUN:-0}" != 1 ]; then
    cat >"$rec" <<'EOF'
# age recipients. One ssh public key per line; every secret in this vault is
# encrypted to all of them. Add a host by appending its public key and running
# `kickstart secrets rekey`.
#
# Removing a line stops that host decrypting FUTURE ciphertext. Anything it
# already had a copy of must be rotated.
EOF
    ks_chg "created $(ks_relpath "$rec")"
  fi

  ks_config_set KICKSTART_VAULT "$vault"
  ks_secrets_recipient_add "$id.pub"
  ks_ok "vault ready at $(ks_relpath "$vault")"
}

# ks_secrets_recipient_add <pubkey-file>
ks_secrets_recipient_add() {
  local pub=$1 vault rec key
  vault=$(ks_vault_dir)
  rec="$vault/recipients.txt"
  key=$(awk 'NF {print $1" "$2}' "$pub" | head -1)

  if [ -f "$rec" ] && grep -qF "$key" "$rec"; then
    ks_ok "already a recipient: $(awk '{print $3}' <"$pub")"
    return 0
  fi
  if [ "${KS_DRY_RUN:-0}" = 1 ]; then
    ks_dry "append $KS_HOSTNAME to $(ks_relpath "$rec")"
    return 0
  fi
  printf '%s  # %s\n' "$(cat "$pub")" "$KS_HOSTNAME" >>"$rec"
  ks_chg "added $KS_HOSTNAME as a recipient"
  ks_info "re-encrypt existing secrets to it: kickstart secrets rekey"
}

# _ks_age_recipients -- recipient flags, as a file age can read directly.
_ks_age_recipients() {
  printf '%s' "$(ks_vault_dir)/recipients.txt"
}

ks_secrets_path() {
  printf '%s/%s.age' "$(ks_vault_dir)" "$1"
}

# ks_secrets_ls
ks_secrets_ls() {
  local vault f n
  vault=$(ks_vault_dir)
  [ -d "$vault" ] || ks_die "no vault  -- run: kickstart secrets init"

  n=$(grep -c '^ssh-' "$vault/recipients.txt" 2>/dev/null || printf 0)
  printf '%svault%s %s  (%s recipients)\n\n' \
    "$C_BOLD" "$C_RESET" "$(ks_relpath "$vault")" "$n"
  local found=0
  for f in "$vault"/*.age; do
    [ -f "$f" ] || continue
    found=1
    printf '  %-28s %s\n' "$(basename "$f" .age)" \
      "$(ks_file_mtime "$f")"
  done
  [ "$found" = 1 ] || printf '  (empty -- add one with: kickstart secrets add <name>)\n'
}

ks_file_mtime() {
  if [ "$KS_OS" = darwin ]; then stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null
  else stat -c '%y' "$1" 2>/dev/null | cut -c1-16; fi
}

ks_secrets_recipients() {
  local rec
  rec=$(_ks_age_recipients)
  [ -f "$rec" ] || ks_die "no vault  -- run: kickstart secrets init"
  grep '^ssh-' "$rec" | while IFS= read -r line; do
    printf '  %s\n' "$(printf '%s' "$line" | awk '{print $3, $4, $5}')"
  done
}

# ks_secrets_add <name> [file] -- encrypt stdin, a file, or an editor buffer.
ks_secrets_add() {
  local name=${1:-} src=${2:-}
  [ -n "$name" ] || ks_die "usage: kickstart secrets add <name> [file]"
  ks_vault_require

  local dest tmp
  dest=$(ks_secrets_path "$name")
  if [ -f "$dest" ]; then
    ks_confirm "$name already exists, overwrite?" || return 1
  fi

  if [ -n "$src" ]; then
    [ -f "$src" ] || ks_die "no such file: $src"
    ks_run_age_encrypt "$src" "$dest" || return 1
  elif [ ! -t 0 ]; then
    # Piped in: encrypt stdin directly, never landing on disk.
    age -R "$(_ks_age_recipients)" -o "$dest" || return 1
    ks_chg "encrypted $name (from stdin)"
    return 0
  else
    tmp=$(ks_secure_tmpdir) || return 1
    : >"$tmp/$name"
    "${EDITOR:-vi}" "$tmp/$name"
    if [ ! -s "$tmp/$name" ]; then
      rm -rf "$tmp"
      ks_die "empty, nothing written"
    fi
    ks_run_age_encrypt "$tmp/$name" "$dest"
    rm -rf "$tmp"
  fi
}

ks_run_age_encrypt() {
  local src=$1 dest=$2
  if [ "${KS_DRY_RUN:-0}" = 1 ]; then
    ks_dry "age -R recipients.txt -o $(ks_relpath "$dest")"
    return 0
  fi
  age -R "$(_ks_age_recipients)" -o "$dest" <"$src" || return 1
  ks_chg "encrypted $(basename "$dest" .age)"
}

# ks_secrets_cat <name>
ks_secrets_cat() {
  local name=${1:-}
  [ -n "$name" ] || ks_die "usage: kickstart secrets cat <name>"
  ks_vault_require
  local f
  f=$(ks_secrets_path "$name")
  [ -f "$f" ] || ks_die "no such secret: $name"
  age -d -i "$(ks_vault_identity)" "$f"
}

# ks_secrets_edit <name> -- decrypt to a private tmpdir, edit, re-encrypt.
ks_secrets_edit() {
  local name=${1:-}
  [ -n "$name" ] || ks_die "usage: kickstart secrets edit <name>"
  ks_vault_require
  local f tmp
  f=$(ks_secrets_path "$name")
  [ -f "$f" ] || ks_die "no such secret: $name  (add it with: kickstart secrets add $name)"

  tmp=$(ks_secure_tmpdir) || return 1
  if ! age -d -i "$(ks_vault_identity)" "$f" >"$tmp/$name"; then
    rm -rf "$tmp"
    ks_die "could not decrypt $name -- is this host a recipient?"
  fi
  local before after
  before=$(ks_checksum "$tmp/$name")
  "${EDITOR:-vi}" "$tmp/$name"
  after=$(ks_checksum "$tmp/$name")

  if [ "$before" = "$after" ]; then
    ks_ok "unchanged"
  else
    ks_run_age_encrypt "$tmp/$name" "$f"
  fi
  rm -rf "$tmp"
}

ks_secrets_rm() {
  local name=${1:-}
  [ -n "$name" ] || ks_die "usage: kickstart secrets rm <name>"
  local f
  f=$(ks_secrets_path "$name")
  [ -f "$f" ] || ks_die "no such secret: $name"
  ks_confirm "delete $name from the vault?" || return 1
  ks_run rm -f "$f"
  ks_warn "deleting the ciphertext does not rotate the secret -- do that too"
}

# ks_secrets_rekey -- re-encrypt everything to the current recipient list.
ks_secrets_rekey() {
  ks_vault_require
  local vault f name tmp rc=0
  vault=$(ks_vault_dir)
  tmp=$(ks_secure_tmpdir) || return 1

  for f in "$vault"/*.age; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .age)
    if ! age -d -i "$(ks_vault_identity)" "$f" >"$tmp/$name" 2>/dev/null; then
      ks_error "cannot decrypt $name -- skipping (this host may not be a recipient)"
      rc=1
      continue
    fi
    ks_run_age_encrypt "$tmp/$name" "$f" || rc=1
    rm -f "$tmp/$name"
  done
  rm -rf "$tmp"
  [ "$rc" = 0 ] && ks_ok "rekeyed to $(grep -c '^ssh-' "$vault/recipients.txt") recipients"
  return $rc
}

# ks_secrets_sync [module...] -- materialise SECRETS declarations onto disk.
#
# A module declares:  SECRETS="npm-token:~/.npmrc:0600"
# as <vault name>:<destination>:<mode>, space separated for several.
ks_secrets_sync() {
  local modules="$*" m path spec name dest mode

  [ -n "$modules" ] || modules=$(ks_profile_resolve "$KS_PROFILE")

  for m in $modules; do
    path=$(ks_module_find "$m") || continue
    [ -f "$path/module.sh" ] || continue
    # Read the declaration without executing the module's hooks.
    spec=$(sed -n 's/^SECRETS=["'"'"']\{0,1\}\(.*\)["'"'"']\{0,1\}$/\1/p' "$path/module.sh" |
           head -1 | sed 's/["'"'"']$//')
    [ -n "$spec" ] || continue

    KS_SCOPE=$m
    local entry
    for entry in $spec; do
      name=$(printf '%s' "$entry" | cut -d: -f1)
      dest=$(printf '%s' "$entry" | cut -d: -f2)
      mode=$(printf '%s' "$entry" | cut -d: -f3)
      [ -n "$mode" ] || mode=600
      # Destinations are written as ~/... in module declarations.
      case "$dest" in \~/*) dest="$HOME/${dest#\~/}" ;; esac
      ks_secret_materialise "$name" "$dest" "$mode"
    done
    KS_SCOPE=""
  done
}

ks_secret_materialise() {
  local name=$1 dest=$2 mode=$3 f tmp

  f=$(ks_secrets_path "$name")
  if [ ! -f "$f" ]; then
    ks_skip "secret '$name' not in the vault"
    return 3
  fi
  if ! ks_have age; then
    ks_skip "age not installed, cannot materialise '$name'"
    return 3
  fi
  if [ ! -f "$(ks_vault_identity)" ]; then
    ks_skip "no age identity on this host, cannot materialise '$name'"
    return 3
  fi

  if [ "${KS_DRY_RUN:-0}" = 1 ]; then
    ks_dry "decrypt $name -> $(ks_relpath "$dest") ($mode)"
    return 0
  fi

  ks_mkdir "$(dirname "$dest")"
  tmp="$dest.ks-new"
  if ! age -d -i "$(ks_vault_identity)" "$f" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    ks_warn "cannot decrypt '$name' -- this host is probably not a recipient"
    return 3
  fi
  chmod "$mode" "$tmp"

  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 3
  fi
  mv "$tmp" "$dest"
  ks_chg "secret $name -> $(ks_relpath "$dest")"
  return 0
}

# ks_secure_tmpdir -- a 0700 directory for transient plaintext.
#
# Note: on an SSD, `rm` is not a secure erase. This is a defence against other
# users and stray backups, not against forensic recovery. Do not put anything
# in the vault whose exposure would be catastrophic rather than merely bad.
ks_secure_tmpdir() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/kickstart-secret.XXXXXX") || return 1
  chmod 700 "$d"
  printf '%s' "$d"
}

ks_checksum() {
  if ks_have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  elif ks_have sha256sum; then sha256sum "$1" | awk '{print $1}'
  else wc -c <"$1"; fi
}
