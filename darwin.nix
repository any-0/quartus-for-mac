{ pkgs, local, ... }:

let
  # Programs the DE0-Nano from macOS. The VM can't see USB, so this runs natively.
  #   de0-program                 load newest .rbf under ~/FPGA into the FPGA (lost on power-off)
  #   de0-program path/to/x.rbf   load a specific file (.rbf or .svf)
  #   de0-program --flash [file]  write to the EPCS flash so it survives power cycles
  de0-program = pkgs.writeShellScriptBin "de0-program" ''
    set -euo pipefail
    mode=()
    if [ "''${1:-}" = "--flash" ]; then
      mode=(-f)
      shift
    fi

    file="''${1:-}"
    if [ -z "$file" ]; then
      file=$(find "$HOME/FPGA" -name '*.rbf' -exec stat -f '%m %N' {} + 2>/dev/null \
        | sort -rn | head -n1 | cut -d' ' -f2-)
      if [ -z "$file" ]; then
        echo "No compiled design found in the FPGA folder. Compile your project in Quartus first." >&2
        exit 1
      fi
    fi

    echo "programming DE0-Nano with $file"
    exec ${pkgs.openfpgaloader}/bin/openFPGALoader -b de0nano "''${mode[@]}" "$file"
  '';
in
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = local.user;
  system.stateVersion = 6;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # nixpkgs' Linux builder on Virtualization.framework; x86_64-linux builds (Quartus)
  # go through Rosetta. install.sh only enables it while building the VM.
  nix.linux-builder = {
    enable = local.builder;
    package = pkgs.darwin.linux-builder-vz;
    systems = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    # defaults to 1 core, which makes compiling through Rosetta crawl
    config.virtualisation.cores = 4;
    config.virtualisation.darwin-builder = {
      memorySize = 4 * 1024;
      # sparse; the Quartus build needs more than the 20 GiB default
      diskSize = 40 * 1024;
    };
  };

  environment.systemPackages = [
    de0-program
    pkgs.openfpgaloader
  ];
}
