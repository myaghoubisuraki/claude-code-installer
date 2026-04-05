#!/usr/bin/env bash
# =============================================================================
# Claude Code Secure Installer — macOS & Linux
# https://github.com/myaghoubisuraki/claude-code-installer
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Constants ─────────────────────────────────────────────────────────────────
MIN_NODE_MAJOR=18
MIN_NODE_MINOR=18
CLAUDE_NPM_PKG="@anthropic-ai/claude-code"
CODEX_MARKETPLACE="openai/codex-plugin-cc"
LOG_FILE="${TMPDIR:-/tmp}/claude-install-$(date +%Y%m%d-%H%M%S).log"

# ── Helpers ───────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

require_command() {
  command_exists "$1" || die "Required command '$1' not found. Please install it and re-run."
}

node_version_ok() {
  if ! command_exists node; then return 1; fi
  local ver; ver=$(node -e "process.stdout.write(process.version)" 2>/dev/null)
  local major minor
  major=$(echo "$ver" | sed 's/v\([0-9]*\).*/\1/')
  minor=$(echo "$ver" | sed 's/v[0-9]*\.\([0-9]*\).*/\1/')
  [ "$major" -gt "$MIN_NODE_MAJOR" ] || \
    { [ "$major" -eq "$MIN_NODE_MAJOR" ] && [ "$minor" -ge "$MIN_NODE_MINOR" ]; }
}

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
  echo ""
  echo -e "${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║      Claude Code — Secure Installer      ║"
  echo "  ║           macOS & Linux Edition           ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo "  Log file: $LOG_FILE"
  echo ""
}

# ── Step 1: OS Detection ──────────────────────────────────────────────────────
detect_os() {
  info "Detecting operating system..."
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS" in
    Linux*)  OS_TYPE="linux" ;;
    Darwin*) OS_TYPE="macos" ;;
    *)       die "Unsupported OS: $OS. Use install.ps1 on Windows." ;;
  esac
  success "Detected: $OS_TYPE ($ARCH)"
}

# ── Step 2: Check/Install Git ─────────────────────────────────────────────────
ensure_git() {
  info "Checking for Git..."
  if command_exists git; then
    success "Git found: $(git --version)"
    return
  fi
  warn "Git not found. Attempting to install..."
  case "$OS_TYPE" in
    macos)
      if command_exists brew; then
        brew install git >>"$LOG_FILE" 2>&1
      else
        # Trigger Xcode CLI tools which includes git
        xcode-select --install 2>/dev/null || true
        die "Git not found. Install Xcode Command Line Tools: xcode-select --install"
      fi
      ;;
    linux)
      if command_exists apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y git >>"$LOG_FILE" 2>&1
      elif command_exists dnf; then
        sudo dnf install -y git >>"$LOG_FILE" 2>&1
      elif command_exists yum; then
        sudo yum install -y git >>"$LOG_FILE" 2>&1
      elif command_exists pacman; then
        sudo pacman -Sy --noconfirm git >>"$LOG_FILE" 2>&1
      else
        die "Could not install Git. Please install it manually."
      fi
      ;;
  esac
  command_exists git || die "Git installation failed."
  success "Git installed: $(git --version)"
}

# ── Step 3: Check/Install Node.js ─────────────────────────────────────────────
ensure_node() {
  info "Checking for Node.js (requires v${MIN_NODE_MAJOR}.${MIN_NODE_MINOR}+)..."

  if node_version_ok; then
    success "Node.js found: $(node --version) — meets requirements"
    return
  fi

  if command_exists node; then
    warn "Node.js $(node --version) is installed but too old. Need v${MIN_NODE_MAJOR}.${MIN_NODE_MINOR}+."
  else
    warn "Node.js not found."
  fi

  # Prefer fnm (fast, no sudo needed) → nvm → system package manager
  if command_exists fnm; then
    info "Installing Node.js via fnm..."
    local FNM_BIN; FNM_BIN="$(command -v fnm)"
    "$FNM_BIN" install --lts >>"$LOG_FILE" 2>&1
    # FIX (HIGH): avoid eval; parse only known env vars instead of executing arbitrary output
    local fnm_env; fnm_env="$("$FNM_BIN" env --shell bash 2>/dev/null)"
    while IFS= read -r line; do
      if [[ "$line" =~ ^export\ (PATH|FNM_DIR|FNM_VERSION_DIR|FNM_MULTISHELL_PATH)=(.+)$ ]]; then
        export "${BASH_REMATCH[1]}"="${BASH_REMATCH[2]//\"/}"
      fi
    done <<< "$fnm_env"
  elif [ -f "$HOME/.nvm/nvm.sh" ]; then
    info "Installing Node.js via nvm..."
    # FIX (MEDIUM): resolve real home from passwd to prevent HOME manipulation
    local real_home; real_home="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6 || echo "$HOME")"
    local nvm_sh="$real_home/.nvm/nvm.sh"
    # Verify file is owned by current user and is not a symlink
    [ -O "$nvm_sh" ] && [ ! -L "$nvm_sh" ] || die "Unsafe nvm.sh path — aborting for security."
    # shellcheck source=/dev/null
    source "$nvm_sh" 2>/dev/null || true
    nvm install --lts >>"$LOG_FILE" 2>&1
    nvm use --lts >>"$LOG_FILE" 2>&1
  else
    info "Installing Node.js via system package manager..."
    case "$OS_TYPE" in
      macos)
        if command_exists brew; then
          brew install node >>"$LOG_FILE" 2>&1
        else
          die "Homebrew not found. Install Node.js from https://nodejs.org or install Homebrew first."
        fi
        ;;
      linux)
        # FIX (HIGH): no curl-pipe-sudo. Use distro package manager with official NodeSource repo setup
        # only via signed apt/rpm sources — never execute a downloaded shell script as root.
        info "Installing Node.js via distro package manager..."
        if command_exists apt-get; then
          # Add NodeSource signed apt repo without executing a downloaded script
          local keyring_dir="/usr/share/keyrings"
          local node_key="$keyring_dir/nodesource.gpg"
          curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" 2>>"$LOG_FILE" \
            | sudo gpg --dearmor -o "$node_key" >>"$LOG_FILE" 2>&1
          echo "deb [signed-by=$node_key] https://deb.nodesource.com/node_lts.x nodistro main" \
            | sudo tee /etc/apt/sources.list.d/nodesource.list >>"$LOG_FILE" 2>&1
          sudo apt-get update -qq >>"$LOG_FILE" 2>&1
          sudo apt-get install -y nodejs >>"$LOG_FILE" 2>&1
        elif command_exists dnf; then
          sudo dnf module install -y nodejs:lts >>"$LOG_FILE" 2>&1 || \
            sudo dnf install -y nodejs >>"$LOG_FILE" 2>&1
        elif command_exists yum; then
          sudo yum install -y nodejs >>"$LOG_FILE" 2>&1
        else
          die "Could not install Node.js automatically. Install manually from https://nodejs.org"
        fi
        ;;
    esac
  fi

  node_version_ok || die "Node.js installation failed or version still too old. Install manually from https://nodejs.org"
  success "Node.js ready: $(node --version)"
}

# ── Step 4: Install Claude Code ───────────────────────────────────────────────
install_claude() {
  info "Installing Claude Code from npm (official registry)..."

  # Ensure we're hitting the official registry
  local registry; registry=$(npm config get registry 2>/dev/null || echo "https://registry.npmjs.org/")
  if [[ "$registry" != *"registry.npmjs.org"* && "$registry" != *"registry.npmjs.com"* ]]; then
    warn "Non-default npm registry detected: $registry"
    warn "Installing with explicit official registry..."
    npm install -g "$CLAUDE_NPM_PKG" --registry https://registry.npmjs.org/ >>"$LOG_FILE" 2>&1
  else
    npm install -g "$CLAUDE_NPM_PKG" >>"$LOG_FILE" 2>&1
  fi

  command_exists claude || die "Claude Code installation failed. Check log: $LOG_FILE"
  success "Claude Code installed: $(claude --version)"
}

# ── Step 5: Verify Installation ───────────────────────────────────────────────
verify_install() {
  info "Verifying installation..."
  local failed=0

  command_exists node  || { error "node not found";   failed=1; }
  command_exists npm   || { error "npm not found";    failed=1; }
  command_exists claude || { error "claude not found"; failed=1; }

  [ "$failed" -eq 0 ] || die "Verification failed. Check log: $LOG_FILE"

  success "All components verified:"
  echo "    node   → $(node --version)"
  echo "    npm    → $(npm --version)"
  echo "    claude → $(claude --version)"
}

# ── Step 6: Authenticate ──────────────────────────────────────────────────────
authenticate() {
  echo ""
  info "Starting Claude Code authentication..."
  echo ""
  echo -e "  ${BOLD}You will be redirected to claude.ai to log in.${RESET}"
  echo "  Make sure you have a Claude account ready."
  echo ""
  read -r -p "  Press ENTER to open the browser login... (Ctrl+C to skip)"
  claude login || warn "Login skipped or failed. Run 'claude login' manually later."
}

# ── Step 7: Optional — Install Codex Plugin ───────────────────────────────────
install_codex_plugin() {
  echo ""
  read -r -p "  Install the OpenAI Codex plugin for Claude Code? [y/N] " answer
  case "$answer" in
    [Yy]*)
      info "Adding OpenAI Codex marketplace..."
      claude plugin marketplace add "$CODEX_MARKETPLACE" >>"$LOG_FILE" 2>&1 && \
        claude plugin install "codex@openai-codex" >>"$LOG_FILE" 2>&1 && \
        success "Codex plugin installed. Restart Claude Code and run /codex:setup" || \
        warn "Codex plugin install failed. You can retry with: claude plugin marketplace add $CODEX_MARKETPLACE"
      ;;
    *) info "Skipping Codex plugin." ;;
  esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  banner
  detect_os
  ensure_git
  ensure_node
  install_claude
  verify_install
  authenticate
  install_codex_plugin

  echo ""
  echo -e "${BOLD}${GREEN}  ✓ Claude Code setup complete!${RESET}"
  echo ""
  echo "  Run 'claude' to start."
  echo "  Log saved to: $LOG_FILE"
  echo ""
}

main "$@"
