{ config, pkgs, lib, inputs, meta, ... }:

let
  # The authored agents/skills/commands/bin/AGENTS.md/package.json content
  # lives in the agora flake input's source tree (github:vansweej/agora).
  # This references the flake input's raw store path directly (like the old
  # `../opencode` relative path) rather than a built package — no per-system
  # derivation build is needed for plain file content, which also avoids
  # requiring an x86_64-linux builder on darwin hosts for the oryp6 config.
  # To update: nix flake update agora && home-manager switch.
  opencodeDir = inputs.agora;

  # The ai-coding Nix package: full source tree + node_modules, built offline
  # from the pinned flake input. Read-only in the store; bun run works fine
  # from read-only paths (verified). No git clone or bun install at activation.
  aiCodingPkg  = inputs.ai-coding.packages.${meta.system}.default;
  # AI_CODING_MONOREPO runtime root. Must be the Nix store $out (= aiCodingPkg):
  # it is the only tree with a complete node_modules/** — workspace:* links are
  # resolved by bun2nix at build time. bun run --cwd $AI_CODING_MONOREPO <script>
  # runs the TS source directly from this read-only path; no git clone or bun
  # install at activation. Matches the aiCodingPkg value already used by
  # choragos.nix and claude-mcp.nix for consistency. (Reverts regression 5a78655
  # which pointed at the writable source checkout — that tree has no
  # node_modules/@ai-coding/* so @ai-coding/* imports throw at module load.)
  aiCodingRepo = "${aiCodingPkg}";

  # The `ai-pipeline` wrapper: the CORRECTNESS mechanism for reaching the
  # ai-coding monorepo from ANY shell, not just login shells. home.sessionVariables
  # only propagate via hm-session-vars.sh in login shells, so non-login callers
  # (choragos subshells, editor tasks, ssh host commands, cron) otherwise invoke
  # `bun run --cwd $AI_CODING_MONOREPO pipeline` with an unset AI_CODING_MONOREPO /
  # CEREBRUM_BIN and fail silently at module load. This wrapper hardwires both
  # from the Nix store closure (rebuild re-derives them, robust to cerebrum churn)
  # and asserts the target tree is runnable before exec. Mirrors the
  # writeShellScriptBin + home.packages pattern in choragos.nix / claude-mcp.nix.
  #
  # TWO-LAYER SELF-ENFORCING GUARD (plan:self-enforcing-pipeline-guards-v1):
  #   * Layer 1 (item 3) — pipelineWrapper is a PURE build-time runCommand that
  #     asserts node_modules/@ai-coding/pipeline EXISTS in the wired tree
  #     (structural / existence check, no bun in the sandbox). Missing link ->
  #     wrapper fails to build -> home-manager generation fails -> switch aborts.
  #   * Layer 2 (item 7) — home.activation.checkAiPipelineDoctor runs the FULL
  #     `doctor` at activation time (real $HOME) to validate entrypoints IMPORT
  #     cleanly; HARD-FAIL aborts the switch. Layer 1 = build-time existence;
  #     Layer 2 = activation-time full-doctor import validation.
  #   The full doctor is deliberately NOT run at build time: the Nix build
  #   sandbox HOME/cwd are non-writable (bun cache EROFS/EACCES) and native
  #   addon dlopen there is unproven. Activation runs under a real $HOME, safe.

  # Build-time-baked wrapper BODY, factored out so the pure structural gate
  # (pipelineWrapper, below) can install it into $out/bin without re-running bun
  # in the sandbox. Byte-identical to the previous writeShellScriptBin body.
  # Escaping: ${aiCodingPkg} / ${config...} are nix antiquotations (build-time);
  # ''${AI_CODING_MONOREPO} are RUNTIME shell vars in the emitted script.
  pipelineScript = pkgs.writeShellScript "ai-pipeline" ''
    set -euo pipefail

    # Store paths baked in at build time — nix antiquotations resolved now,
    # NOT runtime shell vars.
    export AI_CODING_MONOREPO="${aiCodingPkg}"
    export CEREBRUM_BIN="${config.programs.cerebrum.binPath}"

    # Loud, unconditional run-time guard (never TTY-gated): validate that the
    # tree we are about to run actually has its @ai-coding/pipeline workspace
    # linked. Unlike an activation-time check on the store path (a tautology),
    # this can genuinely fire and points at the real fault.
    if [ ! -e "''${AI_CODING_MONOREPO}/node_modules/@ai-coding/pipeline" ]; then
      echo "ai-pipeline: AI_CODING_MONOREPO=''${AI_CODING_MONOREPO} has no node_modules/@ai-coding/pipeline — the tree is not runnable (rebuild home-manager / check the ai-coding flake input)" >&2
      exit 1
    fi

    ${pkgs.bun}/bin/bun run --cwd "''${AI_CODING_MONOREPO}" ai-system/cli/run-pipeline-cli.ts "$@"
  '';

  # ITEM 3 — build-time STRUCTURAL gate (pure; no bun-in-sandbox).
  # Assert the wired ai-coding store tree actually has its @ai-coding/pipeline
  # workspace link. This is the exact regression class the design targets
  # (5a78655 pointed AI_CODING_MONOREPO at a tree with no node_modules/@ai-coding/*
  # so @ai-coding/* imports throw at module load). If the link is absent the
  # wrapper fails to build -> the home-manager generation fails to build ->
  # `home-manager switch` aborts. Non-bypassable, fully reproducible, offline.
  # (The FULL import-validation doctor runs at activation time — layer 2 —
  # where a real $HOME makes bun + native addons safe to run.)
  pipelineWrapper = pkgs.runCommand "ai-pipeline" { } ''
    if [ ! -e "${aiCodingPkg}/node_modules/@ai-coding/pipeline" ]; then
      echo "ai-pipeline: BUILD ABORTED — the wired ai-coding tree (${aiCodingPkg}) has no node_modules/@ai-coding/pipeline; its @ai-coding/* imports would throw at load. home-manager activation is refused. Re-pin/fix the ai-coding flake input, then rebuild." >&2
      exit 1
    fi
    mkdir -p $out/bin
    install -m0755 ${pipelineScript} $out/bin/ai-pipeline
  '';

  # ── Auto-discover agents ────────────────────────────────────────────────────
  # Agora's OpenCode agents now live under the apm-native .apm/agents/
  # layout (agora migrated to apm packages — see agora/docs/architecture.md).
  # Files are named <name>.agent.md there (apm's agent primitive convention);
  # OpenCode itself expects a plain <name>.md, so the suffix is rewritten on
  # deploy. Adding a new agent: drop <name>.agent.md in agora/.apm/agents/,
  # git add, switch.
  agentFiles = builtins.readDir (opencodeDir + "/.apm/agents");
  agentEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/agents/${lib.removeSuffix ".agent.md" name}.md"
      { source = opencodeDir + "/.apm/agents/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".agent.md" n) agentFiles);

  # ── Auto-discover skills ────────────────────────────────────────────────────
  # Every subdirectory of agora's .apm/skills/ is expected to contain a
  # SKILL.md. This now includes what used to be the separate
  # clients/opencode/native/ tree (e.g. context-audit) — apm has no concept
  # of a client-native skill subdirectory, so agora folded it into the same
  # .apm/skills/ namespace during the apm migration; there is nothing
  # client-specific left to discover separately here.
  # Adding a new skill: create agora/.apm/skills/<name>/SKILL.md, git add, switch.
  skillDirs = builtins.readDir (opencodeDir + "/.apm/skills");
  skillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/skills/${name}/SKILL.md"
      { source = opencodeDir + "/.apm/skills/${name}/SKILL.md"; }
  ) (lib.filterAttrs (_: t: t == "directory") skillDirs);

  # ── Auto-discover commands ──────────────────────────────────────────────────
  # Every .md file in agora's commands/ is deployed as a nix-store copy.
  # Adding a new command: drop <name>.md in agora/commands/, git add, switch.
  commandFiles = builtins.readDir (opencodeDir + "/commands");
  commandEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/commands/${name}"
      { source = opencodeDir + "/commands/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) commandFiles);

  # ── Auto-discover tools ─────────────────────────────────────────────────────
  # Every .ts file in agora's tools/ must be deployed as a REAL FILE (not a
  # symlink of any kind) under ~/.config/opencode/tools/ — verified
  # empirically. OpenCode discovers tools by globbing `{tool,tools}/*.ts`
  # relative to each config directory, then `import()`s them; Bun (like
  # Node) resolves symlinks to their realpath BEFORE doing `node_modules`
  # resolution, so a symlink pointing into the read-only Nix store (whether
  # a plain store symlink or the old out-of-store mkOutOfStoreSymlink into a
  # dev checkout) fails with "Cannot find module '@opencode-ai/plugin'"
  # unless that realpath's own directory tree happens to contain
  # node_modules. Only a real file living directly under
  # ~/.config/opencode/tools/ resolves correctly, walking up to
  # ~/.config/opencode/node_modules (which OpenCode auto-installs itself —
  # see config/config.ts).
  #
  # `home.file` cannot produce a real (non-symlinked) file — every entry
  # ends up as a symlink into the Nix store, directly or via an
  # intermediate home-manager-files derivation. So tools are copied by a
  # dedicated activation script (installOpencodeTools below) instead of
  # being declared in home.file. Editing a tool still requires a commit to
  # agora + `nix flake update agora` + `home-manager switch` (same as
  # agents/skills) — there is no live edit-in-place.
  #
  # Adding a new tool: drop <name>.ts in agora/tools/, git add, switch.

  # ── Auto-discover CLI wrapper scripts ───────────────────────────────────────
  # Every file in agora's bin/ is deployed to ~/.local/bin/ as a nix-store
  # copy with the executable bit set. Convention: bin/ contains only shell
  # scripts (no extension). No symlinks needed — scripts have no node_modules
  # dependency.
  #
  # Adding a new wrapper: drop <name> in agora/bin/, git add, switch.
  binFiles = builtins.readDir (opencodeDir + "/bin");
  binEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".local/bin/${name}"
      { source = opencodeDir + "/bin/${name}";
        executable = true; }
  ) (lib.filterAttrs (_: t: t == "regular") binFiles);

  # ── Strip apm instruction frontmatter ────────────────────────────────────────
  # Agora's AGENTS.md is now authored as an apm `instructions` primitive
  # (agora/.apm/instructions/agents.instructions.md), which requires a
  # frontmatter block (`description:`) so `apm compile` can fold it into
  # colleagues' AGENTS.md. That frontmatter is meaningless to OpenCode's own
  # AGENTS.md reader, so it is stripped here before deploy — a pure
  # string-processing step (no derivation), keeping this file plain-text
  # content the same way it always was on Jan's machines.
  #
  # Frontmatter is a leading `---` line, everything up to the next `---`
  # line, then a blank separator line — stripped by dropping every line up
  # to and including that second `---`, plus one following blank line.
  stripFrontmatter = path:
    let
      lines = lib.splitString "\n" (builtins.readFile path);
      afterFirst = lib.lists.drop 1 lines;
      closeIdx = lib.lists.findFirstIndex (l: l == "---") null afterFirst;
      afterClose = if closeIdx == null
        then lines
        else lib.lists.drop (closeIdx + 1) afterFirst;
      withoutLeadingBlank =
        if afterClose != [ ] && builtins.head afterClose == ""
        then lib.lists.drop 1 afterClose
        else afterClose;
    in
    if builtins.head lines == "---"
    then lib.concatStringsSep "\n" withoutLeadingBlank
    else builtins.readFile path;

in
{
  # ── Dotfiles ────────────────────────────────────────────────────────────────
  home.file = {
    # Global agent instructions — sourced from agora's apm instruction
    # primitive with its frontmatter stripped (see stripFrontmatter above).
    ".config/opencode/AGENTS.md".text =
      stripFrontmatter (opencodeDir + "/.apm/instructions/agents.instructions.md");

    # OpenCode config — sourced from the pinned ai-coding Nix store path.
    # To update: nix flake update ai-coding && home-manager switch.
    ".config/opencode/opencode.json".source = "${aiCodingPkg}/opencode.json";
  }
  // agentEntries
  // skillEntries
  // commandEntries
  // binEntries;

  # ── Environment ─────────────────────────────────────────────────────────────
  # AI_CODING_MONOREPO: belt-and-suspenders convenience for skill-retrieval and
  # interactive login shells. The load-bearing transport is the `ai-pipeline`
  # wrapper below (home.packages), which hardwires both AI_CODING_MONOREPO and
  # CEREBRUM_BIN from the store closure so they reach ANY shell, not just login.
  #
  # OPENCODE_ZEN_MODEL: the concrete free model ai-coding's `opencode-free`
  # profile dispatches to via the OpenAI-compatible OpenCode Zen endpoint. Not a
  # secret; intentionally env-driven so swapping the free model when it rotates
  # out is a one-line change here (no ai-coding source edit / rebuild). See
  # ai-coding docs/architecture.md → "opencode-free profile".
  #
  # OPENCODE_ZEN_API_KEY is deliberately NOT set here and is OPTIONAL: OpenCode
  # Zen's free-tier models (e.g. deepseek-v4-flash-free, the default above)
  # accept unauthenticated requests -- verified empirically against
  # https://opencode.ai/zen/v1/chat/completions (200 with no Authorization
  # header for the free model; 401 for a paid one). No Zen account or key is
  # needed to use the opencode-free profile as configured. If you ever point
  # OPENCODE_ZEN_MODEL at a paid Zen model, export a key from your own shell
  # (this repo has no secret manager, so it is never committed):
  #   export OPENCODE_ZEN_API_KEY=...   # from https://opencode.ai/auth
  home.sessionVariables = {
    AI_CODING_MONOREPO = aiCodingRepo;
    OPENCODE_ZEN_MODEL = "deepseek-v4-flash-free";
  };

  # Deploy the `ai-pipeline` wrapper onto PATH (nix profile bin). This is the
  # load-bearing transport for AI_CODING_MONOREPO / CEREBRUM_BIN; the
  # home.sessionVariables above are now belt-and-suspenders only.
  # Named `ai-pipeline` (not `pipeline`) for collision-safety across a 40+ repo
  # fleet. Usage: ai-pipeline plan-cycle <workspace> --plan <file> ...
  home.packages = [ pipelineWrapper ];

  # OpenCode installs its own CLI tools here.
  # ~/.local/bin/ holds shell wrapper scripts deployed from agora's bin/.
  home.sessionPath = [
    "$HOME/.opencode/bin"
    "$HOME/.local/bin"
  ];

  # ── Activation scripts ──────────────────────────────────────────────────────

  # Copy agora's tools/*.ts into ~/.config/opencode/tools/ as REAL files
  # (see the "Auto-discover tools" comment above for why this can't be a
  # home.file symlink). Idempotent: re-copies every switch (cheap, plain
  # text files) and removes any previously-copied tool whose source file no
  # longer exists in agora — these are real files outside home.file, so
  # home-manager's own generation cleanup never reaches them.
  home.activation.installOpencodeTools =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      toolsDir="$HOME/.config/opencode/tools"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$toolsDir"

      for existing in "$toolsDir"/*.ts; do
        [ -e "$existing" ] || continue
        name=$(${pkgs.coreutils}/bin/basename "$existing")
        if [ ! -e "${opencodeDir}/tools/$name" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$existing"
        fi
      done

      for src in ${opencodeDir}/tools/*.ts; do
        [ -e "$src" ] || continue
        name=$(${pkgs.coreutils}/bin/basename "$src")
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -f "$src" "$toolsDir/$name"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod u+w "$toolsDir/$name"
      done
    '';

  # ITEM 7 — activation-time FULL doctor (import-validation layer, HARD-FAIL).
  # Layer 1 (build-time) only asserts the workspace link EXISTS. This layer runs
  # the real pipeline `doctor` at switch time — where $HOME is the real user home
  # and there is no build-sandbox purity constraint, so bun + native-addon dlopen
  # run safely — to validate that the pipeline entrypoint modules actually IMPORT
  # cleanly (not merely that the link exists). doctor is offline (no network /
  # tokens): first positional `doctor`, exit 0 pass / non-zero fail. HARD-FAIL:
  # a failure here means the wired tree is not runnable, so activation is refused.
  # ($DRY_RUN_CMD keeps `--dry-run` inert: it becomes `echo`, exits 0, guard skips.)
  home.activation.checkAiPipelineDoctor =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      echo "ai-pipeline: activation doctor — validating pipeline entrypoints import cleanly against ${aiCodingPkg}" >&2
      $DRY_RUN_CMD ${pkgs.bun}/bin/bun run --cwd ${aiCodingPkg} \
        ai-system/cli/run-pipeline-cli.ts doctor \
        || { echo "ai-pipeline: ACTIVATION ABORTED — pipeline doctor failed against ${aiCodingPkg}; entrypoints do not import cleanly. Fix/re-pin the ai-coding flake input, then re-switch." >&2; exit 1; }
    '';
}
