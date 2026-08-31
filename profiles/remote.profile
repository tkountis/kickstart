# remote -- pushed to another host over ssh with `kickstart push`.
#
# Assume no direct internet and possibly no sudo. Modules that need either are
# skipped automatically (--offline is implied by push), so this list is about
# intent: what is worth having on a box you only visit occasionally.
@include minimal

core-cli
tmux
