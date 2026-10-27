# NixOS guest (aarch64-linux) run by vfkit on Apple's Virtualization.framework.
# Quartus is x86_64-only and runs through Rosetta for Linux.
#
# Boots straight into Quartus; quitting Quartus shuts the VM down. Projects live in
# ~/FPGA, shared with the Mac, and every compiled .sof also gets an .rbf next to it
# for the "Program DE0-Nano" app.
{
  lib,
  pkgs,
  nixpkgs,
  local,
  ...
}:

let
  hostPkgs = nixpkgs.legacyPackages.aarch64-darwin;

  macHome = "/Users/${local.user}";
  stateDir = "${macHome}/.local/share/quartus-vm";
  projectDir = "${macHome}/FPGA";

  user = "student";
  home = "/home/${user}";

  pkgsX86 = import nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };

  # Cyclone IV only (DE0-Nano). Questa is dropped: it needs 32-bit x86, which Rosetta can't run.
  quartusArgs = {
    withQuesta = false;
    supportedDevices = [ "Cyclone IV" ];
  };
  quartus = pkgsX86.quartus-prime-lite.override (
    quartusArgs
    // {
      # only used by the opt-in reproducible-build mode; the real i686 one can't be built under Rosetta
      pkgsi686Linux = pkgsX86.pkgsi686Linux // {
        inherit (pkgsX86) libfaketime;
      };
      unwrapped = pkgsX86.quartus-prime-lite.unwrapped.override (
        quartusArgs
        // {
          # an x86_64 unstick can't load its seccomp filter when translated, so use the native one
          inherit (pkgs) unstick;
        }
      );
    }
  );

  # what the autologin session runs: Quartus, then power off when it's closed
  quartus-session = pkgs.writeShellScript "quartus-session" ''
    cd ${home}/FPGA || cd ${home}
    ${quartus}/bin/quartus
    systemctl poweroff
  '';

  # vfkit's virtio-gpu defaults to 800x600, which is unusable for Quartus
  vfkit = hostPkgs.writeShellScriptBin "vfkit" ''
    args=()
    for a in "$@"; do
      [ "$a" = virtio-gpu ] && a="virtio-gpu,width=1440,height=900"
      args+=("$a")
    done
    exec ${lib.getExe hostPkgs.vfkit} "''${args[@]}"
  '';
in
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "quartus-vm";
  system.stateVersion = "25.11";

  # for the app icon on the Mac
  system.build.quartusIcon = "${quartus.unwrapped}/quartus/adm/quartusii.png";

  microvm = {
    hypervisor = "vfkit";
    vmHostPackages = hostPkgs;
    vcpu = 4;
    mem = local.vmMemory;
    graphics.enable = true;

    vfkit = {
      package = vfkit;
      rosetta.enable = true;
    };

    preStart = ''
      mkdir -p ${stateDir} ${projectDir}
    '';

    shares = [
      {
        # host store, so the VM doesn't need its own copy of Quartus
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
      {
        proto = "virtiofs";
        tag = "fpga";
        source = projectDir;
        mountPoint = "${home}/FPGA";
      }
    ];

    # everything else is tmpfs; keep /home (Quartus settings, recent projects)
    volumes = [
      {
        image = "${stateDir}/home.img";
        mountPoint = "/home";
        size = 4096;
      }
    ];

    registerClosure = false;
  };

  # mount before activation creates the home directory
  fileSystems."/home".neededForBoot = true;

  nix.enable = false;

  # spelled out instead of isNormalUser, which refuses uids below 1000
  users.users.${user} = {
    uid = local.uid; # same uid as on the Mac, so ~/FPGA is writable
    group = "users";
    home = home;
    createHome = true;
    useDefaultShell = true;
    extraGroups = [ "wheel" ];
    password = "quartus";
  };
  security.sudo.wheelNeedsPassword = false;

  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    xkb.layout = local.keyboard;
  };
  services.displayManager.autoLogin = {
    enable = true;
    inherit user;
  };
  # no screen locker or screensaver getting in the way
  services.xserver.desktopManager.xfce.enableScreensaver = false;

  environment.etc."xdg/autostart/quartus.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Quartus
    Exec=${quartus-session}
  '';

  systemd.user.services.sof-to-rbf = {
    description = "Write an .rbf next to every compiled .sof in ~/FPGA";
    wantedBy = [ "default.target" ];
    path = [
      quartus
      pkgs.inotify-tools
    ];
    script = ''
      inotifywait -m -r -e close_write -e moved_to --format '%w%f' --include '\.sof$' ${home}/FPGA |
        while read -r sof; do
          sleep 2
          quartus_cpf --option=bitstream_compression=off -c "$sof" "''${sof%.sof}.rbf" || true
        done
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
    };
  };

  environment.systemPackages = [
    quartus
    pkgs.iverilog # native simulation, since Questa is out
    pkgs.gtkwave
  ];
}
