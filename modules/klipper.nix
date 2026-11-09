# services.klipper, rebased on the nixpkgs module (nixos-unstable, with CAN flashing) and replacing
# it: nixpkgs' moonraker module reads `services.klipper.{enable,apiSocket,mutableConfig}`, which
# keep their meaning here. Additions over nixpkgs: firmware built from any Klipper package (Kalico),
# the MCU connection set per firmware and written into the Klipper config, plugin configurations
# linked to /etc/klipper/plugins, Katapult bootloader builds, and the host as a Linux-process MCU.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) literalExpression mkEnableOption mkOption types;

  cfg = config.services.klipper;

  format = pkgs.formats.ini {
    # https://github.com/NixOS/nixpkgs/pull/121613#issuecomment-885241996
    listToValue = l:
      if builtins.length l == 1
      then lib.generators.mkValueStringDefault {} (lib.head l)
      else lib.concatMapStrings (s: "\n  ${lib.generators.mkValueStringDefault {} s}") l;
    mkKeyValue = key: value:
      lib.generators.mkKeyValueDefault {} ":" key (
        if builtins.isString value && lib.hasInfix "\n" value
        then "\n  ${lib.replaceString "\n" "\n  " value}"
        else value
      );
  };

  renderSections = sections: lib.optionalString (sections != {}) (format.generate "klipper.cfg" sections).text;

  sanitize = lib.strings.sanitizeDerivationName;

  firmwareSubmodule = types.submodule ({
    name,
    config,
    ...
  }: let
    fromConfig = key:
      config.mcu.${
        key
      }
      or (
        if cfg.settings != null && lib.hasAttrByPath [config.section key] cfg.settings
        then cfg.settings.${config.section}.${key}
        else null
      );
  in {
    options = {
      enable = mkEnableOption "building of firmware for manual flashing";

      enableKlipperFlash = mkEnableOption ''
        flashing scripts for firmware. This will add `klipper-flash-$mcu` scripts to your environment which can be called to flash the firmware.
        Please check the configs at [klipper](https://github.com/Klipper3d/klipper/tree/master/config) whether your board supports flashing via `make flash`
      '';

      configFile = mkOption {
        type = types.path;
        description = "Path to firmware config which is generated using `<package>-menuconfig`.";
      };

      section = mkOption {
        type = types.str;
        default =
          if name == "mcu"
          then "mcu"
          else "mcu ${name}";
        defaultText = literalExpression ''if name == "mcu" then "mcu" else "mcu ''${name}"'';
        example = "mcu toolhead";
        description = "The Klipper config section of this MCU, for `mcu` and to read `serial` and `canbus_uuid` from `settings`.";
      };

      mcu = mkOption {
        type = types.attrsOf (types.oneOf [types.bool types.int types.float types.str]);
        default = {};
        example = {
          canbus_uuid = "eb213ad58522";
        };
        description = ''
          Options of this MCU's Klipper config section (`[<section>]`), written into the generated
          config after `settings` or `configFile`. Klipper merges a section that a file included
          earlier also defines, and these values win, so the connection can live here while the rest
          of the printer stays in `.cfg` files.
        '';
      };

      serial = mkOption {
        type = types.nullOr types.path;
        default = fromConfig "serial";
        defaultText = literalExpression "mcu.serial, else settings.<section>.serial, else null";
        description = "Path to the serial port this MCU is connected to.";
      };

      canbus_uuid = mkOption {
        type = types.nullOr types.str;
        default = fromConfig "canbus_uuid";
        defaultText = literalExpression "mcu.canbus_uuid, else settings.<section>.canbus_uuid, else null";
        description = "CAN bus uuid of this MCU.";
      };

      canbusNetwork = mkOption {
        type = types.nullOr types.str;
        default =
          if config.canbus_uuid == null
          then null
          else lib.defaultTo "can0" (fromConfig "canbus_interface");
        defaultText = literalExpression ''if canbus_uuid != null then canbus_interface from the config or "can0" else null'';
        description = "CAN bus network this MCU is connected to.";
      };

      package = mkOption {
        type = types.nullOr types.package;
        readOnly = true;
        description = "The built firmware package.";
      };

      klipperFlashPackage = mkOption {
        type = types.nullOr types.package;
        readOnly = true;
        description = "The built klipper-flash package.";
      };
    };

    config = {
      package =
        if config.enable
        then
          cfg.firmware-package.override {
            mcu = sanitize name;
            firmwareConfig = config.configFile;
          }
        else null;

      klipperFlashPackage =
        if config.enable && config.enableKlipperFlash
        then
          pkgs.klipper-flash.override ({
              klipper = cfg.package;
              klipper-firmware = config.package;
              mcu = sanitize name;
              firmwareConfig = config.configFile;
            }
            // (
              if config.serial != null
              then {flashDevice = config.serial;}
              else {
                canbusDevice = config.canbus_uuid;
                inherit (config) canbusNetwork;
              }
            ))
        else null;
    };
  });

  enabledFirmwares = lib.filterAttrs (_: f: f.enable) cfg.firmwares;

  mcuSections = lib.mapAttrs' (_: f: lib.nameValuePair f.section f.mcu) (lib.filterAttrs (_: f: f.mcu != {}) cfg.firmwares);

  printerConfig =
    if cfg.settings != null
    then pkgs.writeText "klipper.cfg" (renderSections cfg.settings + renderSections mcuSections + cfg.extraSettings)
    else if mcuSections == {}
    then cfg.configFile
    else pkgs.concatText "klipper.cfg" [cfg.configFile (pkgs.writeText "klipper-mcus.cfg" ("\n" + renderSections mcuSections))];
in {
  disabledModules = ["services/misc/klipper.nix"];

  imports = [
    (lib.mkRenamedOptionModule ["services" "klipper" "mutableConfigFolder"] ["services" "klipper" "configDir"])
  ];

  options.services.klipper = {
    enable = mkEnableOption "Klipper, the 3D printer firmware";

    package = lib.mkPackageOption pkgs "klipper" {};

    firmware-package = mkOption {
      type = types.package;
      default = pkgs.klipper-firmware.override {klipper = cfg.package;};
      defaultText = literalExpression "pkgs.klipper-firmware.override { klipper = config.services.klipper.package; }";
      description = "The firmware package each `firmwares.<mcu>` overrides with its `mcu` and `firmwareConfig`.";
    };

    extraConfigurationPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = ''
        Packages with Klipper configuration (such as KAMP). Each one with `passthru.klipper.config` is
        linked to `/etc/klipper/plugins/<pname>`, like the plugins of `package`.
      '';
    };

    logFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/var/lib/klipper/klipper.log";
      description = ''
        Path of the file Klipper should log to.
        If `null`, it logs to stdout, which is not recommended by upstream.
      '';
    };

    inputTTY = mkOption {
      type = types.path;
      default = "/run/klipper/tty";
      description = "Path of the virtual printer symlink to create.";
    };

    apiSocket = mkOption {
      type = types.nullOr types.path;
      default = "/run/klipper/api";
      description = "Path of the API socket to create.";
    };

    mutableConfig = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether to manage the config outside of NixOS.

        It will still be initialized with the defined NixOS config if the file doesn't already exist.
      '';
    };

    configDir = mkOption {
      type = types.path;
      default = "/var/lib/klipper";
      description = "Folder of `printer.cfg` and Klipper's state; also the klipper user's home.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to default Klipper config.";
    };

    user = mkOption {
      type = types.str;
      default = "klipper";
      description = "User account under which Klipper runs.";
    };

    group = mkOption {
      type = types.str;
      default = "klipper";
      description = "Group account under which Klipper runs.";
    };

    settings = mkOption {
      type = types.nullOr format.type;
      default = null;
      description = ''
        Configuration for Klipper. See the [documentation](https://www.klipper3d.org/Overview.html#configuration-and-tuning-guides)
        for supported values.
      '';
    };

    extraSettings = mkOption {
      type = types.lines;
      default = "";
      description = "Extra lines to append to the generated Klipper configuration.";
    };

    firmwares = mkOption {
      description = "Firmwares Klipper should manage";
      default = {};
      type = types.attrsOf firmwareSubmodule;
      example = {
        toolhead = {
          enable = true;
          enableKlipperFlash = true;
          configFile = literalExpression "./klipper-ebb36.cfg";
          mcu.canbus_uuid = "eb213ad58522";
        };
      };
    };

    katapult = mkOption {
      description = "Katapult bootloader firmwares, linked to `/etc/klipper/katapult-firmwares/<mcu>`.";
      default = {};
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "building of the Katapult firmware for manual flashing";

          configFile = mkOption {
            type = types.path;
            description = "Path to firmware config which is generated using `katapult-menuconfig`.";
          };
        };
      });
    };

    host-mcu = {
      enable = mkEnableOption "the host as an additional MCU for Klipper";

      firmware-package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "The Linux-process firmware: `pkgs.klipper-firmware` overridden with a host MCU config.";
      };

      realtime = mkOption {
        type = types.bool;
        default = false;
        description = "Run with the realtime scheduler priority (the `-r` flag of klipper-mcu-start.sh).";
      };

      watchdog = mkOption {
        type = types.bool;
        default = false;
        description = "Pass `-w` to `klipper.elf`.";
      };

      serial = mkOption {
        type = types.str;
        default = "/run/klipper/host-mcu";
        description = "Serial file location";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      [
        {
          assertion = (cfg.configFile != null) != (cfg.settings != null);
          message = "You need to either specify services.klipper.settings or services.klipper.configFile.";
        }
        {
          assertion = (cfg.configFile != null) -> (cfg.extraSettings == "");
          message = "You can't use services.klipper.extraSettings with services.klipper.configFile.";
        }
        {
          assertion = cfg.host-mcu.enable -> cfg.host-mcu.firmware-package != null;
          message = "Option services.klipper.host-mcu.firmware-package is required for host-mcu to work.";
        }
      ]
      ++ lib.mapAttrsToList (mcu: firmware: {
        assertion = firmware.enableKlipperFlash -> (firmware.serial != null || firmware.canbus_uuid != null);
        message = ''
          Unable to determine the serial or canbus connection for services.klipper.firmwares."${mcu}". Please set one of the following:

            - services.klipper.firmwares."${mcu}".mcu.serial or .serial
            - services.klipper.firmwares."${mcu}".mcu.canbus_uuid or .canbus_uuid
            - services.klipper.settings."${firmware.section}".serial
            - services.klipper.settings."${firmware.section}".canbus_uuid
        '';
      })
      cfg.firmwares;

    environment.etc = let
      pluginsWithConfig = lib.filter (p: p ? klipper && p.klipper.config) ((cfg.package.plugins or []) ++ cfg.extraConfigurationPackages);

      katapultFirmwares = lib.mapAttrs' (name: fcfg:
        lib.nameValuePair (sanitize name) (pkgs.katapult-firmware.override {
          mcu = sanitize name;
          firmwareConfig = fcfg.configFile;
        }))
      (lib.filterAttrs (_: v: v.enable) cfg.katapult);
    in
      lib.listToAttrs (map (p: lib.nameValuePair "klipper/plugins/${p.pname}" {source = "${p}/lib/config";}) pluginsWithConfig)
      // lib.mapAttrs' (name: f: lib.nameValuePair "klipper/firmwares/${sanitize name}" {source = f.package;}) enabledFirmwares
      // lib.mapAttrs' (name: v: lib.nameValuePair "klipper/katapult-firmwares/${name}" {source = v;}) katapultFirmwares;

    environment.systemPackages =
      [(pkgs.klipper-menuconfig.override {klipper = cfg.package;})]
      ++ lib.mapAttrsToList (_: f: f.package) enabledFirmwares
      ++ lib.filter (p: p != null) (lib.mapAttrsToList (_: f: f.klipperFlashPackage) cfg.firmwares);

    systemd.services.klipper = let
      klippyArgs =
        "--input-tty=${cfg.inputTTY}"
        + lib.optionalString (cfg.apiSocket != null) " --api-server=${cfg.apiSocket}"
        + lib.optionalString (cfg.logFile != null) " --logfile=${cfg.logFile}";
    in {
      description = "Klipper 3D Printer Firmware";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      preStart = ''
        mkdir -p ${cfg.configDir}
        pushd ${cfg.configDir}
        if [ -e printer.cfg ]; then
          ${
          if cfg.mutableConfig
          then ":"
          else ''
            # Backup existing config using the same date format klipper uses for SAVE_CONFIG
            old_config="printer-$(date +"%Y%m%d_%H%M%S").cfg"
            mv printer.cfg "$old_config"
            # Preserve SAVE_CONFIG section from the existing config
            cat ${printerConfig} <(printf "\n") <(sed -n '/#*# <---------------------- SAVE_CONFIG ---------------------->/,$p' "$old_config") > printer.cfg
            ${pkgs.diffutils}/bin/cmp printer.cfg "$old_config" && rm "$old_config"
          ''
        }
        else
          cat ${printerConfig} > printer.cfg
        fi
        popd
      '';

      restartTriggers = lib.optionals (!cfg.mutableConfig) [printerConfig];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/klippy ${klippyArgs} ${cfg.configDir}/printer.cfg";
        RuntimeDirectory = "klipper";
        StateDirectory = "klipper";
        WorkingDirectory = "${cfg.package}/lib";
        User = cfg.user;
        Group = cfg.group;
        SupplementaryGroups = ["dialout"];
        OOMScoreAdjust = "-999";
        CPUSchedulingPolicy = "rr";
        CPUSchedulingPriority = 99;
        IOSchedulingClass = "realtime";
        IOSchedulingPriority = 0;
        UMask = "0002";
        Environment = ["KLIPPER_DIR=${cfg.package}/lib"];
      };
    };

    # Based on https://github.com/Klipper3d/klipper/blob/7290c14531211d027b430f36db5645ce496be900/scripts/klipper-mcu-start.sh
    systemd.services.klipper-mcu = lib.mkIf cfg.host-mcu.enable {
      description = "Starts the MCU for Klipper.";

      # Before klipper, which usually connects to the MCU's socket at start.
      before = ["klipper.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig =
        {
          ExecStart = "${cfg.host-mcu.firmware-package}/klipper.elf -I ${cfg.host-mcu.serial}${lib.optionalString cfg.host-mcu.watchdog " -w"}";
          User = cfg.user;
          Group = cfg.group;
        }
        // lib.optionalAttrs cfg.host-mcu.realtime {
          # https://github.com/Klipper3d/klipper/blob/master/src/linux/main.c#L25
          CPUSchedulingPolicy = "fifo";
          CPUSchedulingPriority = 44;
        };
    };

    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        extraGroups = ["dialout"];
        inherit (cfg) group;
        createHome = true;
        home = lib.mkDefault cfg.configDir;
        homeMode = "755";
      };
      groups.${cfg.group} = {};
    };
  };
}
