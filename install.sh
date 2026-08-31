#!/usr/bin/env bash
#
# kickstart bootstrap.
#
#   curl -fsSL https://raw.githubusercontent.com/tkountis/kickstart/main/install.sh | bash
#
# With options (note the `-s --` which passes them through to this script):
#
#   curl -fsSL .../install.sh | bash -s -- --profile work \
#        --overlay git@github.com:tkountis/kickstart-work.git
#
# This script is intentionally standalone: it does not source anything from the
# repo, because at the point it runs the repo may not exist yet. It only does
# three things -- get git, clone the repo, and hand over to `kickstart apply`.

set -euo pipefail

REPO=${KICKSTART_REPO:-https://github.com/tkountis/kickstart.git}
BRANCH=${KICKSTART_BRANCH:-main}
ROOT=${KICKSTART_ROOT:-$HOME/.kickstart}
PROFILE=""
OVERLAY=""
DO_APPLY=1
EXTRA_ARGS=""

if [ -t 2 ]; then
  R=$'\033[0m'; B=$'\033[1m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; BLU=$'\033[34m'
else
  R=''; B=''; GRN=''; YLW=''; RED=''; BLU=''
fi
say()  { printf '%s==>%s %s\n' "$BLU" "$R" "$*" >&2; }
ok()   { printf '%s ok %s %s\n' "$GRN" "$R" "$*" >&2; }
warn() { printf '%swarn%s %s\n' "$YLW" "$R" "$*" >&2; }
die()  { printf '%serr %s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
kickstart bootstrap

  --profile <name>    Profile to activate (personal, work, minimal, ...)
  --overlay <url>     Private overlay repo to add before applying
  --root <path>       Where to clone kickstart (default ~/.kickstart)
  --branch <name>     Branch to track (default main)
  --repo <url>        Source repository
  --no-apply          Clone and configure, but do not install anything
  --dry-run           Pass --dry-run through to kickstart apply
  -h, --help          This text
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) shift; PROFILE=${1:-} ;;
    --profile=*) PROFILE=${1#--profile=} ;;
    --overlay) shift; OVERLAY=${1:-} ;;
    --overlay=*) OVERLAY=${1#--overlay=} ;;
    --root) shift; ROOT=${1:-} ;;
    --branch) shift; BRANCH=${1:-} ;;
    --repo) shift; REPO=${1:-} ;;
    --no-apply) DO_APPLY=0 ;;
    --dry-run|-n) EXTRA_ARGS="$EXTRA_ARGS --dry-run" ;;
    -v|--verbose) EXTRA_ARGS="$EXTRA_ARGS --verbose" ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- prereqs ---

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  say "git is missing, installing it"

  # Container images often run as root with no sudo installed.
  local SUDO=""
  if [ "$(id -u)" != 0 ]; then
    command -v sudo >/dev/null 2>&1 ||
      die "git is missing and this account cannot sudo; install git and re-run"
    SUDO=sudo
  fi

  case "$(uname -s)" in
    Darwin)
      # Command Line Tools ships git. This opens a GUI prompt and returns
      # immediately, so we have to wait for the user to finish.
      xcode-select --install 2>/dev/null || true
      warn "accept the Command Line Tools prompt, then re-run this installer"
      exit 1
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git
      elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y -q git
      elif command -v yum >/dev/null 2>&1; then
        $SUDO yum install -y -q git
      else
        die "no supported package manager found; install git and re-run"
      fi
      ;;
    *) die "unsupported platform: $(uname -s)" ;;
  esac
  command -v git >/dev/null 2>&1 || die "git still not available"
}

# ------------------------------------------------------------------- main ---

printf '\n%skickstart%s -- %s\n\n' "$B" "$R" "$REPO"

ensure_git

if [ -d "$ROOT/.git" ]; then
  say "updating existing checkout at $ROOT"
  git -C "$ROOT" fetch --quiet origin "$BRANCH" ||
    warn "fetch failed; continuing with what is on disk"
  git -C "$ROOT" checkout --quiet "$BRANCH" 2>/dev/null || true
  git -C "$ROOT" merge --ff-only --quiet "origin/$BRANCH" 2>/dev/null ||
    warn "could not fast-forward (local changes?); continuing"
elif [ -e "$ROOT" ]; then
  die "$ROOT exists but is not a git checkout -- move it aside and re-run"
else
  say "cloning into $ROOT"
  git clone --branch "$BRANCH" --quiet "$REPO" "$ROOT" || die "clone failed"
fi

ok "kickstart is at $ROOT"

KS="$ROOT/bin/kickstart"
chmod +x "$KS" "$ROOT"/shell/khelp.sh 2>/dev/null || true
[ -x "$KS" ] || die "$KS is not executable"

if [ -n "$PROFILE" ]; then
  "$KS" profile "$PROFILE" || die "could not set profile '$PROFILE'"
fi

if [ -n "$OVERLAY" ]; then
  say "adding overlay $OVERLAY"
  "$KS" overlay add "$OVERLAY" ||
    warn "overlay add failed (ssh key not set up yet?) -- add it later with: kickstart overlay add $OVERLAY"
fi

if [ "$DO_APPLY" = 1 ]; then
  # shellcheck disable=SC2086
  "$KS" apply $EXTRA_ARGS || die "apply failed -- re-run with: $KS apply -v"
else
  warn "--no-apply given; run '$KS apply' when ready"
fi

cat <<EOF

${B}next${R}
  exec \$SHELL -l          reload your shell
  khelp                   list every shell helper you have
  kickstart status        what this host is set up as
  kickstart doctor        check for problems

EOF
