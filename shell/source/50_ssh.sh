# shellcheck shell=sh
# ssh and remote-box helpers.

#: kpush <host> [opts] -- install kickstart on a remote host over ssh
kpush() { "$KICKSTART_ROOT/bin/kickstart" push "$@"; }

#: sshkey [comment] -- create this host's ed25519 key if it does not exist
# Private keys are generated per host and never leave it. Only the public half
# is meant to travel. See docs/secrets.md.
sshkey() {
  _key="$HOME/.ssh/id_ed25519"
  if [ -f "$_key" ]; then
    echo "key already exists: $_key"
  else
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -a 100 -C "${1:-$(whoami)@$(hostname -s)-$(date +%Y%m)}" -f "$_key" ||
      { unset _key; return 1; }
  fi
  echo
  echo "public key (add this to GitHub / authorized_keys):"
  cat "$_key.pub"
  unset _key
}

#: sshcp <host> -- copy this host's public key to a remote authorized_keys
sshcp() {
  [ -n "${1:-}" ] || { echo "usage: sshcp <host>" >&2; return 2; }
  if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id "$1"
  else
    ssh "$1" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys' \
      <"$HOME/.ssh/id_ed25519.pub"
  fi
}

#: sshfp <host> -- show a remote host's key fingerprints
sshfp() {
  [ -n "${1:-}" ] || { echo "usage: sshfp <host>" >&2; return 2; }
  ssh-keyscan -t ed25519,rsa "$1" 2>/dev/null | ssh-keygen -lf -
}

#: sshforget <host> -- drop a host from known_hosts (after a rebuild)
sshforget() {
  [ -n "${1:-}" ] || { echo "usage: sshforget <host>" >&2; return 2; }
  ssh-keygen -R "$1"
}
