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

        # Owns ~/.config/mimeapps.list. Declares BOTH the pre-existing Firefox
        # browser/HTML defaults (previously set interactively via a generated
        # userapp-*.desktop) AND the Foliate e-book defaults, so home-manager can
        # take over the file without clobbering prior settings.
        #
        # NOTE: userapp-Firefox-R7UUL3.desktop is a desktop-environment-generated
        # launcher in ~/.local/share/applications, NOT managed by Nix. It must keep
        # existing on disk for these associations to resolve. If it is ever
        # regenerated with a different random suffix, update these entries.
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            # Browser / HTML (preserved from prior interactive selection)
            "x-scheme-handler/http" = "userapp-Firefox-R7UUL3.desktop";
            "x-scheme-handler/https" = "userapp-Firefox-R7UUL3.desktop";
            "x-scheme-handler/chrome" = "userapp-Firefox-R7UUL3.desktop";
            "text/html" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-htm" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-html" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-shtml" = "userapp-Firefox-R7UUL3.desktop";
            "application/xhtml+xml" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-xhtml" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-xht" = "userapp-Firefox-R7UUL3.desktop";

            # E-book formats → Foliate
            "application/epub+zip" = "foliate-nixgl.desktop";
            "application/x-mobipocket-ebook" = "foliate-nixgl.desktop";
            "application/vnd.amazon.mobi8-ebook" = "foliate-nixgl.desktop";
            "application/x-fictionbook+xml" = "foliate-nixgl.desktop";
            "application/vnd.comicbook+zip" = "foliate-nixgl.desktop";
          };
          associations.added = {
            # Mirrors the [Added Associations] block from the prior file.
            "x-scheme-handler/http" = "userapp-Firefox-R7UUL3.desktop";
            "x-scheme-handler/https" = "userapp-Firefox-R7UUL3.desktop";
            "x-scheme-handler/chrome" = "userapp-Firefox-R7UUL3.desktop";
            "text/html" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-htm" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-html" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-shtml" = "userapp-Firefox-R7UUL3.desktop";
            "application/xhtml+xml" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-xhtml" = "userapp-Firefox-R7UUL3.desktop";
            "application/x-extension-xht" = "userapp-Firefox-R7UUL3.desktop";
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
