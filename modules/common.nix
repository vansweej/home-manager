{ pkgs, lib, config, inputs, ... }:
{
  imports = [
    ./opencode.nix
    ./grammars.nix
    ./sccache.nix
  ];

  fonts.fontconfig.enable = true;

  xdg.enable = true;

  home.packages = with pkgs; [
    # Fonts
    nerd-fonts.fira-code

    # CLI utilities
    htop
    tree

    # JavaScript runtime (used by opencode pipeline and skill-retrieval tools)
    bun
  ];

  # Home Manager managed dotfiles.
  home.file = {
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
  };

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
    # Lock in legacy defaults; revisit when dropping Ruby/Python3 providers.
    withRuby = true;
    withPython3 = true;
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
