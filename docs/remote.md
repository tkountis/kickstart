# Remote hosts

Some boxes cannot reach GitHub: build machines on an internal network, jump
hosts, customer environments, anything behind a proxy that only allows the
company mirror. You still want your shell there.

```sh
kickstart push build01
```

That packages the local checkout, ships it over ssh, and runs `apply --offline`
on the far end. Your laptop is the delivery mechanism; the remote host needs
nothing but ssh and tar.

## Options

```sh
kickstart push build01                       # the 'remote' profile
kickstart push user@build01 --profile minimal
kickstart push build01 --files-only          # dotfiles and shell only, no installs
kickstart push jump.corp --with-overlays     # include private overlays
kickstart push build01 --dest '$HOME/kick'   # somewhere other than ~/.kickstart
kickstart push build01 -v                    # show everything
```

Or from the shell: `kpush build01`.

## What happens

1. `tar czf` the local `$KICKSTART_ROOT`, excluding `.git`. Typically well
   under a megabyte, so this is fast even on a bad link.
2. Unpack to `~/.kickstart.new` on the remote, then move it into place. The
   old copy is only removed once the new one has landed, so an interrupted
   push does not leave a half-installed tree.
3. With `--with-overlays`, each overlay is packaged and unpacked to
   `~/.local/share/kickstart/overlays/<name>` the same way.
4. Run `~/.kickstart/bin/kickstart apply --profile <p> --offline -y`.

## Offline mode

`push` always implies `--offline`, which means:

- Modules declaring `NET=1` are **skipped**, not failed.
- `brew update` and `brew install` are skipped — Homebrew needs the internet.
- `apt-get` and `dnf` still run. They usually work fine, because a locked-down
  box almost always has an internal mirror configured. If they fail, the module
  is reported as failed and the rest of the run continues.
- Everything file-based — shell integration, dotfiles, tmux, git config,
  neovim config — works unconditionally. On a box where you cannot install
  anything at all, that is still most of the value, and `--files-only` makes it
  explicit.

This is why `modules/neovim` ships a config with no plugin manager and
`modules/tmux` one with no TPM: a config that phones home on first launch is
useless in exactly this situation.

## Choosing what to send

Edit `profiles/remote.profile`. It is deliberately short:

```
@include minimal
core-cli
tmux
```

For a host you only pass through, `--profile minimal` (shell + git) is often
right. For a build box you live on, make a profile for it.

## No sudo

If the remote account cannot `sudo`, package installs will fail and be
reported. Options:

- `--files-only` — skip installs entirely.
- Use Homebrew on Linux (`~/.linuxbrew`), which is a user-space install. It
  needs internet during setup, so bootstrap it once while the box has access.
- Write `ks_install` hooks that drop static binaries into `~/.local/bin`.
  `~/.local/bin` is on `PATH` from `10_path.sh`.

## Updating a pushed host

Push again. It is idempotent, and the atomic swap means a re-push is safe:

```sh
kickstart push build01
```

There is no `git pull` on the remote — it has no git remote, by definition.
Your laptop is the source of truth.

## Limitations

Worth knowing before you rely on it:

- **No pre-downloaded binaries yet.** A planned `kickstart bundle` would fetch
  release tarballs for a target OS/arch into `cache/` and ship them with the
  push, so `ks_install` hooks could work with no network at all. Today,
  anything not in the internal package mirror has to be installed by hand.
- **One host at a time.** Loop in the shell if you need more; there is no
  inventory file and no parallelism, on purpose. Fleet management is Ansible's
  job.
- **Requires `tar` and a POSIX shell on the remote.** Both are safe
  assumptions on Linux and macOS; neither is on a switch or an appliance.
