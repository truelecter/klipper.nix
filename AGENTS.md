# AGENTS.md

Klipper on NixOS: packages, plugins, and NixOS modules, consumed as a flake input (`overlays.default`, `nixosModules.default`).

## Layout

```text
flake.nix                    inputs, `packages`, `overlays.default`, `nixosModules.{default,klipper}`
lib/import-packages.nix      callPackage for every `<name>.nix` in a folder (`_`-prefixed names skipped)
packages/                    one package per file; `klipper.nix` is shared by Klipper and Kalico
packages/_files/             simulator.cfg (default firmware config), host-mcu.config (default host MCU config)
packages/_patches/           cross-ffi patches (Klipper and Kalico spelling)
packages/_deps-hash/         generated hashes (Mainsail's npm dependencies)
plugins/                     Klipper plugins; each sets `passthru.klipper` (extras, config, pythonDependencies)
modules/                     NixOS modules, all imported by `nixosModules.klipper`
sources/                     nvfetcher: `nvfetcher.toml` and the generated sources
.github/                     build on every push, weekly source and lock update
```

## Packages

- Sources come from nvfetcher (`sources/generated.nix`), mostly upstream HEAD. Update them with `nix develop -c nvfetcher --keep-old -c sources/nvfetcher.toml -o sources`, then `nix run .#mainsail.npmDepsHash > packages/_deps-hash/mainsail-npm.nix` when Mainsail moved. CI does both weekly.
- `flake.nix` builds the distributions from `packages/klipper.nix`: `klipper`, `kalico`, `kalico-experimental`, each with `-full-plugins`, `-firmware`, `-menuconfig`, `-olddefconfig`. Kalico installs Klippy as `lib/klippy` and loads plugins from `plugins/`; some plugins don't work on Kalico and are left out of its `-full-plugins`.
- `klipper.nix` installs `lib/scripts/flash_can.py` (Katapult's flashtool; Kalico still ships it as `lib/canboot/flash_can.py`) and `bin/klipper-canbus-query`. Cross builds apply `cross-ffi.patch` or `cross-ffi-kalico.patch`; a Kalico or Klipper update that reformats `klippy/chelper/__init__.py` breaks only the cross build.
- `klipper-firmware.nix` and `klipper-flash.nix` follow nixpkgs' `pkgs/servers/klipper/` (nixos-unstable). Differences: firmware for any Klipper package, `strictDeps` with `libusb1` in `buildInputs`, the toolchain's references removed from `klipper.elf` (`disallowedReferences` keeps `gcc-arm-embedded` out of system closures), and `klipper-flash`'s device check inside `text`, so `.override` works on the default package. Recheck against nixpkgs when updating them.
- `klipper-flash` has no standalone build (it needs a device), so it is left out of `packages`; the module builds one per MCU.
- On macOS, `packages` has only the menuconfig and olddefconfig tools.

## Modules

- `modules/klipper.nix` replaces nixpkgs' `services.klipper` (`disabledModules`), rebased on its nixos-unstable version, so nixpkgs' moonraker module keeps reading `services.klipper.{enable,apiSocket,mutableConfig}`. Keep those options and their meaning. On a nixpkgs update, diff `nixos/modules/services/misc/klipper.nix` there against this module and port what changed.
- Additions over nixpkgs: `firmware-package` (defaults to the firmware of `package`), `firmwares.<mcu>.katapultConfigFile` (builds that MCU's Katapult bootloader into `/etc/klipper/katapult-firmwares/<mcu>`, read-only `katapultPackage`), `extraConfigurationPackages` and plugin configs in `/etc/klipper/plugins`, `host-mcu` (the host as a Linux process MCU, `klipper.elf` from `firmware-package` with `host-mcu.configFile`, run by `klipper-mcu.service`), fixed `user`/`group` (no DynamicUser, moonraker shares the user), firmware links in `/etc/klipper/firmwares`. The other `firmwares.<mcu>` options follow nixpkgs, CAN flashing included, with `canbusUuid` in place of nixpkgs' `canbus_uuid`.
- `modules/spoolman.nix` replaces nixpkgs' `services.spoolman` the same way; its options differ (`dataDir`, `user`, `host`, `port`). `klipper-screen`, `camera-streamer`, and `mobileraker-companion` have no nixpkgs counterpart; if nixpkgs adds one under the same name, the evaluation fails with a duplicate option until the module here disables it.

## Test a change

- `nix flake check` (the current system; the Python packages read their requirements from fetched sources, so other systems need their own builder), then `nix build .#packages.aarch64-linux.<name>` (an aarch64-linux builder, or x86_64-linux for the same names).
- A module change: evaluate a throwaway `nixosSystem` with `nixosModules.default` and build what you touched, for example `config.services.klipper.firmwares.<mcu>.klipperFlashPackage` and `config.systemd.services.klipper.restartTriggers` (the generated `printer.cfg`).
- In a consumer, try a checkout before pushing: `--override-input klipper path:<this checkout>`.

## Commits

- Conventional Commits, scoped by area: `klipper` (the module and packages), `plugins`, `moonraker`, `mainsail`, `camera-streamer`, `klipper-screen`, `mobileraker`, `spoolman`, `ci`, `repo`, `deps`. For example `feat(klipper): ...`.
- Keep the commit body minimal: a few words at most, and none when the subject line already says it all.
