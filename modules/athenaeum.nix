{ config, lib, pkgs, inputs, meta, ... }:

let
  # Store-built athenaeum-mcp binary, consumed as a flake input (mirrors the
  # ai-coding input pattern). Resolved per-machine via meta.system so the same
  # module works on x86_64-linux (oryp6) and aarch64-darwin (M1, M5).
  athenaeumPkg = inputs.athenaeum.packages.${meta.system}.default;

  # Mutable data directory OUTSIDE the Nix store. The MCP server is launched with
  # this as its cwd, so its relative default db_path (./data/athenaeum) resolves
  # to a writable location here. Per-machine home.activation scripts create it.
  # Uses config.home.homeDirectory (not a hardcoded path) because it differs per
  # machine: /home/vansweej on oryp6 vs /Users/janvansweevelt on the Macs.
  dataDir = "${config.home.homeDirectory}/.local/share/athenaeum";

  # Expose ONLY the bulk-ingest CLI on PATH. The server binary is intentionally
  # left off PATH — OpenCode launches it via the absolute store path in the MCP
  # registration below. athenaeumPkg ships both binaries, so symlink just the one
  # we want. The upstream wrapProgram wrapper references the real binary by
  # absolute store path, so symlinking the wrapper preserves the pdfium loader
  # path injection (DYLD_/LD_LIBRARY_PATH) — no re-wrapping needed.
  athenaeumIngest = pkgs.runCommand "athenaeum-ingest" { } ''
    mkdir -p $out/bin
    ln -s ${athenaeumPkg}/bin/athenaeum-ingest $out/bin/athenaeum-ingest
  '';
in
{
  # Read-only option carrying the opencode.json overlay. Machine modules read
  # this via config.programs.athenaeum.opencodeOverlay and fold it into their
  # single lib.recursiveUpdate before one lib.mkForce write of opencode.json.
  options.programs.athenaeum.opencodeOverlay = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    description = ''
      opencode.json overlay that registers the athenaeum-mcp server over stdio
      and scopes its tools to the primary thinking agents (brainstorm, spar,
      teach, plan, explore). Consumed by machine modules via lib.recursiveUpdate
      before a single lib.mkForce write of ~/.config/opencode/opencode.json.
    '';
  };

  # Read-only option exposing the mutable data dir path. Per-machine activation
  # scripts read this to create the directory, guaranteeing the mkdir path can
  # never drift from the cwd used in the MCP registration below.
  options.programs.athenaeum.dataDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      Mutable data directory used as the athenaeum-mcp server's cwd. The server's
      relative default db_path (./data/athenaeum) resolves under this path.
      Per-machine home.activation scripts create it (mkdir -p "<dataDir>/data").
    '';
  };

  config.programs.athenaeum.dataDir = dataDir;

  # Only the ingest CLI lands on PATH; the MCP server is wired into OpenCode via
  # the absolute store path in opencodeOverlay below, so it is deliberately omitted.
  config.home.packages = [ athenaeumIngest ];

  config.programs.athenaeum.opencodeOverlay = {
    # MCP server registration. command is the store-built binary instead of
    # `nix develop … cargo run`, eliminating the manual checkout and the runtime
    # compile. cwd pins the working directory to the mutable data dir so the
    # server's relative db_path resolves to a writable location outside the store.
    mcp = {
      athenaeum = {
        type = "local";
        command = [ "${athenaeumPkg}/bin/athenaeum-mcp-server" ];
        cwd = dataDir;
        enabled = true;
      };
    };

    # Disable the athenaeum tools globally, then enable them only on the primary
    # thinking agents. Tool names are prefixed with the server name, so the glob
    # "athenaeum*" matches athenaeum_search and athenaeum_ingest_file.
    tools = {
      "athenaeum*" = false;
    };

    agent = {
      brainstorm = { tools = { "athenaeum*" = true; }; };
      spar = { tools = { "athenaeum*" = true; }; };
      teach = { tools = { "athenaeum*" = true; }; };
      plan = { tools = { "athenaeum*" = true; }; };
      explore = { tools = { "athenaeum*" = true; }; };
    };
  };
}
