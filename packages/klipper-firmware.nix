# Rebased on nixpkgs' pkgs/servers/klipper/klipper-firmware.nix (nixos-unstable), for any Klipper
# package (Klipper, Kalico): the firmware of one MCU from its menuconfig file, the flash tools the
# flash scripts need, and `passthru.makeFlasher`.
args @ {
  klipper-firmware,
  stdenv,
  lib,
  pkg-config,
  pkgsCross,
  bintools-unwrapped,
  libffi,
  libusb1,
  wxwidgets_3_2,
  python3,
  gcc-arm-embedded,
  removeReferencesTo,
  klipper,
  avrdude,
  stm32flash,
  klipper-flash,
  mcu ? "mcu",
  firmwareConfig ? ./_files/simulator.cfg,
  ...
}:
# are used by flash scripts
# find those with `rg '\[\"lib'` inside of klipper repo
let
  needsBossac = let
    lines = lib.strings.splitString "\n" (builtins.readFile firmwareConfig);
  in
    builtins.any (line: builtins.match "[^#\r\n]*CONFIG_MACH_ATSAMD?=y.*" line != null) lines;
  flashBinaries =
    [
      "lib/hidflash/hid-flash"
      "lib/rp2040_flash/rp2040_flash"
    ]
    ++ lib.optional needsBossac "lib/bossac/bin/bossac";
in
  stdenv.mkDerivation {
    name = "${klipper.pname}-firmware-${mcu}-${klipper.version}";
    inherit (klipper) version src;

    nativeBuildInputs =
      [
        python3
        pkgsCross.avr.stdenv.cc
        gcc-arm-embedded
        bintools-unwrapped
        libffi
        libusb1
        avrdude
        stm32flash
        pkg-config
        removeReferencesTo
      ]
      ++ lib.optional needsBossac wxwidgets_3_2;

    # The flash tools (hid-flash, bossac) run on the host and link these; with strictDeps,
    # pkg-config finds only what is listed here.
    buildInputs = [libusb1] ++ lib.optional needsBossac wxwidgets_3_2;

    configurePhase = ''
      cp ${firmwareConfig} ./.config
      chmod +w ./.config
      echo qy | { make menuconfig >/dev/null || true; }
      if ! diff ${firmwareConfig} ./.config; then
        echo " !!! Klipper KConfig has changed. Please run ${klipper.pname}-menuconfig to update your configuration."
      fi
    '';

    postPatch = ''
      patchShebangs .
    '';

    postBuild = ''
      # build flash binaries
      ${lib.concatStringsSep "\n" (map (path: "make ${path} $out/bin/ || true") flashBinaries)}
    '';

    makeFlags = [
      "V=1"
      "WXVERSION=3.2"
    ];

    installPhase = ''
      mkdir -p $out
      cp ./.config $out/config
      cp out/klipper.bin $out/ || true
      cp out/klipper.elf $out/ || true
      cp out/klipper.elf.hex $out/ || true
      cp out/klipper.uf2 $out/ || true

      mkdir -p $out/lib/

      ${
        lib.concatStringsSep "\n" (
          map (path: ''
            if [ -e ${path} ]; then
              mkdir -p $out/$(dirname ${path})
              cp -r ${path} $out/$(dirname ${path})
            fi
          '')
          flashBinaries
        )
      }
      rmdir $out/lib 2>/dev/null || echo "Flash binaries exist, not cleaning up lib/"

      # klipper.elf keeps the toolchain's paths in its debug info; the firmware must not pull the
      # toolchain into a system closure.
      if [ -e $out/klipper.elf ]; then
        remove-references-to -t ${gcc-arm-embedded} $out/klipper.elf
      fi
    '';

    strictDeps = true;
    disallowedReferences = [
      gcc-arm-embedded
    ];

    dontFixup = true;

    passthru = {
      makeFlasher = {
        flashDevice ? null,
        canbusNetwork ? null,
        canbusDevice ? null,
      }:
        klipper-flash.override {
          klipper-firmware = klipper-firmware.override (lib.removeAttrs args ["klipper-firmware"]);
          inherit
            klipper
            firmwareConfig
            mcu
            flashDevice
            canbusNetwork
            canbusDevice
            ;
        };
    };

    meta = {
      inherit (klipper.meta) homepage license;
      description = "Firmware part of Klipper";
      platforms = lib.platforms.linux;
    };
  }
