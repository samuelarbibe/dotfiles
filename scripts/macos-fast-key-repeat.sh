#!/usr/bin/env sh
# macOS: maximize key repeat for editors (Neovim, etc.).
# Lower KeyRepeat = faster repeats while holding a key.
# Lower InitialKeyRepeat = shorter delay before repeat starts.
#
# A full logout (or reboot) is required before macOS applies KeyRepeat /
# InitialKeyRepeat everywhere. Reopening apps alone is not reliable.

set -eu

defaults write -g KeyRepeat -int 2
defaults write -g InitialKeyRepeat -int 10
# Avoid accent popup on long press; keys should repeat (better for Vim hjkl, etc.).
defaults write -g ApplePressAndHoldEnabled -bool false

echo "KeyRepeat=$(defaults read -g KeyRepeat 2>/dev/null || echo unset)"
echo "InitialKeyRepeat=$(defaults read -g InitialKeyRepeat 2>/dev/null || echo unset)"
echo "ApplePressAndHoldEnabled=$(defaults read -g ApplePressAndHoldEnabled 2>/dev/null || echo unset)"
echo "Done. Log out and back in (or reboot) for key repeat to take effect system-wide."
