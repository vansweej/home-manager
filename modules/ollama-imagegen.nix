{ lib, pkgs, config, meta, ... }:
# ---------------------------------------------------------------------------
# Policy
# ---------------------------------------------------------------------------
# Fast-moving AI tools used daily (Ollama.app, OpenCode) are installed and
# updated by the user with their own updaters, not via home-manager/Nix/brew,
# because package managers lag several versions behind and that has caused
# problems before. That rule does not apply to a deliberately frozen,
# hash-pinned, single-purpose artifact: such an artifact (here Ollama 0.32.5 as
# `ollama-imagegen`) should be managed declaratively by home-manager, because
# automating its many manual steps is the point and staying behind is
# intentional. It must never shadow or interfere with the daily tool (separate
# command name, port and models dir).
#
# Distribution: ollama-darwin.tgz — the standalone CLI distribution, the same
# Apple-signed/notarized Developer ID binaries shipped inside Ollama.app.
# /nix/store files carry no quarantine xattr. We do NOT chmod or relocate the
# binary: Ollama finds its runner libs relative to its own executable and the
# signed files must stay byte-identical.
#
# Fallback (runbook only, not implemented): Ollama-darwin.zip v0.32.5
# (sha256 hex 729396bb6fea20df0f3792087f363b90465e68f7f596fcb4b5926929b0dce4d8)
# running Ollama.app/Contents/Resources/ollama from the store via the same
# runtime detection — switching is a small edit of the `sources` attrset below.
# ---------------------------------------------------------------------------
let
  version = "0.32.5";

  sources = {
    "aarch64-darwin" = {
      url = "https://github.com/ollama/ollama/releases/download/v${version}/ollama-darwin.tgz";
      hash = "sha256-V4ndA3qGrbMoxywR/EXmxVhFLQfltQgUqL23sPvbzYE=";
    };
  };

  src = sources.${meta.system} or (throw "ollama-imagegen: unsupported system ${meta.system} (aarch64-darwin only)");

  modelsDir = "${config.home.homeDirectory}/.local/share/ollama-imagegen/models";
  stateDir = "${config.home.homeDirectory}/.local/state/ollama-imagegen";
  host = "127.0.0.1:11436";

  ollamaImagegenPkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "ollama-imagegen-frozen";
    inherit version;

    src = pkgs.fetchurl { inherit (src) url hash; };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    # gnutar + gzip are in the default PATH of stdenvNoCC on darwin.
    installPhase = ''
      runHook preInstall
      dest="$out/libexec/ollama-imagegen"
      mkdir -p "$dest"
      tar -xzf "$src" -C "$dest"
      if [ -x "$dest/ollama" ] || [ -x "$dest/bin/ollama" ]; then
        :
      else
        echo "ollama-imagegen: no executable ollama / bin/ollama after extraction" >&2
        find "$dest" -maxdepth 3
        exit 1
      fi
      runHook postInstall
    '';

    meta = {
      description = "Frozen Ollama ${version} (image-generation instance, aarch64-darwin only)";
      homepage = "https://github.com/ollama/ollama";
      platforms = builtins.attrNames sources;
    };
  };

  # Plain, NON-exported shell variables consumed by ollama-imagegen.sh.
  preamble = ''
    IG_ROOT=${lib.escapeShellArg "${ollamaImagegenPkg}/libexec/ollama-imagegen"}
    IG_HOST=${lib.escapeShellArg host}
    IG_MODELS=${lib.escapeShellArg modelsDir}
    IG_STATE=${lib.escapeShellArg stateDir}
  '';

  ollama-imagegen = pkgs.writeShellApplication {
    name = "ollama-imagegen";
    runtimeInputs = [ pkgs.coreutils pkgs.curl ];
    text = preamble + builtins.readFile ./ollama-imagegen/ollama-imagegen.sh;
  };
in
{
  home.packages = [ ollama-imagegen ];

  home.activation.createOllamaImagegenDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p ${lib.escapeShellArg modelsDir} ${lib.escapeShellArg stateDir}
  '';
}
