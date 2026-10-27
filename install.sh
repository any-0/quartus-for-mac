#!/bin/bash
# Sets up Quartus Prime Lite (inside a small Linux VM) and a DE0-Nano programmer
# on an Apple Silicon Mac. Safe to run again if it stops partway.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$HOME/.config/quartus-mac"
STATE="$HOME/.local/share/quartus-vm"
APPS="$HOME/Applications"
LOG="$HOME/Library/Logs/quartus-setup.log"
NIX=/nix/var/nix/profiles/default/bin/nix
NIXFLAGS=(--extra-experimental-features "nix-command flakes")

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() {
  printf '\n\033[1;31m%s\033[0m\n' "$*"
  printf '\nNothing is broken; you can run the installer again. Details: %s\n' "$LOG"
  osascript -e 'display alert "Quartus setup stopped" message "See the Terminal window for what went wrong."' >/dev/null 2>&1 || true
  exit 1
}
trap 'die "Something went wrong (line $LINENO)."' ERR

cat <<'EOF'

  Quartus for Mac: installer
  --------------------------
  This sets up Quartus and a DE0-Nano programmer. It takes 30-90 minutes,
  most of it downloading. Keep the Mac plugged in; it won't go to sleep.

EOF

# --- checks -----------------------------------------------------------------

[ "$(id -u)" -ne 0 ] || die "Please run this normally, not with sudo."
[ "$(uname -m)" = arm64 ] || die "This Mac has an Intel processor. This installer only works on Macs with Apple chips (M1 or newer)."

macos_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$macos_major" -ge 14 ] || die "Please update macOS (Apple menu > System Settings > General > Software Update) and run this again."

ram_gb=$(($(sysctl -n hw.memsize) / 1073741824))
[ "$ram_gb" -ge 8 ] || die "This Mac has ${ram_gb} GB of memory; Quartus needs at least 8 GB."
if [ "$ram_gb" -ge 16 ]; then vm_memory=8192; else vm_memory=4096; fi

if [ ! -e "$STATE/runner" ]; then
  free_gb=$(/bin/df -g / | awk 'NR==2 {print $4}')
  [ "$free_gb" -ge 60 ] || die "Not enough free disk space: ${free_gb} GB free, about 60 GB needed. Free some space (Apple menu > System Settings > General > Storage) and run this again."
fi

[ ! -e /usr/local/bin/determinate-nixd ] || die "This Mac has Determinate Nix installed, which this installer doesn't support."

# --- password ---------------------------------------------------------------

say "Your Mac login password is needed. Nothing shows up while you type it; just press Return at the end."
sudo -v || die "That password didn't work."
# keep sudo alive and the Mac awake until we're done
while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 30; done 2>/dev/null &
caffeinate -dims -w $$ &

# --- Rosetta ----------------------------------------------------------------

if [ ! -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ]; then
  say "Installing Rosetta (Apple's Intel translator)..."
  sudo softwareupdate --install-rosetta --agree-to-license
fi

# --- Nix --------------------------------------------------------------------

if [ ! -x "$NIX" ]; then
  say "Installing Nix (the package manager everything else is built with)..."
  curl --proto '=https' --tlsv1.2 -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --no-confirm
fi
set +u
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
set -u

# --- configuration ----------------------------------------------------------

say "Writing the configuration..."
mkdir -p "$CONFIG"
if [ "$SRC" != "$CONFIG" ]; then
  cp "$SRC"/flake.nix "$SRC"/flake.lock "$SRC"/darwin.nix "$SRC"/quartus-vm.nix "$SRC"/install.sh "$SRC"/uninstall.sh "$CONFIG/"
fi

# Linux keyboard layout matching the Mac's
layout_id=$(defaults read com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID 2>/dev/null || true)
case "${layout_id##*.}" in
  German) keyboard=de ;;
  Austrian) keyboard=at ;;
  SwissGerman | Swiss*) keyboard=ch ;;
  British*) keyboard=gb ;;
  French*) keyboard=fr ;;
  Spanish*) keyboard=es ;;
  Italian*) keyboard=it ;;
  Dutch) keyboard=nl ;;
  Swedish*) keyboard=se ;;
  Norwegian) keyboard=no ;;
  Danish) keyboard=dk ;;
  Finnish) keyboard=fi ;;
  Polish*) keyboard=pl ;;
  Portuguese) keyboard=pt ;;
  Canadian*) keyboard=ca ;;
  *) keyboard=us ;;
esac

# The VM's network card address is what the Questa license is tied to, so it's
# generated once and kept across reruns.
mac=$(sed -n 's/^ *mac = "\(.*\)";/\1/p' "$CONFIG/local.nix" 2>/dev/null || true)
if [ -z "$mac" ]; then
  mac=$(printf '02:%02x:%02x:%02x:%02x:%02x' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
fi
nic_id=$(printf '%s' "$mac" | tr -d :)

write_local() { # builder enabled: true/false
  cat >"$CONFIG/local.nix" <<EOF
# written by install.sh
{
  user = "$(id -un)";
  uid = $(id -u);
  vmMemory = $vm_memory;
  keyboard = "$keyboard";
  mac = "$mac";
  builder = $1;
}
EOF
}
write_local true

# --- nix-darwin -------------------------------------------------------------

say "Setting up the Mac side (Linux builder, board programmer)..."
# The Nix installer edits these; nix-darwin takes them over and refuses to
# overwrite files it doesn't recognise.
for f in /etc/nix/nix.conf /etc/bashrc /etc/zshrc /etc/zshenv /etc/zprofile /etc/bash.bashrc; do
  if [ -f "$f" ] && [ ! -L "$f" ] && grep -qi nix "$f"; then
    sudo mv "$f" "$f.before-nix-darwin"
  fi
done
sudo -H "$NIX" "${NIXFLAGS[@]}" run "$CONFIG#darwin-rebuild" -- switch --flake "$CONFIG#quartus"

say "Waiting for the Linux builder to start..."
builder_up=
for _ in $(seq 1 60); do
  if sudo ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new linux-builder true >/dev/null 2>&1; then
    builder_up=1
    break
  fi
  sleep 5
done
[ -n "$builder_up" ] || die "The Linux builder didn't start. Restarting the Mac and running this again usually fixes it."

# --- the VM -----------------------------------------------------------------

say "Building Quartus, Questa and the Linux VM. This is the long part (downloads ~8 GB)..."
mkdir -p "$STATE" "$HOME/FPGA"
"$NIX" "${NIXFLAGS[@]}" build "$CONFIG#quartus-vm" -o "$STATE/runner"

# The builder holds 4 GB of memory and a large disk image while it runs, and
# isn't needed again until the next install. Switching it off deletes both.
say "Switching off the Linux builder..."
write_local false
sudo -H /run/current-system/sw/bin/darwin-rebuild switch --flake "$CONFIG#quartus"

# --- apps -------------------------------------------------------------------

say "Creating the apps..."

make_app() { # name, id, script, [png icon]
  local app="$APPS/$1.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  printf '#!/bin/bash\n%s\n' "$3" >"$app/Contents/MacOS/run"
  chmod +x "$app/Contents/MacOS/run"
  if [ -n "${4:-}" ] && sips -s format icns "$4" --out "$app/Contents/Resources/icon.icns" >/dev/null 2>&1; then :; fi
  cat >"$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$1</string>
  <key>CFBundleIdentifier</key><string>local.quartus-mac.$2</string>
  <key>CFBundleExecutable</key><string>run</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
EOF
}

quartus_icon=$("$NIX" "${NIXFLAGS[@]}" eval --raw "$CONFIG#nixosConfigurations.quartus-vm.config.system.build.quartusIcon" 2>/dev/null || true)

make_app "Quartus" quartus '
if pgrep -qf "quartus-vm/home.img"; then
  osascript -e "display alert \"Quartus is already open.\""
  exit 0
fi
exec "$HOME/.local/share/quartus-vm/runner/bin/microvm-run"
' "$quartus_icon"

make_app "Program DE0-Nano" program-de0 '
alert() { osascript - "$1" "$2" <<EOF >/dev/null
on run argv
  display alert (item 1 of argv) message (item 2 of argv)
end run
EOF
}
rbf=$(find "$HOME/FPGA" -name "*.rbf" -exec stat -f "%m %N" {} + 2>/dev/null | sort -rn | head -n1 | cut -d" " -f2-)
if [ -z "$rbf" ]; then
  alert "No compiled design found" "Compile your project in Quartus first. Projects need to be saved in the FPGA folder."
  exit 0
fi
choice=$(osascript - "$(basename "$rbf" .rbf)" <<EOF
on run argv
  set msg to "Program the DE0-Nano with \"" & item 1 of argv & "\"?" & return & return & "Load: runs until the board is unplugged." & return & "Save: stays on the board permanently (slower)."
  return button returned of (display dialog msg buttons {"Cancel", "Save", "Load"} default button "Load" with title "DE0-Nano")
end run
EOF
) || exit 0
flag=
[ "$choice" = Save ] && flag=--flash
if out=$(/run/current-system/sw/bin/de0-program $flag "$rbf" 2>&1); then
  osascript -e "display notification \"Done\" with title \"DE0-Nano programmed\""
else
  alert "Programming failed" "Is the board plugged in over USB?

$(printf "%s" "$out" | tail -n 4)"
fi
'

# Dock icons, once
for name in "Quartus" "Program DE0-Nano"; do
  if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "$APPS/$name.app"; then
    defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file://$APPS/${name// /%20}.app/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
  fi
done
killall Dock 2>/dev/null || true

# Questa (the simulator) needs a free license from Altera, tied to the VM's network card
cat >"$HOME/FPGA/Questa-Lizenz.txt" <<EOF
Für die Simulation (Questa) braucht man eine kostenlose Lizenz von Altera.

1. Bei Altera ein Konto anlegen und im "Self-Service Licensing Center" (SSLC) anmelden.
2. Die kostenlose Lizenz "Questa - Altera FPGA Starter Edition" (SW-QUESTA) als
   FIXED-Lizenz mit 1 Platz anfordern.
3. Einen neuen Computer anlegen und als NIC ID diese Nummer angeben:

   $nic_id

4. Die Lizenzdatei (endet auf .dat) in diesen FPGA-Ordner legen und Quartus neu öffnen.

Die Lizenz läuft nach 12 Monaten ab und kann dann auf dieselbe Weise erneuert werden.
EOF

trap - ERR
say "All done!"
cat <<EOF

  - "Quartus" (in the Dock) opens Quartus. Closing Quartus closes its window.
  - Save projects in the "FPGA" folder (it's in your home folder in Finder).
  - After compiling, plug in the board and click "Program DE0-Nano".

EOF
osascript -e 'display alert "Quartus is ready" message "Click Quartus in the Dock to start it. Save projects in the FPGA folder; after compiling, use Program DE0-Nano."' >/dev/null 2>&1 || true
