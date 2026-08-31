# work -- work-issued machines.
#
# The interesting part of this profile is not here. A private overlay repo
# (kickstart overlay add git@github.example.com:you/kickstart-work.git) ships
# its own profiles/work.profile which is found first and which can @include
# this one. Modules in the overlay that set REQUIRES_PROFILE="work" will only
# ever apply on hosts marked with `kickstart profile work`.
@include base

gh
direnv
oh-my-bash
oh-my-zsh
iterm2
macos-defaults
