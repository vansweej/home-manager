#!/usr/bin/env bash
# generate-tarball.sh — produce a self-contained opencode-setup-<DATE>.tar.gz
#
# The tarball extracts into ~/ and includes:
#   ~/.config/opencode/  — agents, skills, commands, tools with bundled
#                          node_modules, opencode.json, AGENTS.md
#   ~/.local/bin/        — CLI wrapper scripts (codebase-retrieval, index-codebase)
#
# It is fully self-contained: no Nix, no home-manager, and no post-install steps
# beyond optionally configuring shell environment variables.
#
# Agents, skills, commands, tools, and bin wrappers are auto-discovered from the
# opencode/ directory structure — no manual updates needed when files are added
# or removed.
#
# opencode.json is sourced from the ai-coding repo root (../ai-coding/opencode.json).
# Tool implementations live in opencode/tools/ (self-contained; they delegate to
# the ai-coding monorepo at runtime via subprocess).
#
# Usage:
#   ./generate-tarball.sh          # produce opencode-setup-YYYY-MM-DD.tar.gz
#   ./generate-tarball.sh --clean  # same, but print a prominent clean-install reminder
#   ./generate-tarball.sh --help   # show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_CODING_REPO_URL="https://github.com/vansweej/ai-coding.git"
AI_CODING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/ai-coding"
OPENCODE_SRC="$SCRIPT_DIR/opencode"
DATE="$(date +%Y-%m-%d)"
PLATFORM="$(uname -s)/$(uname -m)"
TARBALL="$SCRIPT_DIR/opencode-setup-${DATE}.tar.gz"

CLEAN_REMINDER=false

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

BUN_VERSION="$(bun --version)"
info "Using bun $BUN_VERSION"

# ---------------------------------------------------------------------------
# Ensure ai-coding repo is present (needed for opencode.json config only)
# ---------------------------------------------------------------------------

if [ ! -d "$AI_CODING_DIR" ]; then
  info "ai-coding not found at $AI_CODING_DIR — cloning..."
  git clone "$AI_CODING_REPO_URL" "$AI_CODING_DIR"
  info "Cloned ai-coding successfully."
else
  info "Found ai-coding at $AI_CODING_DIR"
fi

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

info "Discovered: ${#AGENTS[@]} agent(s), ${#SKILLS[@]} skill(s), ${#COMMANDS[@]} command(s), ${#TOOLS[@]} tool(s), ${#BINS[@]} bin wrapper(s)"

# ---------------------------------------------------------------------------
# Validate expected source files
# ---------------------------------------------------------------------------

MISSING=()

[ -f "$OPENCODE_SRC/AGENTS.md" ]    || MISSING+=("opencode/AGENTS.md")
[ -f "$OPENCODE_SRC/package.json" ] || MISSING+=("opencode/package.json")
[ -f "$OPENCODE_SRC/bun.lock" ]     || MISSING+=("opencode/bun.lock")

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

if [ ${#MISSING[@]} -gt 0 ]; then
  error "The following required source files are missing:
$(printf '  - %s\n' "${MISSING[@]}")
Pull the latest changes from both repos and try again."
fi

# ---------------------------------------------------------------------------
# Create staging directory
# ---------------------------------------------------------------------------

STAGING="$(mktemp -d)"
# Ensure staging is always cleaned up, even on error.
trap 'rm -rf "$STAGING"' EXIT

TARGET="$STAGING/.config/opencode"
BIN_TARGET="$STAGING/.local/bin"

mkdir -p \
  "$TARGET/agents" \
  "$TARGET/commands" \
  "$TARGET/tools" \
  "$BIN_TARGET"

# Create skill subdirectories dynamically
for skill in "${SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  mkdir -p "$TARGET/skills/$skill_name"
done

info "Staging directory created at $STAGING"

# ---------------------------------------------------------------------------
# Copy files from home-manager/opencode/
# ---------------------------------------------------------------------------

info "Copying AGENTS.md, package.json, bun.lock..."
cp "$OPENCODE_SRC/AGENTS.md"    "$TARGET/"
cp "$OPENCODE_SRC/package.json" "$TARGET/"
cp "$OPENCODE_SRC/bun.lock"     "$TARGET/"

info "Copying ${#AGENTS[@]} agent(s)..."
for agent in "${AGENTS[@]}"; do
  cp "$agent" "$TARGET/agents/"
done

info "Copying ${#SKILLS[@]} skill(s)..."
for skill in "${SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  cp "$skill" "$TARGET/skills/$skill_name/"
done

info "Copying ${#COMMANDS[@]} command(s)..."
for cmd in "${COMMANDS[@]}"; do
  cp "$cmd" "$TARGET/commands/"
done

# ---------------------------------------------------------------------------
# Copy tool implementations from opencode/tools/
# (self-contained — delegate to ai-coding monorepo at runtime via subprocess)
# ---------------------------------------------------------------------------

info "Copying ${#TOOLS[@]} tool(s)..."
for tool in "${TOOLS[@]}"; do
  cp "$tool" "$TARGET/tools/"
done

info "Copying opencode.json from ai-coding..."
cp "$AI_CODING_DIR/opencode.json" "$TARGET/"

# ---------------------------------------------------------------------------
# Copy bin wrapper scripts from opencode/bin/
# ---------------------------------------------------------------------------

info "Copying ${#BINS[@]} bin wrapper(s)..."
for bin in "${BINS[@]}"; do
  cp "$bin" "$BIN_TARGET/"
  chmod +x "$BIN_TARGET/$(basename "$bin")"
done

# ---------------------------------------------------------------------------
# Install node_modules
# ---------------------------------------------------------------------------

info "Running bun install to bundle node_modules..."
bun install --cwd "$TARGET" --frozen-lockfile 2>/dev/null \
  || bun install --cwd "$TARGET"

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

join_comma() {
  local IFS=", "
  echo "$*"
}

# ---------------------------------------------------------------------------
# Generate README-install.md
# ---------------------------------------------------------------------------

info "Generating README-install.md..."

cat > "$TARGET/README-install.md" <<README
# OpenCode CLI Setup

Generated: ${DATE}
Platform:  ${PLATFORM}
Bun:       ${BUN_VERSION}

This archive contains a complete global OpenCode CLI configuration: agents,
skills, slash commands, custom tools, CLI wrappers, and global config.

---

## Contents

- **${#AGENT_NAMES[@]} agents** — $(join_comma "${AGENT_NAMES[@]}")
- **${#SKILL_NAMES[@]} skills** — $(join_comma "${SKILL_NAMES[@]}")
- **${#COMMAND_NAMES[@]} commands** — $(join_comma "${COMMAND_NAMES[@]}")
- **${#TOOL_NAMES[@]} custom tool(s)** — $(join_comma "${TOOL_NAMES[@]}") (with bundled node_modules)
- **${#BIN_NAMES[@]} CLI wrapper(s)** — $(join_comma "${BIN_NAMES[@]}") (deployed to ~/.local/bin/)
- **Global config** — opencode.json (GitHub Copilot / claude-sonnet-4.6), AGENTS.md

---

## Prerequisites

Before extracting, ensure the following are installed:

1. **OpenCode CLI**
   See https://opencode.ai for installation instructions.

2. **Bun runtime**
   - macOS:  \`brew install bun\`
   - Linux / WSL:  \`curl -fsSL https://bun.sh/install | bash\`

---

## Install

### 1. Inspect the tarball (recommended first time)

\`\`\`bash
tar tf opencode-setup-${DATE}.tar.gz
\`\`\`

### 2. Back up your existing config (if any)

\`\`\`bash
cp -r ~/.config/opencode ~/.config/opencode.bak
\`\`\`

### 3. Extract

\`\`\`bash
tar xzf opencode-setup-${DATE}.tar.gz -C ~/
\`\`\`

Everything lands in \`~/.config/opencode/\` and \`~/.local/bin/\`.

### 4. Configure your shell profile

Add the following to your \`~/.bashrc\`, \`~/.zshrc\`, or equivalent:

\`\`\`bash
# Path to the ai-coding monorepo — required for all tools to work.
export AI_CODING_MONOREPO="\$HOME/Projects/ai-coding"

# OpenCode CLI binary path.
export PATH="\$HOME/.opencode/bin:\$PATH"

# CLI wrappers (codebase-retrieval, index-codebase).
export PATH="\$HOME/.local/bin:\$PATH"
\`\`\`

Then reload your shell:

\`\`\`bash
source ~/.bashrc   # or source ~/.zshrc
\`\`\`

### 5. Clone the ai-coding monorepo (required for all tools)

If you have not already cloned it:

\`\`\`bash
mkdir -p ~/Projects
git clone https://github.com/vansweej/ai-coding.git ~/Projects/ai-coding
\`\`\`

### 6. Restart OpenCode

Start or restart OpenCode to pick up the new configuration.

---

## Updating

When the configuration is updated, re-generate the tarball on your machine
(pull both repos first) and then do a clean re-install:

\`\`\`bash
# Pull latest changes
cd ~/Projects/home-manager && git pull
cd ~/Projects/ai-coding    && git pull

# Re-generate
cd ~/Projects/home-manager && ./generate-tarball.sh

# Clean re-install (removes stale files from renamed/removed agents, skills, or bin wrappers)
rm -rf ~/.config/opencode
rm -f ~/.local/bin/$(join_comma "${BIN_NAMES[@]}" | tr ', ' ' ' | xargs -n1 echo | sed 's/^/~\/.local\/bin\//') 2>/dev/null || true
tar xzf ~/Projects/home-manager/opencode-setup-\$(date +%Y-%m-%d).tar.gz -C ~/
\`\`\`

> **Why clean?** If an agent, skill, or bin wrapper is renamed or removed
> upstream, the old file remains after a plain re-extract. A clean re-install
> ensures your config exactly matches the source.

For a simpler clean of bin wrappers, remove them by name:

\`\`\`bash
rm -f $(for b in "${BIN_NAMES[@]}"; do printf '~/.local/bin/%s ' "$b"; done)
\`\`\`

---

## The pipeline tool

\`pipeline.ts\` lets any OpenCode agent run multi-step coding pipelines
(scaffold-rust, scaffold-cpp, dev-cycle, rust-dev-cycle, cmake-dev-cycle).
It requires:

- The \`AI_CODING_MONOREPO\` environment variable pointing to your local clone
  of \`ai-coding\`
- Bun on PATH (the tool shells out to \`bun run pipeline\`)

---

## The codebase-retrieval tool and CLI wrapper

\`codebase-retrieval.ts\` performs semantic code search over indexed repositories.
It requires Ollama running locally with the \`nomic-embed-text\` model pulled.

The \`codebase-retrieval\` and \`index-codebase\` CLI wrappers (in \`~/.local/bin/\`)
let you run these operations directly from the terminal:

\`\`\`bash
# Index the current repository
index-codebase

# Search the current repository
codebase-retrieval "hash-based staleness check"
\`\`\`

Both wrappers require:
- \`AI_CODING_MONOREPO\` set in your shell profile (see step 4 above)
- \`~/.local/bin\` on your PATH (see step 4 above)

If you do not need codebase search, the rest of the setup (agents, skills,
commands, pipeline tool, config) works fine without Ollama.
README

# ---------------------------------------------------------------------------
# Pack the tarball
# ---------------------------------------------------------------------------

info "Packing tarball..."
tar czf "$TARBALL" -C "$STAGING" .config .local

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
  echo "│  To ensure stale files are removed before extracting, run:     │"
  echo "│                                                                 │"
  echo "│    rm -rf ~/.config/opencode                                    │"
  echo "│    rm -f ~/.local/bin/{$(join_comma "${BIN_NAMES[@]}")}         │"
  echo "│    tar xzf $(basename "$TARBALL") -C ~/          │"
  echo "│                                                                 │"
  echo "│  See README-install.md inside the tarball for full details.    │"
  echo "└─────────────────────────────────────────────────────────────────┘"
  echo ""
fi

info "Done. Inspect with: tar tf $(basename "$TARBALL")"
info "Extract with:       tar xzf $(basename "$TARBALL") -C ~/"
