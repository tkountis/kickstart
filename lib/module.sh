#!/usr/bin/env bash
# lib/module.sh -- find, describe and apply modules.
#
# A module is a directory containing `module.sh`. In the common case that file
# is pure declaration and defines no functions at all:
#
#   DESC="Fast recursive grep"
#   PROVIDES="rg"
#   PKG_BREW="ripgrep"
#   PKG_APT="ripgrep"
#   PKG_DNF="ripgrep"
#
# See docs/modules.md for the full contract. Everything is optional; a module
# that only ships dotfiles needs nothing but a `files/` directory.
#
# Apply order for one module:
#   1. requirements  (REQUIRES_OS / REQUIRES_PROFILE / REQUIRES_CMD / NET)
#   2. check         (ks_check, else all PROVIDES binaries present)
#   3. install       (ks_install, else PKG_<MGR> + CASK)
#   4. link          (files/, files.$KS_OS/)
#   5. configure     (ks_configure -- always runs, must be idempotent)
#
# Each module runs in a subshell so a stray `cd`, `set -x` or variable cannot
# leak into the next one. Status comes back as an exit code:
#   0 changed   3 already ok   4 skipped   1 failed

# Module declarations are set inside the per-module subshell and read by the
# default check/install helpers, which are called from that same subshell.
# shellcheck disable=SC2030,SC2031
KS_RC_CHANGED=0
KS_RC_OK=3
KS_RC_SKIP=4
KS_RC_FAIL=1

# ks_module_find <name> -- echo the module directory, or fail.
ks_module_find() {
  local name=$1 dir
  for dir in $KS_SEARCH_DIRS; do
    if [ -f "$dir/modules/$name/module.sh" ] || [ -d "$dir/modules/$name/files" ]; then
      printf '%s' "$dir/modules/$name"
      return 0
    fi
  done
  return 1
}

# ks_module_list -- every known module name, deduplicated, sorted.
ks_module_list() {
  local dir
  for dir in $KS_SEARCH_DIRS; do
    [ -d "$dir/modules" ] || continue
    ls -1 "$dir/modules" 2>/dev/null
  done | sort -u
}

# ks_module_desc <name> -- one-line description without executing hooks.
ks_module_desc() {
  local path
  path=$(ks_module_find "$1") || { printf '(not found)'; return 1; }
  [ -f "$path/module.sh" ] || { printf 'dotfiles only'; return 0; }
  sed -n 's/^DESC=["'"'"']\{0,1\}\(.*\)["'"'"']\{0,1\}$/\1/p' "$path/module.sh" |
    head -1 | sed 's/["'"'"']$//'
}

# ks_module_apply <name>
ks_module_apply() {
  local name=$1 path
  path=$(ks_module_find "$name") || { ks_error "unknown module: $name"; return "$KS_RC_FAIL"; }

  (
    set -u
    KS_SCOPE=$name
    KS_MODULE_DIR=$path
    export KS_MODULE_DIR

    DESC=""; TAGS=""; PROVIDES=""
    PKG_BREW=""; PKG_APT=""; PKG_DNF=""; CASK=""
    REQUIRES_OS=""; REQUIRES_PROFILE=""; REQUIRES_CMD=""; NET=0

    if [ -f "$path/module.sh" ]; then
      # shellcheck disable=SC1090
      . "$path/module.sh" || { ks_error "module.sh failed to load"; exit "$KS_RC_FAIL"; }
    fi

    # -- 1. requirements ----------------------------------------------------
    if [ -n "$REQUIRES_OS" ] && ! ks_contains "$KS_OS" "$REQUIRES_OS"; then
      ks_skip "requires os: $REQUIRES_OS"; exit "$KS_RC_SKIP"
    fi
    if [ -n "$REQUIRES_PROFILE" ] && ! ks_contains "$KS_PROFILE" "$REQUIRES_PROFILE"; then
      ks_skip "requires profile: $REQUIRES_PROFILE"; exit "$KS_RC_SKIP"
    fi
    for c in $REQUIRES_CMD; do
      ks_have "$c" || { ks_skip "requires command: $c"; exit "$KS_RC_SKIP"; }
    done
    if [ "$NET" = 1 ] && [ "${KS_OFFLINE:-0}" = 1 ]; then
      ks_skip "needs direct internet, running offline"; exit "$KS_RC_SKIP"
    fi

    changed=0

    # -- 2/3. check + install ----------------------------------------------
    if [ "${KS_FILES_ONLY:-0}" = 1 ]; then
      ks_debug "files-only: skipping install"
    elif ks_module_is_installed; then
      ks_debug "already installed"
    else
      if ! ks_module_do_install; then
        ks_error "install failed"; exit "$KS_RC_FAIL"
      fi
      changed=1
    fi

    # -- 4. link ------------------------------------------------------------
    ks_link_tree "$path/files" && changed=1
    ks_link_tree "$path/files.$KS_OS" && changed=1

    # -- 5. configure -------------------------------------------------------
    if ks_is_function ks_configure; then
      if ks_configure; then :; else
        rc=$?
        if [ "$rc" = "$KS_RC_OK" ]; then :; else
          ks_error "configure failed (rc=$rc)"; exit "$KS_RC_FAIL"
        fi
      fi
      # A configure hook that made a change signals it by calling ks_touched.
      [ -n "${KS_TOUCHED:-}" ] && changed=1
    fi

    [ "$changed" = 1 ] && exit "$KS_RC_CHANGED"
    exit "$KS_RC_OK"
  )
}

# ---- helpers available to module.sh hooks ----------------------------------

# ks_touched -- call from ks_configure when it actually changed something.
ks_touched() { KS_TOUCHED=1; }

ks_is_function() { [ "$(type -t "$1" 2>/dev/null)" = function ]; }

# Default "is it installed?" -- every binary in PROVIDES is on PATH.
ks_module_is_installed() {
  if ks_is_function ks_check; then ks_check; return $?; fi
  [ -n "$PROVIDES" ] || return 1   # nothing declared: let install decide
  local c
  for c in $PROVIDES; do ks_have "$c" || return 1; done
  return 0
}

# Default install -- packages for the detected manager, plus casks.
ks_module_do_install() {
  if ks_is_function ks_install; then ks_install; return $?; fi

  local var pkgs
  var="PKG_$(ks_upper "$KS_PKG")"
  pkgs=${!var:-}

  if [ -z "$pkgs" ] && [ -z "$CASK" ]; then
    ks_warn "nothing to install for pkg=$KS_PKG (no $var declared)"
    return 0
  fi

  local rc=0
  # shellcheck disable=SC2086
  [ -n "$pkgs" ] && { ks_pkg_install $pkgs || rc=1; }
  # shellcheck disable=SC2086
  [ -n "$CASK" ] && ks_pkg_install_cask $CASK
  return $rc
}

# ks_module_tally <rc> <name> -- fold a module result into the run summary.
ks_module_tally() {
  case "$1" in
    "$KS_RC_CHANGED") KS_N_CHANGED=$((KS_N_CHANGED + 1)) ;;
    "$KS_RC_OK")      KS_N_OK=$((KS_N_OK + 1)) ;;
    "$KS_RC_SKIP")    KS_N_SKIPPED=$((KS_N_SKIPPED + 1)) ;;
    *)                KS_N_FAILED=$((KS_N_FAILED + 1))
                      KS_FAILED_NAMES="$KS_FAILED_NAMES $2" ;;
  esac
}
