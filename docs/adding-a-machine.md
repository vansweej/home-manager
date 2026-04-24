# Adding a new machine

This guide walks through every step required to add a new machine to this
home-manager repository. The process takes about 10 minutes.

## Overview

Each machine requires:

1. A **metadata file** (`machines/<name>.nix`) — plain Nix attrset, not a module
2. A **machine module** (`modules/machines/<name>.nix`) — home-manager module for
   machine-specific config
3. A **flake entry** in `flake.nix` — one line wiring the two files together

## Step 1 — Create the metadata file

Create `machines/<name>.nix` as a plain Nix attrset. This file is imported by
`flake.nix` before `pkgs` is instantiated, so it must not reference `pkgs` or any
home-manager options.

```nix
# machines/<name>.nix
{
  system = "aarch64-darwin";   # or "x86_64-linux"
  username = "myuser";
  homeDirectory = "/Users/myuser";   # /home/myuser on Linux
  stateVersion = "25.11";
  cudaSupport = false;   # true only for machines with an NVIDIA GPU
}
```

**Fields:**

| Field | Type | Notes |
|---|---|---|
| `system` | string | Nix system string: `x86_64-linux` or `aarch64-darwin` |
| `username` | string | The OS username on that machine |
| `homeDirectory` | string | Absolute path to the home directory |
| `stateVersion` | string | Home Manager state version — use `"25.11"` for new machines |
| `cudaSupport` | bool | Enables CUDA in nixpkgs; only `true` on machines with an NVIDIA GPU |

## Step 2 — Create the machine module

Create `modules/machines/<name>.nix` as a home-manager module. Start minimal and
add machine-specific packages and services as needed.

```nix
# modules/machines/<name>.nix
{ pkgs, lib, config, ... }:
{
  # Machine-specific packages, session variables, services, etc.
  # Examples:
  #
  # home.packages = with pkgs; [ ollama ];
  #
  # home.sessionVariables = {
  #   MY_VAR = "value";
  # };
  #
  # On Linux only — add systemd services here, never in common.nix or darwin.nix:
  # systemd.user.services.my-service = { ... };
  #
  # On macOS only — add launchd agents here, never in common.nix or linux.nix:
  # launchd.agents.my-agent = { ... };
}
```

**Rules:**

- Do **not** set `home.username`, `home.homeDirectory`, or `home.stateVersion` —
  these are injected automatically from the metadata file by `mkHome`.
- Do **not** put `systemd` config in a Darwin machine module — the `systemd`
  home-manager module does not exist on Darwin and will cause an evaluation error.
- Do **not** put `launchd` config in a Linux machine module.
- Universal config (git, neovim, bat, starship, fonts, opencode) belongs in
  `modules/common.nix`, not here.

## Step 3 — Register in `flake.nix`

Add one line to the `homeConfigurations` attrset in `flake.nix`:

```nix
homeConfigurations."<name>" = mkHome ./machines/<name>.nix ./modules/machines/<name>.nix;
```

The profile name (the string key) is what you pass to `home-manager switch --flake .#<name>`.

**Example** — adding an M5 MacBook:

```nix
homeConfigurations."oryp6" = mkHome ./machines/oryp6.nix ./modules/machines/oryp6.nix;
homeConfigurations."M1"    = mkHome ./machines/m1.nix    ./modules/machines/m1.nix;
homeConfigurations."M5"    = mkHome ./machines/m5.nix    ./modules/machines/m5.nix;
```

## Step 4 — Track the new files in git

Nix flakes only evaluate files that are tracked by git. Stage the new files before
running any `nix` commands:

```bash
git add machines/<name>.nix modules/machines/<name>.nix flake.nix
```

## Step 5 — Validate

```bash
# Check the flake evaluates without errors
nix flake check

# Build the new profile (does not activate)
nix build .#homeConfigurations.<name>.activationPackage
```

Fix any evaluation errors before proceeding.

Also verify the existing profiles still build — the oryp6 build is the regression
gate:

```bash
nix build .#homeConfigurations.oryp6.activationPackage
```

## Step 6 — Commit

```bash
git add -A
git commit -m "feat: add <name> machine profile"
```

## Step 7 — Activate on the new machine

On the new machine, clone this repo and run switch:

```bash
git clone git@github.com:vansweej/home-manager.git ~/Projects/home-manager
home-manager switch --flake ~/Projects/home-manager#<name>
```

On first activation:

1. `~/Projects/ai-coding` is cloned automatically
2. `~/.config/nvim` is bootstrapped from the LazyVim starter
3. All packages, dotfiles, and symlinks are installed

## Adding platform-specific config

If the new machine needs config that applies to **all** machines on the same
platform (not just this one machine), add it to the platform module instead:

- Linux-wide config → `modules/linux.nix`
- macOS-wide config → `modules/darwin.nix`

If the config is truly machine-specific (e.g. local model packages on M5, rootless
Docker on oryp6), it belongs in `modules/machines/<name>.nix`.

## Troubleshooting

**`error: path '...' is not tracked by Git`**  
Run `git add` on the new files before `nix build` or `nix flake check`.

**`error: attribute 'systemd' missing`**  
You have `systemd.user.services` in a module that is evaluated on Darwin. Move it
to the Linux machine module (`modules/machines/<name>.nix`) and ensure the machine
metadata has `system = "x86_64-linux"`.

**`error: attribute 'nixgl' missing`**  
You are referencing `pkgs.nixgl.*` in a module that is evaluated on Darwin. The
nixGL overlay is only applied on Linux. Move the reference to `modules/linux.nix`
or a Linux machine module.

**Symlinks dangling after first activation**  
The `cloneAiCoding` activation script should have run before `writeBoundary`. If
it failed (e.g. no internet), re-run `home-manager switch` after restoring
connectivity.
