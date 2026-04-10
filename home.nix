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

    # Agent profiles: planner (Claude Sonnet via Copilot) and debugger (Qwen3 8B local) available globally.
    ".config/opencode/agents/planner.md".source = ./opencode/agents/planner.md;
    ".config/opencode/agents/debugger.md".source = ./opencode/agents/debugger.md;

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

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/vansweej/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  # Add CLI-installed tools to PATH.
  home.sessionPath = [
    "$HOME/.opencode/bin"
  ];

  # Back up the home directory on every activation.
  # Creates a timestamped snapshot in ~/backups/home using rsync.
  # Excludes the backup destination itself, Nix store links, and large data dirs.
  home.activation.backupHome = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    backup_dest="$HOME/backups/home/$(date +%Y%m%d_%H%M%S)"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$backup_dest"
    $DRY_RUN_CMD ${pkgs.rsync}/bin/rsync -a --delete \
      --exclude="backups/" \
      --exclude=".nix-profile" \
      --exclude=".nix-defexpr" \
      --exclude=".nix-channels" \
      --exclude=".cache/" \
      --exclude=".local/share/Trash/" \
      "$HOME/" "$backup_dest/"
  '';

  # Clone the ai-coding repo on first activation if it is not already present.
  # Does not auto-pull -- run `git pull` manually inside the repo when you want
  # to update. This ensures home-manager switch never fails due to network or
  # local uncommitted changes.
  home.activation.cloneAiCoding = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/Projects/ai-coding" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
        https://github.com/vansweej/ai-coding.git \
        "$HOME/Projects/ai-coding"
    fi
  '';

  programs.bat = {
    enable = true;
  };

  programs.bash = {
    enable = true;
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
