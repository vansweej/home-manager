# Decision Brief: Extend generate-tarball.sh for ai-setup

## Feature
Extend `generate-tarball.sh` into a single `ai-setup-<DATE>.tar.gz` that bundles OpenCode config, Claude Code config, the ai-coding runtime (with `node_modules`), and tree-sitter grammars — fully self-contained. Recipients extract to a temp directory, review contents, then copy the parts they want into their own config directories.

## Context
- Current script only packages OpenCode (`~/.config/opencode/`) for non-Nix users
- New `claude-code/` directory with agents, skills, and `CLAUDE.md` (Claude Code tool config)
- `ai-coding` is now a Nix flake input (no longer a separate clone on dev machines)
- Colleagues need both OpenCode and Claude Code configs + the ai-coding runtime to use the setup
- Recipients should be able to extract, review, and selectively copy without running any post-extract commands

## Explored directions
1. **Single tarball, multi-tool** — extend existing script to include claude-code ✓ **chosen**
2. **Separate tarballs per tool** — rejected (unnecessary complexity for distribution)
3. **Bundle ai-coding via bun install at tarball time** — ✓ **chosen** (pragmatic, no Nix eval needed)
4. **Installer script instead of tarball** — rejected (less portable for air-gapped environments)

## Key decisions made
- **Single tarball** — OpenCode + Claude Code + ai-coding runtime + grammars in one `ai-setup-<DATE>.tar.gz`
- **No post-extract steps** — no `bun install`, no `git clone`, no network access needed by recipients
- **Bundle ai-coding with `node_modules`** — script runs `bun install` at *build* time in staging; recipients get a ready-to-use monorepo
- **Exclude test files** — no `*.test.ts` or `docs/` (no development use case without Nix)
- **Grammars bundled from disk** — copied from `~/.local/share/ai-coding/grammars/*.wasm` on the builder's machine into the tarball
- **Auto-discover claude-code** — agents `*.md`, skills `*/SKILL.md`, `CLAUDE.md`
- **Rename tarball** — `ai-setup-<DATE>.tar.gz`
- **Extract-and-review workflow** — recipients extract to a temp dir, inspect, then manually copy `opencode/` → `~/.config/opencode/`, `claude/` → `~/.claude/`, etc. after backing up their own configs
- **`opencode.json` lives only in the opencode config dir** — not duplicated in the ai-coding bundle

## Tarball internal structure (flat, reviewable)
```
opencode/                              # → copy to ~/.config/opencode/
  AGENTS.md
  opencode.json
  package.json
  node_modules/                        # pre-installed @opencode-ai/plugin
  agents/*.md
  skills/*/SKILL.md
  commands/*.md
  tools/*.ts
claude/                                # → copy to ~/.claude/
  CLAUDE.md
  agents/*.md
  skills/*/SKILL.md
bin/                                   # → copy to ~/.local/bin/ (chmod +x)
  codebase-retrieval
  index-codebase
ai-coding/                             # → copy to ~/.local/share/ai-coding/
  (source tree minus .git, node_modules, *.test.ts, docs/)
  node_modules/                        # pre-installed by bun at build time
  grammars/*.wasm                      # tree-sitter grammars
README-install.md                      # instructions
```

## Implementation scope
1. Auto-discover `claude-code/` agents and skills
2. Copy `../ai-coding` excluding `.git`, `node_modules`, `*.test.ts`, `docs/`
3. Run `bun install` in the staged ai-coding dir (build time only)
4. Copy grammars from `~/.local/share/ai-coding/grammars/*.wasm` into staged `ai-coding/grammars/`
5. Stage `opencode.json` from `../ai-coding/opencode.json` into the opencode config dir only
6. Update README-install.md for the extract-review-copy workflow
7. Add `--dry-run` flag that lists what would be bundled without packing
8. Warn if `../ai-coding` or current repo has uncommitted changes
9. Rename tarball to `ai-setup-<DATE>.tar.gz`

## Risks identified
1. **Tarball size (~100-150MB)** — `node_modules` for both opencode and ai-coding. Acceptable for internal distribution.
2. **Stale grammars on builder's machine** — if builder hasn't run `home-manager switch` recently, grammars may be missing. Script should error if `~/.local/share/ai-coding/grammars/` is empty or has fewer than expected files.
3. **Dirty source trees** — uncommitted changes in either repo get bundled silently. Mitigation: warn on dirty working tree.

## Open questions
- Any files in `claude-code/` beyond agents, skills, and `CLAUDE.md` expected in the future?

## Recommended next steps
1. **plan** — produce implementation steps
2. **implement** — extend `generate-tarball.sh`
3. **test** — generate tarball, extract to temp dir, verify structure
4. **commit** — `feat: extend generate-tarball to bundle full ai-setup`
