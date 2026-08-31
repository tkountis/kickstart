# kickstart

One command to bring any machine of mine up to speed, and keep it there.

macOS or Linux, personal or work, my laptop or a box three ssh hops away with
no internet access. Same repo, same commands, same conventions.

```sh
curl -fsSL https://raw.githubusercontent.com/tkountis/kickstart/main/install.sh | bash
```

That clones the repo to `~/.kickstart`, installs the tooling for this host's
profile, links the dotfiles, and wires the shell. Re-running it is safe.

With options:

```sh
curl -fsSL https://raw.githubusercontent.com/tkountis/kickstart/main/install.sh | bash -s -- \
  --profile work \
  --overlay git@github.example.com:me/kickstart-work.git
```

---

## Day to day

Five commands, all starting with `k`:

| | |
|---|---|
| `khelp [pattern]` | list every shell helper you have, with descriptions |
| `knew <topic>` | create a new helper file and open it |
| `kedit [topic]` | edit an existing helper (fzf picker with no argument) |
| `kreload` | load your changes into the current shell |
| `kup` | pull kickstart plus overlays and re-apply this host |

And the CLI behind them:

```sh
kickstart apply              # bring this box up to date
kickstart apply git tmux -v  # just these two, loudly
kickstart -n apply           # dry run: print everything, change nothing
kickstart status             # what this host is set up as
kickstart doctor             # check for problems
kickstart push build01       # install kickstart on a remote host over ssh
```

---

## The four ideas

### 1. Modules — a thing you want on a machine

A module is a directory with a `module.sh` in it. In the common case that file
is pure declaration:

```sh
# modules/ripgrep/module.sh
DESC="Fast recursive grep"
PROVIDES="rg"
PKG_BREW="ripgrep"
PKG_APT="ripgrep"
PKG_DNF="ripgrep"
```

Anything under the module's `files/` directory is a literal mirror of `$HOME`
and gets symlinked in:

```
modules/nvim/files/.config/nvim/init.lua  ->  ~/.config/nvim/init.lua
```

Existing real files are moved to `~/.local/state/kickstart/backups/<timestamp>/`
before being replaced, never deleted.

When declaration is not enough, define `ks_install` or `ks_configure` and do it
yourself in plain bash. See [docs/modules.md](docs/modules.md).

### 2. Profiles — which modules this host gets

Plain text lists:

```
# profiles/personal.profile
@include base
direnv
macos-defaults
```

`kickstart profile work` records the profile for this host in
`~/.config/kickstart/config`. Modules can gate themselves on it with
`REQUIRES_PROFILE="work"`.

### 3. Overlays — work tooling, kept private

Work environments have binaries and internal URLs that have no business being
in a public repo. An overlay is a second git repo with exactly the same layout,
layered on top:

```sh
kickstart overlay add git@github.example.com:me/kickstart-work.git
```

Its modules, profiles and shell helpers are found *before* the public ones, so
an overlay can add to kickstart or override any part of it. There is no second
mechanism to learn. See [docs/work.md](docs/work.md).

### 4. Helpers — shell functions you can actually find again

`shell/source/NN_topic.sh`, sourced by both bash and zsh, ordered by number:

```
00-09  environment and exports
10-19  PATH
20-29  aliases
30-49  general purpose functions
50-79  tool and domain specific functions
80-89  prompt and theming
90-99  completions, and anything that must load last
```

Files from kickstart and every overlay are interleaved by filename, so a work
overlay's `15_work_path.sh` lands between core's `10_path.sh` and
`20_aliases.sh` without either repo knowing about the other.

Document a function with a `#:` line and it shows up in `khelp`:

```sh
#: mkcd <dir> -- make a directory and cd into it
mkcd() { mkdir -p "$1" && cd "$1"; }
```

That comment *is* the registry. There is no index to keep in sync.
See [docs/helpers.md](docs/helpers.md).

---

## Remote hosts

For a box that cannot reach GitHub, push kickstart to it from your laptop:

```sh
kickstart push build01                          # the 'remote' profile
kickstart push build01 --profile minimal        # just shell + git
kickstart push build01 --files-only             # dotfiles only, no installs
kickstart push jump.corp --with-overlays        # include private overlays
```

This tars the local checkout, ships it over ssh, and runs `apply --offline` on
the far end. Offline mode skips anything marked `NET=1` and never tries to
reach the internet; native package managers still work against internal
mirrors. See [docs/remote.md](docs/remote.md).

---

## Secrets and keys

Currently: kickstart generates a per-host ssh key on request (`sshkey`) and
sources `~/.config/kickstart/env` for machine-local exports. Private keys are
never synced between machines.

An `age`-encrypted vault in the repo is designed but not yet built. The design,
the reasoning, and the alternatives considered are written up in
[docs/secrets.md](docs/secrets.md).

---

## Layout

```
install.sh              one-line bootstrap, standalone, no dependencies
bin/kickstart           the CLI
lib/                    core, platform, pkg, link, module, profile, overlay
modules/<name>/         module.sh + files/ (a mirror of $HOME)
profiles/<name>.profile which modules a host gets
shell/init.sh           the single line your rc files source
shell/source/NN_*.sh    shell helpers, auto-loaded in order
shell/khelp.sh          the helper registry reader
docs/                   the longer explanations
test/smoke.sh           end to end tests against a throwaway $HOME
```

---

## Design notes

**Plain bash, no framework.** No Nix, no Ansible, no chezmoi, no templating
language. The cost of those tools is not installing them, it is that in two
years you have to relearn them to fix one broken box at 11pm. Everything here
is shell you can read top to bottom, and `bash -x` tells you the whole story.

**bash 3.2 compatible.** macOS still ships bash 3.2. No associative arrays, no
`mapfile`, no `${x^^}` anywhere in `lib/` or `bin/`.

**Shell helpers are POSIX.** They are sourced by both bash and zsh, so they
avoid `[[ ]]`, arrays, and shell-specific syntax.

**Idempotent by construction.** Every run reports `changed / ok / skipped /
failed`. A second run of anything should report `0 changed`; the test suite
asserts it.

**Never clobber silently.** Existing files are backed up to a timestamped
directory. Config files kickstart does not own (`~/.bashrc`, `~/.ssh/config`)
get a single marked block and nothing else is touched.

**No hidden state.** The only state is the git checkout, the symlinks, a
one-line profile in `~/.config/kickstart/config`, and the backups directory.

### Non-goals

- Managing the OS itself (packages beyond dev tooling, kernels, users)
- Provisioning fleets — that is Ansible's job, this is for *my* machines
- Reproducibility guarantees — that is Nix's job, and it costs more than it
  is worth here

---

## Hacking

```sh
make test        # smoke tests against a throwaway $HOME
make lint        # shellcheck everything
make check       # both
```

Adding a tool you want everywhere:

```sh
kickstart new module <name>       # edit modules/<name>/module.sh
echo <name> >> profiles/base.profile
kickstart apply <name>
```
