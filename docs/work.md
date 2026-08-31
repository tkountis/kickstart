# Work environments

Work machines need two things the public repo cannot give them: tooling that
only exists behind the corporate network, and configuration that references
internal hostnames, teams, and URLs. Neither belongs in a public git repo.

The answer is an **overlay**: a second, private git repo with exactly the same
layout, layered on top of kickstart.

```sh
kickstart overlay add git@github.example.com:me/kickstart-work.git
kickstart profile work
kickstart apply
```

## What an overlay is

A directory that looks like kickstart:

```
kickstart-work/
  modules/<name>/module.sh
  modules/<name>/files/
  profiles/work.profile
  shell/source/NN_*.sh
```

It is cloned to `~/.local/share/kickstart/overlays/<name>` and searched
**before** the public repo. That single rule gives you three behaviours for
free:

- **Add** — a module or helper name that does not exist in core is simply new.
- **Override** — a module directory with the same name as a core one replaces
  it entirely.
- **Extend** — a `profiles/work.profile` in the overlay is found first, and can
  `@include base` to pull in everything from core.

Shell helpers interleave by filename across both repos, so overlay file
`15_work_path.sh` loads between core's `10_path.sh` and `20_aliases.sh`.

## Two independent gates

They compose, and they answer different questions.

**Where does the code live?** — public repo or private overlay. This is about
disclosure. An internal tool's name, its install URL, and its config all leak
information; put them in the overlay.

**Where does it get applied?** — `REQUIRES_PROFILE="work"` on a module. This is
about relevance. A module in the overlay still only runs on hosts you have
marked with `kickstart profile work`, which matters when the same overlay is
also cloned somewhere it should stay dormant.

```sh
# kickstart-work/modules/deploy-cli/module.sh
DESC="the internal deploy CLI"
REQUIRES_PROFILE="work"
NET=1                        # internal endpoint; skipped when pushed offline
PROVIDES="deploy"

ks_install() {
  ks_run pip3 install --user deploy-cli --index-url "$INTERNAL_PYPI"
}
```

## Marking a host

```sh
kickstart profile work        # writes ~/.config/kickstart/config
kickstart profile             # what am I?
kickstart status              # the full picture
```

This is deliberately explicit rather than sniffed from the hostname or DNS
domain. Auto-detection guesses wrong exactly once — on a personal laptop
joined to a corporate VPN, or a work box you are using for something else —
and then quietly applies the wrong thing. One command per machine, once.

If you do want it automatic, `install.sh --profile work` sets it during
bootstrap, so the one-liner your onboarding docs hand out can carry it.

## Git identity

`modules/git` ships a `.gitconfig` with:

```
[includeIf "gitdir:~/work/"]
	path = ~/.gitconfig.work
```

Clone work repos under `~/work/` and they get your work name and email
automatically. Everything else uses `~/.gitconfig.local`. Both files are
untracked and per-machine. This is git's own mechanism — no templating.

Add internal git hosts to the overlay's `.gitconfig.work`, or via
`~/.ssh/config.d/` entries shipped by an overlay ssh module.

## Bootstrapping a new work machine

```sh
curl -fsSL https://raw.githubusercontent.com/tkountis/kickstart/main/install.sh | bash -s -- \
  --profile work
```

The overlay needs an ssh key that the internal git host trusts, which does not
exist yet on a brand new box. So: bootstrap the public part first, generate a
key, register it, then add the overlay.

```sh
sshkey                                    # prints the public key to register
kickstart overlay add git@github.example.com:me/kickstart-work.git
kickstart apply
```

`install.sh --overlay <url>` does try the clone during bootstrap and degrades
to a warning if it fails, so the order above is a fallback, not a requirement.

## Keeping both in sync

```sh
kup     # git pull kickstart + every overlay, then re-apply
```

## Migrating an existing dotfiles repo

If you already have something like a `source/NN_*.sh` layout, the migration is
mostly a move:

1. `git init` the overlay, or reuse the existing private repo.
2. Move `source/*.sh` to `shell/source/*.sh` — the numbering convention is the
   same, so load order is preserved.
3. Add a `#:` line above each function you want in `khelp`. Optional, and can
   be done gradually; undocumented functions still work.
4. Turn `init/Brewfile-*` into modules. A whole Brewfile can be one module
   with `PKG_BREW` listing the formulae.
5. Move `config/*` into the relevant module's `files/.config/`.
6. Replace git submodules under `vendor/` with either a module that clones them
   (`ks_install`) or, if they are just shell, copy the files into
   `shell/source/` with a `90_` prefix.
