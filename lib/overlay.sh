#!/usr/bin/env bash
# lib/overlay.sh -- private repos layered on top of the public one.
#
# Work tooling lives in a separate private repo with exactly the same layout
# (modules/, profiles/, shell/source/). Nothing internal ever lands in the
# public repo, and there is no second mechanism to learn.
#
#   kickstart overlay add git@github.com:you/kickstart-work.git
#
# Overlays are searched *before* core, so an overlay can also override a core
# module by shipping a directory with the same name.

KS_OVERLAY_DIR="$KS_DATA_DIR/overlays"

# ks_config_get <key> [default]
ks_config_get() {
  local key=$1 def=${2:-}
  [ -f "$KS_CONFIG_FILE" ] || { printf '%s' "$def"; return 0; }
  local val
  val=$(sed -n "s/^${key}=//p" "$KS_CONFIG_FILE" | tail -1)
  # strip optional surrounding quotes
  val=${val%\"}; val=${val#\"}
  [ -z "$val" ] && val=$def
  printf '%s' "$val"
}

# ks_config_set <key> <value>
ks_config_set() {
  local key=$1 val=$2 tmp
  ks_mkdir "$(dirname "$KS_CONFIG_FILE")"
  [ -f "$KS_CONFIG_FILE" ] || {
    printf '# kickstart host configuration -- edit freely, it is just shell.\n' >"$KS_CONFIG_FILE"
  }
  tmp=$(ks_mktemp)
  grep -v "^${key}=" "$KS_CONFIG_FILE" >"$tmp" 2>/dev/null || true
  printf '%s="%s"\n' "$key" "$val" >>"$tmp"
  cat "$tmp" >"$KS_CONFIG_FILE"
  rm -f "$tmp"
  ks_debug "config: $key=$val"
}

# ks_overlay_names -- names of configured overlays.
ks_overlay_names() {
  [ -d "$KS_OVERLAY_DIR" ] || return 0
  ls -1 "$KS_OVERLAY_DIR" 2>/dev/null
}

# ks_overlay_dirs -- absolute paths, one per line.
ks_overlay_dirs() {
  local n
  for n in $(ks_overlay_names); do
    [ -d "$KS_OVERLAY_DIR/$n" ] && printf '%s\n' "$KS_OVERLAY_DIR/$n"
  done
}

# ks_overlay_add <git-url> [name]
ks_overlay_add() {
  local url=$1 name=${2:-}
  [ -n "$url" ] || ks_die "usage: kickstart overlay add <git-url> [name]"
  if [ -z "$name" ]; then
    name=$(basename "$url"); name=${name%.git}
  fi
  local dest="$KS_OVERLAY_DIR/$name"
  if [ -d "$dest/.git" ]; then
    ks_info "overlay '$name' already present at $(ks_relpath "$dest")"
    return 0
  fi
  ks_mkdir "$KS_OVERLAY_DIR"
  ks_step "cloning overlay '$name' from $url"
  ks_run git clone --depth 1 "$url" "$dest" || ks_die "clone failed"
  ks_overlay_submodules "$dest"
  ks_ok "overlay '$name' added"
}

# ks_overlay_submodules <dir> -- best effort. Overlays commonly vendor internal
# completion scripts as submodules whose host is only reachable on the VPN;
# failing to fetch them must not make the whole overlay unusable.
ks_overlay_submodules() {
  local dir=$1
  [ -f "$dir/.gitmodules" ] || return 0
  [ "${KS_OFFLINE:-0}" = 1 ] && { ks_skip "offline: not fetching submodules"; return 0; }
  ks_run git -C "$dir" submodule update --init --recursive --depth 1 ||
    ks_warn "could not fetch submodules for $(basename "$dir") -- the overlay still works, anything that depends on vendor/ will not"
}

# ks_overlay_remove <name>
ks_overlay_remove() {
  local dest="$KS_OVERLAY_DIR/$1"
  [ -d "$dest" ] || ks_die "no such overlay: $1"
  ks_confirm "remove overlay '$1' at $(ks_relpath "$dest")?" || return 0
  ks_run rm -rf "$dest"
  ks_ok "overlay '$1' removed"
}

# ks_overlay_update -- git pull every overlay.
ks_overlay_update() {
  local d
  for d in $(ks_overlay_dirs); do
    ks_step "updating overlay $(basename "$d")"
    ks_run git -C "$d" pull --ff-only --quiet || ks_warn "pull failed for $(basename "$d")"
    ks_overlay_submodules "$d"
  done
}

# ks_search_dirs_init -- overlays first (they win), then core.
ks_search_dirs_init() {
  KS_SEARCH_DIRS=""
  local d
  for d in $(ks_overlay_dirs); do
    KS_SEARCH_DIRS="$KS_SEARCH_DIRS $d"
  done
  KS_SEARCH_DIRS="$KS_SEARCH_DIRS $KS_ROOT"
  export KS_SEARCH_DIRS
  ks_debug "search dirs:$KS_SEARCH_DIRS"
}
