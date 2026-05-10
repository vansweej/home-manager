#!/usr/bin/env bash
# generate-tarball.sh — produce a self-contained opencode-setup-<DATE>.tar.gz
#
# The tarball extracts into ~/.config/opencode/ and includes all agents, skills,
# commands, all tools with bundled node_modules, and a generated README-install.md.
# It is fully self-contained: no Nix, no home-manager, and no post-install steps
# beyond optionally configuring shell environment variables.
#
# Agents, skills, commands, and tools are auto-discovered from the opencode/
# directory structure — no manual updates needed when files are added or removed.
# Tool implementations are always copied from the ai-coding repo (authoritative
# source); opencode/tools/*.ts are marker files only.
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
# Ensure ai-coding repo is present
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
mapfile -t AGENTS < <(find "$OPENCODE_SRC/agents" -maxdepth 1 -name '*.md' -type f | sort)

# Skills: all subdirectories under opencode/skill/ that contain a SKILL.md
mapfile -t SKILLS < <(find "$OPENCODE_SRC/skill" -maxdepth 2 -name 'SKILL.md' -type f | sort)

# Commands: all *.md files under opencode/commands/
mapfile -t COMMANDS < <(find "$OPENCODE_SRC/commands" -maxdepth 1 -name '*.md' -type f | sort)

# Tools: all *.ts marker files under opencode/tools/ — real source is in ai-coding
mapfile -t TOOL_MARKERS < <(find "$OPENCODE_SRC/tools" -maxdepth 1 -name '*.ts' -type f | sort)

info "Discovered: ${#AGENTS[@]} agent(s), ${#SKILLS[@]} skill(s), ${#COMMANDS[@]} command(s), ${#TOOL_MARKERS[@]} tool(s)"

# ---------------------------------------------------------------------------
# Validate expected source files
# ---------------------------------------------------------------------------

MISSING=()

[ -f "$OPENCODE_SRC/AGENTS.md" ]   || MISSING+=("opencode/AGENTS.md")
[ -f "$OPENCODE_SRC/package.json" ] || MISSING+=("opencode/package.json")

for agent in "${AGENTS[@]}"; do
  [ -f "$agent" ] || MISSING+=("agents/$(basename "$agent")")
done

for skill in "${SKILLS[@]}"; do
  [ -f "$skill" ] || MISSING+=("skill/$(basename "$(dirname "$skill")")/SKILL.md")
done

for cmd in "${COMMANDS[@]}"; do
  [ -f "$cmd" ] || MISSING+=("commands/$(basename "$cmd")")
done

for marker in "${TOOL_MARKERS[@]}"; do
  name="$(basename "$marker")"
  [ -f "$AI_CODING_DIR/.opencode/tools/$name" ] \
    || MISSING+=("ai-coding/.opencode/tools/$name")
done

[ -f "$AI_CODING_DIR/opencode/mappings/opencode.json" ] \
  || MISSING+=("ai-coding/opencode/mappings/opencode.json")

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

mkdir -p \
  "$TARGET/agents" \
  "$TARGET/commands" \
  "$TARGET/tools"

# Create skill subdirectories dynamically
for skill in "${SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  mkdir -p "$TARGET/skill/$skill_name"
done

info "Staging directory created at $STAGING"

# ---------------------------------------------------------------------------
# Copy files from home-manager/opencode/
# ---------------------------------------------------------------------------

info "Copying AGENTS.md, package.json..."
cp "$OPENCODE_SRC/AGENTS.md"    "$TARGET/"
cp "$OPENCODE_SRC/package.json" "$TARGET/"

info "Copying ${#AGENTS[@]} agent(s)..."
for agent in "${AGENTS[@]}"; do
  cp "$agent" "$TARGET/agents/"
done

info "Copying ${#SKILLS[@]} skill(s)..."
for skill in "${SKILLS[@]}"; do
  skill_name="$(basename "$(dirname "$skill")")"
  cp "$skill" "$TARGET/skill/$skill_name/"
done

info "Copying ${#COMMANDS[@]} command(s)..."
for cmd in "${COMMANDS[@]}"; do
  cp "$cmd" "$TARGET/commands/"
done

# ---------------------------------------------------------------------------
# Copy tool implementations from ai-coding/
# (marker files in opencode/tools/ identify which tools; ai-coding is authoritative)
# ---------------------------------------------------------------------------

info "Copying ${#TOOL_MARKERS[@]} tool(s) from ai-coding..."
for marker in "${TOOL_MARKERS[@]}"; do
  name="$(basename "$marker")"
  cp "$AI_CODING_DIR/.opencode/tools/$name" "$TARGET/tools/"
done

info "Copying opencode.json from ai-coding..."
cp "$AI_CODING_DIR/opencode/mappings/opencode.json" "$TARGET/"

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
for marker in "${TOOL_MARKERS[@]}"; do
  TOOL_NAMES+=("$(basename "$marker" .ts)")
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
skills, slash commands, custom tools, and global config.

---

## Contents

- **${#AGENT_NAMES[@]} agents** — $(join_comma "${AGENT_NAMES[@]}")
- **${#SKILL_NAMES[@]} skills** — $(join_comma "${SKILL_NAMES[@]}")
- **${#COMMAND_NAMES[@]} commands** — $(join_comma "${COMMAND_NAMES[@]}")
- **${#TOOL_NAMES[@]} custom tool(s)** — $(join_comma "${TOOL_NAMES[@]}") (with bundled node_modules)
- **Global config** — opencode.json (GitHub Copilot / claude-sonnet-4.6), AGENTS.md

---

## Prerequisites

Before extracting, ensure the following are installed:

1. **OpenCode CLI**
   See https://opencode.ai for installation instructions.

2. **Bun runtime**
   - macOS:  \`brew install bun\`
   - Linux:  \`curl -fsSL https://bun.sh/install | bash\`

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

Everything lands in \`~/.config/opencode/\`.

### 4. Configure your shell profile

Add the following to your \`~/.bashrc\`, \`~/.zshrc\`, or equivalent:

\`\`\`bash
# Path to the ai-coding monorepo — required for the pipeline tool to work.
export AI_CODING_MONOREPO="\$HOME/Projects/ai-coding"

# OpenCode CLI binary path.
export PATH="\$HOME/.opencode/bin:\$PATH"
\`\`\`

Then reload your shell:

\`\`\`bash
source ~/.bashrc   # or source ~/.zshrc
\`\`\`

### 5. Clone the ai-coding monorepo (required for pipeline tool)

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

# Clean re-install (removes stale files from renamed/removed agents or skills)
rm -rf ~/.config/opencode
tar xzf ~/Projects/home-manager/opencode-setup-\$(date +%Y-%m-%d).tar.gz -C ~/
\`\`\`

> **Why clean?** If an agent or skill is renamed or removed upstream, the old
> file remains in \`~/.config/opencode/\` after a plain re-extract. A clean
> re-install ensures your config exactly matches the source.

---

## The pipeline tool

\`pipeline.ts\` lets any OpenCode agent run multi-step coding pipelines
(scaffold-rust, scaffold-cpp, dev-cycle, rust-dev-cycle, cmake-dev-cycle).
It requires:

- The \`AI_CODING_MONOREPO\` environment variable pointing to your local clone
  of \`ai-coding\`
- Bun on PATH (the tool shells out to \`bun run pipeline\`)

If you do not need pipeline support, the rest of the setup (agents, skills,
commands, config) works fine without it.
README

# ---------------------------------------------------------------------------
# Pack the tarball
# ---------------------------------------------------------------------------

info "Packing tarball..."
tar czf "$TARBALL" -C "$STAGING" .config

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
  echo "│    tar xzf $(basename "$TARBALL") -C ~/          │"
  echo "│                                                                 │"
  echo "│  See README-install.md inside the tarball for full details.    │"
  echo "└─────────────────────────────────────────────────────────────────┘"
  echo ""
fi

info "Done. Inspect with: tar tf $(basename "$TARBALL")"
info "Extract with:       tar xzf $(basename "$TARBALL") -C ~/"
