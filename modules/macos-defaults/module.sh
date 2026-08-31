# macos-defaults -- system preferences that are tedious to set by hand.
#
# Every line here is a `defaults write`, which is idempotent, so this module is
# safe to re-run. Nothing destructive and nothing that needs a logout beyond
# the affected app being restarted.
DESC="Opinionated macOS system defaults"
TAGS="os"
REQUIRES_OS="darwin"

ks_check() { return 0; }
ks_install() { return 0; }

ks_configure() {
  ks_step "applying macOS defaults"

  # Keyboard: fast repeat, no substitutions fighting you while writing code.
  ks_run defaults write NSGlobalDomain KeyRepeat -int 2
  ks_run defaults write NSGlobalDomain InitialKeyRepeat -int 15
  ks_run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
  ks_run defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  ks_run defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  ks_run defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

  # Finder: show what is actually there.
  ks_run defaults write com.apple.finder AppleShowAllExtensions -bool true
  ks_run defaults write com.apple.finder ShowPathbar -bool true
  ks_run defaults write com.apple.finder ShowStatusBar -bool true
  ks_run defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  ks_run defaults write com.apple.finder _FXSortFoldersFirst -bool true
  ks_run defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  ks_run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # Save and print dialogs expanded by default.
  ks_run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  ks_run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true

  # Screenshots somewhere other than the Desktop.
  ks_mkdir "$HOME/Screenshots"
  ks_run defaults write com.apple.screencapture location -string "$HOME/Screenshots"
  ks_run defaults write com.apple.screencapture disable-shadow -bool true

  # Dock: get out of the way, no auto-rearranging.
  ks_run defaults write com.apple.dock autohide -bool true
  ks_run defaults write com.apple.dock autohide-delay -float 0
  ks_run defaults write com.apple.dock mru-spaces -bool false
  ks_run defaults write com.apple.dock show-recents -bool false

  ks_run defaults write com.apple.LaunchServices LSQuarantine -bool false

  if [ "${KS_DRY_RUN:-0}" != 1 ]; then
    killall Finder Dock SystemUIServer >/dev/null 2>&1 || true
  fi
  ks_info "some settings only apply to newly launched apps"
  return 0
}
