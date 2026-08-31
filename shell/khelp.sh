#!/usr/bin/env bash
# shell/khelp.sh -- print every documented shell helper.
#
# The registry is the code: any line of the form
#
#   #: name -- what it does
#
# in a shell/source/*.sh file (kickstart's or an overlay's) shows up here.
# That is the whole discoverability mechanism. No index to keep in sync.

set -uo pipefail

ROOT="${KICKSTART_ROOT:-$HOME/.kickstart}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/kickstart"
FILTER="${1:-}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; D=$'\033[2m'; C=$'\033[36m'; R=$'\033[0m'
else
  B=''; D=''; C=''; R=''
fi

dirs() {
  printf '%s\n' "$ROOT/shell/source"
  [ -d "$DATA/overlays" ] && ls -d "$DATA"/overlays/*/shell/source 2>/dev/null
}

found=0
while IFS= read -r dir; do
  [ -d "$dir" ] || continue
  origin=""
  case "$dir" in "$DATA"/overlays/*)
    origin=$(printf '%s' "${dir#"$DATA"/overlays/}" | cut -d/ -f1) ;;
  esac

  for f in "$dir"/*.sh; do
    [ -f "$f" ] || continue
    entries=$(sed -n 's/^#:[[:space:]]*//p' "$f")
    [ -z "$entries" ] && continue
    if [ -n "$FILTER" ]; then
      # A filter matching the filename shows the whole topic ("khelp git" ->
      # everything in 30_git.sh). Otherwise it filters individual entries.
      if ! printf '%s' "$(basename "$f")" | grep -qi -- "$FILTER"; then
        entries=$(printf '%s\n' "$entries" | grep -i -- "$FILTER") || continue
      fi
    fi
    [ -z "$entries" ] && continue

    found=1
    if [ -n "$origin" ]; then
      printf '\n%s%s%s %s(%s)%s\n' "$B" "$(basename "$f")" "$R" "$D" "$origin" "$R"
    else
      printf '\n%s%s%s\n' "$B" "$(basename "$f")" "$R"
    fi
    printf '%s\n' "$entries" | while IFS= read -r line; do
      name=${line%%--*}
      desc=${line#*--}
      if [ "$name" = "$line" ]; then
        printf '  %s\n' "$line"
      else
        # trim trailing/leading spaces without invoking sed per line
        while [ "${name% }" != "$name" ]; do name=${name% }; done
        while [ "${desc# }" != "$desc" ]; do desc=${desc# }; done
        printf '  %s%-24s%s %s\n' "$C" "$name" "$R" "$desc"
      fi
    done
  done
done <<EOF
$(dirs)
EOF

if [ "$found" = 0 ]; then
  if [ -n "$FILTER" ]; then
    printf 'no helpers matching %s\n' "$FILTER" >&2
  else
    printf 'no documented helpers found under %s\n' "$ROOT/shell/source" >&2
  fi
  exit 1
fi
printf '\n%sadd one with:%s knew <topic>   %sthen document it with a #: line%s\n' \
  "$D" "$R" "$D" "$R"
