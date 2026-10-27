{
  description = "Quartus Prime Lite for the DE0-Nano on Apple Silicon Macs (NixOS VM + Rosetta)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      microvm,
      ...
    }:
    let
      # written by install.sh: { user, uid, vmMemory }
      local = import ./local.nix;

      quartusVm = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit nixpkgs local; };
        modules = [
          microvm.nixosModules.microvm
          ./quartus-vm.nix
        ];
      };
    in
    {
      nixosConfigurations.quartus-vm = quartusVm;

      packages.aarch64-darwin = {
        # Built by install.sh after the first switch, since it needs the Linux builder
        quartus-vm = quartusVm.config.microvm.declaredRunner;
        # same nix-darwin as in flake.lock, for the first switch
        inherit (nix-darwin.packages.aarch64-darwin) darwin-rebuild;
      };

      darwinConfigurations.quartus = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit local; };
        modules = [ ./darwin.nix ];
      };
    };
}
