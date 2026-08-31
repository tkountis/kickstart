# Testing without touching your machine

Four harnesses, in increasing order of isolation and cost. The first two are
completely safe to run on a working machine.

| | Isolates | Installs packages | Tests Linux |
|---|---|---|---|
| `make dry` | everything (changes nothing) | no | no |
| `make test` | `$HOME` | no | no |
| `make sandbox` | `$HOME` | no | no |
| `make docker` | everything | yes | yes |

---

## `make dry` — read-only against your real setup

```sh
kickstart apply --dry-run          # or: make dry
kickstart apply --dry-run -v       # with every command it would run
```

Prints every command and every symlink it would create, executes nothing. This
is the fastest way to see what kickstart would do to *your* machine, including
which of your existing files it would back up.

`kickstart doctor` is also read-only, and tells you what is already wired.

---

## `make test` — the assertion suite

```sh
./test/smoke.sh
```

~95 assertions against a `mktemp -d` home directory. Covers linking, backups,
idempotency, profiles, overlays, precedence, scaffolding, keys, the age vault,
and that both shells load. Takes a few seconds and needs no network.

This is what CI runs. Add an assertion for every bug you fix.

---

## `make sandbox` — an interactive throwaway home

```sh
./test/sandbox.sh                  # bash, personal profile
./test/sandbox.sh --shell zsh
./test/sandbox.sh --dirty          # include uncommitted changes
./test/sandbox.sh --profile work --overlay ~/path/to/private-overlay
./test/sandbox.sh --repo https://github.com/tkountis/kickstart.git
./test/sandbox.sh --keep           # leave the directory behind to poke at
```

Runs the real `install.sh`, against a real `git clone`, into a throwaway
`$HOME` — then drops you into a **login shell** inside it. You can type
`khelp`, open files, break things, and `exit` to make it all disappear.

It also checks the two properties worth checking automatically: that a second
apply reports `0 changed`, and that `bash -l` and `zsh -l` actually reach
kickstart.

By default it tests your committed HEAD, because that is what a real machine
would get. `--dirty` layers your working tree on top for the edit-test loop.

### What a `$HOME` override does not isolate

Worth being precise, because it is easy to assume more than you get:

- **Package installs.** `brew` writes to `/opt/homebrew`, `apt` to `/usr`.
  Installs are off by default (`--files-only`). `--install` turns them on, and
  then you are modifying the real machine — the script asks first and cannot
  undo it. Use `make docker` instead if you want to test installs.
- **macOS preferences.** `defaults write` talks to cfprefsd for the real
  logged-in user regardless of `$HOME`, and `killall Dock` restarts your actual
  desktop. Modules like this declare `SANDBOX_UNSAFE=1`; the sandbox sets
  `KICKSTART_SANDBOX=1` and they are skipped with a visible message.
- **ssh-agent, keychain, launchd.** Process- and system-level, not file-level.

---

## `make docker` — real installs, real Linux, fully disposable

```sh
./test/docker.sh                       # ubuntu 24.04
./test/docker.sh --image debian:12
./test/docker.sh --image fedora:41
./test/docker.sh --all                 # all three, sequentially
./test/docker.sh --shell               # interactive shell in the container
./test/docker.sh --offline             # apply as if there were no internet
./test/docker.sh --profile minimal
```

The only harness where nothing at all leaks: package installs, system files,
everything is inside a container that is deleted on exit. It is also the only
way to exercise the Linux paths from a Mac — `apt` vs `dnf`, the Debian
`fd`/`bat` binary renames, `sudo` handling, missing `hostname`.

Your working tree is what gets tested (tracked plus untracked, respecting
`.gitignore`), so no commit is needed.

`--offline` passes `--offline` to `kickstart apply` rather than cutting the
container's network. That is deliberate: the situation worth testing is "cannot
reach the internet, but the distro mirror works", which is what a locked-down
corporate box looks like and what `kickstart push` assumes. Removing the
network entirely would just fail to install `git` and prove nothing.

Requires Docker to be running. If it is not, the script says so and points you
at the other harnesses rather than failing obscurely.

---

## Testing a remote push

`kickstart push` needs a host you can ssh to. A container works:

```sh
docker run -d --name kspush -p 2222:22 rastasheep/ubuntu-sshd:18.04
ssh-copy-id -p 2222 root@localhost
kickstart push root@localhost -p 2222 --profile minimal   # see docs/remote.md
docker rm -f kspush
```

Any spare VM or box you do not mind resetting works equally well. Start with
`--files-only`, which cannot install anything.

---

## When you are ready for the real thing

In order:

```sh
make check                    # lint + assertions
make dry                      # see exactly what would change here
kickstart apply shell -v      # just the shell wiring, the reversible part
exec $SHELL -l                # confirm your shell still works
kickstart apply               # the rest
```

If something goes wrong:

- Your original files are in `~/.local/state/kickstart/backups/<timestamp>/`,
  moved not deleted. `cp -a` them back.
- `kickstart unlink` removes every symlink kickstart made and leaves installed
  packages alone.
- The blocks added to `~/.bashrc` and `~/.zshrc` are delimited with
  `# >>> kickstart:shell >>>` markers; deleting those blocks fully disables the
  shell integration.
- `kcache clear` if a cached completion ever looks stale.
