{
  description = "Klipper for NixOS: Klipper and Kalico with plugins, firmware builds and flashers, Katapult, Moonraker, Mainsail, KlipperScreen, camera-streamer, Mobileraker companion, Spoolman";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Python environments from upstream lock files (Moonraker, Spoolman, the Cartographer plugin).
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        nixpkgs.follows = "nixpkgs";
      };
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({lib, ...}: let
      importPackages = import ./lib/import-packages.nix {inherit lib;};

      mkPackages = pkgs: let
        sources = pkgs.callPackage ./sources/generated.nix {};

        packages = importPackages {
          inherit sources;

          nixpkgs = pkgs;
          packages = ./packages;

          extraArguments = {
            inherit (inputs) pyproject-nix uv2nix pyproject-build-systems;
          };
        };

        klipper-plugins = importPackages {
          inherit sources;

          nixpkgs = pkgs;
          packages = ./plugins;

          extraArguments = {
            inherit (packages) chopper-resonance-tuner;
            inherit (inputs) pyproject-nix;
          };
        };

        klipper-distribution = {
          name,
          source,
          hasPlugins,
          isKalico,
        }: let
          klipper =
            packages.klipper.override
            {
              inherit isKalico;

              pluginsInstallDir =
                if hasPlugins
                then "plugins"
                else "extras";

              sources = {
                klipper = source;
              };
            };

          excluded-plugins = lib.optionals isKalico [
            "klipper-gcode_shell_command"
            "klipper-z_calibration"
            "klipper-cartographer"
          ];
        in {
          ${name} = klipper;

          "${name}-full-plugins" = klipper.override {
            plugins = lib.attrValues (lib.filterAttrs (n: _: !builtins.elem n excluded-plugins) klipper-plugins);
          };

          "${name}-menuconfig" = packages.klipper-menuconfig.override {
            inherit klipper;
          };

          "${name}-olddefconfig" = packages.klipper-olddefconfig.override {
            inherit klipper;
          };

          "${name}-firmware" = packages.klipper-firmware.override {
            inherit klipper;
          };
        };
      in
        packages
        # TODO: prefix plugins with klipper- if the name does not have this prefix
        // klipper-plugins
        // {
          klipper-full-plugins = packages.klipper.override {
            plugins = lib.attrValues klipper-plugins;
          };
        }
        // (
          klipper-distribution {
            name = "kalico";
            source = sources.kalico;
            hasPlugins = true;
            isKalico = true;
          }
        )
        // (
          klipper-distribution {
            name = "kalico-experimental";
            source = sources.experimental-kalico;
            hasPlugins = true;
            isKalico = true;
          }
        )
        // {
          camera-streamer-libcamera = packages.camera-streamer.override {
            useLibcamera = true;
          };
        };

      # Builders with Klipper's sources only; they run anywhere `make menuconfig` does.
      configTools = [
        "kalico-menuconfig"
        "kalico-olddefconfig"
        "kalico-experimental-menuconfig"
        "kalico-experimental-olddefconfig"
        "klipper-menuconfig"
        "klipper-olddefconfig"
        "katapult-menuconfig"
        "katapult-olddefconfig"
      ];

      # Built per use from arguments they can't default: the device to flash, the MCU's menuconfig
      # file. The module builds them for each `firmwares.<mcu>` and `katapult.<mcu>`.
      notStandalone = ["klipper-flash" "katapult-firmware"];
    in {
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        klipperPackages = lib.removeAttrs (mkPackages pkgs) notStandalone;
      in {
        # With the overlay, so packages that take each other (`klipper`, `klipper-firmware`,
        # `klipper-flash`) get this flake's versions, as on a system that applies it.
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [self.overlays.default];
        };

        packages =
          if lib.hasSuffix "-linux" system
          then klipperPackages
          else lib.filterAttrs (n: _: builtins.elem n configTools) klipperPackages;

        devShells.default = pkgs.mkShellNoCC {
          packages = [pkgs.nvfetcher];
        };

        formatter = pkgs.alejandra;
      };

      flake = {
        overlays.default = final: _prev: mkPackages final;

        nixosModules = {
          # The modules alone; the packages they default to come from `overlays.default`.
          klipper = {
            imports = map (name: ./modules + "/${name}") (
              lib.attrNames (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name && !lib.hasPrefix "_" name) (builtins.readDir ./modules))
            );
          };

          default = {
            imports = [self.nixosModules.klipper];
            nixpkgs.overlays = [self.overlays.default];
          };
        };
      };
    });
}
