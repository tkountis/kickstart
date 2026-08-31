#!/usr/bin/env bash
#
# test/docker.sh -- run the real bootstrap inside a disposable Linux container.
#
# This is the only harness that isolates *everything*, package installs
# included, and the only one that exercises the Linux code paths from a Mac.
#
#   ./test/docker.sh                       # ubuntu, full apply, report
#   ./test/docker.sh --image debian:12
#   ./test/docker.sh --image fedora:41 --profile base
#   ./test/docker.sh --shell               # interactive shell in the container
#   ./test/docker.sh --all                 # every image, sequentially
#   ./test/docker.sh --offline             # apply as if there were no internet
#
# The container gets your working tree (tracked + untracked, respecting
# .gitignore), so uncommitted changes are what gets tested. Nothing on the host
# is touched. The container is removed on exit.

# Literal $HOME and backticks appear in help text below; they are meant to be
# read, not expanded.
# shellcheck disable=SC2016
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

IMAGES="ubuntu:24.04"
ALL_IMAGES="ubuntu:24.04 debian:12 fedora:41"
PROFILE=base
DO_SHELL=0
OFFLINE=0
AS_ROOT=0

if [ -t 1 ]; then
  B=$'\033[1m'; D=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'
  RED=$'\033[31m'; CYN=$'\033[36m'; R=$'\033[0m'
else
  B=''; D=''; GRN=''; YLW=''; RED=''; CYN=''; R=''
fi
die() { printf '%serror%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --image)   shift; IMAGES=${1:-} ;;
    --all)     IMAGES=$ALL_IMAGES ;;
    --profile) shift; PROFILE=${1:-} ;;
    --shell)   DO_SHELL=1 ;;
    --offline) OFFLINE=1 ;;
    --root)    AS_ROOT=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

command -v docker >/dev/null 2>&1 || die "docker is not installed"
if ! docker info >/dev/null 2>&1; then
  printf '%sdocker is installed but the daemon is not running%s\n' "$YLW" "$R" >&2
  printf 'Start Docker Desktop (or `colima start`) and try again.\n' >&2
  printf '\n%sWithout docker you can still use:%s\n' "$D" "$R" >&2
  printf '  ./test/smoke.sh        assertions against a throwaway $HOME\n' >&2
  printf '  ./test/sandbox.sh      interactive throwaway $HOME (no installs)\n' >&2
  exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kickstart-docker.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Package the working tree, not the git HEAD: the point is to test what you are
# about to commit.
( cd "$ROOT" && git ls-files -co --exclude-standard -z |
    tar czf "$TMP/kickstart.tgz" --null -T - ) 2>/dev/null ||
  die "could not package the working tree"

# The in-container script. Deliberately does the same things a human would:
# create an unprivileged user, run install.sh, then poke at the result.
cat >"$TMP/run.sh" <<'CONTAINER'
set -u

RED=$'\033[31m'; GRN=$'\033[32m'; CYN=$'\033[36m'; YLW=$'\033[33m'; R=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$CYN" "$R" "$*"; }
ok()   { printf '  %sok%s   %s\n' "$GRN" "$R" "$*"; }
bad()  { printf '  %sFAIL%s %s\n' "$RED" "$R" "$*"; FAILED=$((FAILED+1)); }
FAILED=0

say "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") / $(uname -m)"

# Prerequisites a real image would already have, or that install.sh installs.
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq git ca-certificates sudo zsh curl >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q git sudo zsh curl findutils >/dev/null 2>&1
fi

# An unprivileged user with sudo, which is the realistic case.
if [ "${AS_ROOT:-0}" != 1 ]; then
  id ks >/dev/null 2>&1 || useradd -m -s /bin/bash ks
  echo 'ks ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/ks
  mkdir -p /home/ks/src && tar xzf /payload/kickstart.tgz -C /home/ks/src
  chown -R ks:ks /home/ks
  exec su ks -c "HOME=/home/ks AS_ROOT=1 PROFILE=$PROFILE OFFLINE=$OFFLINE DO_SHELL=${DO_SHELL:-0} bash /payload/run.sh"
fi

cd "$HOME" || exit 1
SRC="$HOME/src"
[ -d "$SRC" ] || { mkdir -p "$SRC" && tar xzf /payload/kickstart.tgz -C "$SRC"; }
chmod +x "$SRC/install.sh" "$SRC/bin/kickstart" "$SRC/shell/khelp.sh" 2>/dev/null

say "bootstrap via install.sh"
if "$SRC/install.sh" --repo "file://$SRC" --root "$HOME/.kickstart" \
     --profile "$PROFILE" --no-apply >/tmp/boot.log 2>&1; then
  ok "install.sh clone + profile"
else
  bad "install.sh"
  sed 's/^/       /' /tmp/boot.log | tail -30
fi

KS="$HOME/.kickstart/bin/kickstart"
APPLY_FLAGS="-y"
[ "$OFFLINE" = 1 ] && APPLY_FLAGS="$APPLY_FLAGS --offline"

say "apply $APPLY_FLAGS"
"$KS" apply $APPLY_FLAGS 2>&1 | sed 's/^/       /'

say "platform detection"
"$KS" version 2>&1 | sed 's/^/       /'

say "idempotency"
second=$("$KS" apply $APPLY_FLAGS 2>&1)
if printf '%s' "$second" | grep -q 'done: 0 changed'; then
  ok "re-apply is a no-op"
else
  bad "re-apply changed things"
  printf '%s\n' "$second" | grep -E '^\[|done:' | sed 's/^/       /'
fi

say "doctor"
"$KS" doctor 2>&1 | sed 's/^/       /'

say "login shells reach kickstart"
for sh in bash zsh; do
  command -v $sh >/dev/null 2>&1 || { printf '  skip %s\n' "$sh"; continue; }
  if $sh -l -i -c 'command -v khelp >/dev/null && command -v mkcd >/dev/null' >/dev/null 2>&1; then
    ok "$sh -l"
  else
    bad "$sh -l did not load kickstart"
  fi
done

say "the Debian fd/bat rename is shimmed"
if command -v fdfind >/dev/null 2>&1; then
  command -v fd >/dev/null 2>&1 && ok "fd -> fdfind shim" || bad "fd shim missing"
fi
if command -v batcat >/dev/null 2>&1; then
  command -v bat >/dev/null 2>&1 && ok "bat -> batcat shim" || bad "bat shim missing"
fi

say "helpers work"
bash -l -i -c 'mkcd /tmp/probe && [ "$PWD" = /tmp/probe ]' >/dev/null 2>&1 &&
  ok "mkcd" || bad "mkcd"
bash -l -i -c 'khelp >/dev/null' >/dev/null 2>&1 && ok "khelp" || bad "khelp"

printf '\n'
if [ "$FAILED" = 0 ]; then
  printf '%sall container checks passed%s\n' "$GRN" "$R"
else
  printf '%s%d container check(s) failed%s\n' "$RED" "$FAILED" "$R"
fi

if [ "$DO_SHELL" = 1 ]; then
  printf '\n%sinteractive shell -- exit to destroy the container%s\n\n' "$YLW" "$R"
  exec bash -l
fi
exit "$FAILED"
CONTAINER

# ------------------------------------------------------------------- run ----

overall=0
for image in $IMAGES; do
  printf '\n%s%s%s\n' "$B" "════ $image ════" "$R"
  docker_args="--rm -v $TMP:/payload:ro -e PROFILE=$PROFILE -e OFFLINE=$OFFLINE"
  [ "$DO_SHELL" = 1 ] && docker_args="$docker_args -it"
  [ "$DO_SHELL" = 1 ] && docker_args="$docker_args -e DO_SHELL=1"
  # Note: no --network none. The scenario that matters is "cannot reach the
  # internet, but the distro mirror works" -- which is what a locked-down
  # corporate box looks like, and what `kickstart push` assumes. Cutting the
  # network entirely would just fail to install git and prove nothing.

  # shellcheck disable=SC2086
  docker run $docker_args "$image" bash /payload/run.sh || overall=1
done

printf '\n'
if [ "$overall" = 0 ]; then
  printf '%sdone%s\n' "$GRN" "$R"
else
  printf '%sone or more images reported failures%s\n' "$RED" "$R"
fi
exit "$overall"
