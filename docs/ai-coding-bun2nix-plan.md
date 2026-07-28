# Plan: Replace ai-coding bun-cache FOD with bun2nix

**Status:** Ready to execute  
**Target repo:** `github:vansweej/ai-coding` (all work there; home-manager only bumps the lock at rollout)  
**Platforms:** `aarch64-darwin` (M1, M5) + `x86_64-linux` (oryp6)

---

## Problem

`ai-coding/flake.nix` builds `node_modules` via a hand-maintained per-platform hash
table (`bunCacheHashes`). The table has three independent silent-drift triggers, each
requiring a physical-machine re-harvest:

1. `bun.lock` changes (add/bump a dep) → all platform hashes drift
2. nixpkgs bumps `bun` → FOD derivation name changes → forced rebuild
3. First pristine build on any platform the developer didn't harvest on at that
   exact lockfile revision

The M5 failure on 2026-07-28 was trigger 3: the aarch64-darwin hash `sha256-IhkAEL…`
was masked by M5's warm store at rev `d0a81c8`; the same hash was never actually
correct for that platform but Nix never had to verify it because the FOD output was
already cached. A new rev produced a new `.drv`, the warm store had no hit, the
real hash (`sha256-ehQZ…`) was computed, mismatch. Fix this properly once; do not
patch hashes.

---

## Solution: bun2nix (nix-community/bun2nix v2)

**bun2nix** derives per-package fetch hashes directly from the `sha512` integrity
already present in the text `bun.lock`, via `pkgs.fetchurl`. No prefetch, no
harvest, no per-platform table. A platform-independent bun-compatible cache is
assembled in the Nix store; bun then runs a real offline `bun install` from it,
choosing the host-appropriate optional native addons (both LanceDB platform prebuilds
are already in `bun.lock`). All three drift triggers are eliminated.

---

## Dependency surface (verified from all 5 package.json files at rev d0a81c8)

| Package | Relevant deps | Native? |
|---|---|---|
| root | `@aws-sdk/client-bedrock-runtime`; `@lancedb/lancedb-darwin-arm64@0.27.2` + `@lancedb/lancedb-linux-x64-gnu@0.27.2` (optionalDependencies) | biome dev binary (optional) |
| codebase | `@lancedb/lancedb ^0.27.2`, `apache-arrow`, `ignore`, `web-tree-sitter` (WASM), `@ai-coding/embeddings workspace:*` | lancedb `.node` only |
| skills | `@lancedb/lancedb ^0.27.2`, `apache-arrow`, `@ai-coding/embeddings workspace:*` | lancedb `.node` only |
| embeddings, pipeline | dev-only | none |

**Key fact:** both LanceDB platform prebuilds are declared as explicit
`optionalDependencies` at the same version, so both are in `bun.lock` with sha512
integrity. The lockfile-integrity approach is therefore genuinely platform-independent
for this repo. `web-tree-sitter` is WASM (portable); `apache-arrow` is pure JS. The
only true native addon is LanceDB.

---

## $out contract (what home-manager reads from the store path)

`opencode.nix` consumes the ai-coding store path in three ways. The replacement
build **must** preserve all three:

| Consumer | Location | Requirement |
|---|---|---|
| `home.file.".config/opencode/opencode.json".source` | `opencode.nix:136` | `$out/opencode.json` must exist |
| `home.sessionVariables.AI_CODING_MONOREPO` | `opencode.nix:156` | `$out` must be a valid bun workspace root: `package.json` with its scripts, all `.ts` source under `ai-system/` and `packages/*/src/`, `tsconfig.json`, and working `node_modules` (incl. `workspace:*` links) so `bun run --cwd $AI_CODING_MONOREPO <script>` works |
| Comment at `opencode.nix:173` | n/a | No activation-time `bun install` for ai-coding; `node_modules` must be baked into `$out` |

**Implication:** `bun2nix.mkDerivation` (produces a compiled single binary) is the
**wrong** pattern here. The correct pattern is `stdenv.mkDerivation` with the
`bun2nix.hook` + a custom `installPhase` that copies the full source tree. This is
identical to the current `cp -rP . $out/` installPhase.

---

## Phase 0 — Spike (throwaway branch; validate before touching main)

This phase is **manual** and must run on both target machines. Do darwin first.

### Prerequisites

On M5 (aarch64-darwin):
```bash
cd ~/Projects/ai-coding
git checkout -b spike/bun2nix
```

On oryp6 (x86_64-linux), from main after the darwin spike passes:
```bash
git checkout -b spike/bun2nix
```

### 0-A: Apply the minimal spike flake.nix

Make only the changes described in Phase 1 + Phase 2 + Phase 3 (below) on the
spike branch. Do not add the staleness check yet.

### 0-B: Generate bun.nix

In the ai-coding devShell (which will have bun2nix after Phase 1):
```bash
nix develop . --command bun2nix -o bun.nix
git add bun.nix
```

### 0-C: Build test on M5

```bash
nix build .#packages.aarch64-darwin.default 2>&1 | tee /tmp/spike-darwin.log
```

**Expected first-run issues and fixes:**

- If you see `clonefile: …: Operation not supported` or permission errors during
  `bun install` inside the derivation → add `bunInstallFlags` to the derivation
  (see Phase 3; these flags are pre-filled in the plan as the documented fix).
- If you see `AccessDenied` writing to the bun cache dir → verify
  `cp -r ${bunDeps}` + `chmod -R u+w` is in the hook (bun2nix hook handles this
  internally; if it still appears, file a bun2nix issue and fall back to an explicit
  copy in buildPhase).

### 0-D: Runtime test on M5

```bash
result_path=$(nix build .#packages.aarch64-darwin.default --print-out-paths --no-link)

# 1. opencode.json present
ls "$result_path/opencode.json"

# 2. workspace root valid
bun run --cwd "$result_path" typecheck

# 3. LanceDB native addon loads
bun --cwd "$result_path" -e "import('@lancedb/lancedb').then(m => console.log('lancedb ok', typeof m.connect))"

# 4. One real pipeline invocation (short smoke test)
AI_CODING_MONOREPO="$result_path" bun run --cwd "$result_path" pipeline --help
```

All four must pass. If test 3 fails with a DLOPEN or symbol error:
- Confirm `--linker=hoisted` is in `bunInstallFlags` (isolated linker can confuse
  lancedb's prebuild resolver)
- Confirm `autoPatchElf` is not set (it is a `fetchBunDeps` argument defaulting
  to `false` — lancedb ships its own prebuilt `.node` and must not be relinked)

### 0-E: Build + runtime test on oryp6

Same four tests, substitute `x86_64-linux`. On oryp6 only:
```bash
nix build .#packages.x86_64-linux.default --print-out-paths --no-link
```

### 0-F: Spike outcome

- **Both pass** → proceed to Phase 1–4 on a proper feature branch on main.
  Delete the spike branch.
- **Darwin fails, Linux passes** → document the exact error and the fix applied,
  incorporate the fix into Phase 3's `bunInstallFlags`. Retry.
- **Both fail after tuning** → fall back to the Option 1-hardened plan (add
  `checks.<system>` that build the FOD + a harvest runbook). File a bun2nix issue.

---

## Phase 1 — Add bun2nix input to ai-coding

**Branch:** `feat/bun2nix-vendoring` off main  
**Commit message:** `feat(flake): add bun2nix input for lockfile-integrity vendoring`

### Step 1: Add flake input and nixConfig

Edit `flake.nix`. Replace the current `inputs` block:

```nix
# BEFORE
inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
```

```nix
# AFTER
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  bun2nix = {
    url = "github:nix-community/bun2nix/2.1.2";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

And add `nixConfig` at the top level (before `outputs`). This enables the
nix-community binary cache when ai-coding is used as the **top-level** flake
(e.g. `nix develop .` or `nix flake check --all-systems` directly in the
ai-coding repo). It does **not** apply transitively through home-manager —
home-manager is the top-level flake during `home-manager switch`, so the
bun2nix Rust binary may compile locally on first use there. This is acceptable:
the binary is only needed for the devShell and `checks.bun-nix-fresh`, not for
the package build itself (which uses only `bun` + eval-time `fetchBunDeps`):

```nix
nixConfig = {
  extra-substituters = [
    "https://nix-community.cachix.org"
  ];
  extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
};
```

Update the `outputs` function signature to receive the new input:

```nix
# BEFORE
outputs = { self, nixpkgs }:
```

```nix
# AFTER
outputs = { self, nixpkgs, bun2nix }:
```

### Step 2: Apply the bun2nix overlay and thread pkgs through

Replace the `forEachSystem` helper and introduce a `pkgsFor` that has the overlay:

```nix
# BEFORE
let
  systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
  forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  bunCacheHashes = { ... };  # ← entire table deleted
in
```

```nix
# AFTER
let
  systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];

  # Instantiate pkgs per system with the bun2nix overlay applied.
  # This puts pkgs.bun2nix (the CLI binary + passthru functions) into scope.
  pkgsFor = nixpkgs.lib.genAttrs systems (system:
    import nixpkgs {
      inherit system;
      overlays = [ bun2nix.overlays.default ];
    }
  );

  forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f pkgsFor.${system});
in
```

### Step 3: Add bun2nix to the devShell

This lets developers run `bun2nix -o bun.nix` from inside `nix develop .` to
regenerate `bun.nix` when they update the lockfile:

```nix
# BEFORE
devShells = forEachSystem (pkgs: {
  default = pkgs.mkShell {
    packages = [ pkgs.bun pkgs.ollama ];
  };
});
```

```nix
# AFTER
devShells = forEachSystem (pkgs: {
  default = pkgs.mkShell {
    packages = [
      pkgs.bun
      pkgs.ollama
      pkgs.bun2nix  # regenerate bun.nix after lockfile changes: bun2nix -o bun.nix
    ];
  };
});
```

### Verification

```bash
nix flake check --all-systems  # must eval clean (bun.nix not needed yet for eval)
```

---

## Phase 2 — Codegen: generate bun.nix and wire the postinstall hook

**Commit message:** `chore(deps): generate bun.nix from lockfile via bun2nix`

### Step 1: Add postinstall to package.json

In `package.json`, add to `scripts`:

```json
"postinstall": "bun2nix -o bun.nix"
```

This keeps `bun.nix` automatically in sync on every `bun install` / `bun update`
during development (when inside `nix develop .`, which has bun2nix on PATH).

### Step 2: Generate bun.nix

```bash
nix develop . --command bun2nix -o bun.nix
```

This reads `bun.lock` (and the workspace `package.json` files for workspace
packages) and writes `bun.nix` — a Nix expression mapping every package in the
lockfile to a `pkgs.fetchurl` call keyed on the lockfile's sha512 integrity hash.

Commit the result:

```bash
git add package.json bun.nix
```

### What bun.nix looks like (representative excerpt)

```nix
# bun.nix — generated by bun2nix; do not edit by hand
# Regenerate: bun2nix -o bun.nix
{ fetchurl, ... }:
{
  "@aws-sdk/client-bedrock-runtime@3.1095.0" = fetchurl {
    url = "https://registry.npmjs.org/@aws-sdk/client-bedrock-runtime/-/client-bedrock-runtime-3.1095.0.tgz";
    hash = "sha512-<from bun.lock>";
  };
  "@lancedb/lancedb-darwin-arm64@0.27.2" = fetchurl {
    url = "https://registry.npmjs.org/@lancedb/lancedb-darwin-arm64/-/lancedb-darwin-arm64-0.27.2.tgz";
    hash = "sha512-<from bun.lock>";
  };
  "@lancedb/lancedb-linux-x64-gnu@0.27.2" = fetchurl {
    url = "https://registry.npmjs.org/@lancedb/lancedb-linux-x64-gnu/-/lancedb-linux-x64-gnu-0.27.2.tgz";
    hash = "sha512-<from bun.lock>";
  };
  # ... all other packages from bun.lock ...
}
```

Both LanceDB platform prebuilds appear as entries. The `fetchBunDeps` function in
Phase 3 fetches ALL of them into the Nix store, then bun's offline install picks
the right one for the host platform. Platform-independence comes from this
completeness.

---

## Phase 3 — Replace the two FOD phases with bun2nix hook

**Commit message:** `feat(flake): replace per-platform bun-cache FOD with bun2nix`

### Full replacement for the `packages` output

Delete the entire `bunCache` + `default` derivation block (and the now-deleted
`bunCacheHashes` table) and replace with:

```nix
packages = forEachSystem (pkgs: {
  default = pkgs.stdenv.mkDerivation {
    pname = "ai-coding";
    version = "0.1.0";
    src = pkgs.lib.cleanSource ./.;

    nativeBuildInputs = [
      pkgs.bun
      pkgs.bun2nix.hook  # sets up BUN_INSTALL_CACHE_DIR + runs bun install
    ];

    # fetchBunDeps builds the per-package FOD cache from bun.nix.
    # Hashes come from bun.lock's sha512 integrity — no per-platform table.
    # autoPatchElf is false by default: preserves the LanceDB prebuilt .node
    # binary unrelinked (equivalent to the previous dontFixup = true).
    bunDeps = pkgs.bun2nix.fetchBunDeps {
      bunNix = ./bun.nix;
    };

    # bun2nix's default isolated linker causes two known issues:
    #   - On darwin: clonefile fails against nix-store permissions
    #   - On both:   lancedb's prebuild resolver may fail to find the .node
    #                addon under an isolated node_modules tree
    # hoisted linker matches bun's own default since 1.3.2 and avoids both.
    # copyfile backend is required on darwin because hardlink/symlink also fail
    # against the store; on linux the default backend is fine.
    bunInstallFlags =
      if pkgs.stdenv.hostPlatform.isDarwin
      then [ "--linker=hoisted" "--backend=copyfile" ]
      else [ "--linker=hoisted" ];

    # ai-coding runs TypeScript source directly via `bun run` — it is not
    # compiled to a binary. Disable bun2nix's default compile + check phases.
    dontUseBunBuild = true;
    dontUseBunCheck = true;

    # The hook's bunNodeModulesInstallPhase runs `bun install --ignore-scripts`.
    # A separate bunLifecycleScriptsPhase then executes any missing lifecycle
    # scripts — including `postinstall`, which would invoke `bun2nix -o bun.nix`
    # inside the Nix sandbox where bun2nix is not a build input and the source
    # tree is read-only. ai-coding needs no lifecycle scripts: LanceDB prebuilds
    # are separate packages already listed in bun.nix, not fetched by scripts.
    dontRunLifecycleScripts = true;

    installPhase = ''
      # Preserve the exact $out shape home-manager depends on:
      #   $out/opencode.json          (home.file source for ~/.config/opencode/opencode.json)
      #   $out/package.json + $out/ai-system/**/*.ts + $out/packages/**/*.ts
      #   $out/tsconfig.json
      #   $out/node_modules/**        (bun install output; workspace:* links resolved)
      # opencode.nix:136 reads $out/opencode.json directly.
      # opencode.nix:156 sets AI_CODING_MONOREPO=$out; agora's tools run
      #   `bun run --cwd $AI_CODING_MONOREPO <script>` against this layout.
      mkdir -p $out
      cp -rP . $out/
    '';

    # Do not repath or strip binaries. The LanceDB prebuilt .node targets
    # standard system library paths and must not be relinked against Nix store
    # paths (same reason as the previous dontFixup = true).
    dontFixup = true;
  };
});
```

### Why each flag is set

| Flag | Reason |
|---|---|
| `dontUseBunBuild = true` | ai-coding is run as source (`bun run pipeline …`), not compiled to a single binary. `bun build --compile` would produce the wrong $out shape. |
| `dontUseBunCheck = true` | Tests run in dev (bun test), not during the Nix build. |
| `dontRunLifecycleScripts = true` | The hook's `bunNodeModulesInstallPhase` already passes `--ignore-scripts` to `bun install`. A separate `bunLifecycleScriptsPhase` then reruns missing lifecycle scripts — including `postinstall`, which would invoke `bun2nix -o bun.nix` inside the Nix sandbox where `bun2nix` is not a build input and src is read-only. Disabling is safe: LanceDB prebuilds are separate `bun.nix` entries, not install-script-fetched. |
| `dontFixup = true` | LanceDB ships a pre-built `.node` native addon for each platform. Nix's standard fixup would try to relink its ELF dependencies against store paths; the binary already links against the host's standard libraries (glibc on Linux, dyld on darwin) and must not be touched. |
| `--linker=hoisted` | bun2nix defaults to `--linker=isolated` which is known to cause bugs with tools that expect hoisted `node_modules`. LanceDB's prebuild resolution code walks up to find its `.node` file and requires hoisted layout. Also bun's own default reverted to hoisted in 1.3.2. |
| `--backend=copyfile` (darwin only) | bun's default backend on darwin is `clonefile`, which fails when the source is a read-only Nix store path. `copyfile` is the documented workaround. |
| `autoPatchElf` in `fetchBunDeps` (default `false`, not set) | `autoPatchElf` is a `fetchBunDeps` argument, not a derivation attribute. It defaults to `false` — the LanceDB prebuilt `.node` addon is left unrelinked. Omit it; do not set it explicitly. Same rationale as `dontFixup`. |

---

## Phase 4 — Staleness gate: checks.bun-nix-fresh

**Commit message:** `feat(flake): add bun-nix-fresh check to catch stale bun.nix`

Add to the `outputs` attrset, mirroring the pattern from agora's
`checks.claude-render-fresh`:

```nix
checks = forEachSystem (pkgs: {
  # Regenerates bun.nix from bun.lock in a pure sandbox and diffs it against
  # the committed ./bun.nix. Fails `nix flake check` if they differ.
  # This catches: a dep bump with `bun update`, adding a package with
  # `bun add`, or any bun.lock edit that wasn't followed by `bun2nix -o bun.nix`.
  #
  # To fix a failure: nix develop . --command bun2nix -o bun.nix && git add bun.nix
  bun-nix-fresh = pkgs.runCommand "check-bun-nix-fresh"
    { nativeBuildInputs = [ pkgs.bun2nix ]; }
    ''
      # Provide the minimal source set bun2nix needs: bun.lock + all package.jsons
      # (workspace package detection reads the manifests)
      cp ${./bun.lock} bun.lock
      cp ${./package.json} package.json
      mkdir -p packages/codebase packages/embeddings packages/pipeline packages/skills
      cp ${./packages/codebase/package.json}   packages/codebase/package.json
      cp ${./packages/embeddings/package.json} packages/embeddings/package.json
      cp ${./packages/pipeline/package.json}   packages/pipeline/package.json
      cp ${./packages/skills/package.json}     packages/skills/package.json

      bun2nix -o bun-fresh.nix

      if ! diff ${./bun.nix} bun-fresh.nix > /dev/null 2>&1; then
        echo ""
        echo "ERROR: bun.nix is stale — it does not match the current bun.lock."
        echo "Fix: nix develop . --command bun2nix -o bun.nix && git add bun.nix"
        echo ""
        diff ${./bun.nix} bun-fresh.nix || true
        exit 1
      fi

      touch $out
    '';
});
```

**What this enforces:** if `bun.lock` or any `package.json` changes without a
matching `bun2nix -o bun.nix` regeneration, `nix flake check` fails with a clear
error message. This is a pre-commit gate and a CI gate — the next `home-manager
switch` will fail at eval time before any build starts.

> **Fragility note:** the gate uses an exact `diff` against a hardcoded copy of
> the four current workspace `package.json` files. Two failure modes to be aware of:
> (1) adding or removing a workspace silently drifts the check (the copy list must
> be updated alongside the new workspace); (2) if `bun2nix` output is not perfectly
> deterministic between the devShell-native CLI and the sandbox (whitespace, ordering,
> tool version), the check will produce false failures. **The spike (Phase 0) must
> generate `bun.nix` once and then immediately run the check against it** to confirm
> byte-stability before the gate is trusted in CI.

**Developer workflow after any dep change:**
```bash
# 1. Add/update a package
nix develop . --command bun add some-package    # or bun update

# 2. Regenerate bun.nix (postinstall also does this automatically if inside nix develop)
nix develop . --command bun2nix -o bun.nix

# 3. Commit both
git add bun.lock bun.nix package.json
git commit -m "chore(deps): add some-package"

# 4. Verify
nix flake check --all-systems
```

---

## Phase 5 — Rollout to home-manager

**This phase executes on the machines themselves, not in ai-coding.**

### On M5 (aarch64-darwin)

```bash
cd ~/Projects/home-manager

# Bump the ai-coding lock to the new main
nix flake update ai-coding

# Full build test before switching (this is the real proof)
nix build .#homeConfigurations.M5.activationPackage

# Apply
home-manager switch --flake .#M5

# Smoke test: AI_CODING_MONOREPO in a new shell must point to the new store path
# and pipeline must work
echo $AI_CODING_MONOREPO    # (in a new terminal after switch)
```

Commit `flake.lock` alone:
```bash
git add flake.lock
git commit -m "chore: lock ai-coding <old-sha> -> <new-sha> (bun2nix lockfile vendoring)"
```

### On M1 (aarch64-darwin)

Same as M5:
```bash
nix flake update ai-coding   # only if not already done; lock is shared in git
nix build .#homeConfigurations.M1.activationPackage
home-manager switch --flake .#M1
```

### On oryp6 (x86_64-linux)

Must run on oryp6 itself (this Mac cannot cross-build x86_64-linux):
```bash
cd ~/Projects/home-manager
git pull                     # get the flake.lock from the darwin switch
nix build .#homeConfigurations.oryp6.activationPackage
home-manager switch --flake .#oryp6
```

### Final verification gate

All three must pass before the feature branch in ai-coding is merged to main:

```
[ ] nix flake check --all-systems (in ai-coding) — all evals + bun-nix-fresh
[ ] nix build .#homeConfigurations.M5.activationPackage
[ ] nix build .#homeConfigurations.oryp6.activationPackage (on oryp6)
[ ] home-manager switch --flake .#M5 — clean activation, zero errors
[ ] home-manager switch --flake .#oryp6 — clean activation, zero errors
[ ] AI_CODING_MONOREPO in a new terminal points to the new store path on both
[ ] bun run --cwd $AI_CODING_MONOREPO pipeline --help works on both
```

---

## What does NOT change in home-manager

Nothing in home-manager needs any code change. The contract between home-manager and
the ai-coding store path is fully preserved:

| home-manager touch point | Contract | Still satisfied? |
|---|---|---|
| `opencode.nix:21` `aiCodingPkg = inputs.ai-coding.packages.${meta.system}.default` | must be a valid derivation | yes — `packages.<system>.default` still exists |
| `opencode.nix:136` `.source = "${aiCodingPkg}/opencode.json"` | `$out/opencode.json` must exist | yes — `cp -rP . $out/` copies it |
| `opencode.nix:156` `AI_CODING_MONOREPO = aiCodingRepo` | `$out` is a valid bun workspace root | yes — full source tree + node_modules in $out |
| `opencode.nix:173` comment "node_modules baked in" | no activation bun install for ai-coding | yes — bun2nix hook installs node_modules at build time |

---

## Risk register

| Risk | Likelihood | Pre-validated? | Mitigation |
|---|---|---|---|
| Darwin clonefile fails against nix-store perms | High (documented in bun2nix) | No — spike must confirm | `--backend=copyfile` pre-filled in Phase 3 |
| LanceDB .node fails to load under isolated linker | Medium | No — spike must confirm | `--linker=hoisted` pre-filled in Phase 3; both flags are the documented fix |
| Workspace `workspace:*` links break | Low (workspace template exists in bun2nix) | No — spike must confirm | `hoisted` linker resolves this naturally; bun2nix has a workspace test template |
| bun.nix goes stale silently | Low | N/A | `postinstall` hook + `checks.bun-nix-fresh` together make this impossible to miss |
| bun2nix WASM vs native CLI output mismatch | Low (same lockfile, same algorithm) | N/A | Use only native CLI (from `nix develop .`) for both generation and check |
| bun2nix tag 2.1.2 incompatible with a future bun version | Low | N/A | Pin tag in input; bump deliberately with `nix flake update bun2nix` when bun is bumped in nixpkgs |
| aarch64-linux (parallels-ubuntu) has no LanceDB prebuild in bun.lock | Known, chosen gap | N/A — not tested in spike | LanceDB will be absent on that platform; parallels-ubuntu is a test bed with no dev-tools deploy. Acceptable. |

---

## Complete flake.nix after all phases

For reference, the full final `flake.nix` (starting from rev `d0a81c8`):

```nix
{
  description = "AI Coding OS — TypeScript monorepo for AI coding workflows";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    bun2nix = {
      url = "github:nix-community/bun2nix/2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, bun2nix }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Instantiate pkgs per system with the bun2nix overlay applied.
      pkgsFor = nixpkgs.lib.genAttrs systems (system:
        import nixpkgs {
          inherit system;
          overlays = [ bun2nix.overlays.default ];
        }
      );

      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f pkgsFor.${system});
    in
    {
      packages = forEachSystem (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "ai-coding";
          version = "0.1.0";
          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = [
            pkgs.bun
            pkgs.bun2nix.hook
          ];

          bunDeps = pkgs.bun2nix.fetchBunDeps {
            bunNix = ./bun.nix;
          };

          bunInstallFlags =
            if pkgs.stdenv.hostPlatform.isDarwin
            then [ "--linker=hoisted" "--backend=copyfile" ]
            else [ "--linker=hoisted" ];

          dontUseBunBuild = true;
          dontUseBunCheck = true;
          dontRunLifecycleScripts = true;

          installPhase = ''
            mkdir -p $out
            cp -rP . $out/
          '';

          dontFixup = true;
        };
      });

      checks = forEachSystem (pkgs: {
        bun-nix-fresh = pkgs.runCommand "check-bun-nix-fresh"
          { nativeBuildInputs = [ pkgs.bun2nix ]; }
          ''
            cp ${./bun.lock} bun.lock
            cp ${./package.json} package.json
            mkdir -p packages/codebase packages/embeddings packages/pipeline packages/skills
            cp ${./packages/codebase/package.json}   packages/codebase/package.json
            cp ${./packages/embeddings/package.json} packages/embeddings/package.json
            cp ${./packages/pipeline/package.json}   packages/pipeline/package.json
            cp ${./packages/skills/package.json}     packages/skills/package.json
            bun2nix -o bun-fresh.nix
            if ! diff ${./bun.nix} bun-fresh.nix > /dev/null 2>&1; then
              echo "ERROR: bun.nix is stale. Fix: nix develop . --command bun2nix -o bun.nix"
              diff ${./bun.nix} bun-fresh.nix || true
              exit 1
            fi
            touch $out
          '';
      });

      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.bun
            pkgs.ollama
            pkgs.bun2nix
          ];
        };
      });
    };
}
```
