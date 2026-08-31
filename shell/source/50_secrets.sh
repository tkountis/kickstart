# shellcheck shell=sh
# Secrets and key helpers. Thin wrappers so the common operations are short
# enough to actually use. The real work is in `kickstart secrets` / `keys`.

#: secrets [pattern] -- list what is in the vault
secrets() { "$KICKSTART_ROOT/bin/kickstart" secrets ls "$@"; }

#: secret <name> -- print one secret to stdout (careful with your scrollback)
secret() { "$KICKSTART_ROOT/bin/kickstart" secrets cat "$@"; }

#: secedit <name> -- decrypt to a private tmpdir, edit, re-encrypt
secedit() { "$KICKSTART_ROOT/bin/kickstart" secrets edit "$@"; }

#: secenv <name> -- eval a secret's KEY=value lines into the current shell
# The secret never touches disk. Use for short-lived tokens:  secenv npm-token
secenv() {
  [ -n "${1:-}" ] || { echo "usage: secenv <name>" >&2; return 2; }
  _s=$("$KICKSTART_ROOT/bin/kickstart" secrets cat "$1") || { unset _s; return 1; }
  eval "$(printf '%s\n' "$_s" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=/export \1=/p')"
  unset _s
  echo "exported from '$1'"
}

#: keys -- what ssh keys does this host have, and are they in the agent
keys() { "$KICKSTART_ROOT/bin/kickstart" keys status; }
