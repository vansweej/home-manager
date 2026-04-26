{ pkgs, lib, config, ... }:
let
  ghostty-nixgl = pkgs.writeShellScriptBin "ghostty-nixgl" ''
    exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.ghostty}/bin/ghostty "$@"
  '';

  obs-nixgl = pkgs.writeShellScriptBin "obs-nixgl" ''
    exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.obs-studio}/bin/obs "$@"
  '';
in
{
  # Linux-specific: nixGL OpenGL wrapper and Ghostty launcher.
  home.packages = with pkgs; [
    nixgl.nixGLIntel

    ghostty-nixgl
    obs-nixgl
  ];

  # freedesktop.org .desktop entry so Ghostty appears in application launchers.
  home.file.".local/share/applications/ghostty-nixgl.desktop".text = ''
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

  # freedesktop.org .desktop entry so OBS Studio appears in application launchers.
  home.file.".local/share/applications/obs-nixgl.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=OBS Studio (nixGL)
    GenericName=Screen Recorder
    Comment=Free and open source software for video recording and live streaming (with nixGL wrapper)
    Exec=${obs-nixgl}/bin/obs-nixgl
    Icon=com.obsproject.Studio
    Terminal=false
    Categories=Video;AudioVideo;
    StartupWMClass=obs
  '';

  # Flameshot screenshot tool: autostart via systemd user service and D-Bus activation.
  services.flameshot = {
    enable = true;
    settings = {
      General = {
        showStartupLaunchMessage = false;
        savePath = "${config.home.homeDirectory}/Pictures/Screenshots";
      };
    };
  };

}
