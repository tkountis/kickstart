# shellcheck shell=sh
# Rust toolchain, if one is installed.

[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

if command -v cargo >/dev/null 2>&1; then
  # Panics without a backtrace are useless, and the cost is zero until one
  # happens. Set RUST_BACKTRACE=full in ~/.config/kickstart/env if you want more.
  export RUST_BACKTRACE="${RUST_BACKTRACE:-1}"
fi
