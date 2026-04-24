## Feature
Multi-machine home-manager support with per-machine profiles (oryp6, M1, M5, Parallels VM).

## Key decisions made
- **Single repo, multi-machine** — all machines managed from one flake, composed via modules
- **Module architecture**: `common.nix` (universal) + `linux.nix` / `darwin.nix` (platform) + per-machine modules
- **Option A for machine identity** — each machine gets two files: a plain metadata attrset (system, username, homeDirectory, feature flags) and a home-manager module (machine-specific config)
- **`flake.nix` uses a `mkHome` helper** that reads machine metadata, instantiates the correct `pkgs`, and composes the right module list
- **Username is per-machine**, not per-platform (`vansweej`, `janvansweevelt`, and potentially others)
- **Git identity is universal** — same personal GitHub account across all machines (linked to Philips access)
- **Ghostty managed by home-manager on all platforms** — no nixGL wrapper on Darwin, native `programs.ghostty`
- **`common.nix` owns universal sessionVariables/sessionPath**, machine modules add their own (home-manager merges)
- **ai-coding repo cloned on all machines** via activation script, so `mkOutOfStoreSymlink` paths are valid everywhere

## Open questions
- What is the username on the M5?
- What is the username on the Parallels VM, and which host runs it?
- What local-model packages does the M5 need (ollama, llama.cpp, other)?
- Does the Parallels VM need any unique packages or services?
- Should `nix fmt` / formatter be added to the flake now that it's growing?

## Rejected alternatives
- **Single `home.nix` with `stdenv.isDarwin` conditionals** — rejected because machine-specific differences (Docker, CUDA, local models) go beyond platform, and conditionals become unreadable at 4 machines
- **`common.nix` + `linux.nix` + `darwin.nix` only (no per-machine modules)** — rejected because M1 and M5 are both `aarch64-darwin` but will diverge (local models on M5), and usernames differ per machine
- **Option B: centralized machine metadata in `flake.nix`** — rejected in favor of per-machine metadata files for isolation as installations drift

## Risks identified
1. **Activation ordering bug (pre-existing, high)** — `mkOutOfStoreSymlink` entries are created during `writeBoundary`, but `cloneAiCoding` runs *after* `writeBoundary`. On a fresh machine, symlinks point to nonexistent targets on first activation. Must reorder or guard.
2. **`cudaSupport = true` leaking to Darwin (high)** — current `pkgs` instantiation applies CUDA globally. Must be gated by machine metadata to avoid eval failures or mass rebuilds on Mac.
3. **`nixgl.overlay` on Darwin (medium)** — overlay should only be applied on Linux. Applying it on Darwin is at best dead code, at worst an eval error.
4. **`systemd.user.services` on Darwin (high)** — will fail to evaluate. Must be architecturally excluded via module composition, not conditionals.
5. **`programs.ghostty` on Darwin (low)** — should work natively but needs verification that the home-manager module produces a usable config on macOS without nixGL.
6. **Module proliferation (low)** — 2 files per machine × 4+ machines + platform modules + common. Manageable now, but worth keeping the structure documented.

## Recommended next steps
1. Define the `modules/` directory structure and create the machine metadata files for `oryp6` and `M1`
2. Extract `common.nix` from current `home.nix` — universal programs, fonts, opencode skills, git, neovim, bat, starship, ai-coding clone, LazyVim bootstrap
3. Extract `linux.nix` — nixGL, XDG, `.desktop` files
4. Create `darwin.nix` — any macOS-specific defaults that emerge
5. Create per-machine modules — `oryp6.nix` gets systemd Docker service, CUDA flag; `M1.nix` starts minimal
6. Refactor `flake.nix` — `mkHome` helper, per-machine `pkgs` instantiation, conditional overlays
7. Fix the `cloneAiCoding` vs `writeBoundary` activation ordering
8. Validate with `nix flake check` and `nix build .#homeConfigurations.oryp6.activationPackage` to ensure the Linux config is unchanged before touching Darwin
