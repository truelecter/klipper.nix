# Calls every `<name>.nix` file and `<name>/default.nix` folder in `packages` with `callPackage`,
# passing `sources` (nvfetcher's generated sources) and `extraArguments`. Names starting with `_`
# are private (hashes, helper files) and skipped.
{lib}: {
  nixpkgs,
  packages,
  sources,
  extraArguments ? {},
}: let
  entries = lib.filterAttrs (name: type:
    !lib.hasPrefix "_" name
    && (
      (type == "regular" && lib.hasSuffix ".nix" name)
      || (type == "directory" && builtins.pathExists (packages + "/${name}/default.nix"))
    ))
  (builtins.readDir packages);
in
  lib.mapAttrs' (name: type:
    lib.nameValuePair (lib.removeSuffix ".nix" name) (
      nixpkgs.callPackage (packages + "/${name}") (extraArguments // {inherit sources;})
    ))
  entries
