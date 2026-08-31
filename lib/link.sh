#!/usr/bin/env bash
# lib/link.sh -- the dotfile engine.
#
# Model: a module's `files/` directory is a literal mirror of $HOME.
#
#   modules/git/files/.gitconfig            -> ~/.gitconfig
#   modules/nvim/files/.config/nvim/init.lua -> ~/.config/nvim/init.lua
#
# Directories are created, files are symlinked. We symlink files rather than
# whole directories so a tool that drops state next to its config (nvim, ssh)
# does not end up writing into the repo.
#
# OS specialisation: `files.darwin/` and `files.linux/` are overlaid on top of
# `files/` when they match the current host.

# Anything matching these is never linked.
KS_LINK_IGNORE='.DS_Store .git .gitkeep .keep'

# ks_link_tree <srcdir> [dest_root]
ks_link_tree() {
  local src=$1 dest_root=${2:-$HOME}
  [ -d "$src" ] || return 3

  local rel target found=0 changed=0
  # -print avoids relying on GNU find extensions; works on macOS and Linux.
  while IFS= read -r file; do
    rel=${file#"$src"/}
    case " $KS_LINK_IGNORE " in *" $(basename "$rel") "*) continue ;; esac
    found=1
    target="$dest_root/$rel"
    if ks_link_file "$file" "$target"; then changed=1; fi
  done <<EOF
$(find "$src" \( -type f -o -type l \) -print | sort)
EOF

  [ "$found" = 0 ] && return 3
  [ "$changed" = 1 ] && return 0
  return 3
}

# ks_link_file <src> <target> -- returns 0 if it changed anything, 3 if not.
ks_link_file() {
  local src=$1 target=$2

  if [ -L "$target" ]; then
    local current
    current=$(ks_link_target "$target")
    if [ "$current" = "$src" ]; then
      ks_debug "link ok: $(ks_relpath "$target")"
      return 3
    fi
    ks_chg "relink $(ks_relpath "$target") -> $(ks_relpath "$src")"
    ks_run rm -f "$target"
  elif [ -e "$target" ]; then
    ks_backup_path "$target" || return 1
    ks_chg "link   $(ks_relpath "$target") -> $(ks_relpath "$src")"
  else
    ks_chg "link   $(ks_relpath "$target") -> $(ks_relpath "$src")"
  fi

  ks_mkdir "$(dirname "$target")"
  ks_run ln -sfn "$src" "$target" || return 1
  return 0
}

# ks_unlink_tree <srcdir> [dest_root] -- remove only symlinks we own.
ks_unlink_tree() {
  local src=$1 dest_root=${2:-$HOME}
  [ -d "$src" ] || return 3
  local rel target
  while IFS= read -r file; do
    rel=${file#"$src"/}
    case " $KS_LINK_IGNORE " in *" $(basename "$rel") "*) continue ;; esac
    target="$dest_root/$rel"
    if [ -L "$target" ] && [ "$(ks_link_target "$target")" = "$file" ]; then
      ks_chg "unlink $(ks_relpath "$target")"
      ks_run rm -f "$target"
    fi
  done <<EOF
$(find "$src" \( -type f -o -type l \) -print | sort)
EOF
}

# ks_backup_path <path> -- move an existing real file out of the way.
# Backups land in one timestamped directory per run so a bad apply is a single
# `cp -a` away from being undone.
ks_backup_path() {
  local path=$1
  local dir="$KS_STATE_DIR/backups/$KS_RUN_ID"
  local rel="${path#"$HOME"/}"
  local dest="$dir/$rel"
  ks_warn "backing up existing $(ks_relpath "$path") -> $(ks_relpath "$dest")"
  ks_mkdir "$(dirname "$dest")"
  ks_run mv "$path" "$dest"
}

# ks_link_target <path> -- the raw target a symlink stores.
#
# Deliberately NOT `readlink -f`. Canonicalising resolves symlinked parent
# directories (/var -> /private/var on macOS, /home -> /export/home on plenty
# of NFS setups), so the result would never equal the path we wrote and every
# apply would relink. We wrote the link, so a literal comparison is both
# correct and cheaper.
ks_link_target() { readlink "$1" 2>/dev/null; }
