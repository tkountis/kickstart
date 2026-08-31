#!/usr/bin/env bash
#
# test/smoke.sh -- end to end check against a throwaway $HOME.
#
# Nothing here touches your real home directory. It runs the full apply in
# --files-only mode (so no packages are installed), then asserts the things
# that actually matter: links land where they should, a second run is a no-op,
# existing files are preserved, overlays win over core, and the shell layer
# loads under both bash and zsh.
#
#   ./test/smoke.sh

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/kickstart-smoke.XXXXXX")
FAILED=0

if [ -t 1 ]; then GRN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RST=$'\033[0m'
else GRN=''; RED=''; DIM=''; RST=''; fi

cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

pass() { printf '  %sPASS%s %s\n' "$GRN" "$RST" "$1"; }
fail() { printf '  %sFAIL%s %s\n' "$RED" "$RST" "$1"; FAILED=$((FAILED + 1)); }
check() { if [ "$1" = 0 ]; then pass "$2"; else fail "$2"; fi; }
# refute <label> <cmd>... -- the command is expected to fail.
refute() { local label=$1; shift; if "$@" >/dev/null 2>&1; then fail "$label"; else pass "$label"; fi; }
section() { printf '\n%s\n' "$1"; }

# `cmd | grep -q` would return 141 under pipefail when grep exits on the first
# match and the producer is still writing. Match against a captured string.
has() { printf '%s\n' "$1" | grep -q -- "$2"; }

# filemode <path> -- octal permissions, portably.
filemode() {
  if [ "$(uname -s)" = Darwin ]; then stat -f '%OLp' "$1"; else stat -c '%a' "$1"; fi
}

# Every invocation runs against the sandbox home.
ks() {
  env HOME="$SANDBOX/home" \
      XDG_CONFIG_HOME="$SANDBOX/home/.config" \
      XDG_STATE_HOME="$SANDBOX/home/.local/state" \
      XDG_DATA_HOME="$SANDBOX/home/.local/share" \
      "$ROOT/bin/kickstart" "$@"
}

mkdir -p "$SANDBOX/home"
printf 'sandbox: %s\n' "$SANDBOX"

# --------------------------------------------------------------------------
section "basics"
ks version >/dev/null 2>&1; check $? "version runs"
ks list modules >/dev/null 2>&1; check $? "list modules runs"
ks list profiles >/dev/null 2>&1; check $? "list profiles runs"
ks --help >/dev/null 2>&1; check $? "help runs"
ks apply --dry-run >/dev/null 2>&1; check $? "dry-run apply runs"
[ ! -e "$SANDBOX/home/.gitconfig" ]; check $? "dry run created nothing"

# --------------------------------------------------------------------------
section "apply (files-only)"
out=$(ks apply --files-only --profile base -y 2>&1); rc=$?
[ "$rc" = 0 ]; check $? "apply succeeded"
[ "$rc" = 0 ] || printf '%s\n' "$out" | sed 's/^/      /'

[ -L "$SANDBOX/home/.gitconfig" ];                     check $? ".gitconfig is a symlink"
[ -L "$SANDBOX/home/.tmux.conf" ];                     check $? ".tmux.conf is a symlink"
[ -L "$SANDBOX/home/.config/nvim/init.lua" ];          check $? "nested config linked"
[ -L "$SANDBOX/home/.ssh/config.d/00-kickstart.conf" ];check $? "ssh config.d linked"
[ -f "$SANDBOX/home/.config/kickstart/env" ];          check $? "machine-local env file created"
[ -L "$SANDBOX/home/.local/bin/kickstart" ];           check $? "cli linked into ~/.local/bin"
[ -f "$SANDBOX/home/.gitconfig.local" ];               check $? "git identity stub created"

grep -q 'kickstart:shell' "$SANDBOX/home/.bashrc" 2>/dev/null; check $? ".bashrc wired"
grep -q 'kickstart:shell' "$SANDBOX/home/.zshrc"  2>/dev/null; check $? ".zshrc wired"
grep -q 'Include ~/.ssh/config.d' "$SANDBOX/home/.ssh/config" 2>/dev/null
check $? "ssh config Include added"

# The link must point at the repo, not be a copy.
[ "$(readlink "$SANDBOX/home/.tmux.conf")" = "$ROOT/modules/tmux/files/.tmux.conf" ]
check $? "symlink points back at the repo"

# --------------------------------------------------------------------------
section "idempotency"
out=$(ks apply --files-only --profile base -y 2>&1)
has "$out" 'done: 0 changed'; check $? "second run changes nothing"
[ "$(grep -c 'kickstart:shell' "$SANDBOX/home/.bashrc")" = 2 ]
check $? "rc block not duplicated"

# --------------------------------------------------------------------------
section "existing files are backed up, not clobbered"
rm -f "$SANDBOX/home/.tmux.conf"
printf 'my precious config\n' >"$SANDBOX/home/.tmux.conf"
ks apply --files-only --profile base -y >/dev/null 2>&1
[ -L "$SANDBOX/home/.tmux.conf" ]; check $? "existing file replaced by link"
grep -rq 'my precious config' "$SANDBOX/home/.local/state/kickstart/backups" 2>/dev/null
check $? "original content preserved in backups/"

# --------------------------------------------------------------------------
section "unlink"
ks unlink --profile base -y >/dev/null 2>&1
[ ! -L "$SANDBOX/home/.tmux.conf" ]; check $? "unlink removes our symlinks"
[ ! -L "$SANDBOX/home/.gitconfig" ]; check $? "unlink is thorough"
[ -f "$SANDBOX/home/.gitconfig.local" ]; check $? "unlink leaves untracked files alone"
ks apply --files-only --profile base -y >/dev/null 2>&1  # put it back

# --------------------------------------------------------------------------
section "profiles"
ks profile minimal >/dev/null 2>&1; check $? "profile can be set"
[ "$(ks profile)" = minimal ]; check $? "profile persists to config"
refute "unknown profile rejected" ks profile nope
[ "$(ks list profiles | wc -l | tr -d ' ')" -ge 5 ]; check $? "all profiles listed"

# A module gated on a profile it does not match must be skipped, not run.
out=$(ks apply --files-only macos-defaults --profile minimal -y 2>&1)
case "$(uname -s)" in
  Linux) has "$out" 'requires os'; check $? "os-gated module skipped on linux" ;;
  *)     has "$out" 'done: '; check $? "os-gated module runs on darwin" ;;
esac

# --------------------------------------------------------------------------
section "scaffolding"
ks new module mytool >/dev/null 2>&1; check $? "new module scaffolds"
[ -f "$ROOT/modules/mytool/module.sh" ]; check $? "module.sh created"
refute "refuses to overwrite module" ks new module mytool
rm -rf "$ROOT/modules/mytool"

ks new helper mytopic >/dev/null 2>&1; check $? "new helper scaffolds"
[ -f "$ROOT/shell/source/50_mytopic.sh" ]; check $? "helper uses the 50 band by default"
helpers=$(env HOME="$SANDBOX/home" KICKSTART_ROOT="$ROOT" "$ROOT/shell/khelp.sh" 2>/dev/null)
has "$helpers" 'mytopic'; check $? "new helper is discoverable via khelp"
rm -f "$ROOT/shell/source/50_mytopic.sh"

# --------------------------------------------------------------------------
section "shell integration loads"
# The -c bodies below are single quoted on purpose: they must be evaluated by
# the child shell, not by this one.
# shellcheck disable=SC2016
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || {
    printf '  %sskip%s %s not installed\n' "$DIM" "$RST" "$sh"; continue; }
  err=$(env HOME="$SANDBOX/home" KICKSTART_ROOT="$ROOT" "$sh" -c '
    . "$KICKSTART_ROOT/shell/init.sh"
    for f in mkcd khelp path gclone kreload path_prepend groot extract; do
      command -v "$f" >/dev/null || { echo "missing: $f" >&2; exit 1; }
    done
    mkcd "$HOME/probe-'"$sh"'" || { echo "mkcd failed" >&2; exit 1; }
    case "$PWD" in *probe-'"$sh"') ;; *) echo "cd failed: $PWD" >&2; exit 1 ;; esac
    path_prepend /tmp; case ":$PATH:" in *:/tmp:*) ;; *) echo "path_prepend failed" >&2; exit 1;; esac
    path_prepend /tmp
    [ "$(printf %s "$PATH" | tr : "\n" | grep -c "^/tmp$")" = 1 ] || { echo "path_prepend not idempotent" >&2; exit 1; }
  ' 2>&1 >/dev/null)
  rc=$?
  check $rc "$sh loads helpers and they work"
  [ "$rc" = 0 ] || printf '       %s\n' "$err"
done

# --------------------------------------------------------------------------
section "overlays"
OV="$SANDBOX/overlay"
mkdir -p "$OV/modules/hello/files" "$OV/profiles" "$OV/shell/source" "$OV/modules/tmux/files"
cat >"$OV/modules/hello/module.sh" <<'EOF'
DESC="overlay test module"
ks_check() { return 0; }
ks_install() { return 0; }
EOF
printf 'overlay file\n' >"$OV/modules/hello/files/.hello-overlay"
# Same name as a core module: the overlay copy must win.
cat >"$OV/modules/tmux/module.sh" <<'EOF'
DESC="overlay tmux override"
ks_check() { return 0; }
ks_install() { return 0; }
EOF
printf '@include minimal\nhello\n' >"$OV/profiles/team.profile"
printf '#: hellofn -- overlay helper\nhellofn() { echo hi; }\n' >"$OV/shell/source/55_hello.sh"
( cd "$OV" && git init -q && git add -A &&
  git -c user.email=t@t -c user.name=t commit -qm init )

ks overlay add "$OV" testov >/dev/null 2>&1; check $? "overlay added"
mods=$(ks list modules); profs=$(ks list profiles); ovs=$(ks list overlays)
has "$ovs"   'testov';                  check $? "overlay listed"
has "$mods"  '^hello ';                 check $? "overlay module visible"
has "$mods"  'overlay tmux override';   check $? "overlay overrides core module"
has "$profs" '^team ';                  check $? "overlay profile visible"
has "$profs" '^team .*shell git hello'; check $? "overlay profile can @include a core one"

ks apply --files-only --profile team -y >/dev/null 2>&1
[ -L "$SANDBOX/home/.hello-overlay" ]; check $? "overlay dotfile linked"
# Overlays live under a path that may reach $HOME through a symlink
# (/var -> /private/var). If we canonicalised link targets, this would relink
# on every run.
out=$(ks apply --files-only --profile team -y 2>&1)
has "$out" 'done: 0 changed'; check $? "overlay links are idempotent"

helpers=$(env HOME="$SANDBOX/home" XDG_DATA_HOME="$SANDBOX/home/.local/share" \
  KICKSTART_ROOT="$ROOT" "$ROOT/shell/khelp.sh" 2>/dev/null)
has "$helpers" 'hellofn'; check $? "overlay helper appears in khelp"
has "$helpers" 'testov';  check $? "khelp shows which overlay a helper came from"

# shellcheck disable=SC2016  # evaluated by the child shell
order=$(env HOME="$SANDBOX/home" KICKSTART_ROOT="$ROOT" KICKSTART_TRACE=1 \
  bash -c '. "$KICKSTART_ROOT/shell/init.sh"' 2>&1 | sed 's|.*/||')
expected=$(printf '%s\n' "$order" | LC_ALL=C sort)
[ "$order" = "$expected" ]; check $? "helper files load in filename order across repos"

# --------------------------------------------------------------------------
section "shell-specific helper files"
mkdir -p "$SANDBOX/home/.local/share/kickstart/overlays/testov/shell/source"
OVS="$SANDBOX/home/.local/share/kickstart/overlays/testov/shell/source"
printf '#: bashfn -- bash only helper\nbashfn() { echo b; }\n' >"$OVS/56_bashonly.bash"
printf '#: zshfn -- zsh only helper\nzshfn() { echo z; }\n'    >"$OVS/57_zshonly.zsh"
printf '#: bothfn -- portable helper\nbothfn() { echo p; }\n'  >"$OVS/58_both.sh"

# shellcheck disable=SC2016  # evaluated by the child shell
probe() { # probe <shell> <fn> -- is <fn> defined after init?
  env HOME="$SANDBOX/home" KICKSTART_ROOT="$ROOT" "$1" -c \
    ". \"\$KICKSTART_ROOT/shell/init.sh\"; command -v $2" >/dev/null 2>&1
}
probe bash bashfn; check $? ".bash helper loads in bash"
refute ".bash helper does not load in zsh" probe zsh bashfn
probe zsh zshfn;   check $? ".zsh helper loads in zsh"
refute ".zsh helper does not load in bash" probe bash zshfn
probe bash bothfn; check $? ".sh helper loads in bash"
probe zsh bothfn;  check $? ".sh helper loads in zsh"

helpers=$(env HOME="$SANDBOX/home" XDG_DATA_HOME="$SANDBOX/home/.local/share" \
  KICKSTART_ROOT="$ROOT" "$ROOT/shell/khelp.sh" 2>/dev/null)
has "$helpers" 'bashfn';    check $? "khelp lists shell-specific helpers"
has "$helpers" 'bash only'; check $? "khelp labels which shell a file needs"

ks new helper probebash --bash >/dev/null 2>&1
[ -f "$ROOT/shell/source/50_probebash.bash" ]; check $? "new helper --bash makes a .bash file"
rm -f "$ROOT/shell/source/50_probebash.bash"

# --------------------------------------------------------------------------
section "keys"
# Work against the *cloned* overlay, which is what kickstart actually reads.
# (A real workflow would commit to $OV and `kickstart overlay update`.)
OVC="$SANDBOX/home/.local/share/kickstart/overlays/testov"
mkdir -p "$OVC/keys"
ks keys new -y >/dev/null 2>&1; check $? "keys new generates an ed25519 key"
[ -f "$SANDBOX/home/.ssh/id_ed25519" ]; check $? "private key created"
[ "$(filemode "$SANDBOX/home/.ssh/id_ed25519")" = 600 ]
check $? "private key is mode 600"
ks keys status >/dev/null 2>&1; check $? "keys status runs"

ks keys track >/dev/null 2>&1; check $? "keys track copies the public key"
[ -n "$(ls "$OVC"/keys/*.pub 2>/dev/null)" ]
check $? "public key tracked in the overlay"
# Tracking must never copy the private half.
[ -z "$(find "$OVC/keys" -type f ! -name '*.pub' 2>/dev/null)" ]
check $? "no private key material tracked"

ks keys authorized >/dev/null 2>&1; check $? "keys authorized rebuilds the file"
auth="$SANDBOX/home/.ssh/authorized_keys"
grep -q 'kickstart:keys' "$auth" 2>/dev/null; check $? "authorized_keys has our block"
grep -q "$(awk '{print $2}' <"$SANDBOX/home/.ssh/id_ed25519.pub")" "$auth"
check $? "authorized_keys contains the key"
# Content outside our block must survive a rebuild.
printf 'ssh-ed25519 AAAAsomeoneelse other@host\n' >>"$auth"
ks keys authorized >/dev/null 2>&1
grep -q 'other@host' "$auth"; check $? "pre-existing authorized_keys entries preserved"

# --------------------------------------------------------------------------
section "secrets (age vault)"
if ! command -v age >/dev/null 2>&1; then
  printf '  %sskip%s age not installed\n' "$DIM" "$RST"
else
  ks secrets init --in "$OVC/secrets" -y >/dev/null 2>&1
  check $? "secrets init creates a vault"
  [ -f "$OVC/secrets/recipients.txt" ]; check $? "recipients.txt created"
  recips=$(ks secrets recipients 2>/dev/null)
  has "$recips" "$(uname -n | cut -d. -f1)"; check $? "this host is a recipient"

  printf 'TOKEN=hunter2\n' | ks secrets add tok >/dev/null 2>&1
  check $? "secrets add from stdin"
  [ -f "$OVC/secrets/tok.age" ]; check $? "ciphertext written"
  # The whole point: the plaintext must not be recoverable from the file.
  refute "plaintext is not in the ciphertext" grep -q 'hunter2' "$OVC/secrets/tok.age"

  out=$(ks secrets cat tok 2>/dev/null)
  [ "$out" = "TOKEN=hunter2" ]; check $? "secrets cat round-trips"

  listing=$(ks secrets ls 2>/dev/null); has "$listing" 'tok'; check $? "secrets ls shows it"
  ks secrets rekey >/dev/null 2>&1; check $? "secrets rekey runs"
  out=$(ks secrets cat tok 2>/dev/null)
  [ "$out" = "TOKEN=hunter2" ]; check $? "still decryptable after rekey"

  # A module declaring SECRETS= gets it materialised during apply.
  mkdir -p "$OVC/modules/withsecret"
  cat >"$OVC/modules/withsecret/module.sh" <<'EOF'
DESC="module with a secret"
SECRETS="tok:~/.tokrc:0600"
ks_check() { return 0; }
ks_install() { return 0; }
EOF
  printf '@include minimal\nwithsecret\n' >"$OVC/profiles/sec.profile"
  ks apply --files-only --profile sec -y >/dev/null 2>&1
  [ -f "$SANDBOX/home/.tokrc" ]; check $? "SECRETS= materialised during apply"
  [ "$(cat "$SANDBOX/home/.tokrc" 2>/dev/null)" = "TOKEN=hunter2" ]
  check $? "materialised content is correct"
  [ "$(filemode "$SANDBOX/home/.tokrc")" = 600 ]
  check $? "materialised with the declared mode"
  out=$(ks apply --files-only --profile sec -y 2>&1)
  has "$out" 'done: 0 changed'; check $? "re-apply does not rewrite the secret"

  # A host that is not a recipient must skip the secret, not fail the run.
  ssh-keygen -q -t ed25519 -N '' -f "$SANDBOX/home/.ssh/stranger" </dev/null
  printf 'KICKSTART_AGE_IDENTITY="%s"\n' "$SANDBOX/home/.ssh/stranger" \
    >>"$SANDBOX/home/.config/kickstart/config"
  rm -f "$SANDBOX/home/.tokrc"
  out=$(ks apply --files-only --profile sec -y 2>&1); rc=$?
  [ "$rc" = 0 ]; check $? "non-recipient host does not fail the run"
  has "$out" 'cannot decrypt'; check $? "non-recipient host warns and skips"
  [ ! -f "$SANDBOX/home/.tokrc" ]; check $? "no half-written secret left behind"
  refute "secrets cat fails cleanly for a non-recipient" ks secrets cat tok

  # Put the real identity back and confirm it works again.
  grep -v KICKSTART_AGE_IDENTITY "$SANDBOX/home/.config/kickstart/config" \
    >"$SANDBOX/cfg" && mv "$SANDBOX/cfg" "$SANDBOX/home/.config/kickstart/config"
  ks apply --files-only --profile sec -y >/dev/null 2>&1
  [ -f "$SANDBOX/home/.tokrc" ]; check $? "recipient host still gets the secret"

  # Nothing decrypted may be left lying around in the vault.
  [ -z "$(find "$OVC/secrets" -type f ! -name '*.age' ! -name 'recipients.txt')" ]
  check $? "no plaintext left in the vault directory"
fi

# --------------------------------------------------------------------------
section "doctor"
ks doctor >/dev/null 2>&1; [ $? -le 1 ]; check $? "doctor runs and reports"

# --------------------------------------------------------------------------
printf '\n'
if [ "$FAILED" = 0 ]; then
  printf '%sall checks passed%s\n' "$GRN" "$RST"
  exit 0
fi
printf '%s%d check(s) failed%s\n' "$RED" "$FAILED" "$RST"
exit 1
