#!/usr/bin/env bash
# lib/platform.sh -- detect what box we are on.
#
# Exports (all lowercase values, always set):
#   KS_OS        darwin | linux
#   KS_ARCH      arm64 | amd64 | <uname -m>
#   KS_DISTRO    darwin | ubuntu | debian | fedora | rhel | amzn | arch | unknown
#   KS_FAMILY    darwin | debian | rhel | arch | unknown
#   KS_PKG       brew | apt | dnf | none
#   KS_HOSTNAME  short hostname
#   KS_FQDN      best-effort fully qualified name

ks_detect_platform() {
  case "$(uname -s)" in
    Darwin) KS_OS=darwin ;;
    Linux)  KS_OS=linux ;;
    *)      ks_die "unsupported OS: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    arm64|aarch64) KS_ARCH=arm64 ;;
    x86_64|amd64)  KS_ARCH=amd64 ;;
    *)             KS_ARCH=$(uname -m) ;;
  esac

  KS_DISTRO=unknown
  KS_FAMILY=unknown
  if [ "$KS_OS" = darwin ]; then
    KS_DISTRO=darwin
    KS_FAMILY=darwin
  elif [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    KS_DISTRO=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
    local like
    like=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
    case "$KS_DISTRO $like" in
      *debian*|*ubuntu*) KS_FAMILY=debian ;;
      *rhel*|*fedora*|*centos*|*amzn*) KS_FAMILY=rhel ;;
      *arch*) KS_FAMILY=arch ;;
    esac
  fi

  # Package manager. Homebrew wins on macOS; on Linux the native manager wins
  # (it works without internet against internal mirrors, brew does not), but
  # brew is still usable as a fallback for user-space installs.
  KS_PKG=none
  if [ "$KS_OS" = darwin ]; then
    KS_PKG=brew
  elif ks_have apt-get; then
    KS_PKG=apt
  elif ks_have dnf; then
    KS_PKG=dnf
  elif ks_have yum; then
    KS_PKG=dnf
  elif ks_have brew; then
    KS_PKG=brew
  fi

  # Linuxbrew may be installed but not yet on PATH.
  if [ "$KS_OS" = linux ] && ! ks_have brew; then
    for p in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
      [ -x "$p" ] && eval "$("$p" shellenv)" && break
    done
  fi

  KS_HOSTNAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')
  KS_FQDN=$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf '%s' "$KS_HOSTNAME")

  export KS_OS KS_ARCH KS_DISTRO KS_FAMILY KS_PKG KS_HOSTNAME KS_FQDN
  ks_debug "platform: os=$KS_OS arch=$KS_ARCH distro=$KS_DISTRO family=$KS_FAMILY pkg=$KS_PKG host=$KS_HOSTNAME"
}

# ks_platform_summary -- one line, for `status` / `doctor`.
ks_platform_summary() {
  printf '%s/%s (%s, pkg=%s) on %s' \
    "$KS_OS" "$KS_ARCH" "$KS_DISTRO" "$KS_PKG" "$KS_HOSTNAME"
}
