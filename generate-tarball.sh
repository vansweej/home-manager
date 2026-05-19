#!/usr/bin/env bash
# generate-tarball.sh — produce a self-contained ai-setup-<DATE>.tar.gz
#
# The tarball extracts into a temporary directory and includes:
#   opencode/        — agents, skills, commands, tools with bundled node_modules,
#                      opencode.json, AGENTS.md, package.json, bun.lock
#   claude/          — Claude Code agents, skills, CLAUDE.md
#   bin/             — CLI wrapper scripts (codebase-retrieval, index-codebase)
#   ai-coding/       — full ai-coding runtime with pre-installed node_modules
#                      and tree-sitter grammars
#   README-install.md — comprehensive installation and usage guide
#
# It is fully self-contained: no Nix, no home-manager, and no post-install steps
# beyond extracting and copying to the appropriate directories.
#
# All components are auto-discovered from the home-manager and claude-code
# directory structures — no manual updates needed when files are added or removed.
#
# Usage:
#   ./generate-tarball.sh          # produce ai-setup-YYYY-MM-DD.tar.gz
#   ./generate-tarball.sh --dry-run # show what would be bundled without creating tarball
#   ./generate-tarball.sh --clean  # same, but print a prominent clean-install reminder
#   ./generate-tarball.sh --help   # show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCODE_SRC="$SCRIPT_DIR/opencode"
CLAUDE_CODE_SRC="$SCRIPT_DIR/claude-code"
AI_CODING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/ai-coding"
GRAMMARS_DIR="$HOME/.local/share/ai-coding/grammars"
DATE="$(date +%Y-%m-%d)"
PLATFORM="$(uname -s)/$(uname -m)"
TARBALL="$SCRIPT_DIR/ai-setup-${DATE}.tar.gz"

CLEAN_REMINDER=false
DRY_RUN=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "[info]  $*"; }
warn()  { echo "[warn]  $*" >&2; }
error() { echo "[error] $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage ;;
    --clean)   CLEAN_REMINDER=true ;;
    --dry-run) DRY_RUN=true ;;
    *) error "Unknown argument: $arg. Run with --help for usage." ;;
  esac
done

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

if ! command -v bun &>/dev/null; then
  error "bun is required but not found on PATH.
  Install it with your package manager, for example:
    macOS:  brew install bun
    Linux:  curl -fsSL https://bun.sh/install | bash
  Then re-run this script."
fi

if ! command -v git &>/dev/null; then
  error "git is required but not found on PATH."
fi

if ! command -v rsync &>/dev/null; then
  error "rsync is required but not found on PATH.
  Install it with your package manager, for example:
    macOS:  brew install rsync
    Linux:  apt-get install rsync
  Then re-run this script."
fi

BUN_VERSION="$(bun --version)"
info "Using bun $BUN_VERSION"

# ---------------------------------------------------------------------------
# Warn on dirty working trees
# ---------------------------------------------------------------------------

if git -C "$SCRIPT_DIR" status --porcelain | grep -q .; then
  warn "home-manager repo has uncommitted changes — they will be bundled."
fi

if git -C "$AI_CODING_DIR" status --porcelain | grep -q .; then
  warn "ai-coding repo has uncommitted changes — they will be bundled."
fi

# ---------------------------------------------------------------------------
# Ensure ai-coding repo is present (needed for runtime bundling)
# ---------------------------------------------------------------------------

if [ ! -d "$AI_CODING_DIR" ]; then
  error "ai-coding not found at $AI_CODING_DIR
Ensure the repo is checked out alongside home-manager:
  git clone https://github.com/vansweej/ai-coding.git $AI_CODING_DIR
Then re-run this script."
fi

info "Found ai-coding at $AI_CODING_DIR"

# ---------------------------------------------------------------------------
# Auto-discover source files
# ---------------------------------------------------------------------------

# Agents: all *.md files under opencode/agents/
AGENTS=()
while IFS= read -r f; do AGENTS+=("$f"); done < <(find "$OPENCODE_SRC/agents" -maxdepth 1 -name '*.md' -type f | sort)

# Skills: all subdirectories under opencode/skills/ that contain a SKILL.md
SKILLS=()
while IFS= read -r f; do SKILLS+=("$f"); done < <(find "$OPENCODE_SRC/skills" -maxdepth 2 -name 'SKILL.md' -type f | sort)

# Commands: all *.md files under opencode/commands/
COMMANDS=()
while IFS= read -r f; do COMMANDS+=("$f"); done < <(find "$OPENCODE_SRC/commands" -maxdepth 1 -name '*.md' -type f | sort)

# Tools: all *.ts files under opencode/tools/ — self-contained implementations
TOOLS=()
while IFS= read -r f; do TOOLS+=("$f"); done < <(find "$OPENCODE_SRC/tools" -maxdepth 1 -name '*.ts' -type f | sort)

# Bin wrappers: all files under opencode/bin/
BINS=()
while IFS= read -r f; do BINS+=("$f"); done < <(find "$OPENCODE_SRC/bin" -maxdepth 1 -type f | sort)

# Claude Code agents: all *.md files under claude-code/agents/
CLAUDE_AGENTS=()
while IFS= read -r f; do CLAUDE_AGENTS+=("$f"); done < <(find "$CLAUDE_CODE_SRC/agents" -maxdepth 1 -name '*.md' -type f | sort)

# Claude Code skills: all subdirectories under claude-code/skills/ that contain a SKILL.md
CLAUDE_SKILLS=()
while IFS= read -r f; do CLAUDE_SKILLS+=("$f"); done < <(find "$CLAUDE_CODE_SRC/skills" -maxdepth 2 -name 'SKILL.md' -type f | sort)

# Tree-sitter grammars: all *.wasm files under ~/.local/share/ai-coding/grammars/
# home-manager deploys home.file entries as nix-store symlinks, so match both
# regular files (-type f) and symlinks (-type l).
GRAMMARS=()
while IFS= read -r f; do GRAMMARS+=("$f"); done < <(find "$GRAMMARS_DIR" -maxdepth 1 -name '*.wasm' \( -type f -o -type l \) 2>/dev/null | sort)

info "Discovered: ${#AGENTS[@]} opencode agent(s), ${#SKILLS[@]} opencode skill(s), ${#COMMANDS[@]} command(s), ${#TOOLS[@]} tool(s), ${#BINS[@]} bin wrapper(s)"
info "Discovered: ${#CLAUDE_AGENTS[@]} claude agent(s), ${#CLAUDE_SKILLS[@]} claude skill(s), ${#GRAMMARS[@]} grammar(s)"

# ---------------------------------------------------------------------------
# Validate expected source files
# ---------------------------------------------------------------------------

MISSING=()

[ -f "$OPENCODE_SRC/AGENTS.md" ]    || MISSING+=("opencode/AGENTS.md")
[ -f "$OPENCODE_SRC/package.json" ] || MISSING+=("opencode/package.json")

for agent in "${AGENTS[@]}"; do
  [ -f "$agent" ] || MISSING+=("agents/$(basename "$agent")")
done

for skill in "${SKILLS[@]}"; do
  [ -f "$skill" ] || MISSING+=("skills/$(basename "$(dirname "$skill")")/SKILL.md")
done

for cmd in "${COMMANDS[@]}"; do
  [ -f "$cmd" ] || MISSING+=("commands/$(basename "$cmd")")
done

for tool in "${TOOLS[@]}"; do
  [ -f "$tool" ] || MISSING+=("tools/$(basename "$tool")")
done

for bin in "${BINS[@]}"; do
  [ -f "$bin" ] || MISSING+=("bin/$(basename "$bin")")
done

[ -f "$AI_CODING_DIR/opencode.json" ] \
  || MISSING+=("ai-coding/opencode.json")

# Validate Claude Code files
[ -f "$CLAUDE_CODE_SRC/CLAUDE.md" ] || MISSING+=("claude-code/CLAUDE.md")

for agent in "${CLAUDE_AGENTS[@]}"; do
  [ -f "$agent" ] || MISSING+=("claude-code/agents/$(basename "$agent")")
done

for skill in "${CLAUDE_SKILLS[@]}"; do
  [ -f "$skill" ] || MISSING+=("claude-code/skills/$(basename "$(dirname "$skill")")/SKILL.md")
done

# Validate grammars
if [ "${#GRAMMARS[@]}" -eq 0 ]; then
  error "No tree-sitter grammars found at $GRAMMARS_DIR
Run 'home-manager switch' first to deploy grammars, then re-run this script."
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  error "The following required source files are missing:
$(printf '  - %s\n' "${MISSING[@]}")
Pull the latest changes from both repos and try again."
fi

# ---------------------------------------------------------------------------
# Dry-run output (if requested)
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "=== DRY RUN — would bundle the following ==="
  echo ""
  echo "OpenCode config (→ opencode/):"
  echo "  AGENTS.md, opencode.json, package.json, bun.lock"
  printf '  agents/%s\n' "${AGENTS[@]##*/}"
  for s in "${SKILLS[@]}"; do printf '  skills/%s/SKILL.md\n' "$(basename "$(dirname "$s")")"; done
  printf '  commands/%s\n' "${COMMANDS[@]##*/}"
  printf '  tools/%s\n' "${TOOLS[@]##*/}"
  echo ""
  echo "Claude Code config (→ claude/):"
  echo "  CLAUDE.md"
  printf '  agents/%s\n' "${CLAUDE_AGENTS[@]##*/}"
  for s in "${CLAUDE_SKILLS[@]}"; do printf '  skills/%s/SKILL.md\n' "$(basename "$(dirname "$s")")"; done
  echo ""
  echo "CLI wrappers (→ bin/):"
  printf '  %s\n' "${BINS[@]##*/}"
  echo ""
  echo "ai-coding runtime (→ ai-coding/):"
  echo "  Source: $AI_CODING_DIR (excluding .git, node_modules, *.test.ts, docs/)"
  echo "  bun install will run at build time"
  echo ""
  echo "Tree-sitter grammars (→ ai-coding/grammars/):"
  printf '  %s\n' "${GRAMMARS[@]##*/}"
  echo ""
  echo "=== END DRY RUN ==="
  exit 0
fi

# ---------------------------------------------------------------------------
# Create staging directory
# ---------------------------------------------------------------------------

STAGING="$(mktemp -d)"
# Ensure staging is always cleaned up, even on error.
trap 'rm -rf "$STAGING"' EXIT

OC_TARGET="$STAGING/opencode"
CLAUDE_TARGET="$STAGING/claude"
BIN_TARGET="$STAGING/bin"
AI_TARGET="$STAGING/ai-coding"

mkdir -p \
  "$OC_TARGET/agents" \
  "$OC_TARGET/commands" \
  "$OC_TARGET/tools" \
  "$CLAUDE_TARGET/agents" \
  "$BIN_TARGET" \
  "$AI_TARGET/grammars"

# Create opencode skill subdirectories dynamically
for skill in "${SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  mkdir -p "$OC_TARGET/skills/$skill_name"
done

# Create claude skill subdirectories dynamically
for skill in "${CLAUDE_SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  mkdir -p "$CLAUDE_TARGET/skills/$skill_name"
done

info "Staging directory created at $STAGING"

# ---------------------------------------------------------------------------
# Copy files from home-manager/opencode/
# ---------------------------------------------------------------------------

info "Copying opencode AGENTS.md, package.json, opencode.json..."
cp "$OPENCODE_SRC/AGENTS.md"    "$OC_TARGET/"
cp "$OPENCODE_SRC/package.json" "$OC_TARGET/"
[ -f "$OPENCODE_SRC/bun.lock" ] && cp "$OPENCODE_SRC/bun.lock" "$OC_TARGET/"
cp "$AI_CODING_DIR/opencode.json" "$OC_TARGET/"

info "Copying ${#AGENTS[@]} opencode agent(s)..."
for agent in "${AGENTS[@]}"; do
  cp "$agent" "$OC_TARGET/agents/"
done

info "Copying ${#SKILLS[@]} opencode skill(s)..."
for skill in "${SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  cp "$skill" "$OC_TARGET/skills/$skill_name/"
done

info "Copying ${#COMMANDS[@]} opencode command(s)..."
for cmd in "${COMMANDS[@]}"; do
  cp "$cmd" "$OC_TARGET/commands/"
done

info "Copying ${#TOOLS[@]} opencode tool(s)..."
for tool in "${TOOLS[@]}"; do
  cp "$tool" "$OC_TARGET/tools/"
done

# ---------------------------------------------------------------------------
# Copy files from home-manager/claude-code/
# ---------------------------------------------------------------------------

info "Copying Claude Code CLAUDE.md..."
cp "$CLAUDE_CODE_SRC/CLAUDE.md" "$CLAUDE_TARGET/"

info "Copying ${#CLAUDE_AGENTS[@]} claude agent(s)..."
for agent in "${CLAUDE_AGENTS[@]}"; do
  cp "$agent" "$CLAUDE_TARGET/agents/"
done

info "Copying ${#CLAUDE_SKILLS[@]} claude skill(s)..."
for skill in "${CLAUDE_SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  cp "$skill" "$CLAUDE_TARGET/skills/$skill_name/"
done

# ---------------------------------------------------------------------------
# Copy bin wrapper scripts from opencode/bin/
# ---------------------------------------------------------------------------

info "Copying ${#BINS[@]} bin wrapper(s)..."
for bin in "${BINS[@]}"; do
  cp "$bin" "$BIN_TARGET/"
  chmod +x "$BIN_TARGET/$(basename "$bin")"
done

# ---------------------------------------------------------------------------
# Copy ai-coding source tree (excluding .git, node_modules, tests, docs)
# ---------------------------------------------------------------------------

info "Copying ai-coding source tree (excluding .git, node_modules, tests, docs)..."
rsync -a \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='*.test.ts' \
  --exclude='docs/' \
  "$AI_CODING_DIR/" "$AI_TARGET/"

# ---------------------------------------------------------------------------
# Run bun install in staged ai-coding (pre-installing for recipients)
# ---------------------------------------------------------------------------

info "Running bun install in staged ai-coding (pre-installing for recipients)..."
bun install --cwd "$AI_TARGET" --frozen-lockfile 2>/dev/null \
  || bun install --cwd "$AI_TARGET"

# ---------------------------------------------------------------------------
# Copy tree-sitter grammars
# ---------------------------------------------------------------------------

info "Copying ${#GRAMMARS[@]} tree-sitter grammar(s)..."
for grammar in "${GRAMMARS[@]}"; do
  cp "$grammar" "$AI_TARGET/grammars/"
done

# ---------------------------------------------------------------------------
# Install node_modules for opencode tools
# ---------------------------------------------------------------------------

info "Running bun install for opencode tools..."
bun install --cwd "$OC_TARGET" --frozen-lockfile 2>/dev/null \
  || bun install --cwd "$OC_TARGET"

# ---------------------------------------------------------------------------
# Collect names for README
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Collect names for README
# ---------------------------------------------------------------------------

AGENT_NAMES=()
for agent in "${AGENTS[@]}"; do
  AGENT_NAMES+=("$(basename "$agent" .md)")
done

SKILL_NAMES=()
for skill in "${SKILLS[@]}"; do
  SKILL_NAMES+=("$(basename "$(dirname "$skill")")")
done

COMMAND_NAMES=()
for cmd in "${COMMANDS[@]}"; do
  COMMAND_NAMES+=("$(basename "$cmd" .md)")
done

TOOL_NAMES=()
for tool in "${TOOLS[@]}"; do
  TOOL_NAMES+=("$(basename "$tool" .ts)")
done

BIN_NAMES=()
for bin in "${BINS[@]}"; do
  BIN_NAMES+=("$(basename "$bin")")
done

CLAUDE_AGENT_NAMES=()
for agent in "${CLAUDE_AGENTS[@]}"; do
  CLAUDE_AGENT_NAMES+=("$(basename "$agent" .md)")
done

CLAUDE_SKILL_NAMES=()
for skill in "${CLAUDE_SKILLS[@]}"; do
  CLAUDE_SKILL_NAMES+=("$(basename "$(dirname "$skill")")")
done

GRAMMAR_NAMES=()
for grammar in "${GRAMMARS[@]}"; do
  GRAMMAR_NAMES+=("$(basename "$grammar")")
done

join_comma() {
  local IFS=", "
  echo "$*"
}

# ---------------------------------------------------------------------------
# Generate README-install.md
# ---------------------------------------------------------------------------

info "Generating README-install.md..."

cat > "$STAGING/README-install.md" <<'README'
# AI Setup — OpenCode + Claude Code + ai-coding Runtime

Generated: ${DATE}
Platform:  ${PLATFORM}
Bun:       ${BUN_VERSION}

This archive contains a complete, self-contained AI coding setup for colleagues
without Nix/home-manager:

- **OpenCode CLI** — agents, skills, commands, custom tools, global config
- **Claude Code** — agents, skills, project rules
- **ai-coding runtime** — monorepo with pre-installed node_modules
- **Tree-sitter grammars** — for semantic code indexing

No post-extract steps required — everything is pre-installed and ready to use.

---

## Contents

- **${#AGENT_NAMES[@]} OpenCode agents** — $(join_comma "${AGENT_NAMES[@]}")
- **${#SKILL_NAMES[@]} OpenCode skills** — $(join_comma "${SKILL_NAMES[@]}")
- **${#COMMAND_NAMES[@]} OpenCode commands** — $(join_comma "${COMMAND_NAMES[@]}")
- **${#TOOL_NAMES[@]} OpenCode tools** — $(join_comma "${TOOL_NAMES[@]}")
- **${#BIN_NAMES[@]} CLI wrappers** — $(join_comma "${BIN_NAMES[@]}")
- **${#CLAUDE_AGENT_NAMES[@]} Claude Code agents** — $(join_comma "${CLAUDE_AGENT_NAMES[@]}")
- **${#CLAUDE_SKILL_NAMES[@]} Claude Code skills** — $(join_comma "${CLAUDE_SKILL_NAMES[@]}")
- **ai-coding runtime** — full monorepo with node_modules pre-installed
- **${#GRAMMAR_NAMES[@]} tree-sitter grammars** — $(join_comma "${GRAMMAR_NAMES[@]}")

---

## Prerequisites

Before extracting, ensure the following are installed:

1. **OpenCode CLI**
   See https://opencode.ai for installation instructions.

2. **Bun runtime**
   - macOS:  \`brew install bun\`
   - Linux / WSL:  \`curl -fsSL https://bun.sh/install | bash\`

3. **Ollama** (optional, for semantic codebase search)
   - See https://ollama.ai for installation instructions.
   - Pull the embedding model: \`ollama pull nomic-embed-text\`

---

## Install

### 1. Extract to a temporary directory

\`\`\`bash
mkdir -p /tmp/ai-setup
tar xzf ai-setup-${DATE}.tar.gz -C /tmp/ai-setup
\`\`\`

### 2. Review the contents

\`\`\`bash
ls /tmp/ai-setup/
# Expected output:
#   opencode/
#   claude/
#   bin/
#   ai-coding/
#   README-install.md
\`\`\`

### 3. Back up your existing configs (if any)

\`\`\`bash
[ -d ~/.config/opencode ] && cp -r ~/.config/opencode ~/.config/opencode.bak
[ -d ~/.claude ] && cp -r ~/.claude ~/.claude.bak
\`\`\`

### 4. Copy OpenCode config

\`\`\`bash
cp -r /tmp/ai-setup/opencode/ ~/.config/opencode/
\`\`\`

### 5. Copy Claude Code config

\`\`\`bash
cp -r /tmp/ai-setup/claude/ ~/.claude/
\`\`\`

### 6. Copy CLI wrappers

\`\`\`bash
mkdir -p ~/.local/bin
cp /tmp/ai-setup/bin/* ~/.local/bin/
chmod +x ~/.local/bin/*
\`\`\`

### 7. Copy ai-coding runtime

\`\`\`bash
mkdir -p ~/.local/share
cp -r /tmp/ai-setup/ai-coding/ ~/.local/share/ai-coding/
\`\`\`

### 8. Configure your shell profile

Add the following to your \`~/.bashrc\`, \`~/.zshrc\`, or equivalent:

\`\`\`bash
# Path to the bundled ai-coding runtime — required for all tools to work.
export AI_CODING_MONOREPO="\$HOME/.local/share/ai-coding"

# OpenCode CLI binary path.
export PATH="\$HOME/.opencode/bin:\$PATH"

# CLI wrappers (codebase-retrieval, index-codebase).
export PATH="\$HOME/.local/bin:\$PATH"
\`\`\`

Then reload your shell:

\`\`\`bash
source ~/.bashrc   # or source ~/.zshrc
\`\`\`

### 9. Restart OpenCode

Start or restart OpenCode to pick up the new configuration.

---

## What each component does

### OpenCode CLI

OpenCode is an AI coding assistant that integrates with your editor. The bundled
config includes:

- **Agents** — specialized AI personas for different coding tasks
- **Skills** — domain-specific knowledge (Rust, TypeScript, C++, etc.)
- **Commands** — slash commands for quick AI interactions
- **Tools** — custom integrations (pipeline, codebase-retrieval, skill-retrieval)

### Claude Code

Claude Code is a VS Code extension for AI-assisted development. The bundled config
includes:

- **Agents** — specialized personas (build, plan, explore, debug, test, etc.)
- **Skills** — project-specific conventions and best practices
- **CLAUDE.md** — project rules and coding standards

### ai-coding Runtime

The bundled \`~/.local/share/ai-coding/\` directory contains:

- Full source tree of the ai-coding monorepo
- Pre-installed \`node_modules/\` (ready to use immediately)
- Tree-sitter grammar files for semantic code indexing
- All CLI tools (pipeline, codebase-retrieval, skill-retrieval, etc.)

### CLI Wrappers

- **codebase-retrieval** — search indexed repositories for semantically similar code
- **index-codebase** — index a git repository for semantic search

Both require \`AI_CODING_MONOREPO\` set in your shell profile (see step 8 above).

---

## Using codebase search (optional)

If you have Ollama running with the \`nomic-embed-text\` model:

\`\`\`bash
# Index the current repository
index-codebase

# Search for semantically similar code
codebase-retrieval "hash-based staleness check"
\`\`\`

If Ollama is not running, the tools fall back to keyword-based search (still useful).

---

## Updating

When the configuration is updated upstream, re-generate the tarball on your
machine (pull both repos first) and repeat the copy steps:

\`\`\`bash
# Pull latest changes
cd ~/Projects/home-manager && git pull
cd ~/Projects/ai-coding    && git pull

# Re-generate
cd ~/Projects/home-manager && ./generate-tarball.sh

# Extract and copy (repeat steps 1-7 above)
mkdir -p /tmp/ai-setup-new
tar xzf ai-setup-\$(date +%Y-%m-%d).tar.gz -C /tmp/ai-setup-new
cp -r /tmp/ai-setup-new/opencode/ ~/.config/opencode/
cp -r /tmp/ai-setup-new/claude/ ~/.claude/
cp /tmp/ai-setup-new/bin/* ~/.local/bin/ && chmod +x ~/.local/bin/*
cp -r /tmp/ai-setup-new/ai-coding/ ~/.local/share/ai-coding/
\`\`\`

---

## Troubleshooting

### \`AI_CODING_MONOREPO is not set\`

Make sure you added the environment variable to your shell profile and reloaded:

\`\`\`bash
source ~/.bashrc   # or source ~/.zshrc
echo \$AI_CODING_MONOREPO  # should print the path
\`\`\`

### \`bun: command not found\`

Install Bun:
- macOS:  \`brew install bun\`
- Linux:  \`curl -fsSL https://bun.sh/install | bash\`

### Codebase search returns no results

Ensure Ollama is running and the \`nomic-embed-text\` model is pulled:

\`\`\`bash
ollama pull nomic-embed-text
ollama serve  # in a separate terminal
\`\`\`

Then index your repository:

\`\`\`bash
index-codebase
\`\`\`

---

## Questions?

Refer to the upstream repositories:
- OpenCode: https://opencode.ai
- ai-coding: https://github.com/vansweej/ai-coding
- home-manager: https://github.com/vansweej/home-manager
README

# ---------------------------------------------------------------------------
# Pack the tarball
# ---------------------------------------------------------------------------

info "Packing tarball..."
tar czf "$TARBALL" -C "$STAGING" opencode claude bin ai-coding README-install.md

TARBALL_SIZE="$(du -sh "$TARBALL" | cut -f1)"
info "Created: $TARBALL ($TARBALL_SIZE)"

# ---------------------------------------------------------------------------
# Clean-install reminder (when --clean was passed)
# ---------------------------------------------------------------------------

if [ "$CLEAN_REMINDER" = true ]; then
  echo ""
  echo "┌─────────────────────────────────────────────────────────────────┐"
  echo "│  CLEAN INSTALL REMINDER                                         │"
  echo "│                                                                 │"
  echo "│  To ensure stale files are removed before copying, run:        │"
  echo "│                                                                 │"
  echo "│    rm -rf ~/.config/opencode                                    │"
  echo "│    rm -rf ~/.claude                                             │"
  echo "│    rm -rf ~/.local/share/ai-coding                              │"
  echo "│    rm -f ~/.local/bin/{$(join_comma "${BIN_NAMES[@]}")}         │"
  echo "│                                                                 │"
  echo "│  Then extract and copy as described in README-install.md.      │"
  echo "└─────────────────────────────────────────────────────────────────┘"
  echo ""
fi

info "Done. Inspect with: tar tf $(basename "$TARBALL")"
info "Extract with:       mkdir /tmp/ai-setup && tar xzf $(basename "$TARBALL") -C /tmp/ai-setup"
