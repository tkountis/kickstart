# CLAUDE.md

Working rules for this repo. Read before changing anything.

kickstart bootstraps and maintains working environments across macOS and Linux.
The whole value proposition is that it stays boring: plain shell you can read
top to bottom and debug with `bash -x` two years from now. Every rule below
exists to protect that.

---

## Hard rules

**Plain bash. No frameworks.** No Nix, no Ansible, no chezmoi, no templating
language, no new runtime dependency. If a problem seems to need one, it almost
certainly needs less code instead. `git`, `curl`, `tar`, `ssh` and a package
manager are the only assumptions.

**`lib/` and `bin/` must run on bash 3.2.** macOS still ships it. That means no
associative arrays, no `mapfile`/`readarray`, no `${x^^}`/`${x,,}`, no
`declare -n`. Use `tr` for case conversion. Indexed arrays and `+=` are fine.

**`shell/source/*.sh` must be POSIX.** Those files are sourced by *both* bash
and zsh. No `[[ ]]`, no arrays, no `FUNCNAME`, no `BASH_SOURCE`, no
`function f()`. Use `[ ]` and `case`. Prefix internals with `_` and `unset`
them. When portability genuinely is not worth it, name the file
`NN_topic.bash` or `NN_topic.zsh` — it is then only sourced by that shell.

**No `set -e` in `bin/kickstart`.** Return codes carry meaning here (see
below); `-e` turns that into unreadable control flow. Use `set -uo pipefail`
and check every call site explicitly.

**Everything is idempotent.** A second run of anything must report
`0 changed`. `test/smoke.sh` asserts this; do not weaken it.

**Never clobber a file we do not own.** For `~/.bashrc`, `~/.ssh/config` and
similar, use `ks_ensure_block` so the rest of the file survives. For files we
do own, existing real files are moved to
`~/.local/state/kickstart/backups/<run-id>/`, never deleted.

**No hidden state.** The only state is: the git checkout, the symlinks, one
line in `~/.config/kickstart/config`, the overlay clones under
`~/.local/share/kickstart`, the backups directory, and the startup cache in
`~/.cache/kickstart`. Do not add a database, a manifest, or a lock file.

---

## Return code protocol

Every module and most helpers use these. They are not exit statuses in the
usual sense — they are a status enum.

| Code | Meaning | Constant |
|---|---|---|
| 0 | changed something | `KS_RC_CHANGED` |
| 3 | already correct, did nothing | `KS_RC_OK` |
| 4 | skipped (a requirement gate said no) | `KS_RC_SKIP` |
| 1 | failed | `KS_RC_FAIL` |

A failed module does **not** abort the run. Failures are collected and listed
in the summary. A skip is not a failure: a module that cannot apply on this
host is a normal outcome, and saying so plainly is the whole point.

---

## Module rules

Declarative first. `PROVIDES` + `PKG_BREW`/`PKG_APT`/`PKG_DNF` covers most
cases and needs no code. Reach for `ks_install` / `ks_check` / `ks_configure`
only when declaration cannot express it.

- `ks_configure` runs on **every** apply. It must be idempotent, and must call
  `ks_touched` when it actually changed something, or the run summary lies.
- Use `ks_run` / `ks_sudo` for anything that mutates. That is what makes
  `--dry-run` and `--verbose` work. Direct command invocation silently breaks
  both. Use `ks_dry` to describe an action that has no single command to echo.
- Gate rather than fail. `REQUIRES_OS`, `REQUIRES_PROFILE`, `REQUIRES_CMD`,
  `NET=1` all produce skips.
- Set `SANDBOX_UNSAFE=1` if the module writes state outside `$HOME` (macOS
  `defaults`, `launchctl`, anything system-wide). `test/sandbox.sh` sets
  `KICKSTART_SANDBOX=1` and such modules are skipped.
- Keep shipped configs offline-safe. A config that downloads plugins on first
  run is useless on an air-gapped box, which is where this tool earns its
  keep. Heavyweight variants belong in a separate module.
- `files/` mirrors `$HOME` literally. Individual files are symlinked, never
  whole directories, so a tool that writes state next to its config does not
  write into the repo.

---

## Naming

| Prefix | Scope |
|---|---|
| `ks_*` | functions in `lib/`, callable from module hooks |
| `KS_*` | variables internal to the CLI process |
| `KICKSTART_*` | variables a user's shell sees or sets |
| `_ks_*` | internals inside `shell/source/` and `shell/init.sh` |

Helper files use number bands: `00-09` env, `10-19` PATH, `20-29` aliases,
`30-49` general functions, `50-79` tool/domain specific, `80-89` prompt,
`90-99` completions and anything that must load last.

---

## Public repo hygiene

This repo is published. Nothing environment-specific about any particular
employer, network, or machine goes in it — no internal hostnames, tool names,
tap URLs, team names, or ticket links. That material belongs in a private
overlay repo, which is a first-class documented mechanism (`docs/work.md`), not
a workaround.

When writing examples in docs, use obviously generic placeholders
(`git@github.example.com`, `deploy-cli`, `INTERNAL_PYPI`). Grep before
committing:

```sh
git diff --cached | grep -iE '<your org>|corp\.|internal hostname patterns'
```

Secrets: never commit plaintext. Only `*.age` ciphertext and
`recipients.txt` are tracked, and `.gitignore` enforces that. Private ssh keys
are generated per host and never travel — only public keys are ever copied.

---

## Testing

Run before every commit:

```sh
make check          # shellcheck + the smoke suite
```

- `test/smoke.sh` — ~95 assertions against a throwaway `$HOME`. Never touches
  the real home directory. Add an assertion for every bug you fix.
- `test/sandbox.sh` — bootstraps into a throwaway `$HOME` and drops you into an
  interactive login shell. Use `--dirty` to include uncommitted changes;
  without it you are testing committed HEAD, which is what a real machine gets.
- `test/docker.sh` — the Linux paths and real package installs, disposable.
- CI covers ubuntu/debian/fedora bootstraps and macOS.

Anything that writes outside `$HOME` cannot be sandboxed by overriding `$HOME`.
See `SANDBOX_UNSAFE` above.

Shell startup is a budget, not free. Keep it under ~30ms warm. Anything that
shells out at startup (completion generation, `brew shellenv`) goes through
`_ks_eval_cached`.

---

## Portability traps already paid for

Do not undo these. Each one cost real debugging time.

**`readlink -f` canonicalises symlinked parents.** `/var` → `/private/var` on
macOS, `/home` → `/export/home` on plenty of NFS setups. Comparing a
canonicalised path against the path we wrote never matches, so every apply
relinks everything. Use `ks_link_target` (plain `readlink`) — we wrote the
link, so a literal comparison is correct.

**zsh errors on unmatched globs.** `for f in dir/*.bash` aborts when there is
no match, unlike bash which passes the pattern through. Use `find` when a glob
might not match.

**`cmd | grep -q` returns 141 under `pipefail`.** grep exits on first match,
the producer gets SIGPIPE. In tests, capture to a variable and match against
that (`has()` in `smoke.sh`).

**`sort -k1,1` is not stable.** With equal keys GNU sort falls back to
comparing whole lines. `sort -s` is required for "overlay wins over core" to
be deterministic.

**A bash login shell never reads `.bashrc`.** It reads the first of
`.bash_profile` / `.bash_login` / `.profile` that exists — and on a fresh
`$HOME` none of them do. Every macOS terminal window is a login shell. The
`shell` module creates `.bash_profile` for this reason.

**macOS `defaults` ignores `$HOME`.** It talks to cfprefsd for the real
logged-in user. Overriding `$HOME` does not sandbox it.

**`stat` flags differ.** BSD `stat -f '%OLp'` vs GNU `stat -c '%a'`. Branch on
`$KS_OS`.

**`KS_PKG` is a family, `KS_PKG_BIN` is the binary.** They differ where the
dnf-family manager is still called `yum`.

---

## Commits

Explain *why*, not what — the diff already says what. When a change fixes a
non-obvious bug, describe the failure mode so the next reader does not
reintroduce it. Note behaviour changes that a user would notice.

Do not commit or push unless asked.
