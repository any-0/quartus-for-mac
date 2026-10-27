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

  # Cyclone IV only (DE0-Nano)
  supportedDevices = [ "Cyclone IV" ];
  quartus = pkgsX86.quartus-prime-lite.override {
    inherit supportedDevices;
    # Questa itself is 64-bit; this only drops the 32-bit libraries the wrapper would
    # add for it, which Rosetta can't run
    withQuesta = false;
    # only used by the opt-in reproducible-build mode; the real i686 one can't be built under Rosetta
    pkgsi686Linux = pkgsX86.pkgsi686Linux // {
      inherit (pkgsX86) libfaketime;
    };
    unwrapped = pkgsX86.quartus-prime-lite.unwrapped.override {
      inherit supportedDevices;
      withQuesta = true;
      # an x86_64 unstick can't load its seccomp filter when translated, so use the native one
      inherit (pkgs) unstick;
    };
  };

  questaLicense = "${home}/.questa/license.dat";

  # Openbox with its default config, plus: normal windows open maximized, and no
  # minimize button, since there's no taskbar to bring a minimized window back
  openboxConfig = pkgs.runCommand "openbox-rc.xml" { } ''
    sed \
      -e 's|<titleLayout>NLIMC</titleLayout>|<titleLayout>NLMC</titleLayout>|' \
      -e 's|</applications>|<application type="normal"><maximized>yes</maximized></application></applications>|' \
      ${pkgs.openbox}/etc/xdg/openbox/rc.xml > $out
  '';

  # the X session: just Quartus under Openbox; power off when Quartus is closed
  quartus-session = pkgs.writeShellScript "quartus-session" ''
    ${pkgs.openbox}/bin/openbox --config-file ${openboxConfig} &

    # newest Questa license dropped into ~/FPGA (see Questa-Lizenz.txt there)
    lic=$(ls -t ${home}/FPGA/*.dat 2>/dev/null | head -n1)
    if [ -n "$lic" ]; then
      mkdir -p ${home}/.questa
      cp "$lic" ${questaLicense}
    fi

    cd ${home}/FPGA || cd ${home}
    ${quartus}/bin/quartus
    sudo -n systemctl poweroff
  '';

  # vfkit's virtio-gpu defaults to 800x600; install.sh sizes it to fit her screen
  vfkit = hostPkgs.writeShellScriptBin "vfkit" ''
    args=()
    for a in "$@"; do
      [ "$a" = virtio-gpu ] && a="virtio-gpu,width=${toString local.screen.width},height=${toString local.screen.height}"
      args+=("$a")
    done
    exec ${lib.getExe hostPkgs.vfkit} "''${args[@]}"
  '';
in
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "quartus-vm";
  system.stateVersion = "25.11";

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

    # absolute: the app starts the VM with / as working directory
    socket = "${stateDir}/quartus-vm.sock";

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

    # fixed address, since the Questa license is tied to it
    interfaces = [
      {
        type = "user";
        id = "net0";
        mac = local.mac;
      }
    ];

    registerClosure = false;
  };

  environment.sessionVariables.SALT_LICENSE_SERVER = questaLicense;

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

  # No display manager: LightDM only autologins uids >= 1000, and the uid has to
  # match the Mac's. Instead the console logs in by itself and starts X.
  services.getty.autologinUser = user;
  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    xkb.layout = local.keyboard;
  };
  environment.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "$DISPLAY" ]; then
      exec startx ${quartus-session}
    fi
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
    pkgs.iverilog
    pkgs.gtkwave
  ];
}
