#!/usr/bin/env bash
# OS-aware dependency installer for oh-my-copilot
# Usage: bash scripts/install.sh
set -uo pipefail

DEPS=(sqlite3 jq git)
MISSING=()

check_deps() {
    for dep in "${DEPS[@]}"; do
        command -v "$dep" &>/dev/null || MISSING+=("$dep")
    done
}

install_linux() {
    if command -v apt-get &>/dev/null; then
        echo "[omc] Installing via apt-get..."
        sudo apt-get update -qq && sudo apt-get install -y sqlite3 jq git
    elif command -v dnf &>/dev/null; then
        echo "[omc] Installing via dnf..."
        sudo dnf install -y sqlite jq git
    elif command -v yum &>/dev/null; then
        echo "[omc] Installing via yum..."
        sudo yum install -y sqlite jq git
    elif command -v pacman &>/dev/null; then
        echo "[omc] Installing via pacman..."
        sudo pacman -Sy --noconfirm sqlite jq git
    else
        echo "[omc] ERROR: No supported package manager found (apt/dnf/yum/pacman)"
        echo "[omc] Please install manually: ${MISSING[*]}"
        exit 1
    fi
}

install_macos() {
    if command -v brew &>/dev/null; then
        echo "[omc] Installing via Homebrew..."
        brew install sqlite3 jq git
    else
        echo "[omc] ERROR: Homebrew not found."
        echo "[omc] Install Homebrew first: https://brew.sh"
        echo "[omc] Then run: brew install sqlite3 jq git"
        exit 1
    fi
}

main() {
    echo "[omc] Checking dependencies..."
    check_deps

    if [ ${#MISSING[@]} -eq 0 ]; then
        echo "[omc] All dependencies already installed: ${DEPS[*]}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ oh-my-copilot dependencies ready!"
        echo ""
        echo "⚡ IMPORTANT: Enable experimental features:"
        echo "   Run '/experimental on' in Copilot CLI"
        echo "   Or: copilot --experimental"
        echo ""
        echo "🚀 This unlocks: multi-turn agents, session store,"
        echo "   structured forms, status line, and more."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        # Extensions scaffold notice
        PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
        if [ -d "$PLUGIN_DIR/extensions/oh-my-copilot" ]; then
            echo ""
            echo "  📦 Extensions scaffold available — see extensions/README.md"
        fi
        exit 0
    fi

    echo "[omc] Missing: ${MISSING[*]}"

    OS="$(uname -s)"
    case "$OS" in
        Linux)  install_linux  ;;
        Darwin) install_macos  ;;
        *)
            echo "[omc] Unsupported OS: $OS"
            echo "[omc] Please install manually: ${MISSING[*]}"
            exit 1
            ;;
    esac

    echo "[omc] Verifying installation..."
    STILL_MISSING=()
    for dep in "${MISSING[@]}"; do
        command -v "$dep" &>/dev/null || STILL_MISSING+=("$dep")
    done

    if [ ${#STILL_MISSING[@]} -eq 0 ]; then
        echo "[omc] ✓ All dependencies installed successfully"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ oh-my-copilot dependencies ready!"
        echo ""
        echo "⚡ IMPORTANT: Enable experimental features:"
        echo "   Run '/experimental on' in Copilot CLI"
        echo "   Or: copilot --experimental"
        echo ""
        echo "🚀 This unlocks: multi-turn agents, session store,"
        echo "   structured forms, status line, and more."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        # Extensions scaffold notice
        PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
        if [ -d "$PLUGIN_DIR/extensions/oh-my-copilot" ]; then
            echo ""
            echo "  📦 Extensions scaffold available — see extensions/README.md"
        fi
    else
        echo "[omc] WARNING: Still missing: ${STILL_MISSING[*]}"
        exit 1
    fi
}

main "$@"
