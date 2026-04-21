{ pkgs, lib, inputs, config, ... }:
let
    ghostty-nixgl = pkgs.writeShellScriptBin "ghostty-nixgl" ''
    exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.ghostty}/bin/ghostty "$@"
    '';
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "vansweej";
  home.homeDirectory = "/home/vansweej";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.
  
  fonts.fontconfig.enable = true;

  xdg.enable = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    nerd-fonts.fira-code

    nixgl.nixGLIntel

    ghostty-nixgl

    htop

    bun

    tree

    docker

    slirp4netns   # required by rootless Docker for networking
    rootlesskit   # required by rootless Docker

    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {

    ".local/share/applications/ghostty-nixgl.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Version=1.0
      Name=Ghostty (nixGL)
      GenericName=Terminal
      Comment=Fast GPU terminal emulator (with nixGL wrapper)
      Exec=${ghostty-nixgl}/bin/ghostty-nixgl
      Icon=utilities-terminal
      Terminal=false
      Categories=System;TerminalEmulator;
      StartupWMClass=ghostty
    '';

    ".config/opencode/AGENTS.md".source = ./opencode/AGENTS.md;
    ".config/opencode/skill/analyst/SKILL.md".source = ./opencode/skill/analyst/SKILL.md;
    ".config/opencode/skill/architect/SKILL.md".source = ./opencode/skill/architect/SKILL.md;
    ".config/opencode/skill/documenter/SKILL.md".source = ./opencode/skill/documenter/SKILL.md;
    ".config/opencode/skill/programmer/SKILL.md".source = ./opencode/skill/programmer/SKILL.md;
    ".config/opencode/skill/reviewer/SKILL.md".source = ./opencode/skill/reviewer/SKILL.md;
    ".config/opencode/skill/tester/SKILL.md".source = ./opencode/skill/tester/SKILL.md;

    # Agent profiles available globally:
    #   planner  - Claude Sonnet via Copilot, full tooling
    #   debugger - Qwen3 8B local, read-only debugging
    #   local    - Qwen3 8B local, primary agent with stripped-down tooling
    ".config/opencode/agents/planner.md".source = ./opencode/agents/planner.md;
    ".config/opencode/agents/debugger.md".source = ./opencode/agents/debugger.md;
    ".config/opencode/agents/local.md".source = ./opencode/agents/local.md;

    # Pipeline slash commands -- available in all OpenCode sessions globally.
    # These shell out to `bun run pipeline` in the ai-coding monorepo (AI_CODING_MONOREPO).
    ".config/opencode/commands/scaffold-rust.md".source = ./opencode/commands/scaffold-rust.md;
    ".config/opencode/commands/scaffold-cpp.md".source = ./opencode/commands/scaffold-cpp.md;
    ".config/opencode/commands/pipeline.md".source = ./opencode/commands/pipeline.md;

    # Pipeline custom tool -- allows the LLM to invoke pipelines conversationally.
    # Uses mkOutOfStoreSymlink so the file is resolved from the ai-coding repo (not
    # copied into the nix store), ensuring bun can find node_modules alongside it.
    ".config/opencode/tools/pipeline.ts".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/Projects/ai-coding/.opencode/tools/pipeline.ts";

    # Neovim custom plugin files.
    # LazyVim boilerplate (init.lua, lua/config/*.lua) is left unmanaged --
    # bootstrapped once from the LazyVim starter via the activation script below.
    # Uses mkOutOfStoreSymlink so edits in the repo are reflected immediately
    # without re-running home-manager switch.
    ".config/nvim/lua/plugins/opencode.lua".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/Projects/home-manager/nvim/plugins/opencode.lua";
    ".config/nvim/lua/plugins/rust.lua".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/Projects/home-manager/nvim/plugins/rust.lua";
    ".config/nvim/lazyvim.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/Projects/home-manager/nvim/lazyvim.json";

    # Ollama provider config and default model for all OpenCode sessions.
    # Uses mkOutOfStoreSymlink so edits in the repo are reflected immediately
    # without re-running home-manager switch.
    ".config/opencode/opencode.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/Projects/ai-coding/opencode/mappings/opencode.json";

    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Rootless Docker: point the CLI at the user socket.
  # AI_CODING_MONOREPO: absolute path to the ai-coding monorepo, used by the
  # global OpenCode pipeline commands and tool so they work from any directory.
  home.sessionVariables = {
    DOCKER_HOST = "unix:///run/user/1000/docker.sock";
    AI_CODING_MONOREPO = "${config.home.homeDirectory}/Projects/ai-coding";
  };

  # Add CLI-installed tools to PATH.
  home.sessionPath = [
    "$HOME/.opencode/bin"
  ];

  # Bootstrap LazyVim starter into ~/.config/nvim on first activation.
  # Strips .git so it becomes a plain directory -- home-manager owns the plugin symlinks.
  # Does not re-clone if init.lua already exists.
  home.activation.bootstrapNvim = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    if [ ! -f "$HOME/.config/nvim/init.lua" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
        --depth=1 \
        https://github.com/LazyVim/starter \
        "$HOME/.config/nvim"
      $DRY_RUN_CMD rm -rf "$HOME/.config/nvim/.git"
    fi
  '';

  # Clone the ai-coding repo on first activation if it is not already present.
  home.activation.cloneAiCoding = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/Projects/ai-coding" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
        https://github.com/vansweej/ai-coding.git \
        "$HOME/Projects/ai-coding"
    fi
  '';

  # Register a user-level systemd service for the rootless Docker daemon.
  systemd.user.services.docker = {
    Unit = {
      Description = "Docker Application Container Engine (Rootless)";
      After = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.docker}/bin/dockerd-rootless";
      Environment = [
        "PATH=${pkgs.docker}/bin:${pkgs.slirp4netns}/bin:${pkgs.rootlesskit}/bin:/run/wrappers/bin:/usr/bin:/run/current-system/sw/bin"
      ];
      Restart = "on-failure";
      TimeoutStartSec = 0;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.bat = {
    enable = true;
  };

  programs.bash = {
    enable = true;
    initExtra = ''
      unset __HM_SESS_VARS_SOURCED
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    '';
  };

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "FiraCode Nerd Font";
      theme = "Night Owl";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Jan Van Sweevelt";
        email = "vansweej@gmail.com";
      };
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true; # Sets nvim as default editor
    vimAlias = true;      # Aliases 'vim' to 'nvim'
    viAlias = true;       # Aliases 'vi' to 'nvim'
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
