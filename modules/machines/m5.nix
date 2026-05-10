{ pkgs, lib, config, ... }:
let
  # M5-specific OpenCode configuration.
  # Registers the local Ollama provider and sets gemma4:26b as the default
  # model. Overrides the shared opencode.json symlink from opencode.nix.
  # Fallback to cloud models: Tab to the built-in build/plan agents which
  # use github-copilot/claude-sonnet-4.6.
  m5OpencodeConfig = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
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
    model = "ollama/gemma4:26b";
  };

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
  # static file that registers the Ollama provider and sets gemma4:26b as the
  # default model. Other machines keep the shared symlink pointing to ai-coding.
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "m5-opencode.json" m5OpencodeConfig);

  # Override the shared local.md agent (deployed by opencode.nix auto-discovery)
  # with an M5-specific version whose frontmatter sets model: ollama/gemma4:26b.
  # The frontmatter model field is authoritative for markdown-defined agents and
  # cannot be overridden from opencode.json alone.
  home.file.".config/opencode/agents/local.md".source = lib.mkForce
    (pkgs.writeText "m5-local-agent.md" m5LocalAgent);
}
