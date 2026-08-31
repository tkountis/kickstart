# core-cli -- the small set of tools every box should have.
#
# Package names differ between managers, and Debian renames two of the
# binaries (fd -> fdfind, bat -> batcat). We install the packages and then
# put correctly-named shims in ~/.local/bin so scripts and helpers written on
# macOS keep working on Ubuntu.
DESC="Everyday CLI tools: rg, fd, fzf, jq, bat, tree, htop"
TAGS="core cli"

PROVIDES="rg fd fzf jq bat tree htop"

PKG_BREW="ripgrep fd fzf jq bat tree htop eza coreutils gnu-sed findutils"
PKG_APT="ripgrep fd-find fzf jq bat tree htop unzip"
PKG_DNF="ripgrep fd-find fzf jq bat tree htop unzip"

ks_configure() {
  # Debian and Fedora ship fd/bat under different binary names because of
  # existing packages with those names. Normalise here, once.
  local bin="$HOME/.local/bin" pair src dst
  ks_mkdir "$bin"
  for pair in "fdfind:fd" "batcat:bat"; do
    src=${pair%%:*}
    dst=${pair##*:}
    if ks_have "$src" && ! ks_have "$dst"; then
      ks_chg "shim $dst -> $src"
      ks_run ln -sfn "$(command -v "$src")" "$bin/$dst"
      ks_touched
    fi
  done
  return 0
}
