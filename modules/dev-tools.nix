{ lib, pkgs, meta, ... }:
let
  # Pin an actual release tag from https://github.com/microsoft/apm/releases.
  # Bumping later is a two-line edit: change version and swap the two SRI
  # hashes below (digests are published in each release's .sha256 sidecar).
  version = "0.26.0";

  # system -> prebuilt PyInstaller release asset + its hash.
  # SRI hashes converted from the GitHub release's published sha256 digests via:
  #   nix hash convert --hash-algo sha256 --to sri sha256:<hex>
  sources = {
    "x86_64-linux" = {
      asset = "apm-linux-x86_64";
      hash = "sha256-OvukVcUoOFK6TDkvZovnwntlvEoPpgqLU6RibFJihDE=";
    };
    "aarch64-darwin" = {
      asset = "apm-darwin-arm64";
      hash = "sha256-/r3dCovrS+e0EecI7XRpN6FEgtXgk163drfzXjIGVN8=";
    };
  };
  src = sources.${meta.system}
    or (throw "apm: unsupported system ${meta.system}");

  # All three target machines are FHS/macOS, not NixOS: oryp6 is Pop!_OS
  # (Ubuntu-based, glibc >= 2.35) and M1/M5 are macOS. The prebuilt PyInstaller
  # binary therefore runs directly against the host dynamic loader, so
  # autoPatchelfHook is intentionally omitted here. It would only be needed
  # (nativeBuildInputs = [ pkgs.autoPatchelfHook ]; buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];)
  # if a target ever migrated to NixOS.
  apm = pkgs.stdenvNoCC.mkDerivation {
    pname = "apm-cli";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/microsoft/apm/releases/download/v${version}/${src.asset}.tar.gz";
      inherit (src) hash;
    };

    sourceRoot = ".";
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/apm" "$out/bin"
      cp -r ${src.asset}/* "$out/lib/apm/"
      ln -s "$out/lib/apm/apm" "$out/bin/apm"
      runHook postInstall
    '';

    meta = {
      description = "Microsoft Agent Package Manager (apm) CLI";
      homepage = "https://github.com/microsoft/apm";
      platforms = builtins.attrNames sources;
    };
  };
in
{
  # GitHub CLI via its first-class home-manager module.
  programs.gh.enable = true;

  # Microsoft Agent Package Manager, from the pinned GitHub Release binary.
  home.packages = [ apm ];
}
