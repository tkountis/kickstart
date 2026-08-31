#!/usr/bin/env bash
# lib/profile.sh -- profiles are plain lists of module names.
#
#   # profiles/personal.profile
#   @include base
#   direnv
#   macos-defaults
#
# Lines are module names, `#` starts a comment, `@include <profile>` pulls in
# another profile. Overlays can add their own profiles, or extend a core one by
# shipping a profile of the same name that `@include`s nothing -- lookup finds
# the overlay copy first, so `@include base` from there still resolves to core.

# ks_profile_find <name> -- echo path to the profile file.
ks_profile_find() {
  local name=$1 dir
  for dir in $KS_SEARCH_DIRS; do
    [ -f "$dir/profiles/$name.profile" ] && { printf '%s' "$dir/profiles/$name.profile"; return 0; }
  done
  return 1
}

ks_profile_list() {
  local dir
  for dir in $KS_SEARCH_DIRS; do
    [ -d "$dir/profiles" ] || continue
    # shellcheck disable=SC2012  # profile names are ours; no exotic filenames
    ls -1 "$dir/profiles" 2>/dev/null | sed -n 's/\.profile$//p'
  done | sort -u
}

# ks_profile_resolve <name> -- print module names, one per line, in order,
# deduplicated, with includes expanded. Cycles are reported, not fatal.
ks_profile_resolve() {
  _ks_profile_expand "$1" "" | awk '!seen[$0]++'
}

_ks_profile_expand() {
  local name=$1 seen=$2 file line
  case " $seen " in
    *" $name "*) ks_warn "profile include cycle at '$name', ignoring"; return 0 ;;
  esac
  seen="$seen $name"

  file=$(ks_profile_find "$name") || { ks_error "unknown profile: $name"; return 1; }
  ks_debug "profile $name -> $file"

  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    # trim
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in
      '@include '*) _ks_profile_expand "${line#@include }" "$seen" ;;
      '@'*)         ks_warn "unknown directive in $name.profile: $line" ;;
      *)            printf '%s\n' "$line" ;;
    esac
  done <"$file"
}
