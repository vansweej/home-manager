## Feature
Add an `M5` machine profile (aarch64-darwin) as a clean fork of the M1 configuration, ready to diverge for local model running.

## Key decisions made
- **Architecture**: `aarch64-darwin` (Apple Silicon, same as M1)
- **Username**: `janvansweevelt`, home directory `/Users/janvansweevelt` (identical to M1)
- **Machine name**: `M5` — used as the `homeConfigurations` key and in `home-manager switch --flake .#M5`
- **Starting config**: identical module composition to M1 (empty machine-specific module, `darwin.nix`, full `common.nix`)
- **Git identity**: personal email stays (`vansweej@gmail.com`) — company GitHub profile is attached to it
- **Nix installer**: Determinate Nix on the M5 (no impact on home-manager configuration itself)
- **cudaSupport**: `false` (Apple Silicon)
- **Fork rationale**: M1 laptop is being returned to IT; M5 is the permanent replacement. Forking now is cheaper than untangling later when local models land.

## Open questions
- What local model tooling will be added to `modules/machines/m5.nix` (ollama, llama.cpp, MLX, etc.)
- Whether local model services need launchd integration or just packages

## Rejected alternatives
- **Reusing the M1 profile directly** (`home-manager switch --flake .#M1`) — rejected because the M1 is being phased out (laptop returning to IT) and the two profiles will diverge quickly once local models are added

## Risks identified
1. **`mkOutOfStoreSymlink` dangling on first activation (medium)** — `common.nix` symlinks into `~/Projects/ai-coding` (line 72-74) and `~/Projects/home-manager` (lines 81-89); if those aren't cloned before first `home-manager switch`, symlinks will be broken. The `cloneAiCoding` activation script handles ai-coding automatically, but `home-manager` itself must be manually cloned first.
2. **Cannot validate Darwin build on oryp6 (medium)** — `nix build .#homeConfigurations.M5.activationPackage` requires `aarch64-darwin` and will fail on the Linux machine. `nix flake check` (eval-only) is the gate here; full build validation happens on the M5 itself.
3. **M1 profile becoming stale (low)** — as the M1 is phased out, its profile may rot. Remove it when the laptop is returned.

## Recommended next steps
1. On the M5: clone this repo into `~/Projects/home-manager`
2. Run `home-manager switch --flake .#M5` to activate
3. When local model tooling is decided, add packages/services to `modules/machines/m5.nix`
4. Remove `machines/m1.nix`, `modules/machines/m1.nix`, and the `M1` flake entry when the laptop is returned
