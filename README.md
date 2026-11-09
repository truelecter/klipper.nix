# klipper.nix

Klipper on NixOS: Klipper and [Kalico](https://github.com/KalicoCrew/kalico) with plugins, firmware builds and flash scripts per MCU, Katapult, Moonraker, Mainsail, KlipperScreen, camera-streamer, the Mobileraker companion, and Spoolman. Everything follows upstream's main branches through [nvfetcher](https://github.com/berberman/nvfetcher), updated weekly.

## Use it

```nix
{
  inputs.klipper = {
    url = "github:truelecter/klipper.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # In a NixOS configuration: the modules plus the overlay.
  # imports = [inputs.klipper.nixosModules.default];
}
```

`nixosModules.default` imports every module and applies `overlays.default`; `nixosModules.klipper` is the modules alone.

```nix
{pkgs, ...}: {
  services.klipper = {
    enable = true;
    package = pkgs.kalico-full-plugins;
    settings."include /etc/klipper/main.cfg" = {};

    firmwares.toolhead = {
      enable = true;
      enableKlipperFlash = true; # klipper-flash-toolhead
      configFile = ./firmwares/klipper-ebb36; # from kalico-menuconfig
      mcu.canbus_uuid = "eb213ad58522"; # written into [mcu toolhead]
    };
  };

  services.moonraker = {
    enable = true;
    inherit (config.services.klipper) user group;
  };
}
```

## Modules

| Option                                 | What it is                                                                                                                                                                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `services.klipper`                     | Replaces the nixpkgs module (nixpkgs' moonraker module still finds it). Adds firmware from any Klipper package, `firmwares.<mcu>.mcu` (the MCU's config section, also used for flashing), Katapult builds, plugin configs, and the host MCU |
| `tl.services.klipper-screen`           | KlipperScreen in a cage kiosk, or under X                                                                                                                                                                                        |
| `tl.services.camera-streamer.instances` | One camera-streamer service per camera, optionally behind nginx                                                                                                                                                                 |
| `tl.services.mobileraker-companion`    | Push notifications for the Mobileraker app                                                                                                                                                                                       |
| `tl.services.spoolman`                 | Spoolman, built from its release's `uv.lock`                                                                                                                                                                                     |

## Packages

| Package                                                     | What it is                                                                                                     |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `klipper`, `kalico`, `kalico-experimental`                  | Klippy from the main branches; `<name>-full-plugins` bundles every plugin                                       |
| `<name>-firmware`, `<name>-menuconfig`, `<name>-olddefconfig` | MCU firmware from a menuconfig file, and the tools that write that file (they run on macOS too)              |
| `klipper-flash`                                             | `klipper-flash-<mcu>` over USB, serial, or CAN; built per MCU by `firmwares.<mcu>.enableKlipperFlash`           |
| `katapult-*`                                                | Katapult bootloader firmware, flashtool, and menuconfig                                                         |
| Plugins                                                     | `happy-hare`, `ercf`, `klipper-cartographer`, `klipper-klippain-shaketune`, `kamp`, `klicky-probe`, `klipper_tmc_autotune`, `klipper-led_effect`, `klipper-z_calibration`, `nevermore-*`, ... |
| `moonraker`, `mainsail`, `klipper-screen`, `camera-streamer`, `mobileraker-companion`, `spoolman` | The rest of the stack, from upstream's main branches                                  |

## Develop

[`AGENTS.md`](AGENTS.md) has the layout, how to update sources, and how to test a change.

## License

MIT, see [`COPYING`](COPYING).
