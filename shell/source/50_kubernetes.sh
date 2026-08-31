# shellcheck shell=sh
# kubectl and friends. Completions live in 90_completions.sh, because zsh
# needs compinit to have run first.

#: kctx [name] -- show or switch kubectl context (fzf picker with no argument)
kctx() {
  command -v kubectl >/dev/null 2>&1 || { echo "no kubectl" >&2; return 1; }
  if [ -n "${1:-}" ]; then kubectl config use-context "$1"; return $?; fi
  if command -v fzf >/dev/null 2>&1; then
    _c=$(kubectl config get-contexts -o name | fzf --height 40% --reverse) || return 1
    [ -n "$_c" ] && kubectl config use-context "$_c"
    unset _c
  else
    kubectl config get-contexts
  fi
}

#: kns [name] -- show or switch the default namespace for this context
kns() {
  command -v kubectl >/dev/null 2>&1 || { echo "no kubectl" >&2; return 1; }
  if [ -n "${1:-}" ]; then
    kubectl config set-context --current --namespace "$1"
  else
    kubectl config view --minify -o jsonpath='{..namespace}'; echo
  fi
}

#: kpods [ns] -- pods in a namespace, wide
kpods() { kubectl get pods -o wide ${1:+-n "$1"}; }

#: klog <pod> [ns] -- follow logs for a pod
klog() {
  [ -n "${1:-}" ] || { echo "usage: klog <pod> [ns]" >&2; return 2; }
  kubectl logs -f "$1" ${2:+-n "$2"}
}

#: ksh <pod> [ns] -- shell into a pod, falling back to sh
ksh() {
  [ -n "${1:-}" ] || { echo "usage: ksh <pod> [ns]" >&2; return 2; }
  kubectl exec -it "$1" ${2:+-n "$2"} -- bash 2>/dev/null ||
    kubectl exec -it "$1" ${2:+-n "$2"} -- sh
}
