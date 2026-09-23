{
  description = "Offline laptop inspection NixOS live ISO";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      laptopCheck = pkgs.writeShellApplication {
        name = "laptop-check";
        runtimeInputs = with pkgs; [
          coreutils gnugrep gawk findutils util-linux
          inxi dmidecode pciutils usbutils lshw nvme-cli smartmontools
          lm_sensors edid-decode fwupd stress-ng memtester
          libinput evtest brightnessctl v4l-utils mpv alsa-utils
          networkmanager bluez bolt feh xorg.xrandr xorg.xsetroot
          udev systemd upower tlp jq
        ];
        text = builtins.readFile ./scripts/laptop-check.sh;
      };
      patterns = pkgs.runCommand "laptop-check-patterns" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        mkdir -p "$out"
        python3 ${./scripts/patterns.py} "$out"
      '';
      iso = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ({ ... }: {
            networking.networkmanager.enable = true;
            hardware.bluetooth.enable = true;
            services.hardware.bolt.enable = true;
            services.upower.enable = true;
            services.fwupd.enable = true;
            services.xserver.enable = true;
            services.xserver.windowManager.openbox.enable = true;
            services.xserver.displayManager.lightdm.enable = true;
            services.displayManager.defaultSession = "none+openbox";
            services.displayManager.autoLogin.enable = true;
            services.displayManager.autoLogin.user = "nixos";
            services.xserver.displayManager.sessionCommands = ''
              ${pkgs.xterm}/bin/xterm -fa Monospace -fs 13 -e ${pkgs.bashInteractive}/bin/bash -lc '${laptopCheck}/bin/laptop-check quick; exec bash' &
            '';
            users.users.nixos.extraGroups = [ "networkmanager" "video" "audio" ];
            environment.systemPackages = [ laptopCheck pkgs.xterm pkgs.openbox pkgs.feh ];
            environment.etc."laptop-check/patterns".source = patterns;
            # Favor fast decompression over ISO size for a short in-person inspection.
            isoImage.squashfsCompression = "gzip -Xcompression-level 1";
            system.stateVersion = "25.11";
          })
        ];
      };
    in {
      packages.${system} = {
        default = iso.config.system.build.isoImage;
        iso = iso.config.system.build.isoImage;
        laptop-check = laptopCheck;
      };
      nixosConfigurations.inspection = iso;
    };
}
