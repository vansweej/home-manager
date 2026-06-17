{ config, lib, ... }:

let
  # Absolute path to the athenaeum-mcp checkout. Uses config.home.homeDirectory
  # (not a hardcoded path) because it differs per machine: /home/vansweej on
  # oryp6 (Linux) vs /Users/janvansweevelt on the Macs.
  repoPath = "${config.home.homeDirectory}/Projects/athenaeum-mcp";
in
{
  # Declares a read-only option carrying the opencode.json overlay. Machine
  # modules read this via config.programs.athenaeum.opencodeOverlay and fold it
  # into their single lib.recursiveUpdate before one lib.mkForce write of
  # ~/.config/opencode/opencode.json. The module does not write the file itself,
  # so importing it on a machine that already mkForces opencode.json (M5) does
  # NOT create a conflicting second definition.
  options.programs.athenaeum.opencodeOverlay = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    description = ''
      opencode.json overlay that registers the athenaeum-mcp server over stdio
      and scopes its tools to the primary thinking agents (brainstorm, spar,
      teach, plan). Consumed by machine modules via lib.recursiveUpdate before a
      single lib.mkForce write of ~/.config/opencode/opencode.json.
    '';
  };

  config.programs.athenaeum.opencodeOverlay = {
    # MCP server registration. command is a single array (current OpenCode
    # schema). cwd pins the working directory so the server's relative default
    # db_path (./data/athenaeum) resolves to the repo root; the server reads no
    # env vars and takes no CLI flags, so cwd is the only lever for this.
    mcp = {
      athenaeum = {
        type = "local";
        command = [
          "nix"
          "develop"
          repoPath
          "--command"
          "cargo"
          "run"
          "-p"
          "athenaeum-mcp-server"
        ];
        cwd = repoPath;
        enabled = true;
      };
    };

    # Disable the athenaeum tools globally, then enable them only on the four
    # primary thinking agents. Tool names are prefixed with the server name, so
    # the glob "athenaeum*" matches athenaeum_search and athenaeum_ingest_file.
    tools = {
      "athenaeum*" = false;
    };

    agent = {
      brainstorm = { tools = { "athenaeum*" = true; }; };
      spar = { tools = { "athenaeum*" = true; }; };
      teach = { tools = { "athenaeum*" = true; }; };
      plan = { tools = { "athenaeum*" = true; }; };
    };
  };
}
