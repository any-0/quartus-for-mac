# Quartus for Mac

Intel Quartus Prime Lite plus a DE0-Nano programmer on Apple Silicon Macs, with one command.

Quartus only exists for x86 Windows and Linux, so this runs it in a small NixOS VM
(Apple's Virtualization.framework, via [microvm.nix](https://github.com/microvm-nix/microvm.nix) and vfkit)
and translates it with Rosetta. The board is programmed from macOS with
[openFPGALoader](https://github.com/trabucayre/openFPGALoader), because the VM can't see USB devices.

## Install

Open Terminal, paste this, press Return, and type your Mac password when asked:

```bash
mkdir -p ~/quartus-for-mac && curl -fsSL https://github.com/any-0/quartus-for-mac/archive/main.tar.gz | tar -xz --strip-components=1 -C ~/quartus-for-mac && bash ~/quartus-for-mac/install.sh
```

It takes 30–90 minutes, mostly downloading. The Mac stays awake while it runs.
If it stops partway, run the same line again.

**Needs:** a Mac with an Apple chip (M1 or newer), macOS 14+, 8 GB of memory, about 45 GB free disk space.

## Using it

- **Quartus** (in the Dock) opens Quartus. Closing Quartus closes its window.
- Save projects in the **FPGA** folder in your home folder. It's the same folder on the Mac and in Quartus.
- After compiling, plug in the board and click **Program DE0-Nano**:
  - **Load**: the design runs until the board is unplugged.
  - **Save**: the design is written to the board's flash and stays there.

## What it sets up

- Rosetta, if it's missing
- [Nix](https://github.com/NixOS/nix-installer) (upstream, no account needed)
- [nix-darwin](https://github.com/nix-darwin/nix-darwin) with nixpkgs' `darwin.linux-builder-vz`, a Linux builder
  that builds x86_64 packages through Rosetta
- A NixOS VM with XFCE that logs in automatically and starts Quartus Prime Lite 25.1 (Cyclone IV only).
  Every compiled `.sof` also gets an `.rbf` written next to it, which the programmer uses.
- The two apps in `~/Applications`, added to the Dock

Configuration ends up in `~/.config/quartus-mac`, and the VM's disk in `~/.local/share/quartus-vm`.

## Limitations

- No Questa simulator: it needs 32-bit x86, which Rosetta can't run. Icarus Verilog and GTKWave are installed in the VM instead.
- No Signal Tap or other live JTAG debugging from Quartus, since the VM has no USB access.
- Board files are set up for the DE0-Nano (`openFPGALoader -b de0nano`).

## Uninstall

```bash
bash ~/.config/quartus-mac/uninstall.sh
```

This removes the apps, the VM, nix-darwin and Nix. Projects in `~/FPGA` are kept.
