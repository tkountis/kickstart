# shellcheck shell=sh
# Git helpers.

#: gclone <url> -- clone into ~/workspace/<repo> and cd there
gclone() {
  [ -n "${1:-}" ] || { echo "usage: gclone <url>" >&2; return 2; }
  _ws="${KICKSTART_WORKSPACE:-$HOME/workspace}"
  _name=$(basename "$1"); _name=${_name%.git}
  mkdir -p "$_ws"
  if [ -d "$_ws/$_name" ]; then
    echo "already cloned: $_ws/$_name"
  else
    git clone "$1" "$_ws/$_name" || { unset _ws _name; return 1; }
  fi
  cd "$_ws/$_name" || return 1
  unset _ws _name
}

#: groot -- cd to the root of the current git repository
groot() {
  _r=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "not in a git repository" >&2; return 1
  }
  cd "$_r" || return 1
  unset _r
}

#: gwip -- commit everything as a throwaway WIP commit
gwip() { git add -A && git commit -m "wip: $(date +%F\ %T)" --no-verify; }

#: gunwip -- undo the last commit, keeping the changes staged
gunwip() { git reset --soft HEAD~1; }

#: gsync -- fetch, prune, and fast-forward the current branch
gsync() {
  git fetch --all --prune || return 1
  git merge --ff-only "@{upstream}" 2>/dev/null ||
    echo "cannot fast-forward (diverged or no upstream)" >&2
}

#: gbclean -- delete local branches whose remote is gone
gbclean() {
  git fetch --prune
  git branch -vv | awk '/: gone]/ {print $1}' | while IFS= read -r b; do
    printf 'deleting %s\n' "$b"
    git branch -D "$b"
  done
}

#: gsw -- pick a branch to switch to with fzf
gsw() {
  command -v fzf >/dev/null 2>&1 || { echo "gsw needs fzf" >&2; return 1; }
  _b=$(git branch --all --sort=-committerdate --format='%(refname:short)' |
       grep -v '^origin/HEAD' | fzf --height 40% --reverse) || return 1
  [ -n "$_b" ] || { unset _b; return 1; }
  # Local branch first; fall back to creating a tracking branch for a remote.
  if git switch "${_b#origin/}" 2>/dev/null; then
    unset _b
  else
    git switch --track "$_b"
    unset _b
  fi
}
