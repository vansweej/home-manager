# Decision Brief: ai-coding as a Nix flake

## Feature
Consolidate OpenCode runtime dependencies by making ai-coding a Nix flake that home-manager imports, eliminating manual cloning and git pull.

## Key decisions made
- ai-coding stays a separate repo — it's a software project, not configuration. Mixing it into home-manager's dotfiles repo would conflate two concerns.
- ai-coding becomes a Nix flake that home-manager consumes as a flake input. Source is fetched by Nix (pinned in `flake.lock`), no `git clone` or `git pull` needed.
- `node_modules` (including LanceDB native addon) should be built/assembled in a Nix derivation so `home-manager switch` requires zero network calls at activation time.
- Pipeline definitions stay — they're actively used and planned for more automated workflows. The current static import approach is kept (no dynamic loading needed yet).
- OpenCode config (agents, skills `.md`, commands, `opencode.json`) stays in home-manager where it already lives.
- Claude Code mirroring is a future concern. The current move doesn't optimize for it beyond keeping the runtime tools callable via `bun run`. A generic skill format that compiles to both OpenCode and Claude Code variants is parked.
- Tools continue to use `bun run` (not compiled binaries) — LanceDB native addons and pipeline dynamic imports resist `bun build --compile`.

## Open questions
1. **Bun offline install** — Does `bun install --frozen-lockfile` with a pre-populated `--cache-dir` work fully offline in the Nix sandbox? If yes, the derivation is simple: prefetch the bun cache as a fixed-output derivation, then `bun install --offline`. This is the first thing to research.
2. **LanceDB native addon in Nix** — If bun cache approach doesn't work, can the `@lancedb/lancedb-darwin-arm64` / `@lancedb/lancedb-linux-x64-gnu` npm tarballs be fetched individually (like `grammars.nix` does for tree-sitter `.wasm` files) and placed into `node_modules`?
3. **Flake outputs** — What does ai-coding export? Likely a `packages.${system}.default` derivation containing source + `node_modules`. Home-manager symlinks or copies from this store path.
4. **Runtime resolution** — Tools currently call `bun run --cwd $AI_CODING_MONOREPO`. After the change, they'd call `bun run --cwd <nix-store-path>` or a symlinked location. The store path is read-only — does `bun run` work from a read-only directory? (LanceDB writes to `~/.local/share/ai-coding/` which is outside the store, so likely fine.)
5. **Development workflow** — When iterating on ai-coding locally, you'd `nix develop` in the repo and run tests/tools directly. Home-manager uses the pinned flake input. To pick up changes: commit, push, `nix flake update ai-coding` in home-manager, `home-manager switch`. Is this workflow acceptable, or do you want a dev-mode override that points to a local checkout?
6. **DevShell contents** — ai-coding's `flake.nix` needs a `devShells.default` providing at minimum: bun, biome, typescript, and possibly ollama for testing embeddings.

## Rejected alternatives
- **Merge ai-coding into home-manager** — Rejected because it conflates a software project with a config repo. Commit history, CI concerns, and development workflows are fundamentally different.
- **Compile to standalone binaries (`bun build --compile`)** — Rejected because LanceDB native `.node` addons and dynamic pipeline imports don't work with static compilation.
- **Drop vector skill retrieval** — Rejected outright by user. Non-negotiable requirement.
- **Keep clone activation script but simplify** — Rejected because daily VM provisioning makes the clone + git pull friction a real operational cost.
- **Dynamic pipeline loading** — Rejected as unnecessary complexity. Static imports are fine given current pipeline addition frequency.

## Risks identified
1. **Nix + Bun + native addons build complexity** (high) — Building `@lancedb/lancedb` in the Nix sandbox is the critical path risk. If neither the bun cache approach nor individual tarball fetching works cleanly, this blocks the entire plan.
2. **Cross-platform derivation** (medium) — The derivation must work on both aarch64-darwin (M1/M5) and x86_64-linux (oryp6) with different native addons. Platform-conditional logic in the derivation adds complexity.
3. **Read-only store path at runtime** (medium) — `bun run` from a Nix store path may fail if bun tries to write `.bun` cache files or transpilation artifacts alongside the source.
4. **Version drift between dev and deployed** (low) — Local development uses the working tree; deployed uses the pinned flake input. Forgetting to `nix flake update ai-coding` after pushing changes could cause confusion (same problem as today's `git pull`, but with an explicit version pin making it visible).
5. **`web-tree-sitter` WASM runtime** (low) — `parser-pool.ts` resolves `tree-sitter.wasm` from `node_modules/web-tree-sitter/`. This path must exist in the Nix-built `node_modules`. Likely fine but needs verification.

## Recommended next steps
1. **Research bun offline install** — Test whether `bun install --frozen-lockfile` works with a prefetched cache dir. This determines the derivation strategy.
2. **Scaffold ai-coding `flake.nix`** — Add `devShells.default` and a `packages.default` derivation (even if initially just the source without `node_modules`).
3. **Add ai-coding as a flake input to home-manager** — Wire it into `opencode.nix`, replacing the clone activation and `AI_CODING_MONOREPO` env var.
4. **Test on a fresh VM** — Validate that `home-manager switch` on a clean machine produces a fully working setup with no manual steps.
