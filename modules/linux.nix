{ pkgs, lib, config, meta, ... }:
let
  needsNixGL = meta.nixGL or false;
in
{
  config = lib.mkMerge [

    # ── Shared Linux config (all Linux machines) ────────────────────────────
    {
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

    # ── nixGL wrappers (Intel GPU — opt-in via meta.nixGL = true) ───────────
    # Guards pkgs.nixgl.nixGLIntel behind a lazy mkIf so it is never evaluated
    # on machines where needsNixGL is false (e.g. Parallels Ubuntu VM).
    (lib.mkIf needsNixGL (
      let
        ghostty-nixgl = pkgs.writeShellScriptBin "ghostty-nixgl" ''
          exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.ghostty}/bin/ghostty "$@"
        '';

        obs-nixgl = pkgs.writeShellScriptBin "obs-nixgl" ''
          exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.obs-studio}/bin/obs "$@"
        '';

        foliate-nixgl = pkgs.writeShellScriptBin "foliate-nixgl" ''
          exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.foliate}/bin/foliate "$@"
        '';
      in
      {
        home.packages = with pkgs; [
          nixgl.nixGLIntel

          ghostty-nixgl
          obs-nixgl
          foliate-nixgl
        ];

        # Make Foliate the default handler for the e-book formats its .desktop
        # entry advertises. References foliate-nixgl.desktop (the id defined
        # above), not the upstream app-id. xdg.enable (common.nix) generates
        # ~/.config/mimeapps.list from this.
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "application/epub+zip" = "foliate-nixgl.desktop";
            "application/x-mobipocket-ebook" = "foliate-nixgl.desktop";
            "application/vnd.amazon.mobi8-ebook" = "foliate-nixgl.desktop";
            "application/x-fictionbook+xml" = "foliate-nixgl.desktop";
            "application/vnd.comicbook+zip" = "foliate-nixgl.desktop";
          };
        };

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

        # freedesktop.org .desktop entry so Foliate appears in application launchers.
        home.file.".local/share/applications/foliate-nixgl.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Version=1.0
          Name=Foliate (nixGL)
          GenericName=E-Book Reader
          Comment=Simple and modern GTK eBook reader (with nixGL wrapper)
          Exec=${foliate-nixgl}/bin/foliate-nixgl %U
          Icon=com.github.johnfactotum.Foliate
          Terminal=false
          Categories=Office;Viewer;Literature;
          MimeType=application/epub+zip;application/x-mobipocket-ebook;application/vnd.amazon.mobi8-ebook;application/x-fictionbook+xml;application/vnd.comicbook+zip;
          StartupWMClass=com.github.johnfactotum.Foliate
        '';
      }
    ))

  ];
}
