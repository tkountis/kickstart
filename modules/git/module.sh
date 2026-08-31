# git -- git itself plus a shared config.
#
# Identity is deliberately NOT in the tracked .gitconfig. It lives in
# ~/.gitconfig.local (per host, untracked), and work repos get a different
# identity through the includeIf rule below. That is git's own mechanism,
# so there is no templating engine to maintain.
DESC="git, with a shared config and per-context identity"
TAGS="core vcs"

PROVIDES="git"
PKG_BREW="git"
PKG_APT="git"
PKG_DNF="git"

ks_configure() {
  # Seed ~/.gitconfig.local once so `git commit` does not fail on a fresh box.
  local local_cfg="$HOME/.gitconfig.local"
  if [ ! -f "$local_cfg" ] && [ "${KS_DRY_RUN:-0}" != 1 ]; then
    cat >"$local_cfg" <<'EOF'
# Machine-local git identity. Not tracked by kickstart.
[user]
	name = CHANGE ME
	email = change@me
EOF
    ks_chg "created ~/.gitconfig.local -- set your name and email in it"
    ks_touched
  fi

  # Work identity, applied to anything under ~/work by the includeIf rule.
  if [ "$KS_PROFILE" = work ] && [ ! -f "$HOME/.gitconfig.work" ] &&
     [ "${KS_DRY_RUN:-0}" != 1 ]; then
    cat >"$HOME/.gitconfig.work" <<'EOF'
# Identity used for repositories under ~/work. Not tracked by kickstart.
[user]
	name = CHANGE ME
	email = change@work
EOF
    ks_chg "created ~/.gitconfig.work"
    ks_touched
  fi
  return 0
}
