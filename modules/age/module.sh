# age -- file encryption with no keyring, no daemon, no GPG.
#
# kickstart uses it for the secrets vault, with your ssh key as the identity:
#
#   age -R secrets/recipients.txt -o thing.age thing
#   age -d -i ~/.ssh/id_ed25519 thing.age
#
# See docs/secrets.md.
DESC="age: file encryption, used by the secrets vault"
TAGS="core security"

PROVIDES="age"
PKG_BREW="age"
PKG_APT="age"
PKG_DNF="age"

# age landed in Debian 12 and Ubuntu 23.04. On anything older the package is
# missing, so fall back to the upstream static binary.
ks_install() {
  if ks_pkg_install age 2>/dev/null && ks_have age; then
    return 0
  fi

  if [ "${KS_OFFLINE:-0}" = 1 ]; then
    ks_skip "age not packaged here and we are offline"
    return 0
  fi

  local ver="v1.2.1" url tmp
  url="https://github.com/FiloSottile/age/releases/download/${ver}/age-${ver}-${KS_OS}-${KS_ARCH}.tar.gz"
  ks_step "installing age ${ver} from upstream"
  tmp=$(ks_mktemp)
  ks_run curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
  ks_mkdir "$HOME/.local/bin"
  ks_run tar xzf "$tmp" -C "$HOME/.local/bin" --strip-components=1 age/age age/age-keygen ||
    { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  ks_run chmod +x "$HOME/.local/bin/age" "$HOME/.local/bin/age-keygen"
}
