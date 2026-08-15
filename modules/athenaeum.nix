{ config, lib, pkgs, inputs, meta, ... }:

let
  # Store-built athenaeum-mcp binary, consumed as a flake input (mirrors the
  # ai-coding input pattern). Resolved per-machine via meta.system so the same
  # module works on x86_64-linux (oryp6) and aarch64-darwin (M1, M5).
  athenaeumPkg = inputs.athenaeum.packages.${meta.system}.default;

  # Mutable data directory OUTSIDE the Nix store. The athenaeum-mcp-server binary
  # and the athenaeum-ingest CLI both self-locate their LanceDB store here in-binary
  # (crates/core/src/config.rs's default_data_dir: XDG_DATA_HOME, else HOME/.local/share,
  # resolving to <this>/data/athenaeum) — no `cwd` or `--workdir` is needed for that
  # anymore. dataDir is still used as the corpus-watcher unit's WorkingDirectory and
  # log-file location (see the machine modules' launchd/systemd athenaeum-watch units).
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
  # scripts read this to create the directory (as the corpus-watcher unit's
  # WorkingDirectory / log location — see athenaeum.nix's dataDir comment above),
  # guaranteeing the path can never drift from what the machine modules reference.
  options.programs.athenaeum.dataDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      Mutable data directory used as the corpus-watcher unit's working directory
      and log location. The athenaeum-mcp-server binary and athenaeum-ingest CLI
      self-locate their own LanceDB store beneath this same path in-binary (no
      cwd/--workdir needed); this option no longer feeds either of those.
      Per-machine home.activation scripts create it (mkdir -p "<dataDir>").
    '';
  };

  # User-facing corpus directory watched for new PDFs/EPUBs. Deliberately NOT
  # hidden (under ~/Documents) so it is reachable from file-manager tools and the
  # PDFs/EPUBs can be browsed directly. Kept separate from dataDir so the corpus
  # is decoupled from the disposable LanceDB state under ~/.local/share/athenaeum.
  options.programs.athenaeum.watchDir = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/Documents/corpus";
    description = ''
      Directory watched for new PDF/EPUB files. Any change triggers a full
      recursive athenaeum-ingest run over this directory. Resolved per-machine
      from config.home.homeDirectory; defaults to ~/Documents/corpus.
    '';
  };

  # The fully-resolved watchexec invocation, assembled in config below. Read-only
  # so each machine module wires it into its OS service unit (systemd on Linux,
  # launchd on macOS) without re-deriving store paths. MUST be a single flat
  # whitespace-delimited string with no newlines and no shell metacharacters:
  # systemd splits it into argv directly, and the macOS unit passes it as one
  # argument to `sh -lc`.
  options.programs.athenaeum.watchCommand = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      watchexec command line that watches programs.athenaeum.watchDir and runs a
      full recursive athenaeum-ingest over it on change. The ingest subprocess
      self-locates its LanceDB store in-binary (no cwd/--workdir needed); the
      unit's own WorkingDirectory (dataDir) is set separately for logs/cwd hygiene.
    '';
  };

  config.programs.athenaeum.dataDir = dataDir;

  # Assemble the watchexec command. Flags, each deliberate:
  #   --watch <corpus>         watch the corpus directory recursively
  #   --debounce 5s            coalesce a burst of drops into one reingest, and avoid
  #                            firing on a partially-written file
  #   --postpone               do NOT reingest at unit startup (boot / switch); only
  #                            act on a genuine post-startup change (corpus is stable)
  #   --on-busy-update queue   if a change arrives mid-reingest, queue another run
  #                            after (watchexec default is do-nothing = dropped file)
  # No --workdir: athenaeum-ingest now self-locates its LanceDB store in-binary
  # (crates/core/src/config.rs's default_data_dir), so its cwd no longer matters
  # for correctness. No --exts filter: any change triggers a full reingest;
  # athenaeum-ingest's own discovery filters to .pdf/.epub.
  config.programs.athenaeum.watchCommand =
    "${pkgs.watchexec}/bin/watchexec "
    + "--watch ${config.programs.athenaeum.watchDir} "
    + "--debounce 5s "
    + "--postpone "
    + "--on-busy-update queue "
    + "-- ${athenaeumPkg}/bin/athenaeum-ingest ${config.programs.athenaeum.watchDir} --recursive --verbose";

  # Only the ingest CLI and watchexec land on PATH; the MCP server is wired into
  # OpenCode via the absolute store path in opencodeOverlay below, so it is
  # deliberately omitted.
  config.home.packages = [ athenaeumIngest pkgs.watchexec ];

  config.programs.athenaeum.opencodeOverlay = {
    # MCP server registration. command is the store-built binary instead of
    # `nix develop … cargo run`, eliminating the manual checkout and the runtime
    # compile. No cwd needed: the binary self-locates its LanceDB store in-binary
    # (crates/core/src/config.rs's default_data_dir), resolving to the same
    # dataDir-based path this module previously supplied via cwd.
    mcp = {
      athenaeum = {
        type = "local";
        command = [ "${athenaeumPkg}/bin/athenaeum-mcp-server" ];
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
      coordinator = { tools = { "athenaeum*" = true; }; };
      brainstorm = { tools = { "athenaeum*" = true; }; };
      spar = { tools = { "athenaeum*" = true; }; };
      teach = { tools = { "athenaeum*" = true; }; };
      plan = { tools = { "athenaeum*" = true; }; };
      explore = { tools = { "athenaeum*" = true; }; };
    };
  };
}
