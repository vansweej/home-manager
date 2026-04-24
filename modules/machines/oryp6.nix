{ pkgs, lib, config, ... }:
{
  # oryp6-specific packages: rootless Docker runtime and its dependencies.
  home.packages = with pkgs; [
    docker

    slirp4netns   # required by rootless Docker for networking
    rootlesskit   # required by rootless Docker
  ];

  # Point the Docker CLI at the rootless user socket.
  home.sessionVariables = {
    DOCKER_HOST = "unix:///run/user/1000/docker.sock";
  };

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
}
