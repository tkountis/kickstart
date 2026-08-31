# shellcheck shell=sh
# Tool completions and keybindings. Loaded after 85_completion.sh has set up
# compinit/bashcompinit, and last enough that nothing overwrites them.
#
# Every entry is guarded on the tool existing, so this file is safe on a bare
# remote box where none of them are installed.
#
# Generating a completion script costs 10-30ms per tool, which is most of a
# shell startup once you have a few. _ks_eval_cached (see shell/init.sh) keeps
# the generated script under ~/.cache/kickstart and regenerates it when the
# tool is upgraded. `kcache clear` if you ever suspect it.
#
# Every shell-specific construct below is inside an `if [ -n "$ZSH_VERSION" ]`
# or bash equivalent, so it never runs in a shell that cannot handle it. The
# POSIX linter cannot see that, hence the blanket disable.
# shellcheck disable=SC3024,SC3030,SC3044,SC3046,SC3001,SC1090

if [ -n "${ZSH_VERSION:-}" ]; then
  _ks_shell=zsh
elif [ -n "${BASH_VERSION:-}" ]; then
  _ks_shell=bash
else
  _ks_shell="sh"
fi

# -- fzf ---------------------------------------------------------------------
# fzf 0.48+ generates its own integration; older versions dropped ~/.fzf.*
# during install. Try the modern path first.
if command -v fzf >/dev/null 2>&1; then
  if [ "$_ks_shell" != sh ] && fzf "--$_ks_shell" >/dev/null 2>&1; then
    _ks_eval_cached "fzf.$_ks_shell" fzf fzf "--$_ks_shell"
  elif [ -r "$HOME/.fzf.$_ks_shell" ]; then
    . "$HOME/.fzf.$_ks_shell"
  fi

  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height 40% --reverse --border --info=inline}"
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND="${FZF_DEFAULT_COMMAND:-fd --type f --hidden --exclude .git}"
    export FZF_CTRL_T_COMMAND="${FZF_CTRL_T_COMMAND:-$FZF_DEFAULT_COMMAND}"
  fi
fi

# -- kubectl -----------------------------------------------------------------
if command -v kubectl >/dev/null 2>&1 && [ "$_ks_shell" != sh ]; then
  _ks_eval_cached "kubectl.$_ks_shell" kubectl kubectl completion "$_ks_shell"
  # `k` is aliased to kubectl in 20_aliases.sh; complete it the same way.
  [ "$_ks_shell" = bash ] && complete -o default -F __start_kubectl k 2>/dev/null
fi

# -- gh ----------------------------------------------------------------------
if command -v gh >/dev/null 2>&1 && [ "$_ks_shell" != sh ]; then
  _ks_eval_cached "gh.$_ks_shell" gh gh completion -s "$_ks_shell"
fi

# -- direnv ------------------------------------------------------------------
if command -v direnv >/dev/null 2>&1 && [ "$_ks_shell" != sh ]; then
  _ks_eval_cached "direnv.$_ks_shell" direnv direnv hook "$_ks_shell"
fi

unset _ks_shell

#: kcache [ls|clear] -- inspect or throw away the shell startup cache
kcache() {
  case "${1:-ls}" in
    ls|list) ls -la "$KICKSTART_CACHE_DIR" 2>/dev/null || echo "no cache yet" ;;
    clear|clean)
      rm -rf "$KICKSTART_CACHE_DIR"
      echo "cache cleared; it rebuilds on the next shell (or run kreload)"
      ;;
    *) echo "usage: kcache [ls|clear]" >&2; return 2 ;;
  esac
}
