{
  description = "Home Manager configuration of vansweej";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl.url = "github:guibou/nixGL";
  };

  outputs =
    { self, nixpkgs, home-manager, nixgl, ... }@inputs:
    let
      # Build a homeManagerConfiguration for a given machine.
      #
      # machineMetaPath  - path to a plain Nix attrset file (machines/<name>.nix)
      #                    containing: system, username, homeDirectory, stateVersion,
      #                    cudaSupport
      # machineModulePath - path to the machine-specific home-manager module
      #                     (modules/machines/<name>.nix)
      #
      # The helper:
      #   1. Imports the metadata (before pkgs exists — no chicken-and-egg)
      #   2. Derives isDarwin from the system string
      #   3. Instantiates pkgs with the correct system, cudaSupport, and overlays
      #   4. Composes: identity inline module + common + platform + machine modules
      mkHome = machineMetaPath: machineModulePath:
        let
          meta = import machineMetaPath;
          isDarwin = builtins.match ".*-darwin" meta.system != null;

          pkgs = import nixpkgs {
            system = meta.system;
            config.allowUnfree = true;
            config.cudaSupport = meta.cudaSupport;
            # nixGL is Linux-only; applying its overlay on Darwin causes eval errors.
            overlays = if isDarwin then [] else [ nixgl.overlay ];
          };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit inputs meta;
          };

          modules = [
            # Per-machine identity — derived from the metadata file so no module
            # needs to hardcode username, homeDirectory, or stateVersion.
            {
              home.username = meta.username;
              home.homeDirectory = meta.homeDirectory;
              home.stateVersion = meta.stateVersion;
            }

            # Universal configuration shared by all machines.
            ./modules/common.nix
          ]
          # Platform module: Linux gets nixGL + .desktop; Darwin gets macOS defaults.
          ++ (if isDarwin
              then [ ./modules/darwin.nix ]
              else [ ./modules/linux.nix ])
          # Machine-specific module: Docker/systemd on oryp6, local models on M5, etc.
          ++ [ machineModulePath ];
        };

    in
    {
      homeConfigurations."oryp6"     = mkHome ./machines/oryp6.nix    ./modules/machines/oryp6.nix;
      homeConfigurations."M1"        = mkHome ./machines/m1.nix       ./modules/machines/m1.nix;
      homeConfigurations."parallels" = mkHome ./machines/parallels.nix ./modules/machines/parallels.nix;
    };
}
