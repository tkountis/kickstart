#!/usr/bin/env bash
# lib/pkg.sh -- thin, boring wrapper over brew / apt / dnf.
#
# Deliberately not an abstraction layer with a plugin system: three managers,
# three cases, one file. If a fourth is ever needed, add a case branch.

KS_PKG_REFRESHED=0

# ks_pkg_refresh -- update package indexes at most once per run.
ks_pkg_refresh() {
  [ "$KS_PKG_REFRESHED" = 1 ] && return 0
  KS_PKG_REFRESHED=1
  [ "${KS_OFFLINE:-0}" = 1 ] && { ks_debug "offline: skipping index refresh"; return 0; }
  case "$KS_PKG" in
    brew) ks_run brew update ;;
    apt)  ks_sudo "$KS_PKG_BIN" update -qq ;;
    dnf)  : ;; # dnf/yum refresh their own metadata per transaction
    *)    : ;;
  esac
}

# ks_pkg_installed <pkg> -- is this package present according to the manager?
ks_pkg_installed() {
  case "$KS_PKG" in
    brew) brew list --formula --versions "$1" >/dev/null 2>&1 ||
          brew list --cask --versions "$1" >/dev/null 2>&1 ;;
    apt)  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$' ;;
    dnf)  rpm -q "$1" >/dev/null 2>&1 ;;
    *)    return 1 ;;
  esac
}

# ks_pkg_install <pkg>... -- install packages one at a time.
# One at a time is slower but means a single bad package name does not take
# down the whole module, and the failing name is obvious in the log.
ks_pkg_install() {
  local pkg rc=0
  [ "$KS_PKG" = none ] && { ks_error "no supported package manager on this host"; return 1; }
  for pkg in "$@"; do
    if ks_pkg_installed "$pkg"; then
      ks_debug "package already installed: $pkg"
      continue
    fi
    if [ "${KS_OFFLINE:-0}" = 1 ] && [ "$KS_PKG" = brew ]; then
      ks_skip "offline: cannot brew install $pkg"
      continue
    fi
    ks_pkg_refresh
    ks_chg "install $pkg"
    case "$KS_PKG" in
      brew) ks_run brew install "$pkg" || rc=1 ;;
      apt)  ks_sudo env DEBIAN_FRONTEND=noninteractive "$KS_PKG_BIN" install -y -qq "$pkg" || rc=1 ;;
      dnf)  ks_sudo "$KS_PKG_BIN" install -y -q "$pkg" || rc=1 ;;
    esac
    [ "$rc" = 1 ] && ks_error "failed to install $pkg"
  done
  return $rc
}

# ks_pkg_install_cask <cask>... -- macOS GUI apps; no-op elsewhere.
ks_pkg_install_cask() {
  [ "$KS_OS" = darwin ] || { ks_debug "not darwin, skipping casks: $*"; return 0; }
  local c
  for c in "$@"; do
    if brew list --cask --versions "$c" >/dev/null 2>&1; then continue; fi
    ks_chg "install cask $c"
    ks_run brew install --cask "$c" || ks_warn "failed to install cask $c"
  done
}

# ks_pkg_bootstrap -- make sure we have a usable package manager.
ks_pkg_bootstrap() {
  case "$KS_OS" in
    darwin)
      ks_have brew && return 0
      [ "${KS_OFFLINE:-0}" = 1 ] && { ks_warn "offline: cannot install Homebrew"; return 1; }
      ks_step "installing Homebrew"
      ks_run /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" ||
        return 1
      local p
      for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$p" ] && eval "$("$p" shellenv)" && break
      done
      ks_have brew
      ;;
    linux)
      [ "$KS_PKG" = none ] && { ks_error "no apt/dnf/brew found"; return 1; }
      return 0
      ;;
  esac
}
