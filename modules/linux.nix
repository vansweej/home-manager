{ pkgs, lib, config, ... }:
let
  ghostty-nixgl = pkgs.writeShellScriptBin "ghostty-nixgl" ''
    exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.ghostty}/bin/ghostty "$@"
  '';
in
{
  # Linux-specific: nixGL OpenGL wrapper and Ghostty launcher.
  home.packages = with pkgs; [
    nixgl.nixGLIntel

    ghostty-nixgl
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

}
