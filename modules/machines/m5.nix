{ pkgs, lib, config, inputs, meta, ... }:
let
  # Read the upstream opencode.json from the pinned ai-coding Nix store path and
  # overlay only the M5-specific provider block onto it. All other settings —
  # model, compaction, permission — are inherited from the upstream file so they
  # can never drift out of sync with the other machines.
  #
  # lib.recursiveUpdate merges attrsets deeply. It replaces lists wholesale, not
  # element-by-element. The current schema has no lists under `provider`, so there
  # is no collision risk. If that changes, revisit this merge strategy.
  aiCodingPkg = inputs.ai-coding.packages.${meta.system}.default;
  baseConfig = builtins.fromJSON (builtins.readFile "${aiCodingPkg}/opencode.json");
  m5OpencodeConfig = builtins.toJSON (lib.recursiveUpdate baseConfig {
    provider = {
      ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama (local)";
        options = {
          baseURL = "http://localhost:11434/v1";
        };
        models = {
          "gemma4:26b" = {
            name = "Gemma 4 26B (local)";
            limit = {
              context = 32768;
              output = 8192;
            };
          };
        };
      };
    };
  });

  # M5-specific local agent.
  # Mirrors opencode/agents/local.md exactly, with model and description
  # overridden for Ollama. The markdown frontmatter model field is authoritative
  # for markdown-defined agents — opencode.json agent.local.model cannot
  # override it. lib.strings.trim strips the leading indentation from the
  # Nix indented string so the deployed file has no spurious whitespace.
  # If the shared prompt body changes, keep this in sync.
  m5LocalAgent = lib.strings.trim ''
    ---
    description: General-purpose development with Gemma 4 26B (local Ollama)
    mode: primary
    model: ollama/gemma4:26b
    temperature: 0.3
    steps: 10
    permission:
      pipeline: allow
    ---

    You are a coding assistant. Use tools to complete tasks.

    At the start of every task, call the `skill-retrieval` tool with `action: "edit"`
    and a brief `query` describing what you are about to do. Use the returned skill
    content as additional context.

    **Scaffolding a new project:** call the pipeline tool with the pipeline name and workspace path.
    Available pipelines: scaffold-rust, scaffold-cpp, dev-cycle, rust-dev-cycle, cmake-dev-cycle.

    **Adding Rust dependencies:** use `cargo add <crate>` via bash (use `nix develop . --command cargo add <crate>` if there is a flake.nix).
  '';
in
{
  # M5 MacBook-specific configuration.

  # Override the shared opencode.json symlink (deployed by opencode.nix) with a
  # static file that merges the Ollama provider onto the upstream config. All
  # other settings (model, compaction, permission) are inherited from ai-coding.
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "m5-opencode.json" m5OpencodeConfig);

  # Override the shared local.md agent (deployed by opencode.nix auto-discovery)
  # with an M5-specific version whose frontmatter sets model: ollama/gemma4:26b.
  # The frontmatter model field is authoritative for markdown-defined agents and
  # cannot be overridden from opencode.json alone.
  home.file.".config/opencode/agents/local.md".source = lib.mkForce
    (pkgs.writeText "m5-local-agent.md" m5LocalAgent);
}
