#!/usr/bin/env bash
# generate-tarball.sh — produce a self-contained opencode-setup-<DATE>.tar.gz
#
# The tarball extracts into ~/.config/opencode/ and includes all agents, skills,
# commands, the pipeline tool with bundled node_modules, and a generated
# README-install.md. It is fully self-contained: no Nix, no home-manager, and no
# post-install steps beyond optionally configuring shell environment variables.
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
# Validate expected source files
# ---------------------------------------------------------------------------

MISSING=()

[ -f "$OPENCODE_SRC/AGENTS.md" ]                                  || MISSING+=("opencode/AGENTS.md")
[ -f "$OPENCODE_SRC/package.json" ]                               || MISSING+=("opencode/package.json")
[ -f "$AI_CODING_DIR/.opencode/tools/pipeline.ts" ]               || MISSING+=("ai-coding/.opencode/tools/pipeline.ts")
[ -f "$AI_CODING_DIR/opencode/mappings/opencode.json" ]           || MISSING+=("ai-coding/opencode/mappings/opencode.json")

for skill in analyst architect cpp debugger documenter explorer programmer reviewer rust tester; do
  [ -f "$OPENCODE_SRC/skill/$skill/SKILL.md" ] || MISSING+=("opencode/skill/$skill/SKILL.md")
done

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
  "$TARGET/tools" \
  "$TARGET/skill/analyst" \
  "$TARGET/skill/architect" \
  "$TARGET/skill/cpp" \
  "$TARGET/skill/debugger" \
  "$TARGET/skill/documenter" \
  "$TARGET/skill/explorer" \
  "$TARGET/skill/programmer" \
  "$TARGET/skill/reviewer" \
  "$TARGET/skill/rust" \
  "$TARGET/skill/tester"

info "Staging directory created at $STAGING"

# ---------------------------------------------------------------------------
# Copy files from home-manager/opencode/
# ---------------------------------------------------------------------------

info "Copying agents, skills, commands..."

cp "$OPENCODE_SRC/AGENTS.md"       "$TARGET/"
cp "$OPENCODE_SRC/package.json"    "$TARGET/"
cp "$OPENCODE_SRC/agents/"*.md     "$TARGET/agents/"
cp "$OPENCODE_SRC/commands/"*.md   "$TARGET/commands/"

for skill in analyst architect cpp debugger documenter explorer programmer reviewer rust tester; do
  cp "$OPENCODE_SRC/skill/$skill/SKILL.md" "$TARGET/skill/$skill/"
done

# ---------------------------------------------------------------------------
# Copy files from ai-coding/
# ---------------------------------------------------------------------------

info "Copying pipeline tool and opencode.json from ai-coding..."

cp "$AI_CODING_DIR/.opencode/tools/pipeline.ts"       "$TARGET/tools/"
cp "$AI_CODING_DIR/opencode/mappings/opencode.json"   "$TARGET/"

# ---------------------------------------------------------------------------
# Install node_modules
# ---------------------------------------------------------------------------

info "Running bun install to bundle node_modules..."
bun install --cwd "$TARGET" --frozen-lockfile 2>/dev/null \
  || bun install --cwd "$TARGET"

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
skills, slash commands, a custom pipeline tool, and global config.

---

## Contents

- **11 agents** — 7 primary (plan, build, local, explore, spar, teach, brainstorm)
  and 4 subagents (planner, debugger, reviewer, tester)
- **10 skills** — analyst, architect, cpp, debugger, documenter, explorer,
  programmer, reviewer, rust, tester
- **3 commands** — pipeline, scaffold-rust, scaffold-cpp
- **1 custom tool** — pipeline.ts with bundled node_modules
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
