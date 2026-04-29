#!/usr/bin/env bash
# setup.sh
#
# One-command setup and reproduction for the clang-padding-leakage-checker.
# Detects your OS, installs all dependencies, builds the plugin, and runs
# the full thesis evaluation.
#
# Usage:
#   bash setup.sh
#
# Supported:
#   Arch Linux  (pacman)
#   Ubuntu/Debian (apt)
#
# What this script does:
#   1. Detects OS and installs LLVM 21, cmake, ninja, python, git
#   2. Creates a Python virtual environment and installs CodeChecker
#   3. Builds the checker plugin against LLVM 21
#   4. Runs the synthetic benchmark suite (Appendix A)
#   5. Clones and annotates the 4 evaluated libraries, runs CodeChecker,
#      and prints the metrics from thesis Tables 8.2 and 8.3

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/.codechecker-env"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
section() { echo -e "\n${BOLD}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD} $*${NC}"; \
            echo -e "${BOLD}══════════════════════════════════════════${NC}"; }

# ── OS Detection ─────────────────────────────────────────────────────────────
detect_os() {
  if command -v pacman &>/dev/null; then
    echo "arch"
  elif command -v apt-get &>/dev/null; then
    echo "ubuntu"
  else
    echo "unknown"
  fi
}

OS=$(detect_os)
[ "$OS" = "unknown" ] && error "Unsupported OS. Supported: Arch Linux, Ubuntu/Debian."

# ── Step 1: Install system dependencies ──────────────────────────────────────
section "Step 1: Installing system dependencies"

if [ "$OS" = "arch" ]; then
  info "Detected Arch Linux — installing via pacman..."
  PKGS=()
  for pkg in llvm21 clang21 cmake ninja python git; do
    pacman -Qi "$pkg" &>/dev/null || PKGS+=("$pkg")
  done
  if [ ${#PKGS[@]} -gt 0 ]; then
    info "Installing: ${PKGS[*]}"
    sudo pacman -S --noconfirm "${PKGS[@]}"
  else
    info "All system packages already installed."
  fi
  LLVM21="/usr/lib/llvm21"

elif [ "$OS" = "ubuntu" ]; then
  info "Detected Ubuntu/Debian — installing via apt..."
  if ! command -v clang-tidy-21 &>/dev/null; then
    info "Adding LLVM 21 apt repository..."
    wget -qO- https://apt.llvm.org/llvm.sh | sudo bash -s 21
  fi
  sudo apt-get install -y clang-21 clang-tidy-21 llvm-21-dev \
    cmake ninja-build python3 python3-venv git
  LLVM21="/usr/bin"
fi

info "LLVM 21: $("$LLVM21/bin/clang" --version | head -1)"

# ── Step 2: Create CodeChecker virtual environment ────────────────────────────
section "Step 2: Setting up CodeChecker"

if [ ! -d "$VENV" ]; then
  info "Creating virtual environment at $VENV ..."
  python3 -m venv "$VENV"
fi

info "Activating virtual environment..."
# shellcheck disable=SC1091
source "$VENV/bin/activate"

if ! command -v CodeChecker &>/dev/null; then
  info "Installing CodeChecker..."
  pip install --quiet codechecker
else
  info "CodeChecker already installed: $(CodeChecker --version 2>/dev/null | head -1)"
fi

# ── Step 3: Build the plugin ──────────────────────────────────────────────────
section "Step 3: Building checker plugin"

bash "$ROOT/scripts/build.sh"

PLUGIN="$ROOT/build/SecurityMiscPlugin.so"
[ -f "$PLUGIN" ] || error "Build failed — plugin not found at $PLUGIN"

info "Verifying plugin loads with clang-tidy 21..."
RESULT=$("$LLVM21/bin/clang-tidy" -load "$PLUGIN" \
  -checks='*' -list-checks 2>/dev/null | grep security-misc || true)
[ -n "$RESULT" ] || error "Plugin failed to load. Check LLVM version compatibility."
info "Plugin verified: $RESULT"

# ── Step 4 & 5: Run full reproduction ─────────────────────────────────────────
section "Step 4 & 5: Running full thesis evaluation"
info "This will clone 4 libraries and run CodeChecker — expect 10–20 minutes."
echo ""

bash "$ROOT/scripts/reproduce_all.sh"

# ── Done ──────────────────────────────────────────────────────────────────────
section "Setup complete"
echo ""
info "The plugin is built at:  build/SecurityMiscPlugin.so"
info "CodeChecker venv at:     $VENV"
echo ""
info "To run the checker on your own project in future sessions:"
echo ""
echo "    source $VENV/bin/activate"
echo "    bash scripts/run_codechecker.sh /path/to/project compile_commands.json"
echo ""
info "To re-run the thesis evaluation:"
echo ""
echo "    source $VENV/bin/activate"
echo "    bash scripts/reproduce_all.sh"
echo ""
