# Shell helpers

The part you touch most often, so it is designed to be forgettable and then
rediscoverable.

## The loop

```sh
knew kube          # creates shell/source/50_kube.sh and opens it
                   # ... write a function, document it with #:
                   # ... saving and quitting reloads automatically
khelp kube         # confirm it is registered
kubectx prod       # use it
```

Then commit it. `kup` on your other machines picks it up.

## Where they live

```
shell/source/NN_topic.sh
```

Sourced by both bash and zsh at shell startup, in filename order, from
kickstart **and** from every overlay. The number picks the load order:

| Band | For |
|---|---|
| `00-09` | environment and exports |
| `10-19` | PATH |
| `20-29` | aliases |
| `30-49` | general purpose functions |
| `50-79` | tool and domain specific functions |
| `80-89` | prompt and theming |
| `90-99` | completions, and anything that must load last |

`knew <topic>` defaults to the `50` band. Pass an explicit prefix when you need
a different one: `knew 15_work_path`.

Because ordering is by *filename across all repos*, a work overlay's
`15_work_path.sh` loads after core's `10_path.sh` and before `20_aliases.sh`.
Neither repo needs to know the other exists.

## Documenting a function

One comment line, immediately above it:

```sh
#: kubectx <ctx> -- switch kubectl context, with completion
kubectx() {
  kubectl config use-context "$1"
}
```

`khelp` scans every helper file for `#:` lines. That comment is the entire
registry — there is no index file that can drift out of date. Functions
without a `#:` line still work, they just do not advertise themselves.

## Portability rules

These files are sourced by **both bash and zsh**. Stick to POSIX:

- no `[[ ... ]]` — use `[ ... ]` and `case`
- no arrays
- no `${x^^}`, `${x,,}`, `local -n`
- no `function foo()` — just `foo()`
- prefix internal variables with `_` and `unset` them; there is no `local`
  keyword guarantee across shells for non-function scope
- guard on tool presence: `command -v fzf >/dev/null 2>&1 || return 1`

Shell-specific code is fine when it is guarded:

```sh
if [ -n "${ZSH_VERSION:-}" ]; then
  compdef _mything mything
elif [ -n "${BASH_VERSION:-}" ]; then
  complete -F _mything mything
fi
```

## Finding things

```sh
khelp                # everything
khelp git            # anything matching 'git'
kwhich gclone        # which file defines this?
kedit git            # open that file
```

## Machine-local values

Never put a hostname, API key, or internal URL in a tracked helper. Put it in:

```
~/.config/kickstart/env
```

which is sourced before any helper file and is never tracked. Helpers then
reference `$MY_INTERNAL_HOST` and stay committable.

## Startup cost

Every helper file is sourced on every shell start. The current set costs a few
milliseconds. If a helper needs something expensive (a completion script, a
`brew --prefix` call), do it lazily:

```sh
#: heavy -- does something expensive, set up on first use
heavy() {
  unset -f heavy
  . /some/expensive/setup.sh
  heavy "$@"
}
```

Set `KICKSTART_TRACE=1` in a new shell to see exactly which files are loaded
and in what order.
