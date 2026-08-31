# shellcheck shell=sh
# gpg-agent as the ssh agent.
#
# Off by default, because pointing SSH_AUTH_SOCK at gpg-agent on a machine
# where gpg is not set up for it breaks every ssh connection, and that is a
# miserable thing to debug remotely. Turn it on per host:
#
#   echo 'KICKSTART_GPG_SSH_AGENT=1' >> ~/.config/kickstart/env

if [ "${KICKSTART_GPG_SSH_AGENT:-0}" = 1 ] && command -v gpgconf >/dev/null 2>&1; then
  SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null)
  if [ -n "$SSH_AUTH_SOCK" ]; then
    export SSH_AUTH_SOCK
    export GPG_TTY="${GPG_TTY:-$(tty 2>/dev/null)}"
    gpgconf --launch gpg-agent 2>/dev/null
  else
    unset SSH_AUTH_SOCK
  fi
fi

#: gpgreload -- restart gpg-agent after it wedges
gpgreload() {
  gpgconf --kill gpg-agent && gpgconf --launch gpg-agent && echo "gpg-agent restarted"
}
