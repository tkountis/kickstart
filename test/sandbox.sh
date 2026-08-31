#!/usr/bin/env bash
#
# test/sandbox.sh -- run kickstart against a throwaway $HOME and drop you into
# an interactive shell inside it.
#
# This is how you try kickstart out before letting it near your real setup.
# Nothing outside the sandbox directory is written to.
#
#   ./test/sandbox.sh                    # local checkout, personal profile, bash
#   ./test/sandbox.sh --shell zsh
#   ./test/sandbox.sh --dirty            # include uncommitted changes
#   ./test/sandbox.sh --profile work --overlay ~/workspace/kickstart-work
#   ./test/sandbox.sh --repo https://github.com/tkountis/kickstart.git
#   ./test/sandbox.sh --install          # also install packages (see caveats)
#   ./test/sandbox.sh --no-shell         # just apply and report
#
# By default this goes through `git clone`, so it tests your committed HEAD --
# the same thing a real machine would get. Use --dirty while iterating to layer
# the working tree on top.
#
# WHAT IS ISOLATED
#   $HOME and everything under it: dotfiles, symlinks, ~/.config, ~/.local,
#   ~/.cache, ~/.ssh, the kickstart checkout itself, and the overlay clone.
#
# WHAT IS NOT
#   Anything a tool stores outside $HOME. Concretely:
#     * Installed packages. brew writes to /opt/homebrew, apt to /usr. That is
#       why installs are OFF by default (--files-only); with --install you are
#       modifying the real machine's packages, and nothing here can undo that.
#     * macOS preferences. `defaults write` goes through cfprefsd to the real
#       logged-in user regardless of $HOME. Modules that do this declare
#       SANDBOX_UNSAFE=1 and are skipped automatically.
#     * ssh-agent, keychain, launchd.

# Literal $HOME and backticks appear in help text below; they are meant to be
# read, not expanded.
# shellcheck disable=SC2016
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

REPO="file://$ROOT"
# On a detached HEAD (CI checkouts, mid-rebase) abbrev-ref returns "HEAD",
# which is not a clonable branch name. Fall back to the default branch.
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
[ "$BRANCH" = HEAD ] && BRANCH=$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$BRANCH" ] || BRANCH=main
PROFILE=personal
OVERLAY=""
SHELL_NAME=""
DO_INSTALL=0
DO_SHELL=1
KEEP=0
DIRTY=0

if [ -t 1 ]; then
  B=$'\033[1m'; D=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'
  RED=$'\033[31m'; CYN=$'\033[36m'; R=$'\033[0m'
else
  B=''; D=''; GRN=''; YLW=''; RED=''; CYN=''; R=''
fi
die() { printf '%serror%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     shift; REPO=${1:-} ;;
    --branch)   shift; BRANCH=${1:-} ;;
    --profile)  shift; PROFILE=${1:-} ;;
    --overlay)  shift; OVERLAY=${1:-} ;;
    --shell)    shift; SHELL_NAME=${1:-} ;;
    --install)  DO_INSTALL=1 ;;
    --no-shell) DO_SHELL=0 ;;
    --dirty)    DIRTY=1 ;;
    --keep)     KEEP=1 ;;
    -h|--help)  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ -n "$SHELL_NAME" ] || SHELL_NAME=$(basename "${SHELL:-bash}")
case "$SHELL_NAME" in bash|zsh) ;; *) die "--shell must be bash or zsh" ;; esac
command -v "$SHELL_NAME" >/dev/null 2>&1 || die "$SHELL_NAME is not installed"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/kickstart-sandbox.XXXXXX")
HOME_DIR="$SANDBOX/home"
mkdir -p "$HOME_DIR"

cleanup() {
  if [ "$KEEP" = 1 ]; then
    printf '\n%skept%s %s\n' "$YLW" "$R" "$SANDBOX"
    printf '%s      remove it with: rm -rf %s%s\n' "$D" "$SANDBOX" "$R"
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

# Every kickstart and shell invocation below runs with these overrides. This is
# the whole isolation mechanism: one $HOME, and every XDG directory under it.
sandboxed() {
  env HOME="$HOME_DIR" \
      XDG_CONFIG_HOME="$HOME_DIR/.config" \
      XDG_STATE_HOME="$HOME_DIR/.local/state" \
      XDG_DATA_HOME="$HOME_DIR/.local/share" \
      XDG_CACHE_HOME="$HOME_DIR/.cache" \
      KICKSTART_ROOT="$HOME_DIR/.kickstart" \
      KICKSTART_SANDBOX=1 \
      "$@"
}

# ----------------------------------------------------------------- banner ---

printf '\n%skickstart sandbox%s\n' "$B" "$R"
printf '  home     %s\n' "$HOME_DIR"
printf '  repo     %s (%s)\n' "$REPO" "$BRANCH"
printf '  profile  %s\n' "$PROFILE"
[ -n "$OVERLAY" ] && printf '  overlay  %s\n' "$OVERLAY"
printf '  shell    %s\n' "$SHELL_NAME"
[ "$DIRTY" = 1 ] && printf '  source   %sworking tree (uncommitted changes included)%s\n' "$YLW" "$R"
if [ "$DO_INSTALL" = 1 ]; then
  printf '  installs %sENABLED -- packages go to the REAL machine%s\n' "$YLW" "$R"
else
  printf '  installs %sdisabled (--files-only)%s\n' "$D" "$R"
fi
printf '\n'

if [ "$DO_INSTALL" = 1 ]; then
  printf '%sPackage installs are not sandboxed.%s brew/apt write outside $HOME and\n' "$YLW" "$R"
  printf 'this script cannot undo them. Your dotfiles are still isolated.\n\n'
  if [ -t 0 ]; then
    printf 'continue? [y/N] '
    read -r reply
    case "$reply" in [yY]|[yY][eE][sS]) ;; *) exit 0 ;; esac
    printf '\n'
  fi
fi

# --------------------------------------------------------------- bootstrap ---

# Use the real install.sh, from the real repo, over the real clone path. The
# point is to test the thing users actually run, not a shortcut.
printf '%s==>%s bootstrapping\n' "$CYN" "$R"
INSTALL_ARGS="--repo $REPO --branch $BRANCH --root $HOME_DIR/.kickstart --profile $PROFILE --no-apply"
# shellcheck disable=SC2086
sandboxed "$ROOT/install.sh" $INSTALL_ARGS >"$SANDBOX/bootstrap.log" 2>&1 || {
  printf '%sbootstrap failed%s -- log follows\n\n' "$RED" "$R"
  sed 's/^/  /' "$SANDBOX/bootstrap.log"
  exit 1
}
printf '    clone ok\n'

# The clone only has committed content. While iterating, layer the working tree
# (tracked + untracked, respecting .gitignore) on top so uncommitted changes
# are what actually gets tested.
if [ "$DIRTY" = 1 ]; then
  ( cd "$ROOT" && git ls-files -co --exclude-standard -z |
      tar czf "$SANDBOX/worktree.tgz" --null -T - ) 2>/dev/null ||
    die "could not package the working tree"
  tar xzf "$SANDBOX/worktree.tgz" -C "$HOME_DIR/.kickstart" ||
    die "could not unpack the working tree"
  chmod +x "$HOME_DIR/.kickstart/bin/kickstart" \
           "$HOME_DIR/.kickstart/install.sh" \
           "$HOME_DIR/.kickstart/shell/khelp.sh" 2>/dev/null
  printf '    working tree layered on top\n'
elif ! git -C "$ROOT" diff-index --quiet HEAD -- 2>/dev/null; then
  printf '    %swarn%s working tree is dirty; testing committed HEAD only (use --dirty)\n' "$YLW" "$R"
fi

KS="$HOME_DIR/.kickstart/bin/kickstart"

if [ -n "$OVERLAY" ]; then
  printf '%s==>%s adding overlay\n' "$CYN" "$R"
  sandboxed "$KS" overlay add "$OVERLAY" 2>&1 | sed 's/^/    /'
fi

# --------------------------------------------------------------------- apply --

APPLY_ARGS="-y"
[ "$DO_INSTALL" = 1 ] || APPLY_ARGS="$APPLY_ARGS --files-only"

printf '%s==>%s applying\n' "$CYN" "$R"
# shellcheck disable=SC2086
sandboxed "$KS" apply $APPLY_ARGS 2>&1 | sed 's/^/    /'
APPLY_RC=${PIPESTATUS[0]}

# Idempotency is the property most worth checking, and it is free here.
printf '\n%s==>%s re-applying (should report 0 changed)\n' "$CYN" "$R"
# shellcheck disable=SC2086
second=$(sandboxed "$KS" apply $APPLY_ARGS 2>&1)
if printf '%s' "$second" | grep -q 'done: 0 changed'; then
  printf '    %sok%s   idempotent\n' "$GRN" "$R"
else
  printf '    %sNOT IDEMPOTENT%s\n' "$RED" "$R"
  printf '%s\n' "$second" | grep -E '^\[|done:' | sed 's/^/    /'
fi

printf '\n%s==>%s doctor\n' "$CYN" "$R"
sandboxed "$KS" doctor 2>&1 | sed 's/^/    /'

# The check that actually catches breakage: does a LOGIN shell reach kickstart?
# bash reads .bash_profile and only gets to .bashrc if something says so, and
# that is exactly the path people get wrong.
printf '\n%s==>%s login shell loads kickstart\n' "$CYN" "$R"
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || { printf '    %sskip%s %s\n' "$D" "$R" "$sh"; continue; }
  if sandboxed "$sh" -l -i -c 'command -v khelp >/dev/null && command -v mkcd >/dev/null' \
       >/dev/null 2>&1; then
    printf '    %sok%s   %s -l loads helpers\n' "$GRN" "$R" "$sh"
  else
    printf '    %sFAIL%s %s -l did NOT load kickstart\n' "$RED" "$R" "$sh"
    APPLY_RC=1
  fi
done

# What actually landed in the fake home.
printf '\n%s==>%s what it created in $HOME\n' "$CYN" "$R"
find "$HOME_DIR" -maxdepth 3 \( -type l -o -type f \) \
  -not -path '*/.kickstart/*' -not -path '*/overlays/*' -not -name '.DS_Store' \
  2>/dev/null | sed "s|$HOME_DIR|~|" | sort | sed 's/^/    /'

if [ "$DO_SHELL" = 0 ]; then
  printf '\n'
  [ "$APPLY_RC" = 0 ] && printf '%sdone%s\n' "$GRN" "$R" || printf '%sapply reported failures%s\n' "$RED" "$R"
  exit "$APPLY_RC"
fi

# ------------------------------------------------------- interactive shell ---

cat <<EOF

${B}dropping you into a login $SHELL_NAME with HOME=$HOME_DIR${R}

  Everything you type is confined to that directory. Try:
    khelp                  the helper registry
    kickstart status
    kwhich ll
    mkcd /tmp/x && cd -

  ${D}exit${R} (or ctrl-d) to tear the sandbox down.

EOF

# A login shell, because that is the path that actually breaks: bash reads
# .bash_profile and only reaches .bashrc if something tells it to.
sandboxed "$SHELL_NAME" -l
