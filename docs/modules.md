# Modules

A module is one thing you want on a machine: a binary, a config file, a system
setting, or any combination. It is a directory under `modules/`:

```
modules/<name>/
  module.sh          declarations and optional hooks (may be omitted)
  files/             mirror of $HOME, symlinked in
  files.darwin/      overlaid on files/ when on macOS
  files.linux/       overlaid on files/ when on Linux
```

Both parts are optional. A module with only `files/` is a pure dotfile module.
A module with only `module.sh` installs software and configures nothing.

## Creating one

```sh
kickstart new module mytool
```

That writes a commented template. Then add it to a profile and apply:

```sh
echo mytool >> profiles/base.profile
kickstart apply mytool -v
```

## Declarations

Everything is optional.

| Variable | Meaning |
|---|---|
| `DESC` | One line, shown in `kickstart list modules` |
| `TAGS` | Free-form, space separated. Informational for now |
| `PROVIDES` | Binaries this module provides. If all are on `PATH`, the install step is skipped |
| `PKG_BREW` | Homebrew formula names, space separated |
| `PKG_APT` | Debian/Ubuntu package names |
| `PKG_DNF` | Fedora/RHEL/Amazon package names |
| `CASK` | Homebrew casks (macOS GUI apps); ignored on Linux |
| `REQUIRES_OS` | `darwin`, `linux`, or both. Skipped elsewhere |
| `REQUIRES_PROFILE` | Only apply on hosts with this profile |
| `REQUIRES_CMD` | Skip unless these commands exist |
| `NET=1` | Needs direct internet; skipped under `--offline` |

A minimal module:

```sh
DESC="JSON on the command line"
PROVIDES="jq"
PKG_BREW="jq"
PKG_APT="jq"
PKG_DNF="jq"
```

## Hooks

Define these as shell functions in `module.sh` when declarations are not
enough. They run with `$KS_MODULE_DIR` set to the module's own directory.

### `ks_check`

Return 0 if the module is already installed. Overrides the default
`PROVIDES` check. Use it when the binary name does not match, or when
"installed" means something other than a binary existing.

```sh
ks_check() { [ -d "$HOME/.sdkman" ]; }
```

### `ks_install`

Do the install yourself. Overrides `PKG_*` entirely.

```sh
ks_install() {
  ks_mkdir "$HOME/.local/bin"
  ks_run curl -fsSL "https://example.com/tool-$KS_OS-$KS_ARCH" \
    -o "$HOME/.local/bin/tool"
  ks_run chmod +x "$HOME/.local/bin/tool"
}
```

### `ks_configure`

Runs on **every** apply, after files are linked. Must be idempotent. Call
`ks_touched` when it actually changed something so the run summary stays
honest.

```sh
ks_configure() {
  if [ ! -f "$HOME/.toolrc" ]; then
    printf 'defaults\n' >"$HOME/.toolrc"
    ks_touched
  fi
}
```

## Available helpers

Use these instead of raw commands so `--dry-run` and `--verbose` work.

| | |
|---|---|
| `ks_run <cmd>...` | run a command, respecting `--dry-run` |
| `ks_dry <text>` | under `--dry-run`, describe an action with no single command |
| `ks_sudo <cmd>...` | same, as root when needed |
| `ks_have <cmd>` | is a command on PATH? |
| `ks_mkdir <dir>` | idempotent `mkdir -p` |
| `ks_link_file <src> <dst>` | symlink one file, backing up what is there |
| `ks_pkg_install <pkg>...` | install via the detected package manager |
| `ks_ensure_block <file> <marker> <content>` | maintain a delimited block in a file you do not own |
| `ks_touched` | mark this module as having changed something |
| `ks_info` `ks_warn` `ks_error` `ks_chg` `ks_skip` `ks_debug` | logging |

And these variables: `KS_OS`, `KS_ARCH`, `KS_DISTRO`, `KS_FAMILY`, `KS_PKG`,
`KS_PKG_BIN`, `KS_PROFILE`, `KS_HOSTNAME`, `KS_FQDN`, `KS_ROOT`,
`KS_MODULE_DIR`, `KS_DRY_RUN`, `KS_OFFLINE`, `KS_CONFIG_DIR`, `KS_STATE_DIR`.

`KS_PKG` is the manager *family* (`brew` / `apt` / `dnf` / `none`), which is
what `PKG_*` lookups key off. `KS_PKG_BIN` is the binary to actually invoke;
they differ on Amazon Linux 2 and old CentOS, where the dnf-family manager is
still called `yum`.

## Apply order

For each module, in order:

1. **requirements** — `REQUIRES_*` and `NET` gates. Failing one is a *skip*,
   not an error.
2. **check** — `ks_check`, else all `PROVIDES` binaries present.
3. **install** — `ks_install`, else `PKG_<MGR>` + `CASK`. Skipped if step 2
   said it is already there, or under `--files-only`.
4. **link** — `files/` then `files.$KS_OS/`.
5. **configure** — `ks_configure`, always.

Each module runs in its own subshell, so a stray `cd`, `set -x`, or variable
cannot leak into the next one. The result comes back as an exit code:
`0` changed, `3` already ok, `4` skipped, `1` failed. A failed module does not
stop the run; the failures are listed in the summary at the end.

## Debugging one

```sh
kickstart apply <name> -v          # every command and its output
kickstart apply <name> -n          # print, do not execute
bash -x bin/kickstart apply <name> # the whole trace
```

## Conventions worth keeping

- **Do not own a file you did not create.** For `~/.bashrc`, `~/.ssh/config`
  and friends, use `ks_ensure_block` so the rest of the file survives.
- **Put machine-local values in `~/.config/kickstart/env`**, never in a tracked
  file. It is sourced by every interactive shell.
- **Keep configs offline-safe.** A config that downloads plugins on first run
  is useless on an air-gapped box. If you want the heavy version, make it a
  separate module gated on `REQUIRES_PROFILE="personal"`.
- **One module, one concern.** `core-cli` is a deliberate exception: a bundle
  of small tools that always travel together.
