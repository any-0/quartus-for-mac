#!/bin/bash
# Removes everything install.sh set up, including Nix. Leaves ~/FPGA (her projects) alone.
set -euo pipefail

read -r -p "Remove Quartus, its VM and Nix from this Mac? Projects in ~/FPGA are kept. [y/N] " ok
[ "$ok" = y ] || [ "$ok" = Y ] || exit 0

sudo -v
pkill -f "quartus-vm/home.img" 2>/dev/null || true

rm -rf "$HOME/Applications/Quartus.app" "$HOME/Applications/Program DE0-Nano.app" \
  "$HOME/.local/share/quartus-vm" "$HOME/.config/quartus-mac"

if [ -e /run/current-system/sw/bin/darwin-uninstaller ]; then
  sudo /run/current-system/sw/bin/darwin-uninstaller
fi
if [ -x /nix/nix-installer ]; then
  sudo /nix/nix-installer uninstall --no-confirm
fi

echo "Removed. Drag the two Dock icons out of the Dock to remove them."
