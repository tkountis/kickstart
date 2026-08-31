# shellcheck shell=sh
# Filesystem and navigation helpers.

#: mkcd <dir> -- make a directory and cd into it
mkcd() {
  [ -n "${1:-}" ] || { echo "usage: mkcd <dir>" >&2; return 2; }
  mkdir -p "$1" && cd "$1" || return 1
}

#: up [n] -- go up n directories (default 1)
up() {
  _n=${1:-1}
  _p=""
  while [ "$_n" -gt 0 ]; do _p="../$_p"; _n=$((_n - 1)); done
  unset _n
  cd "$_p" || return 1
  unset _p
}

#: bak <file> -- copy a file to file.YYYYmmdd-HHMMSS.bak
bak() {
  [ -e "${1:-}" ] || { echo "usage: bak <file>" >&2; return 2; }
  cp -a "$1" "$1.$(date +%Y%m%d-%H%M%S).bak" && echo "$1.$(date +%Y%m%d-%H%M%S).bak"
}

#: extract <archive> -- unpack any common archive format
extract() {
  [ -f "${1:-}" ] || { echo "usage: extract <archive>" >&2; return 2; }
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz)   tar xzf "$1" ;;
    *.tar.xz)         tar xJf "$1" ;;
    *.tar)            tar xf "$1" ;;
    *.zip)            unzip -q "$1" ;;
    *.gz)             gunzip "$1" ;;
    *.bz2)            bunzip2 "$1" ;;
    *.7z)             7z x "$1" ;;
    *)                echo "extract: unknown format: $1" >&2; return 1 ;;
  esac
}

#: ff <pattern> -- find files by name under the current directory
ff() {
  [ -n "${1:-}" ] || { echo "usage: ff <pattern>" >&2; return 2; }
  if command -v fd >/dev/null 2>&1; then fd --hidden --exclude .git "$1"
  else find . -path ./.git -prune -o -iname "*$1*" -print; fi
}

#: fif <pattern> -- find text inside files under the current directory
fif() {
  [ -n "${1:-}" ] || { echo "usage: fif <pattern>" >&2; return 2; }
  if command -v rg >/dev/null 2>&1; then rg --hidden --glob '!.git' -n "$@"
  else grep -rn --exclude-dir=.git "$@" .; fi
}

#: ports -- show what is listening on this host
ports() {
  if command -v ss >/dev/null 2>&1; then ss -tulpn
  elif command -v lsof >/dev/null 2>&1; then lsof -nP -iTCP -sTCP:LISTEN
  else netstat -an | grep -i listen; fi
}

#: sizes [dir] -- biggest entries in a directory, largest last
sizes() { du -sh "${1:-.}"/* 2>/dev/null | sort -h; }
